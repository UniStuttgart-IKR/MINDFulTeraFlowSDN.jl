using MA1024
using JSON3
using HTTP
using UUIDs

# Add delete_link function to HTTPClient functionality
function delete_link_http(api_url::String, link_uuid::String)
    url = "$api_url/link/$link_uuid"
    try
        resp = HTTP.delete(url)
        return resp.status == 200
    catch e
        println("Failed to delete link $link_uuid: $e")
        return false
    end
end

println("🔧 INTRA-NODE LINK MODIFICATION TEST")
println("="^60)

# Initialize SDN controller and load existing mappings
sdn = TeraflowSDN()
if isfile("data/device_map.jld2")
    load_device_map!("data/device_map.jld2", sdn)
    println("✓ Loaded existing device and link mappings")
else
    println("❌ No device map found. Please run network creation first.")
    exit(1)
end

# Test with node 10
test_node_id = 10

println("\n1. 🔍 FINDING INTRA-NODE LINK FOR NODE $test_node_id")
println("-"^50)

# Check if node has intra-node link
intra_link_key = (test_node_id, :router_oxc_link)
if !haskey(sdn.intra_link_map, intra_link_key)
    println("❌ No intra-node link found for node $test_node_id")
    println("Available intra-links:")
    for (key, uuid) in sdn.intra_link_map
        println("  Node $(key[1]): $uuid")
    end
    exit(1)
end

# Get the link UUID
link_uuid = sdn.intra_link_map[intra_link_key]
println("✓ Found intra-node link: $link_uuid")

# Verify link exists in TFS
println("\n2. 📡 VERIFYING LINK EXISTS IN TFS")
println("-"^40)

retrieved_link = get_link(sdn.api_url, link_uuid)
if retrieved_link !== nothing
    println("✓ Link exists in TFS")
    println("  Name: $(retrieved_link["name"])")
    println("  Type: $(retrieved_link["link_type"])")
    println("  Endpoints: $(length(retrieved_link["link_endpoint_ids"]))")
    
    # Store original link for recreation
    original_link = retrieved_link
else
    println("❌ Link not found in TFS")
    exit(1)
end

# Get endpoint information for recreation
router_ep_key = (test_node_id, :router_ep)
router_ep_uuid = get(sdn.device_map, router_ep_key, nothing)
println("  Router endpoint: $router_ep_uuid ($(router_ep_key[2]))")

# Find the OXC endpoint by looking at the actual link endpoints
link_endpoint_ids = retrieved_link["link_endpoint_ids"]

# Find which OXC endpoint is actually used in this link
oxc_ep_key = nothing
oxc_ep_uuid = nothing

for endpoint_id in link_endpoint_ids
    endpoint_uuid = endpoint_id["endpoint_uuid"]["uuid"]
    if endpoint_uuid != router_ep_uuid
        # This must be the OXC endpoint
        # Find it in our device map
        for (key, uuid) in sdn.device_map
            if uuid == endpoint_uuid && key[1] == test_node_id && string(key[2]) |> x -> startswith(x, "oxc_ep_")
                global oxc_ep_key = key
                global oxc_ep_uuid = uuid
                println("  ✓ Found actual OXC endpoint from link: $oxc_ep_uuid ($(key[2]))")
                break
            end
        end
        break
    end
end

if router_ep_uuid === nothing || oxc_ep_uuid === nothing
    println("❌ Could not find required endpoints")
    println("Router EP UUID: $router_ep_uuid")
    println("OXC EP UUID: $oxc_ep_uuid")
    println("Available endpoints for node $test_node_id:")
    for (key, uuid) in sdn.device_map
        if key[1] == test_node_id
            used = get(sdn.endpoint_usage, uuid, false)
            println("  $(key[2]): $uuid (used: $used)")
        end
    end
    exit(1)
end

println("  Router endpoint: $router_ep_uuid")
println("  OXC endpoint: $oxc_ep_uuid ($(oxc_ep_key[2]))")

println("\n3. 🗑️  DELETING THE LINK")
println("-"^30)

if delete_link_http(sdn.api_url, link_uuid)
    println("✓ Link deleted successfully from TFS")
    
    # Update local mappings
    delete!(sdn.intra_link_map, intra_link_key)
    sdn.endpoint_usage[router_ep_uuid] = false
    sdn.endpoint_usage[oxc_ep_uuid] = false
    
    println("✓ Updated local mappings")
else
    println("❌ Failed to delete link")
    exit(1)
end


println("\n4. 🔄 RECREATING THE LINK")
println("-"^35)

# Recreate using the TFS module function
if create_router_oxc_link(sdn, test_node_id; link_type=:copper)
    println("✓ Link recreated successfully")
else
    println("❌ Failed to recreate link")
    exit(1)
end

println("\n6. 🔍 VERIFYING RECREATION")
println("-"^35)

# Check if link exists again
new_link_uuid = get(sdn.intra_link_map, intra_link_key, nothing)
if new_link_uuid !== nothing
    println("✓ Link UUID in mapping: $new_link_uuid")
    
    # Verify in TFS
    recreated_link = get_link(sdn.api_url, new_link_uuid)
    if recreated_link !== nothing
        println("✓ Link exists in TFS")
        println("  Name: $(recreated_link["name"])")
        println("  Endpoints match: $(length(recreated_link["link_endpoint_ids"]) == 2)")
        
        # Check endpoint usage
        router_used = get(sdn.endpoint_usage, router_ep_uuid, false)
        oxc_used = get(sdn.endpoint_usage, oxc_ep_uuid, false)
        println("  Router endpoint used: $router_used")
        println("  OXC endpoint used: $oxc_used")
        
    else
        println("❌ Recreated link not found in TFS")
        exit(1)
    end
else
    println("❌ No link UUID found in mapping after recreation")
    exit(1)
end

println("\n7. 💾 SAVING UPDATED MAPPINGS")
println("-"^40)

save_device_map("data/device_map.jld2", sdn)
println("✓ Device and link mappings saved")

println("\n" * "="^60)
println("🎉 INTRA-NODE LINK MODIFICATION COMPLETED SUCCESSFULLY!")
println("   - Link found: ✅")
println("   - Link deleted: ✅") 
println("   - Link recreated: ✅")
println("   - Mappings updated: ✅")
println("="^60)

# Show final link status for this node
println("\n📊 FINAL STATUS FOR NODE $test_node_id:")
println("   Intra-link UUID: $(get(sdn.intra_link_map, intra_link_key, "NONE"))")
println("   Router endpoint used: $(get(sdn.endpoint_usage, router_ep_uuid, false))")
println("   OXC endpoint used: $(get(sdn.endpoint_usage, oxc_ep_uuid, false))")