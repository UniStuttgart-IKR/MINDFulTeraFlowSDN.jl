using JLD2

# Open the JLD2 file
jldopen("data/device_map.jld2", "r") do file
    println("Keys in file: ", keys(file))
    println()
    
    # Access and print the contents of the "device_map" dataset
    if haskey(file, "device_map")
        device_map = file["device_map"]
        println("=== DEVICE MAP ===")
        println(rpad("Node", 10), rpad("Type", 15), "UUID")
        println("-"^60)

        for ((node, dtype), uuid) in sort(collect(device_map))
            println(rpad(string(node), 10), rpad(string(dtype), 15), uuid)
        end
        println()
    else
        println("No device_map found in file")
    end
    
    # Access and print the contents of the "link_map" dataset
    if haskey(file, "link_map")
        link_map = file["link_map"]
        println("=== LINK MAP ===")
        println(rpad("Link Type", 20), rpad("Details", 40), "UUID")
        println("-"^80)

        for (link_key, uuid) in sort(collect(link_map), by=x->string(x[1]))
            if length(link_key) == 2 && link_key[2] == :router_oxc_link
                # Intra-node router-OXC link: (node_id, :router_oxc_link)
                node_id = link_key[1]
                link_type = "Intra-Node"
                details = "Router-OXC on Node $node_id"
                
            elseif length(link_key) == 5 && link_key[1] == :link
                # Inter-node link: (:link, node1, node2, device1_type, device2_type)
                _, node1, node2, dev1_type, dev2_type = link_key
                link_type = "Inter-Node"
                details = "$dev1_type-$node1 ↔ $dev2_type-$node2"
                
            else
                # Unknown format
                link_type = "Unknown"
                details = string(link_key)
            end
            
            println(rpad(link_type, 20), rpad(details, 40), uuid)
        end
        println()
    else
        println("No link_map found in file (legacy format)")
        println()
    end
    
    # Summary
    device_count = haskey(file, "device_map") ? length(file["device_map"]) : 0
    link_count = haskey(file, "link_map") ? length(file["link_map"]) : 0
    
    println("=== SUMMARY ===")
    println("Total devices/endpoints: $device_count")
    println("Total links: $link_count")
end