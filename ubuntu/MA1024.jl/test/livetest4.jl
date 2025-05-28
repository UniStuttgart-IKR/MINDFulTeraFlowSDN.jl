using MA1024, JSON3
using MA1024.TFS
using JLD2, UUIDs
using MINDFul
import AttributeGraphs as AG

const MINDF = MINDFul

println("=== TeraFlow Link Creation Test ===")

# Initialize SDN controller
sdncontroller = TeraflowSDN()
load_device_map!("data/device_map.jld2", sdncontroller)

println("Loaded device map with $(length(sdncontroller.device_map)) entries")

# Display current device map for node 24
node_id = 24
println("\nDevice map entries for node $node_id:")
for (key, uuid) in sdncontroller.device_map
    if key[1] == node_id
        println("  $key => $uuid")
    end
end

# Check if both router and OXC endpoints exist for node 24
router_ep_key = (node_id, :router_ep)
oxc_ep_key = (node_id, :oxc_ep)

if haskey(sdncontroller.device_map, router_ep_key) && haskey(sdncontroller.device_map, oxc_ep_key)
    println("\n✓ Both Router and OXC endpoints found for node $node_id")
    
    router_ep_uuid = sdncontroller.device_map[router_ep_key]
    oxc_ep_uuid = sdncontroller.device_map[oxc_ep_key]
    
    println("  Router endpoint UUID: $router_ep_uuid")
    println("  OXC endpoint UUID: $oxc_ep_uuid")
    
    # Create the link between router and OXC on node 24
    println("\n--- Creating Router-OXC Link for Node $node_id ---")
    
    link_created = create_router_oxc_link(sdncontroller, node_id; 
                                        link_type = :copper) 
    
    if link_created
        println("✅ Successfully created Router-OXC link for node $node_id")
        
        # Save updated device map
        save_device_map("data/device_map.jld2", sdncontroller)
        println("✓ Device map saved")
        
        # Verify the link was created by querying TFS
        println("\n--- Verifying Link Creation ---")
        try
            links_response = get_links(sdncontroller.api_url)
            println("Current links in TFS:")
            
            if haskey(links_response, "links") && !isempty(links_response["links"])
                for link in links_response["links"]
                    link_name = get(link, "name", "Unknown")
                    link_uuid = get(link, "link_id", Dict())["link_uuid"]["uuid"]
                    link_type = get(link, "link_type", "Unknown")
                    println("Found  - $link_name (UUID: $link_uuid, Type: $link_type)")
                end
            else
                println("  No links found")
            end
            
        catch e
            println("⚠️  Error retrieving links: $e")
        end
        
    else
        println("❌ Failed to create Router-OXC link for node $node_id")
    end
    
else
    println("\n❌ Missing endpoints for node $node_id")
    if !haskey(sdncontroller.device_map, router_ep_key)
        println("  Missing: Router endpoint")
    end
    if !haskey(sdncontroller.device_map, oxc_ep_key)
        println("  Missing: OXC endpoint")
    end
    
    println("\nAvailable device map entries:")
    for (key, uuid) in sdncontroller.device_map
        println("  $key => $uuid")
    end
end

println("\n=== Test Complete ===")