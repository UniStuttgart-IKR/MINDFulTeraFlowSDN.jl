"""
Shared OLS device creation and management
"""

# Add new functions for shared OLS devices
function create_shared_ols_device(sdn::TeraflowSDN, node1_id::Int, node2_id::Int)
    """Create a shared OLS device between two nodes with 4 fiber endpoints"""
    # Generate stable UUID for OLS device based on both nodes
    sorted_nodes = sort([node1_id, node2_id])
    ols_key = (sorted_nodes[1], sorted_nodes[2], :shared_ols)
    ols_uuid = get!(sdn.device_map, ols_key) do
        stable_uuid(sorted_nodes[1] * 1000 + sorted_nodes[2], :shared_ols)
    end
    
    # Create 4 fiber endpoints for the shared OLS
    endpoints = String[]
    for ep_id in 1:4
        ep_uuid = stable_uuid(sorted_nodes[1] * 10000 + sorted_nodes[2] * 100 + ep_id, Symbol("shared_ols_ep_$(ep_id)"))
        ep_key = (sorted_nodes[1], sorted_nodes[2], Symbol("shared_ols_ep_$(ep_id)"))
        
        sdn.device_map[ep_key] = ep_uuid
        sdn.endpoint_usage[ep_uuid] = false
        push!(endpoints, ep_uuid)
    end
    
    # Create endpoints config
    endpoints_config = []
    for (i, ep_uuid) in enumerate(endpoints)
        push!(endpoints_config, Dict("sample_types"=>Any[],
                                    "type"=>"fiber",
                                    "uuid"=>ep_uuid,
                                    "name"=>"shared_ols_ep_$(i)_nodes_$(sorted_nodes[1])_$(sorted_nodes[2])"))
    end

    ep_rule = _custom_rule("_connect/settings", Dict("endpoints" => endpoints_config))

    device_drivers = Vector{Ctx.DeviceDriverEnum.T}()
    push!(device_drivers, Ctx.DeviceDriverEnum.DEVICEDRIVER_UNDEFINED)

    dev = Ctx.Device(
        Ctx.DeviceId(Ctx.Uuid(ols_uuid)),
        "SharedOLS-Nodes-$(sorted_nodes[1])-$(sorted_nodes[2])",
        "emu-open-line-system",
        Ctx.DeviceConfig([ep_rule]),
        Ctx.DeviceOperationalStatusEnum.DEVICEOPERATIONALSTATUS_ENABLED,
        device_drivers,
        Ctx.EndPoint[], Ctx.Component[], nothing)

    if ensure_post_device(sdn.api_url, dev)
        println("✓ Shared OLS device $ols_uuid created successfully for nodes $(sorted_nodes[1]) ↔ $(sorted_nodes[2])")
        return ols_uuid, endpoints
    else
        @warn "Shared OLS device $ols_uuid could not be created/updated"
        return nothing, []
    end
end

# Add helper function for shared OLS linking
function create_link_between_devices_shared_ols(sdn::TeraflowSDN, oxc_ep_key::Tuple, ols_ep_key::Tuple,
                                               link_name::String, link_uuid::String;
                                               link_type::Symbol = :fiber)
    
    if !haskey(sdn.device_map, oxc_ep_key)
        @warn "OXC endpoint not found: $oxc_ep_key"
        return false
    end
    
    if !haskey(sdn.device_map, ols_ep_key)
        @warn "Shared OLS endpoint not found: $ols_ep_key"
        return false
    end
    
    oxc_ep_uuid = sdn.device_map[oxc_ep_key]
    ols_ep_uuid = sdn.device_map[ols_ep_key]
    
    # Get OXC device UUID
    node_id = oxc_ep_key[1]
    oxc_device_key = (node_id, :oxc)
    if !haskey(sdn.device_map, oxc_device_key)
        @warn "OXC device not found: $oxc_device_key"
        return false
    end
    oxc_device_uuid = sdn.device_map[oxc_device_key]
    
    # Get shared OLS device UUID
    ols_device_key = (ols_ep_key[1], ols_ep_key[2], :shared_ols)
    if !haskey(sdn.device_map, ols_device_key)
        @warn "Shared OLS device not found: $ols_device_key"
        return false
    end
    ols_device_uuid = sdn.device_map[ols_device_key]
    
    # Create EndPointIds
    endpoint_ids = [
        Ctx.EndPointId(
            nothing,
            Ctx.DeviceId(Ctx.Uuid(oxc_device_uuid)),
            Ctx.Uuid(oxc_ep_uuid)
        ),
        Ctx.EndPointId(
            nothing,
            Ctx.DeviceId(Ctx.Uuid(ols_device_uuid)),
            Ctx.Uuid(ols_ep_uuid)
        )
    ]
    
    # Create link
    link = Ctx.Link(
        Ctx.LinkId(Ctx.Uuid(link_uuid)),
        link_name,
        Ctx.LinkTypeEnum.LINKTYPE_FIBER,
        endpoint_ids,
        Ctx.LinkAttributes(0.0f0, 0.0f0)
    )
    
    return ensure_post_link(sdn.api_url, link)
end