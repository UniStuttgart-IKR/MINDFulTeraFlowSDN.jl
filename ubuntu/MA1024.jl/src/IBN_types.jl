function IBNFramework(ibnag::T, ibnfhandlers::Vector{H}, sdn::TFSSDN) where {T <: IBNAttributeGraph, H <: AbstractIBNFHandler}
    ibnfid = AG.graph_attr(ibnag)
    # abstract type : for remote 
    #make_tfs_topo_from_ibnf(...)
    return IBNFramework(DefaultOperationMode(), ibnfid, IntentDAG(), ibnag, ibnfhandlers, sdn)
end
