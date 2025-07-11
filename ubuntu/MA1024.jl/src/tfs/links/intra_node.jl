"""
Intra-node link creation functions
"""

"""
    create_link_between_devices(sdn::TeraflowSDN, device1_key::Tuple, device2_key::Tuple, 
                               link_name::String, link_uuid::String; 
                               link_type::Symbol = :copper) → Bool

General function to create a link between any two devices using their endpoint keys.
Device-agnostic - works with any device types (router, oxc, tm, ols, etc.)
"""
function create_link_between_devices(sdn::TeraflowSDN, device1_key::Tuple, device2_key::Tuple,
                                   link_name::String, link_uuid::String;
                                   link_type::Symbol = :copper)
    
    # Check if both endpoints exist in device map
    if !haskey(sdn.device_map, device1_key)
        @warn "Device endpoint not found: $device1_key"
        return false
    end
    
    if !haskey(sdn.device_map, device2_key)
        @warn "Device endpoint not found: $device2_key"
        return false
    end
    
    endpoint1_uuid = sdn.device_map[device1_key]
    endpoint2_uuid = sdn.device_map[device2_key]
    
    # Find the corresponding device UUIDs
    # Extract node_id and device type from endpoint keys
    node1_id, ep1_type = device1_key
    node2_id, ep2_type = device2_key
    
    # Updated endpoint type mapping to handle all device types
    device1_type = if string(ep1_type) |> x -> startswith(x, "router_ep_")
        :router
    elseif ep1_type == :oxc_ep || (string(ep1_type) |> x -> startswith(x, "oxc_ep_"))
        :oxc
    elseif string(ep1_type) |> x -> startswith(x, "ols_ep_")
        :ols
    elseif string(ep1_type) |> x -> startswith(x, "tm_")
        Symbol(replace(string(ep1_type), r"_copper_ep_\d+|_fiber_ep_\d+" => ""))
    else
        error("Unknown endpoint type: $ep1_type")
    end
    
    device2_type = if string(ep2_type) |> x -> startswith(x, "router_ep_")
        :router
    elseif ep2_type == :oxc_ep || (string(ep2_type) |> x -> startswith(x, "oxc_ep_"))
        :oxc
    elseif string(ep2_type) |> x -> startswith(x, "ols_ep_")
        :ols
    elseif string(ep2_type) |> x -> startswith(x, "tm_")
        Symbol(replace(string(ep2_type), r"_copper_ep_\d+|_fiber_ep_\d+" => ""))
    else
        error("Unknown endpoint type: $ep2_type")
    end
    
    # Get device UUIDs
    device1_key_lookup = (node1_id, device1_type)
    device2_key_lookup = (node2_id, device2_type)
    
    if !haskey(sdn.device_map, device1_key_lookup)
        @warn "Device not found: $device1_key_lookup"
        return false
    end
    
    if !haskey(sdn.device_map, device2_key_lookup)
        @warn "Device not found: $device2_key_lookup"
        return false
    end
    
    device1_uuid = sdn.device_map[device1_key_lookup]
    device2_uuid = sdn.device_map[device2_key_lookup]
    
    # Create EndPointIds for the link endpoints with proper device_id
    endpoint_ids = [
        Ctx.EndPointId(
            nothing,  # topology_id
            Ctx.DeviceId(Ctx.Uuid(device1_uuid)),  # device_id
            Ctx.Uuid(endpoint1_uuid)  # endpoint_uuid
        ),
        Ctx.EndPointId(
            nothing,  # topology_id
            Ctx.DeviceId(Ctx.Uuid(device2_uuid)),  # device_id
            Ctx.Uuid(endpoint2_uuid)  # endpoint_uuid
        )
    ]
    
    # Updated link type enum mapping to match new proto of TFS 5.0.0
    tfs_link_type = if link_type == :copper
        Ctx.LinkTypeEnum.LINKTYPE_COPPER
    elseif link_type == :fiber || link_type == :optical  # Map :optical to :fiber
        Ctx.LinkTypeEnum.LINKTYPE_FIBER
    elseif link_type == :radio
        Ctx.LinkTypeEnum.LINKTYPE_RADIO
    elseif link_type == :virtual
        Ctx.LinkTypeEnum.LINKTYPE_VIRTUAL
    elseif link_type == :management
        Ctx.LinkTypeEnum.LINKTYPE_MANAGEMENT
    else
        Ctx.LinkTypeEnum.LINKTYPE_COPPER  # Default fallback
    end
    
    # Create link with proper structure
    link = Ctx.Link(
        Ctx.LinkId(Ctx.Uuid(link_uuid)),
        link_name,
        tfs_link_type,           # link_type moved to position 3
        endpoint_ids,            # link_endpoint_ids moved to position 4
        Ctx.LinkAttributes(0.0f0, 0.0f0)  # attributes moved to position 5
    )
    
    # Use ensure_post_link for robust creation with verification
    return ensure_post_link(sdn.api_url, link)
end

"""
    create_router_tm_links(sdn::TeraflowSDN, node_id::Int, num_tms::Int) → Bool
Create intra-node links between router and ALL TMs using copper endpoints.
For each TM: Router ep(2i-1) → TM copper ep1, Router ep(2i) → TM copper ep2
"""
function create_router_tm_links(sdn::TeraflowSDN, node_id::Int, num_tms::Int; link_type::Symbol = :copper)
    success_count = 0
    
    for tm_idx in 1:num_tms
        # Calculate router endpoint indices for this TM
        router_ep1_idx = 2 * tm_idx - 1  # Odd indices: 1, 3, 5, ...
        router_ep2_idx = 2 * tm_idx      # Even indices: 2, 4, 6, ...
        
        # Create 2 links for this TM
        for (router_ep_idx, tm_copper_ep_idx) in [(router_ep1_idx, 1), (router_ep2_idx, 2)]
            router_ep_key = (node_id, Symbol("router_ep_$(router_ep_idx)"))
            tm_ep_key = (node_id, Symbol("tm_$(tm_idx)_copper_ep_$(tm_copper_ep_idx)"))
            
            if !haskey(sdn.device_map, router_ep_key)
                @warn "Router endpoint not found: $router_ep_key"
                continue
            end
            
            if !haskey(sdn.device_map, tm_ep_key)
                @warn "TM copper endpoint not found: $tm_ep_key"
                continue
            end
            
            # Check if already used
            router_ep_uuid = sdn.device_map[router_ep_key]
            tm_ep_uuid = sdn.device_map[tm_ep_key]
            
            if get(sdn.endpoint_usage, router_ep_uuid, false) || get(sdn.endpoint_usage, tm_ep_uuid, false)
                @warn "Endpoints already in use for router-tm$tm_idx link: $router_ep_key ↔ $tm_ep_key"
                continue
            end
            
            # Generate link details
            link_uuid = stable_uuid(node_id * 1000 + tm_idx * 10 + tm_copper_ep_idx, Symbol("router_tm$(tm_idx)_link_$(tm_copper_ep_idx)"))
            link_name = "IntraLink-Router-ep$(router_ep_idx)-TM$(tm_idx)-copper-ep$(tm_copper_ep_idx)-node-$(node_id)"
            link_key = (node_id, Symbol("router_tm$(tm_idx)_link_$(tm_copper_ep_idx)"))
            
            # Store in intra-link map
            sdn.intra_link_map[link_key] = link_uuid
            
            # Create link using the fixed function signature
            success = create_link_between_devices(sdn, router_ep_key, tm_ep_key, 
                                                link_name, link_uuid; link_type=link_type)
            
            if success
                # Mark endpoints as used
                sdn.endpoint_usage[router_ep_uuid] = true
                sdn.endpoint_usage[tm_ep_uuid] = true
                success_count += 1
                println("  ✓ Router-TM$tm_idx link: ep$(router_ep_idx) ↔ copper_ep$(tm_copper_ep_idx)")
            else
                @warn "Failed to create Router-TM$tm_idx link: ep$(router_ep_idx) ↔ copper_ep$(tm_copper_ep_idx)"
            end
        end
    end
    
    expected_links = 2 * num_tms
    println("  Router-TM links: $success_count/$expected_links successful")
    return success_count == expected_links
end

"""
    create_tm_oxc_links(sdn::TeraflowSDN, node_id::Int, num_tms::Int) → Bool
Create intra-node links between ALL TMs and OXC using fiber endpoints.
For each TM: TM fiber ep1 ↔ OXC ep(2i-1), TM fiber ep2 ↔ OXC ep(2i)
"""
function create_tm_oxc_links(sdn::TeraflowSDN, node_id::Int, num_tms::Int; link_type::Symbol = :fiber)
    success_count = 0
    
    for tm_idx in 1:num_tms
        # Calculate OXC endpoint indices for this TM
        oxc_ep1_idx = 2 * tm_idx - 1  # Odd indices: 1, 3, 5, ...
        oxc_ep2_idx = 2 * tm_idx      # Even indices: 2, 4, 6, ...
        
        # Create 2 links for this TM
        for (tm_fiber_ep_idx, oxc_ep_idx) in [(1, oxc_ep1_idx), (2, oxc_ep2_idx)]
            tm_ep_key = (node_id, Symbol("tm_$(tm_idx)_fiber_ep_$(tm_fiber_ep_idx)"))
            oxc_ep_key = (node_id, Symbol("oxc_ep_$(oxc_ep_idx)"))
            
            if !haskey(sdn.device_map, tm_ep_key)
                @warn "TM fiber endpoint not found: $tm_ep_key"
                continue
            end
            
            if !haskey(sdn.device_map, oxc_ep_key)
                @warn "OXC endpoint not found: $oxc_ep_key"
                continue
            end
            
            # Check if already used
            tm_ep_uuid = sdn.device_map[tm_ep_key]
            oxc_ep_uuid = sdn.device_map[oxc_ep_key]
            
            if get(sdn.endpoint_usage, tm_ep_uuid, false) || get(sdn.endpoint_usage, oxc_ep_uuid, false)
                @warn "Endpoints already in use for tm$tm_idx-oxc link: $tm_ep_key ↔ $oxc_ep_key"
                continue
            end
            
            # Generate link details
            link_uuid = stable_uuid(node_id * 2000 + tm_idx * 10 + tm_fiber_ep_idx, Symbol("tm$(tm_idx)_oxc_link_$(tm_fiber_ep_idx)"))
            link_name = "IntraLink-TM$(tm_idx)-fiber-ep$(tm_fiber_ep_idx)-OXC-ep$(oxc_ep_idx)-node-$(node_id)"
            link_key = (node_id, Symbol("tm$(tm_idx)_oxc_link_$(tm_fiber_ep_idx)"))
            
            # Store in intra-link map
            sdn.intra_link_map[link_key] = link_uuid
            
            # Create link using the fixed function signature
            success = create_link_between_devices(sdn, tm_ep_key, oxc_ep_key,
                                                link_name, link_uuid; link_type=link_type)
            
            if success
                # Mark endpoints as used
                sdn.endpoint_usage[tm_ep_uuid] = true
                sdn.endpoint_usage[oxc_ep_uuid] = true
                success_count += 1
                println("  ✓ TM$tm_idx-OXC link: fiber_ep$(tm_fiber_ep_idx) ↔ oxc_ep$(oxc_ep_idx)")
            else
                @warn "Failed to create TM$tm_idx-OXC link: fiber_ep$(tm_fiber_ep_idx) ↔ oxc_ep$(oxc_ep_idx)"
            end
        end
    end
    
    expected_links = 2 * num_tms
    println("  TM-OXC links: $success_count/$expected_links successful")
    return success_count == expected_links
end

"""
    connect_all_intra_node_devices(sdn::TeraflowSDN) → Int
Create all intra-node connections in the correct order:
1. Router ↔ ALL TMs (copper)
2. ALL TMs ↔ OXC (fiber) 
"""
function connect_all_intra_node_devices(sdn::TeraflowSDN)
    println("🔗 Creating intra-node device connections...")
    total_links = 0
    
    # Get all nodes that have devices
    nodes_with_devices = Set{Int}()
    for (key, uuid) in sdn.device_map
        if length(key) >= 2 && key[2] in [:router, :oxc] || (length(key) >= 2 && string(key[2]) |> x -> startswith(x, "tm_") && !contains(x, "_ep_"))
            push!(nodes_with_devices, key[1])
        end
    end
    
    for node_id in sort(collect(nodes_with_devices))
        println("  Node $node_id:")
        
        # Count TMs for this node - ONLY count TMs that actually exist in device_map
        tm_indices = Set{Int}()
        for (key, uuid) in sdn.device_map
            if length(key) >= 2 && key[1] == node_id && string(key[2]) |> x -> startswith(x, "tm_") && !contains(x, "_ep_")
                # Extract TM index from tm_X
                tm_match = match(r"tm_(\d+)", string(key[2]))
                if tm_match !== nothing
                    tm_idx = parse(Int, tm_match.captures[1])
                    push!(tm_indices, tm_idx)
                end
            end
        end
        
        num_tms = length(tm_indices)
        
        if num_tms == 0
            println("    No TMs found, skipping intra-node connections")
            continue
        end
        
        println("    Found $num_tms TMs (indices: $(sort(collect(tm_indices)))), creating connections...")
        
        # 1. Router ↔ ALL TMs (copper) - only for TMs that exist
        if create_router_tm_links_selective(sdn, node_id, tm_indices)
            total_links += 2 * num_tms
        end
        
        # 2. ALL TMs ↔ OXC (fiber) - only for TMs that exist
        if create_tm_oxc_links_selective(sdn, node_id, tm_indices)
            total_links += 2 * num_tms
        end
    end
    
    println("✓ Intra-node connections complete: $total_links links created")
    return total_links
end

"""
    create_router_tm_links_selective(sdn::TeraflowSDN, node_id::Int, tm_indices::Set{Int}) → Bool
Create intra-node links between router and EXISTING TMs only.
"""
function create_router_tm_links_selective(sdn::TeraflowSDN, node_id::Int, tm_indices::Set{Int}; link_type::Symbol = :copper)
    success_count = 0
    
    for tm_idx in sort(collect(tm_indices))
        # Calculate router endpoint indices for this TM
        router_ep1_idx = 2 * tm_idx - 1  # Odd indices: 1, 3, 5, ...
        router_ep2_idx = 2 * tm_idx      # Even indices: 2, 4, 6, ...
        
        # Create 2 links for this TM
        for (router_ep_idx, tm_copper_ep_idx) in [(router_ep1_idx, 1), (router_ep2_idx, 2)]
            router_ep_key = (node_id, Symbol("router_ep_$(router_ep_idx)"))
            tm_ep_key = (node_id, Symbol("tm_$(tm_idx)_copper_ep_$(tm_copper_ep_idx)"))
            
            if !haskey(sdn.device_map, router_ep_key)
                @warn "Router endpoint not found: $router_ep_key"
                continue
            end
            
            if !haskey(sdn.device_map, tm_ep_key)
                @warn "TM copper endpoint not found: $tm_ep_key"
                continue
            end
            
            # Check if already used
            router_ep_uuid = sdn.device_map[router_ep_key]
            tm_ep_uuid = sdn.device_map[tm_ep_key]
            
            if get(sdn.endpoint_usage, router_ep_uuid, false) || get(sdn.endpoint_usage, tm_ep_uuid, false)
                @warn "Endpoints already in use for router-tm$tm_idx link: $router_ep_key ↔ $tm_ep_key"
                continue
            end
            
            # Generate link details
            link_uuid = stable_uuid(node_id * 1000 + tm_idx * 10 + tm_copper_ep_idx, Symbol("router_tm$(tm_idx)_link_$(tm_copper_ep_idx)"))
            link_name = "IntraLink-Router-ep$(router_ep_idx)-TM$(tm_idx)-copper-ep$(tm_copper_ep_idx)-node-$(node_id)"
            link_key = (node_id, Symbol("router_tm$(tm_idx)_link_$(tm_copper_ep_idx)"))
            
            # Store in intra-link map
            sdn.intra_link_map[link_key] = link_uuid
            
            # Create link using the fixed function signature
            success = create_link_between_devices(sdn, router_ep_key, tm_ep_key, 
                                                link_name, link_uuid; link_type=link_type)
            
            if success
                # Mark endpoints as used
                sdn.endpoint_usage[router_ep_uuid] = true
                sdn.endpoint_usage[tm_ep_uuid] = true
                success_count += 1
                println("  ✓ Router-TM$tm_idx link: ep$(router_ep_idx) ↔ copper_ep$(tm_copper_ep_idx)")

                # Add delay to prevent API overload
                sleep(0.1)
            else
                @warn "Failed to create Router-TM$tm_idx link: ep$(router_ep_idx) ↔ copper_ep$(tm_copper_ep_idx)"
            end
        end
    end
    
    expected_links = 2 * length(tm_indices)
    println("  Router-TM links: $success_count/$expected_links successful")
    return success_count == expected_links
end

"""
    create_tm_oxc_links_selective(sdn::TeraflowSDN, node_id::Int, tm_indices::Set{Int}) → Bool
Create intra-node links between EXISTING TMs and OXC only.
"""
function create_tm_oxc_links_selective(sdn::TeraflowSDN, node_id::Int, tm_indices::Set{Int}; link_type::Symbol = :fiber)
    success_count = 0
    
    for tm_idx in sort(collect(tm_indices))
        # Calculate OXC endpoint indices for this TM
        oxc_ep1_idx = 2 * tm_idx - 1  # Odd indices: 1, 3, 5, ...
        oxc_ep2_idx = 2 * tm_idx      # Even indices: 2, 4, 6, ...
        
        # Create 2 links for this TM
        for (tm_fiber_ep_idx, oxc_ep_idx) in [(1, oxc_ep1_idx), (2, oxc_ep2_idx)]
            tm_ep_key = (node_id, Symbol("tm_$(tm_idx)_fiber_ep_$(tm_fiber_ep_idx)"))
            oxc_ep_key = (node_id, Symbol("oxc_ep_$(oxc_ep_idx)"))
            
            if !haskey(sdn.device_map, tm_ep_key)
                @warn "TM fiber endpoint not found: $tm_ep_key"
                continue
            end
            
            if !haskey(sdn.device_map, oxc_ep_key)
                @warn "OXC endpoint not found: $oxc_ep_key"
                continue
            end
            
            # Check if already used
            tm_ep_uuid = sdn.device_map[tm_ep_key]
            oxc_ep_uuid = sdn.device_map[oxc_ep_key]
            
            if get(sdn.endpoint_usage, tm_ep_uuid, false) || get(sdn.endpoint_usage, oxc_ep_uuid, false)
                @warn "Endpoints already in use for tm$tm_idx-oxc link: $tm_ep_key ↔ $oxc_ep_key"
                continue
            end
            
            # Generate link details
            link_uuid = stable_uuid(node_id * 2000 + tm_idx * 10 + tm_fiber_ep_idx, Symbol("tm$(tm_idx)_oxc_link_$(tm_fiber_ep_idx)"))
            link_name = "IntraLink-TM$(tm_idx)-fiber-ep$(tm_fiber_ep_idx)-OXC-ep$(oxc_ep_idx)-node-$(node_id)"
            link_key = (node_id, Symbol("tm$(tm_idx)_oxc_link_$(tm_fiber_ep_idx)"))
            
            # Store in intra-link map
            sdn.intra_link_map[link_key] = link_uuid
            
            # Create link using the fixed function signature
            success = create_link_between_devices(sdn, tm_ep_key, oxc_ep_key,
                                                link_name, link_uuid; link_type=link_type)
            
            if success
                # Mark endpoints as used
                sdn.endpoint_usage[tm_ep_uuid] = true
                sdn.endpoint_usage[oxc_ep_uuid] = true
                success_count += 1
                println("  ✓ TM$tm_idx-OXC link: fiber_ep$(tm_fiber_ep_idx) ↔ oxc_ep$(oxc_ep_idx)")

                # Add delay to prevent API overload
                sleep(0.1)
            else
                @warn "Failed to create TM$tm_idx-OXC link: fiber_ep$(tm_fiber_ep_idx) ↔ oxc_ep$(oxc_ep_idx)"
            end
        end
    end
    
    expected_links = 2 * length(tm_indices)
    println("  TM-OXC links: $success_count/$expected_links successful")
    return success_count == expected_links
end