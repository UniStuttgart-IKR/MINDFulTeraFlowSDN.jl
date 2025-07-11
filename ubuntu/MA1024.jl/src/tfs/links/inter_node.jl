"""
Inter-node link creation with shared OLS
"""

"""
    create_inter_node_connection_with_shared_ols(sdn::TeraflowSDN, node1_id::Int, node2_id::Int, num_tms_node1::Int, num_tms_node2::Int) → Bool
Create inter-node connection with shared OLS device.
Uses DYNAMIC OXC endpoint assignment to avoid conflicts.
"""
function create_inter_node_connection_with_shared_ols(sdn::TeraflowSDN, node1_id::Int, node2_id::Int, num_tms_node1::Int, num_tms_node2::Int; link_type::Symbol = :fiber)
    println("🌉 Creating inter-node connection with shared OLS: $node1_id ↔ $node2_id")
    
    # Check if nodes have OXC
    node1_has_oxc = haskey(sdn.device_map, (node1_id, :oxc))
    node2_has_oxc = haskey(sdn.device_map, (node2_id, :oxc))
    
    # Create shared OLS device
    ols_uuid, ols_endpoints = create_shared_ols_device(sdn, node1_id, node2_id)
    if ols_uuid === nothing
        @warn "Failed to create shared OLS device for nodes $node1_id ↔ $node2_id"
        return false
    end
    
    success_count = 0
    sorted_nodes = sort([node1_id, node2_id])
    
    # Connect node1's OXC to shared OLS (2 links) - only if node1 has OXC
    if node1_has_oxc
        for ep_idx in 1:2
            try
                # Find AVAILABLE OXC endpoint for node1 (starting after TM endpoints)
                oxc_ep_key, oxc_ep_uuid = get_next_available_oxc_endpoint(sdn, node1_id, num_tms_node1)
                
                # Get available shared OLS endpoint
                ols_ep_key, ols_ep_uuid = get_available_shared_ols_endpoint(sdn, node1_id, node2_id)
                
                # Generate link details
                link_uuid = stable_uuid(sorted_nodes[1] * 10000 + sorted_nodes[2] * 100 + ep_idx, 
                                      Symbol("oxc_sharedols_link_node$(node1_id)_ep$(ep_idx)"))
                
                oxc_ep_id = string(oxc_ep_key[2])
                ols_ep_id = string(ols_ep_key[3])
                link_name = "InterLink-OXC-$(oxc_ep_id)-node-$(node1_id)-SharedOLS-$(ols_ep_id)-nodes-$(sorted_nodes[1])-$(sorted_nodes[2])"
                
                # Create link key for inter-link map
                link_key = (node1_id, oxc_ep_id, sorted_nodes[1], sorted_nodes[2], ols_ep_id, :shared_ols_link)
                
                # Store in inter-link map
                sdn.inter_link_map[link_key] = link_uuid
                
                # Create the actual link
                success = create_link_between_devices_shared_ols(sdn, oxc_ep_key, ols_ep_key,
                                                              link_name, link_uuid; link_type=link_type)
                
                if success
                    # Mark endpoints as used
                    sdn.endpoint_usage[oxc_ep_uuid] = true
                    sdn.endpoint_usage[ols_ep_uuid] = true
                    success_count += 1
                    println("✓ Connected OXC node $node1_id ($(oxc_ep_id)) to shared OLS ($(ols_ep_id))")
                else
                    delete!(sdn.inter_link_map, link_key)
                    @warn "✗ Failed to connect OXC node $node1_id to shared OLS"
                end
                
            catch e
                @warn "✗ Failed to get available endpoints for node $node1_id: $e"
            end
        end
    else
        println("⚠️  Node $node1_id has no OXC device - shared OLS created for future connection")
    end
    
    # Connect node2's OXC to shared OLS (2 links) - only if node2 has OXC
    if node2_has_oxc
        for ep_idx in 1:2
            try
                # Find AVAILABLE OXC endpoint for node2 (starting after TM endpoints)
                oxc_ep_key, oxc_ep_uuid = get_next_available_oxc_endpoint(sdn, node2_id, num_tms_node2)
                
                # Get available shared OLS endpoint
                ols_ep_key, ols_ep_uuid = get_available_shared_ols_endpoint(sdn, node1_id, node2_id)
                
                # Generate link details
                link_uuid = stable_uuid(sorted_nodes[1] * 10000 + sorted_nodes[2] * 100 + ep_idx + 10, 
                                      Symbol("oxc_sharedols_link_node$(node2_id)_ep$(ep_idx)"))
                
                oxc_ep_id = string(oxc_ep_key[2])
                ols_ep_id = string(ols_ep_key[3])
                link_name = "InterLink-OXC-$(oxc_ep_id)-node-$(node2_id)-SharedOLS-$(ols_ep_id)-nodes-$(sorted_nodes[1])-$(sorted_nodes[2])"
                
                # Create link key for inter-link map
                link_key = (node2_id, oxc_ep_id, sorted_nodes[1], sorted_nodes[2], ols_ep_id, :shared_ols_link)
                
                # Store in inter-link map
                sdn.inter_link_map[link_key] = link_uuid
                
                # Create the actual link
                success = create_link_between_devices_shared_ols(sdn, oxc_ep_key, ols_ep_key,
                                                              link_name, link_uuid; link_type=link_type)
                
                if success
                    # Mark endpoints as used
                    sdn.endpoint_usage[oxc_ep_uuid] = true
                    sdn.endpoint_usage[ols_ep_uuid] = true
                    success_count += 1
                    println("✓ Connected OXC node $node2_id ($(oxc_ep_id)) to shared OLS ($(ols_ep_id))")
                else
                    delete!(sdn.inter_link_map, link_key)
                    @warn "✗ Failed to connect OXC node $node2_id to shared OLS"
                end
                
            catch e
                @warn "✗ Failed to get available endpoints for node $node2_id: $e"
            end
        end
    else
        println("⚠️  Node $node2_id has no OXC device - shared OLS created for future connection")
    end
    
    # Expected success count depends on how many nodes have OXC
    expected_links = (node1_has_oxc ? 2 : 0) + (node2_has_oxc ? 2 : 0)
    return success_count == expected_links
end

"""
    connect_all_inter_node_with_shared_ols(sdn::TeraflowSDN, nodeviews) → Int
Create all inter-node connections with shared OLS devices.
Creates shared OLS for all node pairs, but only creates links for nodes that have OXC devices.
"""
function connect_all_inter_node_with_shared_ols(sdn::TeraflowSDN, nodeviews)
    println("🌐 Creating inter-node connections with shared OLS...")
    links_created = 0
    
    # Create nodeview lookup for TM counting - HANDLE NOTHING CASE
    node_lookup = Dict{Int, Any}()
    for nodeview in nodeviews
        node_lookup[nodeview.nodeproperties.localnode] = nodeview
    end
    
    # Get all nodes that have OXC devices
    oxc_nodes = Set{Int}()
    for (key, uuid) in sdn.device_map
        if length(key) == 2 && key[2] == :oxc
            push!(oxc_nodes, key[1])
        end
    end
    
    # Get all nodes (including those without OXC)
    all_nodes = Set{Int}()
    for nodeview in nodeviews
        push!(all_nodes, nodeview.nodeproperties.localnode)
    end
    
    println("🌐 Found $(length(oxc_nodes)) nodes with OXC devices out of $(length(all_nodes)) total nodes")
    
    # Track processed node pairs to avoid duplicates
    processed_pairs = Set{Tuple{Int,Int}}()
    
    for nodeview in nodeviews
        node_id = nodeview.nodeproperties.localnode
        
        # Get all neighbors for this node (regardless of whether it has OXC)
        all_neighbors = Set{Int}()
        union!(all_neighbors, nodeview.nodeproperties.inneighbors)
        union!(all_neighbors, nodeview.nodeproperties.outneighbors)
        
        for neighbor_id in all_neighbors
            if neighbor_id in all_nodes  # Make sure neighbor exists in our nodeviews
                # Create ordered pair to avoid duplicates
                link_pair = node_id < neighbor_id ? (node_id, neighbor_id) : (neighbor_id, node_id)
                
                if link_pair ∉ processed_pairs
                    push!(processed_pairs, link_pair)
                    
                    # Calculate TM counts for endpoint calculation - SAFE HANDLING
                    num_tms_node1 = 0
                    num_tms_node2 = 0
                    
                    if haskey(node_lookup, link_pair[1])
                        nodeview1 = node_lookup[link_pair[1]]
                        if nodeview1.transmissionmoduleviewpool !== nothing
                            num_tms_node1 = length(nodeview1.transmissionmoduleviewpool)
                        end
                    end
                    
                    if haskey(node_lookup, link_pair[2])
                        nodeview2 = node_lookup[link_pair[2]]
                        if nodeview2.transmissionmoduleviewpool !== nothing
                            num_tms_node2 = length(nodeview2.transmissionmoduleviewpool)
                        end
                    end
                    
                    # Check if both nodes have OXC devices
                    node1_has_oxc = link_pair[1] in oxc_nodes
                    node2_has_oxc = link_pair[2] in oxc_nodes
                    
                    if node1_has_oxc || node2_has_oxc
                        # At least one node has OXC, proceed with connection
                        if create_inter_node_connection_with_shared_ols(sdn, link_pair[1], link_pair[2], num_tms_node1, num_tms_node2; link_type=:fiber)
                            expected_links = (node1_has_oxc ? 2 : 0) + (node2_has_oxc ? 2 : 0)
                            links_created += expected_links
                        end
                    else
                        # Neither node has OXC, just create the shared OLS device for future use
                        println("🔧 Creating shared OLS for future use: $(link_pair[1]) ↔ $(link_pair[2]) (no OXC devices)")
                        create_shared_ols_device(sdn, link_pair[1], link_pair[2])
                    end
                end
            end
        end
    end
    
    println("✅ Created $links_created inter-node links with shared OLS devices")
    return links_created
end