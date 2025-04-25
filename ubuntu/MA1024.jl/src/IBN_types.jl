function IBNFramework(ibnag::T, ibnfhandlers::Vector{H}, sdn::TFSSDN) where {T <: IBNAttributeGraph, H <: AbstractIBNFHandler}
    ibnfid = AG.graph_attr(ibnag)
    # abstract type : for remote 
    return IBNFramework(DefaultOperationMode(), ibnfid, IntentDAG(), ibnag, ibnfhandlers, sdn)
end
