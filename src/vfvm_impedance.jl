using SparseDiffTools
using SparseArrays

abstract type AbstractImpedanceSystem{Tv <: Number} end





mutable struct ImpedanceSystem{Tv} <: AbstractImpedanceSystem{Tv}
    sysnzval::AbstractVector{Complex{Tv}}
    grid
    storderiv::AbstractMatrix{Tv}
    matrix::AbstractMatrix{Complex{Tv}}
    F::AbstractMatrix{Complex{Tv}}
    U0::AbstractMatrix{Tv}
    ImpedanceSystem{Tv}() where Tv =new()
end




function ImpedanceSystem(sys::AbstractSystem{Tv,Ti}, U0::AbstractMatrix, excited_spec,excited_bc) where {Tv,Ti}
    this=ImpedanceSystem{Tv}()
    this.grid=sys.grid
    this.sysnzval=complex(nonzeros(sys.matrix))
    m,n=size(sys.matrix)
    
    this.storderiv=spzeros(Tv,m,n)
    this.matrix=SparseMatrixCSC(m,n,
                                colptrs(sys.matrix),
                                rowvals(sys.matrix),
                                copy(this.sysnzval)
                                )
    this.U0=U0

    matrix=this.matrix
    storderiv=this.storderiv


    
    F=unknowns(Complex{Float64},sys)
    
    this.F=F
    
    grid=sys.grid
    
    physics=sys.physics
    data=physics.data
    node=Node{Tv,Ti}(sys)
    bnode=BNode{Tv,Ti}(sys)
    nspecies=num_species(sys)
    

    nodeparams=(node,)
    bnodeparams=(bnode,)
    if isdata(data)
        nodeparams=(node,data,)
        bnodeparams=(bnode,data,)
    end    

    storagewrap=function(y::AbstractVector, u::AbstractVector)
        y.=0
        physics.storage(y,u,nodeparams...)
    end
    
    bstoragewrap=function(y::AbstractVector, u::AbstractVector)
        y.=0
        physics.bstorage(y,u,bnodeparams...)
    end
    
        
    F.=0.0
    UK=Array{Tv,1}(undef,nspecies)
    Y=Array{Tv,1}(undef,nspecies)
    
    # structs holding diff results for storage
    result_s=DiffResults.DiffResult(Vector{Tv}(undef,nspecies),Matrix{Tv}(undef,nspecies,nspecies))



    
    geom=grid[CellGeometries][1]
    csys=grid[CoordinateSystem]
    coord=grid[Coordinates]
    cellnodes=grid[CellNodes]
    cellregions=grid[CellRegions]

    bgeom=grid[BFaceGeometries][1]
    bfacenodes=grid[BFaceNodes]
    bfaceregions=grid[BFaceRegions]




    
    # Main cell loop for building up storderiv
    for icell=1:num_cells(grid)
        
        for inode=1:num_nodes(geom)
            _fill!(node,cellnodes,cellregions,inode,icell)
            @views begin
                UK[1:nspecies]=U0[:,node.index]
            end
            
            # Evaluate & differentiate storage term
            ForwardDiff.jacobian!(result_s,storagewrap,Y,UK)
            jac_stor=DiffResults.jacobian(result_s)


            K=node.index
            for idof=_firstnodedof(F,K):_lastnodedof(F,K)
                ispec=_spec(F,idof,K)
                for jdof=_firstnodedof(F,K):_lastnodedof(F,K)
                    jspec=_spec(F,jdof,K)
                    _addnz(storderiv,idof,jdof,jac_stor[ispec,jspec],sys.cellnodefactors[inode,icell])
                end
            end

        end
        
    end

    for ibface=1:num_bfaces(grid)
        ibreg=bfaceregions[ibface]
        for ibnode=1:num_nodes(bgeom)
            @views begin
                _fill!(bnode,bfacenodes,bfaceregions,ibnode,ibface)
                
                UK[1:nspecies]=U0[:,bnode.index]
            end
            if ibreg==excited_bc
                for ispec=1:nspecies # should involve only rspecies
                    if ispec!=excited_spec
                        continue
                    end
                    idof=dof(F,ispec,bnode.index)
                    if idof>0 
                        fac=sys.boundary_factors[ispec,ibreg]
                        val=sys.boundary_values[ispec,ibreg]
                        if fac==Dirichlet
                            F[ispec,bnode.index]+=fac
                        else
                            F[ispec,bnode.index]+=fac*sys.bfacenodefactors[ibnode,ibface]
                        end
                    end
                end
            end
            
            if isdefined(physics, :bstorage) # should involve only bspecies
                # Evaluate & differentiate storage term
                ForwardDiff.jacobian!(result_s,bstoragewrap,Y,UK)
                res_bstor=DiffResults.value(result_s)
                jac_bstor=DiffResults.jacobian(result_s)


                K=bnode.index
                for idof=_firstnodedof(F,K):_lastnodedof(F,K)
                    ispec=_spec(F,idof,K)
                    for jdof=_firstnodedof(F,K):_lastnodedof(F,K)
                        jspec=_spec(F,jdof,K)
                        _addnz(storderiv,idof,jdof,jac_bstor[ispec,jspec],sys.bfacenodefactors[ibnode,ibface])
                    end
                end
            end
            
        end
    end
    return this
end

unknowns(this::ImpedanceSystem{Tv}) where Tv=copy(this.F)
                                                     
function solve!(UZ::AbstractMatrix{Complex{Tv}},this::ImpedanceSystem{Tv}, ω) where Tv
    iω=ω*1im
    matrix=this.matrix
    storderiv=this.storderiv
    grid=this.grid
    nzval=nonzeros(matrix)
    nzval.=this.sysnzval
    U0=this.U0
    for inode=1:num_nodes(grid)
        for idof=_firstnodedof(U0,inode):_lastnodedof(U0,inode)
            for jdof=_firstnodedof(U0,inode):_lastnodedof(U0,inode)
                _addnz(matrix,idof,jdof,storderiv[idof,jdof],iω)
            end
        end
    end
    lufact=LinearAlgebra.lu(matrix)
    ldiv!(values(UZ),lufact,values(this.F))
end



function measurement_derivative(sys,meas,steadystate)
    ndof=num_dof(sys)
    colptr=[i for i in 1:ndof+1]
    rowval=[1 for i in 1:ndof]
    nzval=[1.0 for in in 1:ndof]
    jac=SparseMatrixCSC(1,ndof,colptr,rowval,nzval)
    colors = matrix_colors(jac)
    forwarddiff_color_jacobian!(jac, meas, values(steadystate), colorvec = colors)
    dropzeros!(jac)
    return jac
end

 
function freqdomain_impedance(isys, # frequency domain system
                              ω,   # frequency 
                              steadystate, # steady state slution
                              excited_spec,  # excitated spec
                              excited_bc,  # excitation bc number
                              excited_bcval, # excitation bc value
                              dmeas_stdy,dmeas_tran
                              )
    
    iω=1im*ω
    # solve impedance system
    UZ=unknowns(isys)
    solve!(UZ,isys,ω)
 
    # obtain measurement in frequency  domain
    m_stdy=dmeas_stdy*values(UZ)
    m_tran=dmeas_tran*values(UZ)
    z=m_stdy[1]+iω*m_tran[1]
    return z
end


