"""
Endpoint creation and management functions
"""

# Update OXC endpoint calculation function
function oxc_endpoints_needed(nodeview)
    neighbors = Set{Int}()
    union!(neighbors, nodeview.nodeproperties.inneighbors)
    union!(neighbors, nodeview.nodeproperties.outneighbors)
    # OXC needs: 2 endpoints for TM connection + 2 endpoints per neighbor for inter-node OLS connections
    return 2 + length(neighbors) * 2
end

"""
    calculate_oxc_endpoint_needs(nodeviews) → Dict{Int,Int}

Returns a mapping from OXC node_id to total endpoints needed,
which is 2 for TM connection + 2 × number of neighbors (in + out).
"""
function calculate_oxc_endpoint_needs(nodeviews)
    needs = Dict{Int, Int}()
    for nodeview in nodeviews
        node_id = nodeview.nodeproperties.localnode
        # OXC is created for every node that has devices
        if nodeview.oxcview !== nothing
            neighbors = Set{Int}()
            union!(neighbors, nodeview.nodeproperties.inneighbors)
            union!(neighbors, nodeview.nodeproperties.outneighbors)
            num_links = length(neighbors)
            needs[node_id] = 2 + num_links * 2  # 2 for TM + 2 per neighbor
        end
    end
    for (node, n_endpoints) in sort(collect(needs))
        println("  Node $node: OXC endpoints needed = $n_endpoints")
    end
    return needs
end

function create_router_endpoints(sdn::TeraflowSDN, node_id::Int)
    """Create 2 copper endpoints for a router device"""
    endpoints = String[]
    
    for ep_id in 1:2
        ep_uuid = stable_uuid(node_id * 1000 + ep_id, Symbol("router_ep_$(ep_id)"))
        ep_key = (node_id, Symbol("router_ep_$(ep_id)"))
        
        sdn.device_map[ep_key] = ep_uuid
        sdn.endpoint_usage[ep_uuid] = false  # Initially unused
        push!(endpoints, ep_uuid)
    end
    
    return endpoints
end

function create_tm_endpoints(sdn::TeraflowSDN, node_id::Int, tm_idx::Int)
    """Create 4 endpoints for a TM device (2 copper + 2 fiber)"""
    endpoints = String[]
    
    # 2 copper endpoints
    for ep_id in 1:2
        ep_uuid = stable_uuid(node_id * 10_000 + tm_idx * 100 + ep_id, Symbol("tm_copper_ep_$(ep_id)"))
        ep_key = (node_id, Symbol("tm_$(tm_idx)_copper_ep_$(ep_id)"))
        
        sdn.device_map[ep_key] = ep_uuid
        sdn.endpoint_usage[ep_uuid] = false
        push!(endpoints, ep_uuid)
    end
    
    # 2 fiber endpoints
    for ep_id in 1:2
        ep_uuid = stable_uuid(node_id * 10_000 + tm_idx * 100 + ep_id + 10, Symbol("tm_fiber_ep_$(ep_id)"))
        ep_key = (node_id, Symbol("tm_$(tm_idx)_fiber_ep_$(ep_id)"))
        
        sdn.device_map[ep_key] = ep_uuid
        sdn.endpoint_usage[ep_uuid] = false
        push!(endpoints, ep_uuid)
    end
    
    return endpoints
end

function create_oxc_endpoints(sdn::TeraflowSDN, node_id::Int, min_endpoints::Int = 4)
    """Create fixed number of fiber endpoints for an OXC device"""
    endpoints = String[]
    
    for ep_id in 1:min_endpoints
        ep_uuid = stable_uuid(node_id * 1000 + ep_id, Symbol("oxc_ep_$(ep_id)"))
        ep_key = (node_id, Symbol("oxc_ep_$(ep_id)"))
        
        sdn.device_map[ep_key] = ep_uuid
        sdn.endpoint_usage[ep_uuid] = false  # Initially unused
        push!(endpoints, ep_uuid)
    end
    
    return endpoints
end

function get_available_endpoint(sdn::TeraflowSDN, node_id::Int, ep_prefix::String)
    """Get an available endpoint for a given node and endpoint type prefix"""
    available_endpoints = []
    
    for (key, uuid) in sdn.device_map
        # Handle both regular endpoint keys (node_id, :endpoint_name) and shared OLS endpoints
        if (length(key) == 2 && key[1] == node_id && string(key[2]) |> x -> startswith(x, ep_prefix)) ||
           (length(key) == 3 && string(key[3]) |> x -> startswith(x, ep_prefix))
            if !get(sdn.endpoint_usage, uuid, false)
                push!(available_endpoints, (key, uuid))
            end
        end
    end
    
    if isempty(available_endpoints)
        error("No available $ep_prefix endpoint for node $node_id")
    end
    
    # Return the first available endpoint
    key, uuid = first(available_endpoints)
    return key, uuid
end

function get_available_oxc_endpoint(sdn::TeraflowSDN, node_id::Int)
    return get_available_endpoint(sdn, node_id, "oxc_ep_")
end

function get_available_shared_ols_endpoint(sdn::TeraflowSDN, node1_id::Int, node2_id::Int)
    """Get available endpoint from shared OLS device between two nodes"""
    sorted_nodes = sort([node1_id, node2_id])
    
    # Find existing endpoints for this shared OLS
    existing_endpoints = []
    for (key, uuid) in sdn.device_map
        if length(key) == 3 && key[1] == sorted_nodes[1] && key[2] == sorted_nodes[2] && 
           string(key[3]) |> x -> startswith(x, "shared_ols_ep_")
            push!(existing_endpoints, (key, uuid))
        end
    end
    
    # Check for available endpoint
    for (key, uuid) in existing_endpoints
        if !get(sdn.endpoint_usage, uuid, false)
            return key, uuid
        end
    end
    
    error("No available shared OLS endpoint for nodes $node1_id ↔ $node2_id")
end