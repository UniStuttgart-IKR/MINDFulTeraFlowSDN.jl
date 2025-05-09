using MA1024, JSON3
using MA1024.TFS
using JLD2, UUIDs
using MINDFul
import AttributeGraphs as AG

const MINDF = MINDFul

uuid  = "c944aaeb-bbdf-5f2d-b31c-8cc8903045b6"

# load data
domains_name_graph = first(JLD2.load("data/itz_IowaStatewideFiberMap-itz_Missouri__(1,9)-(2,3),(1,6)-(2,54),(1,1)-(2,21).jld2"))[2]
println("Loaded graph")
ag1 = first(domains_name_graph)[2]

ibnag1 = MINDF.default_IBNAttributeGraph(ag1)

tfs_sdn = TeraflowSDN()

# Prepare all required arguments
operationmode = MINDF.DefaultOperationMode()
ibnfid = AG.graph_attr(ibnag1)  # AG is likely AttributeGraphs
intentdag = MINDF.IntentDAG()
ibnfhandlers = MINDF.AbstractIBNFHandler[]  # or your handlers
sdncontroller = tfs_sdn

# Now call the full constructor
ibnf1 = MINDF.IBNFramework(operationmode, ibnfid, intentdag, ibnag1, ibnfhandlers, sdncontroller)

# Fetch RouterView for node 10
node_id = 10
routerview = MINDF.getrouterview(MINDF.getnodeview(ibnf1, node_id))

if routerview !== nothing
    # Create a config rule from routerview
    port = routerview_to_configrule(routerview)

    rule = Ctx.ConfigRule(
    Ctx.ConfigActionEnum.CONFIGACTION_SET,
    OneOf(:custom,
            Ctx.ConfigRule_Custom(
                "/router-port",
                JSON3.write(Dict(
                    "port"               => "$port",
                )))
    ))
    # Use the same uuid as before
    ok = add_config_rule!(uuid, [rule])
    println(ok ? "\n✓ rule added from routerview\n" : "\n✗ PUT failed\n")
else
    println("No RouterView for node $node_id")
end