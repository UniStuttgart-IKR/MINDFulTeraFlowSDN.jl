using MA1024, JSON3
using MA1024.TFS
using JLD2, UUIDs
using MINDFul
import AttributeGraphs as AG

const MINDF = MINDFul

uuid  = "0dff8c06-873b-5799-ac54-c0452252bae1"

# load data
domains_name_graph = first(JLD2.load("data/itz_IowaStatewideFiberMap-itz_Missouri__(1,9)-(2,3),(1,6)-(2,54),(1,1)-(2,21).jld2"))[2]
println("Loaded graph")
ag1 = first(domains_name_graph)[2]

ibnag1 = MINDF.default_IBNAttributeGraph(ag1)

# Prepare all required arguments
operationmode = MINDF.DefaultOperationMode()
ibnfid = AG.graph_attr(ibnag1)  # AG is likely AttributeGraphs
intentdag = MINDF.IntentDAG()
ibnfhandlers = MINDF.AbstractIBNFHandler[]  # or your handlers
sdncontroller = TeraflowSDN()

# Now call the full constructor
ibnf1 = MINDF.IBNFramework(operationmode, ibnfid, intentdag, ibnag1, ibnfhandlers, sdncontroller)

# Get all contexts
contexts_json = get_contexts(sdncontroller.api_url)
context_uuid = contexts_json["contexts"][1]["context_id"]["context_uuid"]["uuid"]

# Get all topologies for this context
topologies_json = get_topologies(sdncontroller.api_url, context_uuid)
topology_uuid = topologies_json["topologies"][1]["topology_id"]["topology_uuid"]["uuid"]

println("Using context_uuid: $context_uuid")
println("Using topology_uuid: $topology_uuid")

# Fetch RouterView for node 10
node_id = 10
nodeview = MINDF.getnodeview(ibnf1, node_id)
println("Fetched nodeview for node $node_id")
# println(nodeview)
push_node_devices_to_tfs(nodeview, sdncontroller, context_uuid, topology_uuid)

# if routerview !== nothing
#     # Create a config rule from routerview
#     ports = routerview_to_configrule(routerview)

#     rule = Ctx.ConfigRule(
#     Ctx.ConfigActionEnum.CONFIGACTION_SET,
#     OneOf(:custom,
#             Ctx.ConfigRule_Custom(
#                 "/router-ports",
#                 JSON3.write(Dict(
#                     "ports"               => "$ports",
#                 )))
#     ))
#     # Use the same uuid as before
#     ok = add_config_rule!(sdncontroller.api_url,  uuid, [rule])
#     println(ok ? "\n✓ rule added from routerview\n" : "\n✗ PUT failed\n")
# else
#     println("No RouterView for node $node_id")
# end