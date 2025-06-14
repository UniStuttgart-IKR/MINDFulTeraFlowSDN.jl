using MA1024, JLD2, MINDFul
import AttributeGraphs as AG

const MINDF = MINDFul

"""
    verify_tfs_devices_and_links(sdn::TeraflowSDN, nodeviews)

Focused verification that checks:
1. Are expected devices present in TFS based on device_map?
2. Are intra-node links properly created in TFS?
3. Are inter-node links matching MINDFul topology in TFS?
"""
function verify_tfs_devices_and_links(sdn::TeraflowSDN, nodeviews)
    println("\n🔍 FOCUSED TFS VERIFICATION")
    println("="^60)
    
    # Get actual TFS state
    println("📡 Fetching TFS devices and links...")
    tfs_devices = get_devices(sdn.api_url)
    tfs_links = get_links(sdn.api_url)
    
    println("   Found $(length(tfs_devices["devices"])) devices in TFS")
    println("   Found $(length(tfs_links["links"])) links in TFS")
    
    # Extract MINDFul topology
    mindful_neighbors = get_mindful_topology(nodeviews)
    
    # Run verifications
    device_results = verify_devices_against_map(sdn, tfs_devices)
    intra_results = verify_intra_links(sdn, tfs_links)
    inter_results = verify_inter_links(sdn, tfs_links, mindful_neighbors)
    
    # Generate focused report
    generate_focused_report(device_results, intra_results, inter_results)
    
    return (device_results, intra_results, inter_results)
end

function get_mindful_topology(nodeviews)
    """Extract expected topology from MINDFul"""
    neighbors = Dict{Int, Set{Int}}()
    nodes_with_devices = Set{Int}()
    
    for nodeview in nodeviews
        node_id = nodeview.nodeproperties.localnode
        push!(nodes_with_devices, node_id)
        
        all_neighbors = Set{Int}()
        union!(all_neighbors, nodeview.nodeproperties.inneighbors)
        union!(all_neighbors, nodeview.nodeproperties.outneighbors)
        neighbors[node_id] = all_neighbors
    end
    
    return Dict(:neighbors => neighbors, :nodes => nodes_with_devices)
end

function verify_devices_against_map(sdn::TeraflowSDN, tfs_devices)
    """Check if devices in device_map exist in TFS"""
    println("\n📱 DEVICE VERIFICATION")
    println("-"^40)
    
    # Extract expected devices from device_map
    expected_devices = Dict{String, Tuple{Int, Symbol}}()  # uuid => (node_id, device_type)
    nodes_devices = Dict{Int, Set{Symbol}}()  # node_id => set of device types
    
    for (key, uuid) in sdn.device_map
        if length(key) == 2
            node_id, device_type = key
            # Only main devices, not endpoints
            if device_type in [:router, :oxc, :ols] || (string(device_type) |> x -> startswith(x, "tm_") && !contains(x, "_ep_"))
                expected_devices[uuid] = (node_id, device_type)
                
                if !haskey(nodes_devices, node_id)
                    nodes_devices[node_id] = Set{Symbol}()
                end
                push!(nodes_devices[node_id], device_type)
            end
        end
    end
    
    # Extract actual devices from TFS
    tfs_device_uuids = Set(dev["device_id"]["device_uuid"]["uuid"] for dev in tfs_devices["devices"])
    
    # Check matches
    found_devices = intersect(Set(keys(expected_devices)), tfs_device_uuids)
    missing_devices = setdiff(Set(keys(expected_devices)), tfs_device_uuids)
    
    println("✅ Devices found in TFS: $(length(found_devices))/$(length(expected_devices))")
    
    # Analyze by node and device type
    nodes_complete = 0
    nodes_incomplete = 0
    missing_by_node = Dict{Int, Vector{Symbol}}()
    
    for (node_id, expected_types) in nodes_devices
        found_types = Set{Symbol}()
        
        for uuid in found_devices
            if haskey(expected_devices, uuid)
                dev_node, dev_type = expected_devices[uuid]
                if dev_node == node_id
                    push!(found_types, dev_type)
                end
            end
        end
        
        missing_types = setdiff(expected_types, found_types)
        
        if isempty(missing_types)
            nodes_complete += 1
            println("✅ Node $node_id: All devices present ($(join(string.(expected_types), ", ")))")
        else
            nodes_incomplete += 1
            missing_by_node[node_id] = collect(missing_types)
            println("❌ Node $node_id: Missing $(join(string.(missing_types), ", "))")
            println("   Expected: $(join(string.(expected_types), ", "))")
            println("   Found: $(join(string.(found_types), ", "))")
        end
    end
    
    # Show missing device details
    if !isempty(missing_devices)
        println("\n❌ MISSING DEVICES DETAILS:")
        for uuid in missing_devices
            if haskey(expected_devices, uuid)
                node_id, device_type = expected_devices[uuid]
                println("   $uuid → Node $node_id $device_type")
            end
        end
    end
    
    return Dict(
        :total_expected => length(expected_devices),
        :found_in_tfs => length(found_devices),
        :missing_count => length(missing_devices),
        :nodes_complete => nodes_complete,
        :nodes_incomplete => nodes_incomplete,
        :missing_by_node => missing_by_node,
        :missing_devices => missing_devices
    )
end

function verify_intra_links(sdn::TeraflowSDN, tfs_links)
    """Check if intra-node links exist in TFS"""
    println("\n🔗 INTRA-NODE LINK VERIFICATION")
    println("-"^45)
    
    # Extract expected intra-node links
    expected_intra = Set(keys(sdn.intra_link_map))
    expected_uuids = Set(values(sdn.intra_link_map))
    
    # Extract TFS link UUIDs
    tfs_link_uuids = Set(link["link_id"]["link_uuid"]["uuid"] for link in tfs_links["links"])
    
    # Check matches
    found_links = intersect(expected_uuids, tfs_link_uuids)
    missing_links = setdiff(expected_uuids, tfs_link_uuids)
    
    println("✅ Intra-node links found: $(length(found_links))/$(length(expected_uuids))")
    
    # Analyze by node and link type
    nodes_with_complete_intra = 0
    intra_by_node = Dict{Int, Dict{Symbol, Bool}}()
    
    for ((node_id, link_type), uuid) in sdn.intra_link_map
        if !haskey(intra_by_node, node_id)
            intra_by_node[node_id] = Dict{Symbol, Bool}()
        end
        intra_by_node[node_id][link_type] = uuid in found_links
    end
    
    # Sort the node IDs explicitly instead of the whole pairs
    sorted_node_ids = sort(collect(keys(intra_by_node)))
    
    for node_id in sorted_node_ids
        link_status = intra_by_node[node_id]
        all_present = all(values(link_status))
        
        if all_present
            nodes_with_complete_intra += 1
            link_types = collect(keys(link_status))
            println("✅ Node $node_id: All $(length(link_types)) intra-links present")
        else
            missing_link_types = [lt for (lt, present) in link_status if !present]
            present_link_types = [lt for (lt, present) in link_status if present]
            
            println("❌ Node $node_id: Missing $(length(missing_link_types)) intra-links")
            println("   ✓ Present: $(join(string.(present_link_types), ", "))")
            println("   ✗ Missing: $(join(string.(missing_link_types), ", "))")
        end
    end
    
    # Show missing link details
    if !isempty(missing_links)
        println("\n❌ MISSING INTRA-LINK DETAILS:")
        for ((node_id, link_type), uuid) in sdn.intra_link_map
            if uuid in missing_links
                println("   $uuid → Node $node_id $link_type")
            end
        end
    end
    
    return Dict(
        :total_expected => length(expected_uuids),
        :found_in_tfs => length(found_links),
        :missing_count => length(missing_links),
        :nodes_complete => nodes_with_complete_intra,
        :total_nodes => length(intra_by_node),
        :missing_links => missing_links
    )
end

function verify_inter_links(sdn::TeraflowSDN, tfs_links, mindful_topology)
    """Check if inter-node links match MINDFul topology"""
    println("\n🌐 INTER-NODE LINK VERIFICATION")
    println("-"^45)
    
    mindful_neighbors = mindful_topology[:neighbors]
    
    # Extract expected inter-node links from device map
    expected_inter_uuids = Set(values(sdn.inter_link_map))
    
    # Extract TFS link UUIDs
    tfs_link_uuids = Set(link["link_id"]["link_uuid"]["uuid"] for link in tfs_links["links"])
    
    # Check matches
    found_inter_links = intersect(expected_inter_uuids, tfs_link_uuids)
    missing_inter_links = setdiff(expected_inter_uuids, tfs_link_uuids)
    
    println("✅ Inter-node links found: $(length(found_inter_links))/$(length(expected_inter_uuids))")
    
    # Analyze topology coverage
    # Extract actual connections from our inter-link map
    actual_connections = Dict{Int, Set{Int}}()
    
    for (link_key, uuid) in sdn.inter_link_map
        if length(link_key) >= 6
            node1, ep1_id, node2, ep2_id, _, direction = link_key
            # Only count if link exists in TFS
            if uuid in found_inter_links
                if !haskey(actual_connections, node1)
                    actual_connections[node1] = Set{Int}()
                end
                push!(actual_connections[node1], node2)
            end
        end
    end
    
    # Compare with MINDFul expectations
    topology_matches = 0
    topology_partial = 0
    topology_missing = 0
    
    missing_connections = Dict{Int, Set{Int}}()
    
    for (node_id, expected_neighbors) in mindful_neighbors
        actual_neighbors = get(actual_connections, node_id, Set{Int}())
        
        if expected_neighbors == actual_neighbors
            topology_matches += 1
            println("✅ Node $node_id: Perfect topology match ($(length(expected_neighbors)) neighbors)")
        else
            missing_neighs = setdiff(expected_neighbors, actual_neighbors)
            extra_neighs = setdiff(actual_neighbors, expected_neighbors)
            common_neighs = intersect(expected_neighbors, actual_neighbors)
            
            if !isempty(common_neighs)
                topology_partial += 1
                println("⚠️  Node $node_id: Partial match ($(length(common_neighs))/$(length(expected_neighbors)) neighbors)")
            else
                topology_missing += 1
                println("❌ Node $node_id: No connections found")
            end
            
            if !isempty(missing_neighs)
                missing_connections[node_id] = missing_neighs
                println("   Missing connections to: $(collect(missing_neighs))")
            end
            if !isempty(extra_neighs)
                println("   Extra connections to: $(collect(extra_neighs))")
            end
        end
    end
    
    # Show missing inter-link details
    if !isempty(missing_inter_links)
        println("\n❌ MISSING INTER-LINK DETAILS:")
        for (link_key, uuid) in sdn.inter_link_map
            if uuid in missing_inter_links && length(link_key) >= 6
                node1, ep1_id, node2, ep2_id, _, direction = link_key
                println("   $uuid → $node1($ep1_id) ↔ $node2($ep2_id) [$direction]")
            end
        end
    end
    
    return Dict(
        :total_expected => length(expected_inter_uuids),
        :found_in_tfs => length(found_inter_links),
        :missing_count => length(missing_inter_links),
        :topology_perfect => topology_matches,
        :topology_partial => topology_partial,
        :topology_missing => topology_missing,
        :total_nodes => length(mindful_neighbors),
        :missing_connections => missing_connections,
        :missing_links => missing_inter_links
    )
end

function generate_focused_report(device_results, intra_results, inter_results)
    """Generate focused verification report"""
    println("\n" * "="^60)
    println("🏁 FOCUSED VERIFICATION SUMMARY")
    println("="^60)
    
    # Device summary
    dev_health = (device_results[:found_in_tfs] / max(device_results[:total_expected], 1)) * 100
    println("📱 Devices: $(device_results[:found_in_tfs])/$(device_results[:total_expected]) found ($(round(dev_health, digits=1))%)")
    println("   Complete nodes: $(device_results[:nodes_complete])")
    println("   Incomplete nodes: $(device_results[:nodes_incomplete])")
    
    # Intra-link summary
    intra_health = (intra_results[:found_in_tfs] / max(intra_results[:total_expected], 1)) * 100
    println("🔗 Intra-links: $(intra_results[:found_in_tfs])/$(intra_results[:total_expected]) found ($(round(intra_health, digits=1))%)")
    println("   Complete nodes: $(intra_results[:nodes_complete])/$(intra_results[:total_nodes])")
    
    # Inter-link summary  
    inter_health = (inter_results[:found_in_tfs] / max(inter_results[:total_expected], 1)) * 100
    println("🌐 Inter-links: $(inter_results[:found_in_tfs])/$(inter_results[:total_expected]) found ($(round(inter_health, digits=1))%)")
    println("   Perfect topology: $(inter_results[:topology_perfect])/$(inter_results[:total_nodes])")
    println("   Partial topology: $(inter_results[:topology_partial])/$(inter_results[:total_nodes])")
    
    # Overall health
    overall_health = (dev_health + intra_health + inter_health) / 3
    println("\n🎯 Overall Health: $(round(overall_health, digits=1))%")
    
    println("\n🔍 KEY ISSUES ANALYSIS")
    println("-"^40)
    
    issues_found = false
    
    # Key issues summary
    # Device issues
    if device_results[:missing_count] > 0
        issues_found = true
        println("❌ DEVICE ISSUES:")
        println("   • $(device_results[:missing_count]) devices missing from TFS")
        if !isempty(device_results[:missing_by_node])
            println("   • Affected nodes: $(join(sort(collect(keys(device_results[:missing_by_node]))), ", "))")
        end
    else
        println("✅ DEVICES: All $(device_results[:total_expected]) devices present in TFS")
    end
    
    # Intra-link issues
    if intra_results[:missing_count] > 0
        issues_found = true
        println("\n❌ INTRA-NODE LINK ISSUES:")
        println("   • $(intra_results[:missing_count]) intra-node links missing from TFS")
        incomplete_nodes = intra_results[:total_nodes] - intra_results[:nodes_complete]
        if incomplete_nodes > 0
            println("   • $incomplete_nodes nodes have incomplete internal connectivity")
        end
    else
        println("\n✅ INTRA-LINKS: All $(intra_results[:total_expected]) internal links present in TFS")
    end
    
    # Inter-link issues
    if inter_results[:missing_count] > 0
        issues_found = true
        println("\n❌ INTER-NODE LINK ISSUES:")
        println("   • $(inter_results[:missing_count]) inter-node links missing from TFS")
    else
        println("\n✅ INTER-LINKS: All $(inter_results[:total_expected]) inter-node links present in TFS")
    end
    
    # Topology connectivity issues
    if !isempty(inter_results[:missing_connections])
        issues_found = true
        total_missing_connections = sum(length(v) for v in values(inter_results[:missing_connections]))
        println("\n❌ TOPOLOGY CONNECTIVITY ISSUES:")
        println("   • $total_missing_connections network connections not established")
        println("   • $(inter_results[:topology_missing]) nodes have no connections")
        println("   • $(inter_results[:topology_partial]) nodes have partial connections")
        
        # Show specific missing connections
        println("\n   📋 Missing connections details:")
        for node_id in sort(collect(keys(inter_results[:missing_connections])))
            missing_neighbors = inter_results[:missing_connections][node_id]
            neighbors_str = join(sort(collect(missing_neighbors)), ", ")
            println("      Node $node_id → [$neighbors_str]")
        end
    else
        println("\n✅ TOPOLOGY: All expected network connections established")
    end
    
    println("="^60)
    
    return overall_health
end

# Main execution function
function run_focused_verification()
    # Load data
    domains_name_graph = first(JLD2.load("data/itz_IowaStatewideFiberMap-itz_Missouri__(1,9)-(2,3),(1,6)-(2,54),(1,1)-(2,21).jld2"))[2]
    println("Loaded graph")
    ag1 = first(domains_name_graph)[2]
    
    ibnag1 = MINDF.default_IBNAttributeGraph(ag1)
    
    # Prepare framework
    operationmode = MINDF.DefaultOperationMode()
    ibnfid = AG.graph_attr(ibnag1) 
    intentdag = MINDF.IntentDAG()
    ibnfhandlers = MINDF.AbstractIBNFHandler[]
    sdncontroller = TeraflowSDN()
    
    # Load device/link maps
    if isfile("data/device_map.jld2")
        load_device_map!("data/device_map.jld2", sdncontroller)
        println("✓ Loaded device and link maps")
    else
        println("❌ No device map found - cannot verify")
        return nothing
    end
    
    # Create framework
    ibnf1 = MINDF.IBNFramework(operationmode, ibnfid, intentdag, ibnag1, ibnfhandlers, sdncontroller)
    ibnag = MINDF.getibnag(ibnf1)
    nodeviews = MINDF.getnodeviews(ibnag)
    
    println("📋 Verification scope: $(length(nodeviews)) nodes")
    println("📋 Device map entries: $(length(sdncontroller.device_map))")
    println("📋 Intra-link entries: $(length(sdncontroller.intra_link_map))")
    println("📋 Inter-link entries: $(length(sdncontroller.inter_link_map))")
    
    # Run verification
    verify_tfs_devices_and_links(sdncontroller, nodeviews)
    return nothing
end

# Execute the verification
run_focused_verification()