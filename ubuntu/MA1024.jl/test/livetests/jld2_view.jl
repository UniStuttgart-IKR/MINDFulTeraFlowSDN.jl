using JLD2

# Open the JLD2 file
jldopen("data/device_map.jld2", "r") do file
    println("Keys in file: ", keys(file))
    println()
    
    # Access and print the contents of the "device_map" dataset
    if haskey(file, "device_map")
        device_map = file["device_map"]
        println("=== DEVICE MAP ===")
        println(rpad("Node", 6), rpad("Type", 20), rpad("UUID", 38), "Description")
        println("-"^90)

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
                if dtype_str in ["router", "oxc"]
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
                elseif dtype_str == "router_ep"
                    "Router endpoint (copper)"
                elseif startswith(dtype_str, "oxc_ep_")
                    ep_num = replace(dtype_str, "oxc_ep_" => "")
                    "OXC endpoint #$ep_num (fiber)"
                elseif dtype isa Tuple && length(dtype) == 2 && dtype[1] == :tm
                    "Transmission module #$(dtype[2])"
                elseif dtype isa Tuple && length(dtype) == 2 && dtype[1] == :tm_ep
                    "TM endpoint #$(dtype[2]) (copper)"
                else
                    "Unknown device type"
                end
                
                println(rpad(string(node_id), 6), rpad(dtype_str, 20), 
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
        
        # Group endpoints by node
        endpoint_nodes = Dict{Int, Vector{Tuple}}()
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
                if !haskey(endpoint_nodes, node_id)
                    endpoint_nodes[node_id] = []
                end
                push!(endpoint_nodes[node_id], (dtype, uuid, is_used))
            end
        end
        
        println(rpad("Node", 6), rpad("Endpoint", 20), rpad("Status", 8), "UUID")
        println("-"^70)
        
        for node_id in sort(collect(keys(endpoint_nodes)))
            endpoints = sort(endpoint_nodes[node_id], by=x->string(x[1]))
            
            for (dtype, uuid, is_used) in endpoints
                status = is_used ? "USED" : "FREE"
                status_colored = is_used ? "🔴 USED" : "🟢 FREE"
                
                println(rpad(string(node_id), 6), rpad(string(dtype), 20), 
                       rpad(status_colored, 8), uuid)
            end
            
            if node_id != maximum(keys(endpoint_nodes))
                println()
            end
        end
        
        # Summary stats
        used_count = count(values(endpoint_usage))
        total_count = length(endpoint_usage)
        println("\nEndpoint Summary: $used_count/$total_count used ($(round(used_count/total_count*100, digits=1))%)")
        println()
    else
        println("No endpoint_usage found in file")
        println()
    end
    
    # Access and print intra-node links
    if haskey(file, "intra_link_map")
        intra_link_map = file["intra_link_map"]
        println("=== INTRA-NODE LINKS ===")
        println(rpad("Node", 6), rpad("Link Type", 20), rpad("UUID", 38), "Description")
        println("-"^90)

        for ((node_id, link_type), uuid) in sort(collect(intra_link_map))
            description = if link_type == :router_oxc_link
                "Router ↔ OXC connection"
            else
                "Unknown intra-node link"
            end
            
            println(rpad(string(node_id), 6), rpad(string(link_type), 20), 
                   rpad(uuid, 38), description)
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
        println(rpad("Connection", 40), rpad("Direction", 15), rpad("UUID", 38), "Description")
        println("-"^100)

        for (link_key, uuid) in sort(collect(inter_link_map), by=x->string(x[1]))
            if length(link_key) == 6 && link_key[5] == :link
                node1, ep1_id, node2, ep2_id, _, direction = link_key
                connection = "$ep1_id-node-$node1 ↔ $ep2_id-node-$node2"
                direction_str = string(direction)
                description = "OXC fiber connection"
                
                println(rpad(connection, 40), rpad(direction_str, 15), 
                       rpad(uuid, 38), description)
            else
                # Handle unknown format
                connection = string(link_key)
                println(rpad(connection, 40), rpad("unknown", 15), 
                       rpad(uuid, 38), "Unknown inter-node link")
            end
        end
        println()
    else
        println("No inter_link_map found in file")
        println()
    end
    
    # Summary
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
        
        println("\nNetwork Composition:")
        println("  Routers: $router_count")
        println("  OXCs: $oxc_count")
        
        if endpoint_count > 0
            used_endpoints = haskey(file, "endpoint_usage") ? count(values(file["endpoint_usage"])) : 0
            utilization = round(used_endpoints / endpoint_count * 100, digits=1)
            println("  Endpoint utilization: $utilization%")
        end
    end
end