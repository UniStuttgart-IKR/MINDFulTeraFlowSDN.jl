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
    create_router_tm_link(sdn::TeraflowSDN, node_id::Int) → Bool
Create intra-node link between router and first TM using copper endpoints.
Router ep1 (incoming) → TM copper ep1, Router ep2 (outgoing) → TM copper ep2
"""
function create_router_tm_link(sdn::TeraflowSDN, node_id::Int; link_type::Symbol = :copper)
    # Check if first TM exists
    tm_key = (node_id, :tm_1)
    if !haskey(sdn.device_map, tm_key)
        @warn "First TM device not found for node $node_id"
        return false
    end
    
    success_count = 0
    
    # Create two links: Router ep1 ↔ TM copper ep1, Router ep2 ↔ TM copper ep2
    for ep_pair in [(1, 1), (2, 2)]
        router_ep_idx, tm_ep_idx = ep_pair
        
        router_ep_key = (node_id, Symbol("router_ep_$(router_ep_idx)"))
        tm_ep_key = (node_id, Symbol("tm_1_copper_ep_$(tm_ep_idx)"))
        
        if !haskey(sdn.device_map, router_ep_key)
            @warn "Router endpoint not found: $router_ep_key"
            continue
        end
        
        if !haskey(sdn.device_map, tm_ep_key)
            @warn "TM endpoint not found: $tm_ep_key"
            continue
        end
        
        router_ep_uuid = sdn.device_map[router_ep_key]
        tm_ep_uuid = sdn.device_map[tm_ep_key]
        
        # Check if already used
        if get(sdn.endpoint_usage, router_ep_uuid, false) || get(sdn.endpoint_usage, tm_ep_uuid, false)
            @warn "Endpoints already in use for router-tm link: $router_ep_key ↔ $tm_ep_key"
            continue
        end
        
        # Generate link details
        link_uuid = stable_uuid(node_id * 100 + ep_pair[1], Symbol("router_tm_link_$(ep_pair[1])"))
        link_name = "IntraLink-Router-ep$(router_ep_idx)-TM1-copper-ep$(tm_ep_idx)-node-$(node_id)"
        link_key = (node_id, Symbol("router_tm_link_$(ep_pair[1])"))
        
        # Store in intra-link map
        sdn.intra_link_map[link_key] = link_uuid
        
        # Create the link
        success = create_link_between_devices(sdn, router_ep_key, tm_ep_key, 
                                            link_name, link_uuid; link_type=link_type)
        
        if success
            # Mark endpoints as used
            sdn.endpoint_usage[router_ep_uuid] = true
            sdn.endpoint_usage[tm_ep_uuid] = true
            success_count += 1
            println("✓ Created router-TM link: Router-ep$(router_ep_idx) ↔ TM1-copper-ep$(tm_ep_idx) (node $node_id)")
        else
            @warn "✗ Failed to create router-TM link for endpoints $(ep_pair) (node $node_id)"
        end
    end
    
    return success_count == 2  # Both links should succeed
end

"""
    create_tm_oxc_link(sdn::TeraFlowSDN, node_id::Int) → Bool
Create intra-node link between first TM and OXC using fiber endpoints.
TM fiber ep1 ↔ OXC ep1, TM fiber ep2 ↔ OXC ep2
"""
function create_tm_oxc_link(sdn::TeraflowSDN, node_id::Int; link_type::Symbol = :fiber)
    success_count = 0
    
    # Create two links: TM fiber ep1 ↔ OXC ep1, TM fiber ep2 ↔ OXC ep2
    for ep_pair in [(1, 1), (2, 2)]
        tm_ep_idx, oxc_ep_idx = ep_pair
        
        tm_ep_key = (node_id, Symbol("tm_1_fiber_ep_$(tm_ep_idx)"))
        oxc_ep_key = (node_id, Symbol("oxc_ep_$(oxc_ep_idx)"))
        
        if !haskey(sdn.device_map, tm_ep_key)
            @warn "TM fiber endpoint not found: $tm_ep_key"
            continue
        end
        
        if !haskey(sdn.device_map, oxc_ep_key)
            @warn "OXC endpoint not found: $oxc_ep_key"
            continue
        end
        
        tm_ep_uuid = sdn.device_map[tm_ep_key]
        oxc_ep_uuid = sdn.device_map[oxc_ep_key]
        
        # Check if already used
        if get(sdn.endpoint_usage, tm_ep_uuid, false) || get(sdn.endpoint_usage, oxc_ep_uuid, false)
            @warn "Endpoints already in use for tm-oxc link: $tm_ep_key ↔ $oxc_ep_key"
            continue
        end
        
        # Generate link details
        link_uuid = stable_uuid(node_id * 200 + ep_pair[1], Symbol("tm_oxc_link_$(ep_pair[1])"))
        link_name = "IntraLink-TM1-fiber-ep$(tm_ep_idx)-OXC-ep$(oxc_ep_idx)-node-$(node_id)"
        link_key = (node_id, Symbol("tm_oxc_link_$(ep_pair[1])"))
        
        # Store in intra-link map
        sdn.intra_link_map[link_key] = link_uuid
        
        # Create the link
        success = create_link_between_devices(sdn, tm_ep_key, oxc_ep_key,
                                            link_name, link_uuid; link_type=link_type)
        
        if success
            # Mark endpoints as used
            sdn.endpoint_usage[tm_ep_uuid] = true
            sdn.endpoint_usage[oxc_ep_uuid] = true
            success_count += 1
            println("✓ Created TM-OXC link: TM1-fiber-ep$(tm_ep_idx) ↔ OXC-ep$(oxc_ep_idx) (node $node_id)")
        else
            @warn "✗ Failed to create TM-OXC link for endpoints $(ep_pair) (node $node_id)"
        end
    end
    
    return success_count == 2
end

# Update intra-node connection function to only do Router ↔ TM ↔ OXC
"""
    connect_all_intra_node_devices(sdn::TeraflowSDN) → Int
Create all intra-node connections in the correct order:
1. Router ↔ TM1 (copper)
2. TM1 ↔ OXC (fiber) 
Note: OXC ↔ OLS connections are now handled in inter-node linking with shared OLS
"""
function connect_all_intra_node_devices(sdn::TeraflowSDN)
    links_created = 0
    
    # Find nodes with complete device sets (router, tm, oxc)
    nodes_with_router = Set{Int}()
    nodes_with_tm = Set{Int}()
    nodes_with_oxc = Set{Int}()
    
    for (key, uuid) in sdn.device_map
        if string(key[2]) |> x -> startswith(x, "router_ep_")
            push!(nodes_with_router, key[1])
        elseif key[2] == :tm_1
            push!(nodes_with_tm, key[1])
        elseif key[2] == :oxc
            push!(nodes_with_oxc, key[1])
        end
    end
    
    nodes_for_connection = intersect(nodes_with_router, nodes_with_tm, nodes_with_oxc)
    
    println("🔗 Found $(length(nodes_for_connection)) nodes for complete intra-node connections")
    
    for node_id in sort(collect(nodes_for_connection))
        println("🔧 Creating intra-node connections for node $node_id...")
        
        # Step 1: Router ↔ TM1 (copper)
        if create_router_tm_link(sdn, node_id; link_type=:copper)
            links_created += 2  # Two links created (ep1↔ep1, ep2↔ep2)
        end
        
        # Step 2: TM1 ↔ OXC (fiber)
        if create_tm_oxc_link(sdn, node_id; link_type=:fiber)
            links_created += 2  # Two links created
        end
        
        # Note: OXC ↔ OLS connections are now handled in inter-node linking
    end
    
    println("✅ Created $links_created total intra-node links")
    return links_created
end