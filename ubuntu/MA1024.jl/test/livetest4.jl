using MA1024, JSON3
using MA1024.TFS
using JLD2, UUIDs
using MINDFul
import AttributeGraphs as AG
using HTTP
const MINDF = MINDFul

println("=== TeraFlow Context and Topology Creation Test ===")

# Initialize SDN controller
sdncontroller = TeraflowSDN()

# First, clean up all existing contexts
println("--- Cleaning up existing contexts ---")

# UUID of the topology to keep
keep_topology_uuid = "c76135e3-24a8-5e92-9bed-c3c9139359c8"

try
    contexts_response = get_contexts(sdncontroller.api_url)
    if haskey(contexts_response, "contexts")
        existing_contexts = contexts_response["contexts"]
        if !isempty(existing_contexts)
            println("Found $(length(existing_contexts)) existing contexts, cleaning them up...")
            
            # First, delete all topologies EXCEPT the one we want to keep
            for context in existing_contexts
                context_uuid = context["context_id"]["context_uuid"]["uuid"]
                context_name = get(context, "name", "Unknown")
                
                println("  Processing context: $context_name (UUID: $context_uuid)")
                
                # Get and delete all topologies in this context (except the one we keep)
                try
                    topologies_response = get_topologies(sdncontroller.api_url, context_uuid)
                    if haskey(topologies_response, "topologies")
                        existing_topologies = topologies_response["topologies"]
                        if !isempty(existing_topologies)
                            println("    Found $(length(existing_topologies)) topologies, filtering...")
                            for topology in existing_topologies
                                topology_uuid = topology["topology_id"]["topology_uuid"]["uuid"]
                                topology_name = get(topology, "name", "Unknown")
                                
                                # Skip the topology we want to keep
                                if topology_uuid == keep_topology_uuid
                                    println("      ⚪ Keeping topology: $topology_name (UUID: $topology_uuid)")
                                    continue
                                end
                                
                                println("      Deleting topology: $topology_name (UUID: $topology_uuid)")
                                
                                try
                                    delete_response = HTTP.request("DELETE", 
                                        "$(sdncontroller.api_url)/context/$context_uuid/topology/$topology_uuid",
                                        headers=["Content-Type" => "application/json"]
                                    )
                                    
                                    if delete_response.status == 200
                                        println("        ✅ Successfully deleted topology: $topology_name")
                                    else
                                        println("        ⚠️  Delete topology response status: $(delete_response.status)")
                                    end
                                    
                                catch delete_topo_error
                                    println("        ❌ Error deleting topology $topology_name: $delete_topo_error")
                                end
                            end
                        else
                            println("    No topologies found in context")
                        end
                    end
                catch topo_error
                    println("    ⚠️  Error getting topologies for context $context_name: $topo_error")
                end
            end
            
            # Wait a moment for topology deletions to process
            sleep(2)
            
            # Now delete contexts that have NO topologies left (except the one with our kept topology)
            println("  Checking which contexts to delete...")
            for context in existing_contexts
                context_uuid = context["context_id"]["context_uuid"]["uuid"]
                context_name = get(context, "name", "Unknown")
                
                # Check if this context still has topologies
                try
                    topologies_response = get_topologies(sdncontroller.api_url, context_uuid)
                    remaining_topologies = get(topologies_response, "topologies", [])
                    
                    if isempty(remaining_topologies)
                        # No topologies left, safe to delete context
                        println("    Deleting context (no topologies): $context_name (UUID: $context_uuid)")
                        
                        try
                            delete_response = HTTP.request("DELETE", 
                                "$(sdncontroller.api_url)/context/$context_uuid",
                                headers=["Content-Type" => "application/json"]
                            )
                            
                            if delete_response.status == 200
                                println("      ✅ Successfully deleted context: $context_name")
                            else
                                println("      ⚠️  Delete context response status: $(delete_response.status)")
                            end
                            
                        catch delete_context_error
                            println("      ❌ Error deleting context $context_name: $delete_context_error")
                        end
                    else
                        # Context still has topologies, check if it's our kept topology
                        kept_topology_found = false
                        for topo in remaining_topologies
                            if topo["topology_id"]["topology_uuid"]["uuid"] == keep_topology_uuid
                                kept_topology_found = true
                                break
                            end
                        end
                        
                        if kept_topology_found
                            println("    ⚪ Keeping context (contains kept topology): $context_name (UUID: $context_uuid)")
                        else
                            println("    ⚠️  Context $context_name still has $(length(remaining_topologies)) topology(ies) but not our target")
                        end
                    end
                    
                catch context_check_error
                    println("    ⚠️  Error checking context $context_name: $context_check_error")
                end
            end
            
        else
            println("No existing contexts found")
        end
    end
    
    # Verify cleanup
    sleep(2)
    contexts_after_cleanup = get_contexts(sdncontroller.api_url)
    remaining_contexts = get(contexts_after_cleanup, "contexts", [])
    
    println("\n--- Cleanup Summary ---")
    if isempty(remaining_contexts)
        println("⚠️  All contexts were deleted - this might not be intended if we wanted to keep the topology")
    else
        println("✅ $(length(remaining_contexts)) context(s) remain after cleanup")
        for remaining_context in remaining_contexts
            remaining_name = get(remaining_context, "name", "Unknown")
            remaining_uuid = remaining_context["context_id"]["context_uuid"]["uuid"]
            println("    - $remaining_name (UUID: $remaining_uuid)")
            
            # Check if our target topology is still there
            try
                topologies_response = get_topologies(sdncontroller.api_url, remaining_uuid)
                if haskey(topologies_response, "topologies")
                    for topology in topologies_response["topologies"]
                        topo_uuid = topology["topology_id"]["topology_uuid"]["uuid"]
                        topo_name = get(topology, "name", "Unknown")
                        if topo_uuid == keep_topology_uuid
                            println("      ✅ Target topology found: $topo_name (UUID: $topo_uuid)")
                        else
                            println("      - Other topology: $topo_name (UUID: $topo_uuid)")
                        end
                    end
                end
            catch e
                println("      ⚠️  Error checking topologies: $e")
            end
        end
    end
    
catch cleanup_error
    println("❌ Error during cleanup: $cleanup_error")
end

println("\n=== Starting fresh context creation ===")

println("Creating admin context and topology...")

# Create proper stable UUIDs using the TFS stable_uuid function
admin_context_uuid = TFS.stable_uuid(999999, :admin_context)

println("Generated admin_context_uuid: $admin_context_uuid")

# Check if we already have the target topology
target_topology_uuid = "c76135e3-24a8-5e92-9bed-c3c9139359c8"

# Create admin context (this is safe to recreate)
admin_context = Ctx.Context(
    Ctx.ContextId(Ctx.Uuid(admin_context_uuid)),
    "admin",  # name
    Ctx.TopologyId[],  # topology_ids (empty initially)
    Ctx.ServiceId[],   # service_ids
    Ctx.SliceId[],     # slice_ids
    nothing            # controller
)

# Post the context
println("--- Creating Admin Context ---")
context_success = post_context(sdncontroller.api_url, admin_context)

if context_success
    println("✅ Successfully created admin context")
    
    # Check if we already have our target topology
    println("--- Checking for existing target topology ---")
    try
        topologies_response = get_topologies(sdncontroller.api_url, admin_context_uuid)
        existing_topologies = get(topologies_response, "topologies", [])
        
        target_topology_exists = false
        for topology in existing_topologies
            if topology["topology_id"]["topology_uuid"]["uuid"] == target_topology_uuid
                target_topology_exists = true
                println("✅ Target topology already exists: $(get(topology, "name", "Unknown"))")
                break
            end
        end
        
        if !target_topology_exists
            println("⚠️  Target topology not found, creating it...")
            
            # Create the target topology
            target_topology = Ctx.Topology(
                Ctx.TopologyId(
                    Ctx.ContextId(Ctx.Uuid(admin_context_uuid)),
                    Ctx.Uuid(target_topology_uuid)
                ),
                "admin",  # name
                Ctx.DeviceId[],  # device_ids (empty initially)
                Ctx.LinkId[],    # link_ids (empty)
                Ctx.LinkId[]     # optical_link_ids (empty)
            )
            
            # Post the target topology
            println("--- Creating Target Topology ---")
            target_topology_success = post_topology_minimal(sdncontroller.api_url, admin_context_uuid, target_topology)
            
            if target_topology_success
                println("✅ Successfully created target topology: $target_topology_uuid")
            else
                println("❌ Failed to create target topology")
            end
        else
            println("--- Using existing target topology ---")
        end
        
    catch e
        println("⚠️  Error checking existing topologies: $e")
        println("Attempting to create target topology anyway...")
        
        # Create the target topology as fallback
        target_topology = Ctx.Topology(
            Ctx.TopologyId(
                Ctx.ContextId(Ctx.Uuid(admin_context_uuid)),
                Ctx.Uuid(target_topology_uuid)
            ),
            "expected_topology",  # name
            Ctx.DeviceId[],  # device_ids (empty initially)
            Ctx.LinkId[],    # link_ids (empty)
            Ctx.LinkId[]     # optical_link_ids (empty)
        )
        
        # Post the target topology
        println("--- Creating Target Topology (fallback) ---")
        target_topology_success = post_topology_minimal(sdncontroller.api_url, admin_context_uuid, target_topology)
        
        if target_topology_success
            println("✅ Successfully created target topology: $target_topology_uuid")
        else
            println("❌ Failed to create target topology")
        end
    end
    
    # Proceed directly to device testing
    println("\n--- Testing Device Creation ---")
    
    test_device_uuid = "test-router"
    
    # The target topology should already exist from cleanup phase
    expected_topology_uuid = target_topology_uuid  # Use the preserved topology
    
    println("--- Using existing topology: $expected_topology_uuid ---")
    
    # Now create the device - it should find the topology it expects
    device_drivers = Vector{Ctx.DeviceDriverEnum.T}()
    push!(device_drivers, Ctx.DeviceDriverEnum.DEVICEDRIVER_UNDEFINED)
    
    test_device = Ctx.Device(
        Ctx.DeviceId(Ctx.Uuid(test_device_uuid)),
        "Test-Router-Device", 
        "emu-packet-router",
        Ctx.DeviceConfig(Ctx.ConfigRule[]),  # EMPTY config - no endpoints
        Ctx.DeviceOperationalStatusEnum.DEVICEOPERATIONALSTATUS_ENABLED,
        device_drivers,
        Ctx.EndPoint[],  # Empty endpoints array
        Ctx.Component[],
        nothing
    )
    
    device_success = ensure_post_device(sdncontroller.api_url, test_device)
    
    if device_success
        println("✅ Successfully created test device: $test_device_uuid")
        
        # Verify device exists
        try
            retrieved_device = get_device(sdncontroller.api_url, test_device_uuid)
            println("✅ Successfully retrieved device: $(retrieved_device.name)")
            
            # Delete the test device
            println("--- Deleting test device ---")
            try
                delete_response = HTTP.request("DELETE", 
                    "$(sdncontroller.api_url)/device/$test_device_uuid",
                    headers=["Content-Type" => "application/json"]
                )
                
                if delete_response.status == 200
                    println("✅ Successfully deleted test device: $test_device_uuid")
                    
                    # Verify device is deleted
                    try
                        get_device(sdncontroller.api_url, test_device_uuid)
                        println("⚠️  Device still exists after deletion attempt")
                    catch e
                        println("✅ Confirmed device deletion - device no longer exists")
                    end
                else
                    println("⚠️  Delete device response status: $(delete_response.status)")
                end
                
            catch delete_error
                println("❌ Error deleting test device: $delete_error")
            end
            
        catch e
            println("❌ Could not retrieve device: $e")
        end
    else
        println("❌ Failed to create test device")
    end
    
else
    println("❌ Failed to create admin context")
end

println("\n=== Test Complete ===")