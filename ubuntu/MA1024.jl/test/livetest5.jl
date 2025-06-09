using MA1024, MA1024.TFS, JLD2, MINDFul
import AttributeGraphs as AG

const MINDF = MINDFul

# Load data (same way as livetest3.jl)
domains_name_graph = first(JLD2.load("data/itz_IowaStatewideFiberMap-itz_Missouri__(1,9)-(2,3),(1,6)-(2,54),(1,1)-(2,21).jld2"))[2]
println("Loaded graph")
ag1 = first(domains_name_graph)[2]

ibnag1 = MINDF.default_IBNAttributeGraph(ag1)

# Prepare all required arguments
operationmode = MINDF.DefaultOperationMode()
ibnfid = AG.graph_attr(ibnag1) 
intentdag = MINDF.IntentDAG()
ibnfhandlers = MINDF.AbstractIBNFHandler[]
sdncontroller = TeraflowSDN()

# Load existing device/link maps
if isfile("data/device_map.jld2")
    load_device_map!("data/device_map.jld2", sdncontroller)
end

# Now call the full constructor
ibnf1 = MINDF.IBNFramework(operationmode, ibnfid, intentdag, ibnag1, ibnfhandlers, sdncontroller)

ibnag = MINDF.getibnag(ibnf1)
nodeviews = MINDF.getnodeviews(ibnag)

println("🔍 CONNECTION VERIFICATION")
println("="^40)

# Get MINDFul neighbors
mindful_neighbors = Dict{Int, Set{Int}}()
for nodeview in nodeviews
    node_id = nodeview.nodeproperties.localnode
    all_neighbors = Set{Int}()
    union!(all_neighbors, nodeview.nodeproperties.inneighbors)
    union!(all_neighbors, nodeview.nodeproperties.outneighbors)
    mindful_neighbors[node_id] = all_neighbors
end

# Get TFS neighbors  
tfs_neighbors = Dict{Int, Set{Int}}()
for (key, uuid) in sdncontroller.device_map
    if length(key) >= 2 && key[2] == :oxc
        tfs_neighbors[key[1]] = Set{Int}()
    end
end

for (link_key, link_uuid) in sdncontroller.inter_link_map
    if length(link_key) >= 6
        node1, ep1_id, node2, ep2_id, link_type, direction = link_key
        push!(tfs_neighbors[node1], node2)
        push!(tfs_neighbors[node2], node1)
    end
end

# Add this function after loading the data:
function verify_connections(mindful_neighbors, tfs_neighbors)
    matches = 0
    total = 0
    
    for (node, mindful_neighs) in mindful_neighbors
        total += 1
        tfs_neighs = get(tfs_neighbors, node, Set{Int}())
        
        if mindful_neighs == tfs_neighs
            matches += 1
            println("✅ Node $node: Perfect match")
        else
            overlap = intersect(mindful_neighs, tfs_neighs)
            missing = setdiff(mindful_neighs, tfs_neighs)
            extra = setdiff(tfs_neighs, mindful_neighs)
            
            if !isempty(overlap)
                println("⚠️  Node $node: Partial match ($overlap)")
            else
                println("❌ Node $node: No match")
            end
            
            if !isempty(missing)
                println("   Missing: $missing")
            end
        end
    end
    
    println("\nRESULT: $matches/$total perfect matches ($(round(matches/total*100))%)")
end

# Then call it:
verify_connections(mindful_neighbors, tfs_neighbors)