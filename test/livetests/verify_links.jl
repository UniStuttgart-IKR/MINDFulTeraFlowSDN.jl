using MINDFulTeraFlowSDN, JLD2, MINDFul
import AttributeGraphs as AG

const MINDF = MINDFul

# Load data (same way as graph_creation.jl)
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
println("="^50)

# Get MINDFul neighbors
mindful_neighbors = Dict{Int, Set{Int}}()
for nodeview in nodeviews
    node_id = nodeview.nodeproperties.localnode
    all_neighbors = Set{Int}()
    union!(all_neighbors, nodeview.nodeproperties.inneighbors)
    union!(all_neighbors, nodeview.nodeproperties.outneighbors)
    mindful_neighbors[node_id] = all_neighbors
end

# Get TFS neighbors from OLS inter-node connections
tfs_neighbors = Dict{Int, Set{Int}}()
for (key, uuid) in sdncontroller.device_map
    if length(key) >= 2 && key[2] == :ols
        tfs_neighbors[key[1]] = Set{Int}()
    end
end

for (link_key, link_uuid) in sdncontroller.inter_link_map
    if length(link_key) >= 6
        node1, ep1_id, node2, ep2_id, link_type, direction = link_key
        # Only count OLS-to-OLS connections
        if string(ep1_id) |> x -> startswith(x, "ols_ep_") && 
           string(ep2_id) |> x -> startswith(x, "ols_ep_")
            push!(tfs_neighbors[node1], node2)
            push!(tfs_neighbors[node2], node1)
        end
    end
end

# Verify intra-node connectivity
function verify_intra_node_connectivity(sdn::TeraflowSDN)
    println("\n📍 INTRA-NODE CONNECTIVITY VERIFICATION")
    println("-"^60)
    
    # Get all nodes with devices
    nodes_with_devices = Set{Int}()
    device_counts = Dict{Int, Dict{Symbol, Int}}()
    
    for (key, uuid) in sdn.device_map
        node_id, device_type = key
        push!(nodes_with_devices, node_id)
        
        if !haskey(device_counts, node_id)
            device_counts[node_id] = Dict{Symbol, Int}()
        end
        
        # Count main devices (not endpoints)
        main_device = if device_type == :router
            :router
        elseif device_type == :oxc  
            :oxc
        elseif device_type == :ols
            :ols
        elseif string(device_type) |> x -> startswith(x, "tm_") && !contains(x, "_ep_")
            :tm
        else
            nothing
        end
        
        if main_device !== nothing
            device_counts[node_id][main_device] = get(device_counts[node_id], main_device, 0) + 1
        end
    end
    
    # Check intra-node links
    expected_links_per_node = 6  # 2 router-tm + 2 tm-oxc + 2 oxc-ols
    nodes_with_complete_links = 0
    
    for node_id in sort(collect(nodes_with_devices))
        devices = get(device_counts, node_id, Dict())
        
        # Count intra-node links for this node
        node_intra_links = 0
        router_tm_links = 0
        tm_oxc_links = 0
        oxc_ols_links = 0
        
        for ((link_node, link_type), link_uuid) in sdn.intra_link_map
            if link_node == node_id
                node_intra_links += 1
                link_type_str = string(link_type)
                
                if startswith(link_type_str, "router_tm_link")
                    router_tm_links += 1
                elseif startswith(link_type_str, "tm_oxc_link")
                    tm_oxc_links += 1
                elseif startswith(link_type_str, "oxc_ols_link")
                    oxc_ols_links += 1
                end
            end
        end
        
        # Check completeness
        has_router = get(devices, :router, 0) > 0
        has_tm = get(devices, :tm, 0) > 0
        has_oxc = get(devices, :oxc, 0) > 0
        has_ols = get(devices, :ols, 0) > 0
        
        complete_devices = has_router && has_tm && has_oxc && has_ols
        complete_links = (router_tm_links == 2) && (tm_oxc_links == 2) && (oxc_ols_links == 2)
        
        if complete_devices && complete_links
            nodes_with_complete_links += 1
            println("✅ Node $node_id: Complete (R-TM:$router_tm_links, TM-OXC:$tm_oxc_links, OXC-OLS:$oxc_ols_links)")
        else
            status_parts = []
            if !has_router; push!(status_parts, "no router"); end
            if !has_tm; push!(status_parts, "no TM"); end
            if !has_oxc; push!(status_parts, "no OXC"); end
            if !has_ols; push!(status_parts, "no OLS"); end
            if router_tm_links != 2; push!(status_parts, "R-TM:$router_tm_links≠2"); end
            if tm_oxc_links != 2; push!(status_parts, "TM-OXC:$tm_oxc_links≠2"); end
            if oxc_ols_links != 2; push!(status_parts, "OXC-OLS:$oxc_ols_links≠2"); end
            
            println("⚠️  Node $node_id: Incomplete ($(join(status_parts, ", ")))")
        end
    end
    
    total_nodes = length(nodes_with_devices)
    println("\nIntra-node Summary: $nodes_with_complete_links/$total_nodes nodes fully connected ($(round(nodes_with_complete_links/total_nodes*100))%)")
    
    return nodes_with_complete_links, total_nodes
end

# Verify inter-node connectivity  
function verify_inter_node_connectivity(mindful_neighbors, tfs_neighbors, sdn::TeraflowSDN)
    println("\n🌐 INTER-NODE CONNECTIVITY VERIFICATION")
    println("-"^60)
    
    matches = 0
    total = 0
    perfect_matches = 0
    
    for (node, mindful_neighs) in mindful_neighbors
        total += 1
        tfs_neighs = get(tfs_neighbors, node, Set{Int}())
        
        if mindful_neighs == tfs_neighs
            matches += 1
            perfect_matches += 1
            println("✅ Node $node: Perfect match ($(length(mindful_neighs)) neighbors)")
        else
            overlap = intersect(mindful_neighs, tfs_neighs)
            missing = setdiff(mindful_neighs, tfs_neighs)
            extra = setdiff(tfs_neighs, mindful_neighs)
            
            if !isempty(overlap) && isempty(missing) && isempty(extra)
                matches += 1
                println("✅ Node $node: Complete match ($(length(overlap)) neighbors)")
            elseif !isempty(overlap)
                println("⚠️  Node $node: Partial match")
                println("   ✓ Connected: $overlap")
                if !isempty(missing)
                    println("   ✗ Missing: $missing")
                end
                if !isempty(extra)
                    println("   ➕ Extra: $extra")
                end
            else
                println("❌ Node $node: No matches")
                println("   Expected: $mindful_neighs")
                println("   Found: $tfs_neighs")
            end
        end
    end
    
    # Additional verification: Check if each connection has both directions
    bidirectional_complete = 0
    total_connections = 0
    
    println("\n🔄 BIDIRECTIONAL LINK VERIFICATION")
    println("-"^40)
    
    connection_pairs = Set{Tuple{Int,Int}}()
    for (link_key, link_uuid) in sdn.inter_link_map
        if length(link_key) >= 6
            node1, ep1_id, node2, ep2_id, link_type, direction = link_key
            if string(ep1_id) |> x -> startswith(x, "ols_ep_")
                pair = node1 < node2 ? (node1, node2) : (node2, node1)
                push!(connection_pairs, pair)
            end
        end
    end
    
    for (node1, node2) in sort(collect(connection_pairs))
        total_connections += 1
        
        # Check for both directions
        has_outgoing = any(k -> (k[1] == node1 && k[3] == node2 && k[6] == :outgoing), keys(sdn.inter_link_map))
        has_incoming = any(k -> (k[1] == node2 && k[3] == node1 && k[6] == :incoming), keys(sdn.inter_link_map))
        
        if has_outgoing && has_incoming
            bidirectional_complete += 1
            println("✅ $node1 ↔ $node2: Bidirectional complete")
        else
            directions = []
            if has_outgoing; push!(directions, "$node1→$node2"); end
            if has_incoming; push!(directions, "$node2→$node1"); end
            println("⚠️  $node1 ↔ $node2: Only $(join(directions, ", "))")
        end
    end
    
    println("\nInter-node Summary:")
    println("  Topology matches: $perfect_matches/$total perfect matches ($(round(perfect_matches/total*100))%)")
    println("  Bidirectional links: $bidirectional_complete/$total_connections complete ($(round(bidirectional_complete/total_connections*100))%)")
    
    return perfect_matches, matches, total
end

# Verify endpoint usage
function verify_endpoint_usage(sdn::TeraflowSDN)
    println("\n📡 ENDPOINT USAGE VERIFICATION")
    println("-"^60)
    
    # Count endpoints by type and usage
    endpoint_stats = Dict{String, Dict{String, Int}}()
    
    for (key, uuid) in sdn.device_map
        if length(key) >= 2
            node_id, endpoint_type = key
            endpoint_type_str = string(endpoint_type)
            
            # Categorize endpoint
            category = if startswith(endpoint_type_str, "router_ep_")
                "Router"
            elseif startswith(endpoint_type_str, "tm_") && contains(endpoint_type_str, "_copper_ep_")
                "TM-Copper"
            elseif startswith(endpoint_type_str, "tm_") && contains(endpoint_type_str, "_fiber_ep_")
                "TM-Fiber"
            elseif startswith(endpoint_type_str, "oxc_ep_")
                "OXC"
            elseif startswith(endpoint_type_str, "ols_ep_")
                "OLS"
            else
                continue  # Skip main devices
            end
            
            if !haskey(endpoint_stats, category)
                endpoint_stats[category] = Dict("total" => 0, "used" => 0)
            end
            
            endpoint_stats[category]["total"] += 1
            if get(sdn.endpoint_usage, uuid, false)
                endpoint_stats[category]["used"] += 1
            end
        end
    end
    
    # Display stats - sort by category name only
    for category in sort(collect(keys(endpoint_stats)))
        stats = endpoint_stats[category]
        used = stats["used"]
        total = stats["total"]
        percentage = total > 0 ? round(used/total*100, digits=1) : 0.0
        println("  $category: $used/$total used ($percentage%)")
    end
    
    # Overall usage
    total_used = sum(stats["used"] for stats in values(endpoint_stats))
    total_endpoints = sum(stats["total"] for stats in values(endpoint_stats))
    overall_percentage = total_endpoints > 0 ? round(total_used/total_endpoints*100, digits=1) : 0.0
    
    println("\nOverall Endpoint Usage: $total_used/$total_endpoints ($overall_percentage%)")
    
    return total_used, total_endpoints
end

# Run all verifications
println("Running comprehensive network verification...\n")

# 1. Verify intra-node connectivity
intra_complete, intra_total = verify_intra_node_connectivity(sdncontroller)

# 2. Verify inter-node connectivity
inter_perfect, inter_connected, inter_total = verify_inter_node_connectivity(mindful_neighbors, tfs_neighbors, sdncontroller)

# 3. Verify endpoint usage
used_endpoints, total_endpoints = verify_endpoint_usage(sdncontroller)

# Final summary
println("\n" * "="^60)
println("🏁 FINAL VERIFICATION SUMMARY")
println("="^60)

println("📍 Intra-node: $intra_complete/$intra_total nodes fully connected ($(round(intra_complete/intra_total*100, digits=1))%)")
println("🌐 Inter-node: $inter_perfect/$inter_total perfect topology matches ($(round(inter_perfect/inter_total*100, digits=1))%)")
println("📡 Endpoints: $used_endpoints/$total_endpoints in use ($(round(used_endpoints/total_endpoints*100, digits=1))%)")

# Overall health score
connectivity_score = (intra_complete/intra_total + inter_perfect/inter_total) / 2 * 100
endpoint_efficiency = used_endpoints/total_endpoints * 100

println("\n🎯 Network Health:")
println("   Connectivity Score: $(round(connectivity_score, digits=1))%")
println("   Endpoint Efficiency: $(round(endpoint_efficiency, digits=1))%")
