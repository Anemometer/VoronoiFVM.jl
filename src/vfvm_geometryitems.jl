abstract type AbstractGeometryItem{Tv<:Number, Ti <:Integer} end

##################################################################
"""
$(TYPEDEF)

Structure holding local boundary  node information.

$(TYPEDFIELDS)
"""
mutable struct BNode{Tv, Ti} <: AbstractGeometryItem{Tv, Ti}

    """
    Index in grid
    """
    index::Ti

    """
    Boundary region number
    """
    region::Ti

    """
    Number of species defined in node
    """
    nspec::Ti

    """
    Grid coordinates
    """
    coord::Matrix{Tv}
    
    BNode{Tv,Ti}(sys::AbstractSystem{Tv,Ti}) where {Tv,Ti}  =new(0,0,num_species(sys),coordinates(sys.grid))
end

function _fill!(node::BNode,bfacenodes,bfaceregions,ibnode,ibface)
    K=bfacenodes[ibnode,ibface]
    node.region=bfaceregions[ibface]
    node.index=K
end





##################################################################
"""
$(TYPEDEF)

Structure holding local node information.

$(TYPEDFIELDS)
"""
mutable struct Node{Tv,Ti} <: AbstractGeometryItem{Tv, Ti} 

    """
    Index in grid

    """
    index::Ti
    """
    Inner region number
    """
    region::Ti

    """
    Number of species defined in node
    """
    nspec::Ti

    """
    Number of discretization cell the node is invoked from
    """
    icell::Ti

    """
    Grid coordinates
    """
    coord::Matrix{Tv}

    Node{Tv,Ti}(sys::AbstractSystem{Tv,Ti}) where {Tv,Ti}  =new(zero(Ti),0,num_species(sys),0, coordinates(sys.grid))
end

function _fill!(node::Node,cellnodes,cellregions,inode,icell)
    K=cellnodes[inode,icell]
    node.region=cellregions[icell]
    node.index=K
    node.icell=icell
end


Base.size(node::Node)=(size(node.coord)[1],)

Base.getindex(node::Node, idim)= node.coord[idim,node.index]

##################################################################
"""
$(TYPEDEF)

Structure holding local edge information.

$(TYPEDFIELDS)
"""
mutable struct Edge{Tv,Ti}  <: AbstractGeometryItem{Tv, Ti}

    """
    Index in grid
    """
    index::Ti

    """
    Index 
    """
    node::Vector{Ti}

    """
    Inner region number corresponding to edge
    """
    region::Ti

    """
    Number of species defined in edge
    """
    nspec::Ti

    """
    Number of discretization cell the edge is invoked from
    """
    icell::Ti
    
    """
    Grid coordinates
    """
    coord::Matrix{Tv}
    
    Edge{Tv,Ti}(sys::AbstractSystem{Tv,Ti}) where {Tv,Ti}  =new(0,[0,0],0,num_species(sys),0,coordinates(sys.grid))
end


function _fill!(edge::Edge,cellx,edgenodes,cellregions,iedge,icell, has_celledges) where Tv
    if has_celledges #  cellx==celledges, edgenodes==global_edgenodes
        # If we work with projections of fluxes onto edges,
        # we need to ensure that the edges are accessed with the
        # same orientation without regard of the orientation induced
        # by local cell numbering
        edge.index=cellx[iedge,icell]
        edge.node[1]=edgenodes[1,edge.index]
        edge.node[2]=edgenodes[2,edge.index]
    else # cx==cellnodes, edgenodes== local_edgenodes
        edge.index=0
        edge.node[1]=cellx[edgenodes[1,iedge],icell]
        edge.node[2]=cellx[edgenodes[2,iedge],icell]
    end
    edge.region=cellregions[icell]
    edge.icell=icell
end


Base.size(edge::Edge)=(size(edge.coord)[1],2)
Base.getindex(edge::Edge, idim,inode)= edge.coord[idim,edge.node[inode]]

##################################################################
"""
$(TYPEDSIGNATURES)

Return number of species for edge
"""
num_species(edge::Edge)=edge.nspec


##################################################################
"""
$(TYPEDSIGNATURES)
   
Calculate the length of an edge. 
"""
function meas(edge::Edge)
    l=0.0
    for i=1:size(edge.coord)[1]
        d=edge.coord[i,edge.node[1]]-edge.coord[i,edge.node[2]]
        l=l+d*d
    end
    return sqrt(l)
end

edgelength(edge::Edge)=meas(edge)


"""
$(TYPEDSIGNATURES)

Solution view on first edge node
"""
@inline viewK(edge::Edge,u::AbstractArray)=@views u[1:edge.nspec]


"""
$(TYPEDSIGNATURES)

Solution view on second edge node
"""
@inline viewL(edge::Edge,u::AbstractArray)=@views u[edge.nspec+1:2*edge.nspec]

"""
$(TYPEDSIGNATURES)

Solution view on first edge node
"""
@inline viewK(nspec,u::AbstractArray)=@views u[1:nspec]


"""
$(TYPEDSIGNATURES)

Solution view on second edge node
"""
@inline viewL(nspec,u::AbstractArray)=@views u[nspec+1:2*nspec]
