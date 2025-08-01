using MINDFulTeraFlowSDN, JLD2, MINDFul
import AttributeGraphs as AG

const MINDF = MINDFul

"""
    verify_tfs_devices_and_links(sdn::TeraflowSDN, nodeviews)

Focused verification that checks:
1. Are expected devices present in TFS based on device_map?
2. Are intra-node links properly created in TFS (ALL TMs linked)?
3. Are inter-node links matching MINDFul topology in TFS?
"""
function verify_tfs_devices_and_links(sdn::TeraflowSDN, nodeviews)
    println("\n🔍 FOCUSED TFS VERIFICATION (Multi-TM Architecture)")
    println("="^65)
    
    # Get actual TFS state
    println("📡 Fetching TFS devices and links...")
    tfs_devices = get_devices(sdn.api_url)
    tfs_links = get_links(sdn.api_url)
    
    println("   Found $(length(tfs_devices["devices"])) devices in TFS")
    println("   Found $(length(tfs_links["links"])) links in TFS")
    
    # Extract MINDFul topology
    mindful_neighbors = get_mindful_topology(nodeviews)
    
    # Run verifications
    device_results = verify_devices_against_map(sdn, tfs_devices, nodeviews)
    intra_results = verify_intra_links_multi_tm(sdn, tfs_links, nodeviews)
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

function verify_devices_against_map(sdn::TeraflowSDN, tfs_devices, nodeviews)
    """Check if devices in device_map exist in TFS (including multi-TM verification)"""
    println("\n📱 DEVICE VERIFICATION (Multi-TM + Shared OLS)")
    println("-"^50)
    
    # Extract expected devices from device_map
    expected_devices = Dict{String, Any}()  # uuid => device_info
    nodes_devices = Dict{Int, Set{Symbol}}()  # node_id => set of device types
    shared_ols_devices = Dict{String, Tuple{Int, Int}}()  # uuid => (node1, node2)
    tm_devices_by_node = Dict{Int, Set{Int}}()  # node_id => set of TM indices
    
    for (key, uuid) in sdn.device_map
        if length(key) == 2
            node_id, device_type = key
            # Only main devices, not endpoints
            if device_type in [:router, :oxc]
                expected_devices[uuid] = (node_id, device_type)
                
                if !haskey(nodes_devices, node_id)
                    nodes_devices[node_id] = Set{Symbol}()
                end
                push!(nodes_devices[node_id], device_type)
            elseif string(device_type) |> x -> startswith(x, "tm_") && !contains(x, "_ep_")
                # Extract TM index from tm_X
                tm_match = match(r"tm_(\d+)", string(device_type))
                if tm_match !== nothing
                    tm_idx = parse(Int, tm_match.captures[1])
                    expected_devices[uuid] = (node_id, device_type)
                    
                    if !haskey(nodes_devices, node_id)
                        nodes_devices[node_id] = Set{Symbol}()
                    end
                    push!(nodes_devices[node_id], device_type)
                    
                    # Track TM indices per node
                    if !haskey(tm_devices_by_node, node_id)
                        tm_devices_by_node[node_id] = Set{Int}()
                    end
                    push!(tm_devices_by_node[node_id], tm_idx)
                end
            end
        elseif length(key) == 3 && key[3] == :shared_ols
            # Handle shared OLS devices
            node1, node2, device_type = key
            expected_devices[uuid] = (node1, node2, device_type)
            shared_ols_devices[uuid] = (node1, node2)
        end
    end
    
    # Extract actual devices from TFS
    tfs_device_uuids = Set(dev["device_id"]["device_uuid"]["uuid"] for dev in tfs_devices["devices"])
    
    # Check matches
    found_devices = intersect(Set(keys(expected_devices)), tfs_device_uuids)
    missing_devices = setdiff(Set(keys(expected_devices)), tfs_device_uuids)
    
    println("✅ Devices found in TFS: $(length(found_devices))/$(length(expected_devices))")
    
    # Analyze by node and device type with TM verification
    nodes_complete = 0
    nodes_incomplete = 0
    nodes_empty = 0
    shared_ols_found = length(intersect(Set(keys(shared_ols_devices)), tfs_device_uuids))
    
    # Create nodeview lookup for TM count verification
    node_lookup = Dict{Int, Any}()
    for nodeview in nodeviews
        node_lookup[nodeview.nodeproperties.localnode] = nodeview
    end
    
    for (node_id, expected_types) in nodes_devices
        found_types = Set{Symbol}()
        
        for uuid in found_devices
            if haskey(expected_devices, uuid)
                dev_info = expected_devices[uuid]
                if length(dev_info) == 2  # Regular node device
                    dev_node, dev_type = dev_info
                    if dev_node == node_id
                        push!(found_types, dev_type)
                    end
                end
            end
        end
        
        missing_types = setdiff(expected_types, found_types)
        
        # Verify TM count matches nodeview expectation
        expected_tm_count = 0
        if haskey(node_lookup, node_id) && node_lookup[node_id].transmissionmoduleviewpool !== nothing
            expected_tm_count = length(node_lookup[node_id].transmissionmoduleviewpool)
        end
        
        found_tm_count = haskey(tm_devices_by_node, node_id) ? length(tm_devices_by_node[node_id]) : 0
        
        if isempty(missing_types)
            nodes_complete += 1
            if isempty(expected_types)
                nodes_empty += 1
                println("📝 Node $node_id: Empty node (no devices)")
            else
                tm_status = found_tm_count == expected_tm_count ? "✓" : "✗"
                println("✅ Node $node_id: All devices present - TMs: $found_tm_count/$expected_tm_count $tm_status")
            end
        else
            nodes_incomplete += 1
            tm_missing = expected_tm_count - found_tm_count
            println("❌ Node $node_id: Missing $(length(missing_types)) device types, TMs: $found_tm_count/$expected_tm_count")
            if tm_missing > 0
                println("   Missing TM devices: $tm_missing")
            end
        end
    end
    
    println("✅ Shared OLS devices found: $shared_ols_found/$(length(shared_ols_devices))")
    
    # Show TM distribution summary
    println("\n📊 Transmission Module Distribution:")
    total_expected_tms = sum(length(node_lookup[node_id].transmissionmoduleviewpool) for node_id in keys(node_lookup) if node_lookup[node_id].transmissionmoduleviewpool !== nothing)
    total_found_tms = sum(length(tm_set) for tm_set in values(tm_devices_by_node))
    println("   Total TMs expected: $total_expected_tms")
    println("   Total TMs found: $total_found_tms")
    
    # Show shared OLS details
    if length(shared_ols_devices) > 0
        println("\n📊 Shared OLS Infrastructure:")
        found_shared_ols = intersect(Set(keys(shared_ols_devices)), tfs_device_uuids)
        missing_shared_ols = setdiff(Set(keys(shared_ols_devices)), tfs_device_uuids)
        
        for uuid in sort(collect(found_shared_ols))
            if haskey(shared_ols_devices, uuid)
                node1, node2 = shared_ols_devices[uuid]
                println("   ✅ Shared OLS: Nodes $node1 ↔ $node2")
            end
        end
        
        for uuid in sort(collect(missing_shared_ols))
            if haskey(shared_ols_devices, uuid)
                node1, node2 = shared_ols_devices[uuid]
                println("   ❌ Missing shared OLS: Nodes $node1 ↔ $node2")
            end
        end
    end
    
    return Dict(
        :total_expected => length(expected_devices),
        :found_in_tfs => length(found_devices),
        :missing_count => length(missing_devices),
        :nodes_complete => nodes_complete,
        :nodes_incomplete => nodes_incomplete,
        :nodes_empty => nodes_empty,
        :shared_ols_found => shared_ols_found,
        :shared_ols_total => length(shared_ols_devices),
        :missing_devices => missing_devices,
        :total_expected_tms => total_expected_tms,
        :total_found_tms => total_found_tms
    )
end

function verify_intra_links_multi_tm(sdn::TeraflowSDN, tfs_links, nodeviews)
    """Check if intra-node links exist in TFS for ALL TMs"""
    println("\n🔗 INTRA-NODE LINK VERIFICATION (Multi-TM Architecture)")
    println("-"^55)
    
    # Extract expected intra-node links
    expected_intra = Set(keys(sdn.intra_link_map))
    expected_uuids = Set(values(sdn.intra_link_map))
    
    # Extract TFS link UUIDs
    tfs_link_uuids = Set(link["link_id"]["link_uuid"]["uuid"] for link in tfs_links["links"])
    
    # Check matches
    found_links = intersect(expected_uuids, tfs_link_uuids)
    missing_links = setdiff(expected_uuids, tfs_link_uuids)
    
    println("✅ Intra-node links found: $(length(found_links))/$(length(expected_uuids))")
    
    # Create nodeview lookup for TM count verification
    node_lookup = Dict{Int, Any}()
    for nodeview in nodeviews
        node_lookup[nodeview.nodeproperties.localnode] = nodeview
    end
    
    # Analyze by node and link type with detailed TM verification
    nodes_with_complete_intra = 0
    intra_by_node = Dict{Int, Dict{String, Bool}}()  # Changed to String for detailed link names
    expected_links_by_node = Dict{Int, Int}()  # Expected link count per node
    
    for ((node_id, link_type), uuid) in sdn.intra_link_map
        if !haskey(intra_by_node, node_id)
            intra_by_node[node_id] = Dict{String, Bool}()
        end
        intra_by_node[node_id][string(link_type)] = uuid in found_links
    end
    
    # Calculate expected link counts for each node based on TM count
    for (node_id, nodeview) in node_lookup
        num_tms = nodeview.transmissionmoduleviewpool !== nothing ? length(nodeview.transmissionmoduleviewpool) : 0
        if num_tms > 0
            # Each TM needs: 2 router-tm links + 2 tm-oxc links = 4 links per TM
            expected_links_by_node[node_id] = 4 * num_tms
        else
            expected_links_by_node[node_id] = 0
        end
    end
    
    # Sort node IDs for consistent output
    sorted_node_ids = sort(collect(keys(intra_by_node)))
    
    for node_id in sorted_node_ids
        link_status = intra_by_node[node_id]
        all_present = all(values(link_status))
        
        num_tms = haskey(node_lookup, node_id) && node_lookup[node_id].transmissionmoduleviewpool !== nothing ? 
                  length(node_lookup[node_id].transmissionmoduleviewpool) : 0
        expected_count = get(expected_links_by_node, node_id, 0)
        found_count = count(values(link_status))
        
        if all_present && found_count == expected_count
            nodes_with_complete_intra += 1
            println("✅ Node $node_id: All $found_count intra-links present ($(num_tms) TMs)")
        else
            missing_link_types = [lt for (lt, present) in link_status if !present]
            present_link_types = [lt for (lt, present) in link_status if present]
            
            println("❌ Node $node_id: Incomplete intra-links ($found_count/$expected_count) for $(num_tms) TMs")
            
            # Analyze by link category
            router_tm_links = [lt for lt in keys(link_status) if contains(lt, "router_tm")]
            tm_oxc_links = [lt for lt in keys(link_status) if contains(lt, "tm") && contains(lt, "oxc")]
            
            router_tm_present = count(get(link_status, lt, false) for lt in router_tm_links)
            tm_oxc_present = count(get(link_status, lt, false) for lt in tm_oxc_links)
            
            expected_router_tm = 2 * num_tms
            expected_tm_oxc = 2 * num_tms
            
            println("   Router↔TM links: $router_tm_present/$expected_router_tm")
            println("   TM↔OXC links: $tm_oxc_present/$expected_tm_oxc")
            
            if !isempty(missing_link_types)
                println("   ✗ Missing: $(join(missing_link_types[1:min(5, end)], ", "))$(length(missing_link_types) > 5 ? "..." : "")")
            end
        end
    end
    
    # Show missing link details by category
    if !isempty(missing_links)
        println("\n❌ MISSING INTRA-LINK ANALYSIS:")
        router_tm_missing = 0
        tm_oxc_missing = 0
        other_missing = 0
        
        for ((node_id, link_type), uuid) in sdn.intra_link_map
            if uuid in missing_links
                link_type_str = string(link_type)
                if contains(link_type_str, "router_tm")
                    router_tm_missing += 1
                elseif contains(link_type_str, "tm") && contains(link_type_str, "oxc")
                    tm_oxc_missing += 1
                else
                    other_missing += 1
                end
            end
        end
        
        println("   Router↔TM links missing: $router_tm_missing")
        println("   TM↔OXC links missing: $tm_oxc_missing")
        println("   Other links missing: $other_missing")
    end
    
    return Dict(
        :total_expected => length(expected_uuids),
        :found_in_tfs => length(found_links),
        :missing_count => length(missing_links),
        :nodes_complete => nodes_with_complete_intra,
        :total_nodes => length(intra_by_node),
        :missing_links => missing_links,
        :expected_links_by_node => expected_links_by_node
    )
end

function verify_inter_links(sdn::TeraflowSDN, tfs_links, mindful_topology)
    """Check if inter-node links with shared OLS match MINDFul topology, accounting for empty nodes and multi-TM offset"""
    println("\n🌐 INTER-NODE LINK VERIFICATION (Shared OLS + Multi-TM Offset)")
    println("-"^60)
    
    mindful_neighbors = mindful_topology[:neighbors]
    
    # Get nodes that actually have OXC devices from device_map
    oxc_nodes = Set{Int}()
    for (key, uuid) in sdn.device_map
        if length(key) == 2 && key[2] == :oxc
            push!(oxc_nodes, key[1])
        end
    end
    
    println("📊 Topology analysis:")
    println("   Total nodes in topology: $(length(mindful_neighbors))")
    println("   Nodes with OXC devices: $(length(oxc_nodes))")
    println("   Empty nodes (no OXC): $(length(mindful_neighbors) - length(oxc_nodes))")
    
    # Extract expected inter-node links from device map (only from OXC nodes)
    expected_inter_uuids = Set(values(sdn.inter_link_map))
    
    # Extract TFS link UUIDs
    tfs_link_uuids = Set(link["link_id"]["link_uuid"]["uuid"] for link in tfs_links["links"])
    
    # Check matches
    found_inter_links = intersect(expected_inter_uuids, tfs_link_uuids)
    missing_inter_links = setdiff(expected_inter_uuids, tfs_link_uuids)
    
    println("✅ Inter-node links found: $(length(found_inter_links))/$(length(expected_inter_uuids))")
    
    # Analyze actual connections established (only count OXC nodes)
    actual_connections = Dict{Int, Set{Int}}()
    
    for (link_key, uuid) in sdn.inter_link_map
        if length(link_key) >= 6 && link_key[6] == :shared_ols_link
            node_id, oxc_ep_id, shared_node1, shared_node2, ols_ep_id, link_type = link_key
            # Only count if link exists in TFS and node has OXC
            if uuid in found_inter_links && node_id in oxc_nodes
                # Determine the other node in the shared OLS connection
                other_node = shared_node1 == node_id ? shared_node2 : shared_node1
                
                if !haskey(actual_connections, node_id)
                    actual_connections[node_id] = Set{Int}()
                end
                push!(actual_connections[node_id], other_node)
            end
        end
    end
    
    # Verify shared OLS devices exist for all expected node pairs
    expected_shared_ols = Dict{Tuple{Int,Int}, Bool}()
    shared_ols_found = Dict{Tuple{Int,Int}, Bool}()
    
    # Extract shared OLS devices from device_map
    for (key, uuid) in sdn.device_map
        if length(key) == 3 && key[3] == :shared_ols
            node1, node2 = key[1], key[2]
            sorted_pair = node1 < node2 ? (node1, node2) : (node2, node1)
            shared_ols_found[sorted_pair] = true
        end
    end
    
    # Expected shared OLS based on MINDFul topology
    for (node_id, neighbors) in mindful_neighbors
        for neighbor_id in neighbors
            if node_id < neighbor_id  # Avoid duplicates
                expected_shared_ols[(node_id, neighbor_id)] = true
            end
        end
    end
    
    # Analyze topology coverage considering empty nodes
    topology_matches = 0
    topology_partial = 0
    topology_missing = 0
    empty_node_connections = 0
    
    missing_connections = Dict{Int, Set{Int}}()
    missing_shared_ols = Dict{Tuple{Int,Int}, Bool}()
    
    for (node_id, expected_neighbors) in mindful_neighbors
        if node_id in oxc_nodes
            # Node has OXC - should have physical links to shared OLS devices
            actual_neighbors = get(actual_connections, node_id, Set{Int}())
            
            if expected_neighbors == actual_neighbors
                topology_matches += 1
                println("✅ Node $node_id (OXC): Perfect topology match via shared OLS ($(length(expected_neighbors)) neighbors)")
            else
                missing_neighs = setdiff(expected_neighbors, actual_neighbors)
                if !isempty(missing_neighs)
                    missing_connections[node_id] = missing_neighs
                    if !isempty(intersect(expected_neighbors, actual_neighbors))
                        topology_partial += 1
                        println("⚠️  Node $node_id (OXC): Partial shared OLS connections")
                    else
                        topology_missing += 1
                        println("❌ Node $node_id (OXC): No shared OLS connections found")
                    end
                    println("   Missing shared OLS connections to: $(collect(missing_neighs))")
                end
            end
        else
            # Empty node - should have shared OLS devices but no physical links
            empty_node_connections += 1
            
            # Check if shared OLS devices exist for this empty node's connections
            missing_ols_for_node = Set{Int}()
            for neighbor_id in expected_neighbors
                sorted_pair = node_id < neighbor_id ? (node_id, neighbor_id) : (neighbor_id, node_id)
                if !get(shared_ols_found, sorted_pair, false)
                    push!(missing_ols_for_node, neighbor_id)
                    missing_shared_ols[sorted_pair] = true
                end
            end
            
            if isempty(missing_ols_for_node)
                println("✅ Node $node_id (Empty): All shared OLS devices present ($(length(expected_neighbors)) neighbors)")
            else
                println("❌ Node $node_id (Empty): Missing shared OLS devices to: $(collect(missing_ols_for_node))")
            end
        end
    end
    
    # Verify that all expected shared OLS devices exist
    shared_ols_missing_count = length(setdiff(Set(keys(expected_shared_ols)), Set(keys(shared_ols_found))))
    
    println("\n📊 Shared OLS Infrastructure:")
    println("   Expected shared OLS devices: $(length(expected_shared_ols))")
    println("   Found shared OLS devices: $(length(shared_ols_found))")
    println("   Missing shared OLS devices: $shared_ols_missing_count")
    
    # Show endpoint offset analysis for debugging
    println("\n📊 OXC Endpoint Usage Analysis (Multi-TM Offset):")
    oxc_endpoint_usage = Dict{Int, Int}()  # node_id => used endpoints
    
    for (link_key, uuid) in sdn.inter_link_map
        if length(link_key) >= 6 && link_key[6] == :shared_ols_link
            node_id = link_key[1]
            if node_id in oxc_nodes
                oxc_endpoint_usage[node_id] = get(oxc_endpoint_usage, node_id, 0) + 1
            end
        end
    end
    
    for node_id in sort(collect(oxc_nodes))
        used_eps = get(oxc_endpoint_usage, node_id, 0)
        expected_neighbors = length(get(mindful_neighbors, node_id, Set{Int}()))
        expected_inter_eps = expected_neighbors * 2  # 2 links per neighbor
        
        if used_eps == expected_inter_eps
            println("   ✅ Node $node_id: Using $used_eps/$expected_inter_eps inter-node endpoints")
        else
            println("   ⚠️  Node $node_id: Using $used_eps/$expected_inter_eps inter-node endpoints")
        end
    end
    
    if shared_ols_missing_count > 0
        println("\n❌ MISSING SHARED OLS DEVICES:")
        for pair in setdiff(Set(keys(expected_shared_ols)), Set(keys(shared_ols_found)))
            println("   Nodes $(pair[1]) ↔ $(pair[2])")
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
        :oxc_nodes => length(oxc_nodes),
        :empty_nodes => length(mindful_neighbors) - length(oxc_nodes),
        :empty_node_connections => empty_node_connections,
        :missing_connections => missing_connections,
        :missing_links => missing_inter_links,
        :shared_ols_expected => length(expected_shared_ols),
        :shared_ols_found => length(shared_ols_found),
        :shared_ols_missing => shared_ols_missing_count,
        :missing_shared_ols => missing_shared_ols,
        :oxc_endpoint_usage => oxc_endpoint_usage
    )
end

function generate_focused_report(device_results, intra_results, inter_results)
    """Generate focused verification report for multi-TM architecture"""
    println("\n" * "="^65)
    println("🏁 FOCUSED VERIFICATION SUMMARY (Multi-TM Architecture)")
    println("="^65)
    
    # Device summary with TM details
    dev_health = (device_results[:found_in_tfs] / max(device_results[:total_expected], 1)) * 100
    println("📱 Devices: $(device_results[:found_in_tfs])/$(device_results[:total_expected]) found ($(round(dev_health, digits=1))%)")
    println("   Complete nodes: $(device_results[:nodes_complete])")
    println("   Incomplete nodes: $(device_results[:nodes_incomplete])")
    println("   Transmission modules: $(device_results[:total_found_tms])/$(device_results[:total_expected_tms])")
    println("   Shared OLS devices: $(device_results[:shared_ols_found])/$(device_results[:shared_ols_total])")
    
    # Intra-link summary with multi-TM details
    intra_health = (intra_results[:found_in_tfs] / max(intra_results[:total_expected], 1)) * 100
    println("🔗 Intra-links: $(intra_results[:found_in_tfs])/$(intra_results[:total_expected]) found ($(round(intra_health, digits=1))%)")
    println("   Complete nodes: $(intra_results[:nodes_complete])/$(intra_results[:total_nodes])")
    
    # Calculate total expected links for all TMs
    total_expected_intra = sum(values(intra_results[:expected_links_by_node]))
    println("   Multi-TM architecture: $(intra_results[:found_in_tfs])/$total_expected_intra links")
    
    # Inter-link summary with empty node considerations
    inter_health = (inter_results[:found_in_tfs] / max(inter_results[:total_expected], 1)) * 100
    println("🌐 Inter-links: $(inter_results[:found_in_tfs])/$(inter_results[:total_expected]) found ($(round(inter_health, digits=1))%)")
    println("   OXC nodes with perfect topology: $(inter_results[:topology_perfect])/$(inter_results[:oxc_nodes])")
    println("   OXC nodes with partial topology: $(inter_results[:topology_partial])/$(inter_results[:oxc_nodes])")
    println("   Empty nodes (no physical links): $(inter_results[:empty_nodes])")
    println("   Shared OLS infrastructure: $(inter_results[:shared_ols_found])/$(inter_results[:shared_ols_expected])")
    
    # Overall health
    overall_health = (dev_health + intra_health + inter_health) / 3
    println("\n🎯 Overall Health: $(round(overall_health, digits=1))%")
    
    println("\n🔍 KEY ISSUES ANALYSIS (Multi-TM Architecture)")
    println("-"^55)
    
    issues_found = false
    
    # Device issues with TM details
    if device_results[:missing_count] > 0
        issues_found = true
        println("❌ DEVICE ISSUES:")
        println("   • $(device_results[:missing_count]) devices missing from TFS")
        
        tm_missing = device_results[:total_expected_tms] - device_results[:total_found_tms]
        if tm_missing > 0
            println("   • $tm_missing transmission modules missing")
        end
        
        if device_results[:shared_ols_found] < device_results[:shared_ols_total]
            missing_shared_ols = device_results[:shared_ols_total] - device_results[:shared_ols_found]
            println("   • $missing_shared_ols shared OLS devices missing")
        end
    else
        println("✅ DEVICES: All $(device_results[:total_expected]) devices present in TFS")
        println("✅ TRANSMISSION MODULES: All $(device_results[:total_expected_tms]) TMs present")
        if device_results[:shared_ols_found] == device_results[:shared_ols_total]
            println("✅ SHARED OLS: All $(device_results[:shared_ols_total]) shared OLS devices present")
        end
    end
    
    # Intra-link issues with multi-TM context
    if intra_results[:missing_count] > 0
        issues_found = true
        println("\n❌ INTRA-NODE LINK ISSUES (Multi-TM Architecture):")
        println("   • $(intra_results[:missing_count]) intra-node links missing from TFS")
        incomplete_nodes = intra_results[:total_nodes] - intra_results[:nodes_complete]
        if incomplete_nodes > 0
            println("   • $incomplete_nodes nodes have incomplete TM connectivity")
            println("   • Multi-TM architecture requires 4 links per TM (2 router↔TM + 2 TM↔OXC)")
        end
    else
        println("\n✅ INTRA-LINKS: All $(intra_results[:total_expected]) internal links present in TFS")
        println("✅ MULTI-TM: All TMs properly connected to router and OXC")
    end
    
    # Inter-link issues with empty node context
    if inter_results[:missing_count] > 0
        issues_found = true
        println("\n❌ INTER-NODE LINK ISSUES:")
        println("   • $(inter_results[:missing_count]) inter-node links missing from TFS")
        println("   • Note: OXC endpoints for inter-node links start after TM endpoints")
        println("   • Only OXC nodes ($(inter_results[:oxc_nodes])) should have physical links")
        println("   • Empty nodes ($(inter_results[:empty_nodes])) only need shared OLS devices")
    else
        println("\n✅ INTER-LINKS: All $(inter_results[:total_expected]) inter-node links present in TFS")
        println("✅ ENDPOINT OFFSET: Multi-TM endpoint allocation working correctly")
    end
    
    # Shared OLS infrastructure issues
    if inter_results[:shared_ols_missing] > 0
        issues_found = true
        println("\n❌ SHARED OLS INFRASTRUCTURE ISSUES:")
        println("   • $(inter_results[:shared_ols_missing]) shared OLS devices missing")
        println("   • This affects both OXC and empty nodes")
        
        if !isempty(inter_results[:missing_shared_ols])
            println("   📋 Missing shared OLS for node pairs:")
            for (pair, _) in inter_results[:missing_shared_ols]
                println("      Nodes $(pair[1]) ↔ $(pair[2])")
            end
        end
    else
        println("\n✅ SHARED OLS: All $(inter_results[:shared_ols_expected]) shared OLS devices present")
    end
    
    # Topology connectivity issues (only for OXC nodes)
    if !isempty(inter_results[:missing_connections])
        issues_found = true
        oxc_nodes_with_issues = length(inter_results[:missing_connections])
        total_missing_connections = sum(length(v) for v in values(inter_results[:missing_connections]))
        println("\n❌ TOPOLOGY CONNECTIVITY ISSUES (OXC Nodes Only):")
        println("   • $total_missing_connections network connections not established")
        println("   • $oxc_nodes_with_issues OXC nodes have missing connections")
        println("   • $(inter_results[:topology_missing]) OXC nodes have no connections")
        println("   • $(inter_results[:topology_partial]) OXC nodes have partial connections")
        
        # Show specific missing connections for OXC nodes only
        println("\n   📋 Missing connections details (OXC nodes only):")
        for node_id in sort(collect(keys(inter_results[:missing_connections])))
            missing_neighbors = inter_results[:missing_connections][node_id]
            neighbors_str = join(sort(collect(missing_neighbors)), ", ")
            println("      OXC Node $node_id → [$neighbors_str]")
        end
    else
        println("\n✅ TOPOLOGY: All expected network connections established for OXC nodes")
    end
    
    # Multi-TM architecture summary
    println("\n📊 MULTI-TM ARCHITECTURE SUMMARY:")
    println("   • All TMs linked to both router and OXC (not just first TM)")
    println("   • Router endpoints: 2 per TM (incoming + outgoing)")
    println("   • OXC endpoints: 2 per TM + 2 per neighbor (TM + inter-node)")
    println("   • Inter-node links use OXC endpoints after TM endpoint offset")
    
    if inter_results[:empty_nodes] > 0
        println("\n📊 EMPTY NODE SUMMARY:")
        println("   • $(inter_results[:empty_nodes]) nodes have no OXC devices")
        println("   • These nodes only participate via shared OLS devices")
        println("   • No physical links or TM endpoint offsets for these nodes")
    end
    
    println("="^65)
    
    return overall_health
end

# Main execution function (unchanged)
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
    
    # Create IBNFCommunication from handlers (missing parameter)
    ibnfcomm = MINDF.IBNFCommunication(nothing, ibnfhandlers)

    # Now call the full constructor with correct parameters
    ibnf1 = MINDF.IBNFramework(operationmode, ibnfid, intentdag, ibnag1, ibnfcomm, sdncontroller)
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