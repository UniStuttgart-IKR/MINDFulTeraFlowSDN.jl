using JLD2

# Open the JLD2 file
jldopen("data/device_map.jld2", "r") do file
    println("Keys in file: ", keys(file))
    println()
    
    # Access and print the contents of the "device_map" dataset
    if haskey(file, "device_map")
        device_map = file["device_map"]
        println("=== DEVICE MAP ===")
        println(rpad("Node", 6), rpad("Type", 25), rpad("UUID", 38), "Description")
        println("-"^95)

        # Group by node for better organization
        nodes = Dict{Int, Vector{Tuple}}()
        for ((node, dtype), uuid) in device_map
            if !haskey(nodes, node)
                nodes[node] = []
            end
            push!(nodes[node], (dtype, uuid))
        end

        for node_id in sort(collect(keys(nodes)))
            # Sort device types: main devices first, then endpoints
            device_entries = sort(nodes[node_id], by=x->begin
                dtype_str = string(x[1])
                if dtype_str in ["router", "oxc", "ols", "tm_1"]
                    "1_" * dtype_str  # Main devices first
                elseif contains(dtype_str, "_ep")
                    "2_" * dtype_str  # Endpoints second
                else
                    "3_" * dtype_str  # Others last
                end
            end)
            
            for (i, (dtype, uuid)) in enumerate(device_entries)
                dtype_str = string(dtype)
                
                # Generate description based on device type
                description = if dtype_str == "router"
                    "Main router device"
                elseif dtype_str == "oxc"
                    "Optical cross-connect"
                elseif dtype_str == "ols"
                    "Open line system"
                elseif startswith(dtype_str, "tm_")
                    tm_num = replace(dtype_str, "tm_" => "")
                    "Transmission module #$tm_num"
                elseif startswith(dtype_str, "router_ep_")
                    ep_num = replace(dtype_str, "router_ep_" => "")
                    "Router endpoint #$ep_num (copper)"
                elseif startswith(dtype_str, "oxc_ep_")
                    ep_num = replace(dtype_str, "oxc_ep_" => "")
                    "OXC endpoint #$ep_num (fiber)"
                elseif startswith(dtype_str, "ols_ep_")
                    ep_num = replace(dtype_str, "ols_ep_" => "")
                    "OLS endpoint #$ep_num (fiber)"
                elseif startswith(dtype_str, "tm_") && contains(dtype_str, "_copper_ep_")
                    parts = split(dtype_str, "_")
                    tm_num = parts[2]
                    ep_num = parts[end]
                    "TM#$tm_num copper endpoint #$ep_num"
                elseif startswith(dtype_str, "tm_") && contains(dtype_str, "_fiber_ep_")
                    parts = split(dtype_str, "_")
                    tm_num = parts[2]
                    ep_num = parts[end]
                    "TM#$tm_num fiber endpoint #$ep_num"
                else
                    "Unknown device type"
                end
                
                println(rpad(string(node_id), 6), rpad(dtype_str, 25), 
                       rpad(uuid, 38), description)
            end
            
            # Add spacing between nodes for readability
            if node_id != maximum(keys(nodes))
                println()
            end
        end
        println()
    else
        println("No device_map found in file")
    end
    
    # Access and print endpoint usage
    if haskey(file, "endpoint_usage")
        endpoint_usage = file["endpoint_usage"]
        println("=== ENDPOINT USAGE ===")
        
        # Group endpoints by node and device
        endpoint_nodes = Dict{Int, Dict{String, Vector{Tuple}}}()
        device_map = haskey(file, "device_map") ? file["device_map"] : Dict()
        
        for (uuid, is_used) in endpoint_usage
            # Find which device this endpoint belongs to
            node_info = nothing
            for ((node, dtype), dev_uuid) in device_map
                if dev_uuid == uuid
                    node_info = (node, dtype)
                    break
                end
            end
            
            if node_info !== nothing
                node_id, dtype = node_info
                dtype_str = string(dtype)
                
                # Categorize by device type
                device_category = if startswith(dtype_str, "router_ep_")
                    "Router"
                elseif startswith(dtype_str, "tm_") && contains(dtype_str, "_copper_ep_")
                    "TM (Copper)"
                elseif startswith(dtype_str, "tm_") && contains(dtype_str, "_fiber_ep_")
                    "TM (Fiber)"
                elseif startswith(dtype_str, "oxc_ep_")
                    "OXC"
                elseif startswith(dtype_str, "ols_ep_")
                    "OLS"
                else
                    "Other"
                end
                
                if !haskey(endpoint_nodes, node_id)
                    endpoint_nodes[node_id] = Dict{String, Vector{Tuple}}()
                end
                if !haskey(endpoint_nodes[node_id], device_category)
                    endpoint_nodes[node_id][device_category] = []
                end
                push!(endpoint_nodes[node_id][device_category], (dtype, uuid, is_used))
            end
        end
        
        println(rpad("Node", 6), rpad("Device", 15), rpad("Endpoint", 25), rpad("Status", 10), "UUID")
        println("-"^100)
        
        for node_id in sort(collect(keys(endpoint_nodes)))
            device_categories = ["Router", "TM (Copper)", "TM (Fiber)", "OXC", "OLS", "Other"]
            
            for category in device_categories
                if haskey(endpoint_nodes[node_id], category)
                    endpoints = sort(endpoint_nodes[node_id][category], by=x->string(x[1]))
                    
                    for (dtype, uuid, is_used) in endpoints
                        status = is_used ? "🔴 USED" : "🟢 FREE"
                        
                        println(rpad(string(node_id), 6), rpad(category, 15), 
                               rpad(string(dtype), 25), rpad(status, 10), uuid)
                    end
                end
            end
            
            if node_id != maximum(keys(endpoint_nodes))
                println()
            end
        end
        
        # Summary stats by device type
        device_usage = Dict{String, Tuple{Int, Int}}()  # (used, total)
        for (node_id, categories) in endpoint_nodes
            for (category, endpoints) in categories
                if !haskey(device_usage, category)
                    device_usage[category] = (0, 0)
                end
                used, total = device_usage[category]
                category_used = count(x -> x[3], endpoints)
                category_total = length(endpoints)
                device_usage[category] = (used + category_used, total + category_total)
            end
        end
        
        println("\nEndpoint Summary by Device Type:")
        for (device_type, (used, total)) in sort(collect(device_usage))
            percentage = total > 0 ? round(used/total*100, digits=1) : 0.0
            println("  $device_type: $used/$total used ($percentage%)")
        end
        
        used_count = count(values(endpoint_usage))
        total_count = length(endpoint_usage)
        println("\nTotal Endpoints: $used_count/$total_count used ($(round(used_count/total_count*100, digits=1))%)")
        println()
    else
        println("No endpoint_usage found in file")
        println()
    end
    
    # Access and print intra-node links
    if haskey(file, "intra_link_map")
        intra_link_map = file["intra_link_map"]
        println("=== INTRA-NODE LINKS ===")
        println(rpad("Node", 6), rpad("Link Type", 25), rpad("UUID", 38), "Description")
        println("-"^95)

        # Group by node
        intra_links_by_node = Dict{Int, Vector{Tuple}}()
        for ((node_id, link_type), uuid) in intra_link_map
            if !haskey(intra_links_by_node, node_id)
                intra_links_by_node[node_id] = []
            end
            push!(intra_links_by_node[node_id], (link_type, uuid))
        end

        for node_id in sort(collect(keys(intra_links_by_node)))
            # Sort links by type for consistent ordering
            links = sort(intra_links_by_node[node_id], by=x->string(x[1]))
            
            for (link_type, uuid) in links
                link_type_str = string(link_type)
                
                description = if startswith(link_type_str, "router_tm_link")
                    ep_num = replace(link_type_str, "router_tm_link_" => "")
                    "Router ep$ep_num ↔ TM1 copper ep$ep_num"
                elseif startswith(link_type_str, "tm_oxc_link")
                    ep_num = replace(link_type_str, "tm_oxc_link_" => "")
                    "TM1 fiber ep$ep_num ↔ OXC ep$ep_num"
                elseif startswith(link_type_str, "oxc_ols_link")
                    ep_num = replace(link_type_str, "oxc_ols_link_" => "")
                    oxc_ep = parse(Int, ep_num) + 2  # OXC ep3,ep4
                    "OXC ep$oxc_ep ↔ OLS ep$ep_num"
                elseif link_type_str == "router_ols_link"
                    "Router ↔ OLS connection (legacy)"
                else
                    "Unknown intra-node link"
                end
                
                println(rpad(string(node_id), 6), rpad(link_type_str, 25), 
                       rpad(uuid, 38), description)
            end
            
            if node_id != maximum(keys(intra_links_by_node))
                println()
            end
        end
        println()
    else
        println("No intra_link_map found in file")
        println()
    end
    
    # Access and print inter-node links
    if haskey(file, "inter_link_map")
        inter_link_map = file["inter_link_map"]
        println("=== INTER-NODE LINKS ===")
        println(rpad("Connection", 45), rpad("Direction", 15), rpad("UUID", 38), "Description")
        println("-"^105)

        for (link_key, uuid) in sort(collect(inter_link_map), by=x->string(x[1]))
            if length(link_key) == 6 && link_key[5] == :link
                node1, ep1_id, node2, ep2_id, _, direction = link_key
                connection = "$ep1_id-node-$node1 ↔ $ep2_id-node-$node2"
                direction_str = string(direction)
                
                # Determine link description based on endpoint types
                description = if string(ep1_id) |> x -> startswith(x, "ols_ep_")
                    "OLS-to-OLS fiber connection"
                elseif string(ep1_id) |> x -> startswith(x, "oxc_ep_")
                    "OXC-to-OXC fiber connection (legacy)"
                else
                    "Unknown inter-node connection"
                end
                
                println(rpad(connection, 45), rpad(direction_str, 15), 
                       rpad(uuid, 38), description)
            else
                # Handle unknown format
                connection = string(link_key)
                println(rpad(connection, 45), rpad("unknown", 15), 
                       rpad(uuid, 38), "Unknown inter-node link")
            end
        end
        println()
    else
        println("No inter_link_map found in file")
        println()
    end
    
    # Enhanced Summary
    device_count = haskey(file, "device_map") ? length(file["device_map"]) : 0
    endpoint_count = haskey(file, "endpoint_usage") ? length(file["endpoint_usage"]) : 0
    intra_link_count = haskey(file, "intra_link_map") ? length(file["intra_link_map"]) : 0
    inter_link_count = haskey(file, "inter_link_map") ? length(file["inter_link_map"]) : 0
    
    println("=== SUMMARY ===")
    println("Total devices/endpoints: $device_count")
    println("Total managed endpoints: $endpoint_count")
    println("Total intra-node links: $intra_link_count")
    println("Total inter-node links: $inter_link_count")
    
    # Network topology summary
    if haskey(file, "device_map")
        device_map = file["device_map"]
        router_count = count(x -> x[1][2] == :router, device_map)
        oxc_count = count(x -> x[1][2] == :oxc, device_map)
        ols_count = count(x -> x[1][2] == :ols, device_map)
        tm_count = count(x -> string(x[1][2]) |> y -> startswith(y, "tm_") && !contains(y, "_ep_"), device_map)
        
        println("\nNetwork Composition:")
        println("  Routers: $router_count")
        println("  Transmission Modules: $tm_count")
        println("  OXCs: $oxc_count")
        println("  OLS devices: $ols_count")
        
        if endpoint_count > 0
            used_endpoints = haskey(file, "endpoint_usage") ? count(values(file["endpoint_usage"])) : 0
            utilization = round(used_endpoints / endpoint_count * 100, digits=1)
            println("  Endpoint utilization: $utilization%")
        end
        
        # Connectivity summary
        if intra_link_count > 0 && router_count > 0
            expected_intra_links = router_count * 6  # 2 router-tm + 2 tm-oxc + 2 oxc-ols per node
            connectivity = round(intra_link_count / expected_intra_links * 100, digits=1)
            println("  Intra-node connectivity: $connectivity% ($intra_link_count/$expected_intra_links)")
        end
    end
end