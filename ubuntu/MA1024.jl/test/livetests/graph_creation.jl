using MA1024, JSON3
using MA1024.TFS
using JLD2, UUIDs
using MINDFul
import AttributeGraphs as AG

const MINDF = MINDFul

# load data
domains_name_graph = first(JLD2.load("data/itz_IowaStatewideFiberMap-itz_Missouri__(1,9)-(2,3),(1,6)-(2,54),(1,1)-(2,21).jld2"))[2]
println("Imported graph")
ag1 = first(domains_name_graph)[2]

ibnag1 = MINDF.default_IBNAttributeGraph(ag1)

# Prepare all required arguments
operationmode = MINDF.DefaultOperationMode()
ibnfid = AG.graph_attr(ibnag1) 
intentdag = MINDF.IntentDAG()
ibnfhandlers = MINDF.AbstractIBNFHandler[]
sdncontroller = TeraflowSDN()
load_device_map!("data/device_map.jld2", sdncontroller)

# Now call the full constructor
ibnf1 = MINDF.IBNFramework(operationmode, ibnfid, intentdag, ibnag1, ibnfhandlers, sdncontroller)

ibnag = MINDF.getibnag(ibnf1)                       
nodeviews = MINDF.getnodeviews(ibnag)
println("Loaded IBN graph with $(length(nodeviews)) nodeviews")

println("\n=== Creating Devices ===")
for nodeview in nodeviews
    # If you want to see which node: 
    println("Processing node: ", nodeview.nodeproperties.localnode)  # if nodeview has a getnode method
    push_node_devices_to_tfs(nodeview, sdncontroller)
end

println("\n=== Saving Device Map ===")
save_device_map("data/device_map.jld2", sdncontroller)
println("✓ Device map saved with $(length(sdncontroller.device_map)) entries")

# Create all network links after devices are created
intra_links, inter_links = create_all_network_links(sdncontroller, nodeviews)

println("\n=== Final Save ===")
save_device_map("data/device_map.jld2", sdncontroller)
println("✓ Final device map saved with all devices and links")

println("\n=== Process Complete ===")
println("Total devices and endpoints: $(length(sdncontroller.device_map))")
println("Total intra-node links: $(length(sdncontroller.intra_link_map))")
println("Total inter-node links: $(length(sdncontroller.inter_link_map))")
println("Intra-node links created: $intra_links") 
println("Inter-node links created: $inter_links")
