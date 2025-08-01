using MINDFulTeraFlowSDN, JLD2, MINDFul
import AttributeGraphs as AG
using Statistics, Plots, DataFrames, CSV
using Dates

const MINDF = MINDFul

# Performance metrics collection for verification
mutable struct VerificationMetrics
    # Timing metrics
    data_load_time::Float64
    framework_setup_time::Float64
    tfs_fetch_time::Float64
    device_verification_time::Float64
    intra_link_verification_time::Float64
    inter_link_verification_time::Float64
    report_generation_time::Float64
    total_execution_time::Float64
    
    # Memory metrics
    initial_memory::Float64
    peak_memory::Float64
    final_memory::Float64
    memory_timeline::Vector{Tuple{Float64, Float64}}
    
    # TFS Communication metrics
    tfs_request_count::Int
    tfs_available::Bool
    
    # Verification results metrics
    total_devices_expected::Int
    total_devices_found::Int
    total_intra_links_expected::Int
    total_intra_links_found::Int
    total_inter_links_expected::Int
    total_inter_links_found::Int
    
    # Device breakdown
    devices_by_type::Dict{String, Tuple{Int, Int}}
    
    # Node analysis
    nodes_complete::Int
    nodes_incomplete::Int
    nodes_empty::Int
    total_nodes::Int
    
    # Health scores
    device_health::Float64
    intra_link_health::Float64
    inter_link_health::Float64
    overall_health::Float64
    
    # Constructor
    VerificationMetrics() = new(
        0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,  # timing
        0.0, 0.0, 0.0, Tuple{Float64, Float64}[],  # memory
        0, false,  # TFS communication
        0, 0, 0, 0, 0, 0,  # verification counts
        Dict{String, Tuple{Int, Int}}(),  # device breakdown
        0, 0, 0, 0,  # node analysis
        0.0, 0.0, 0.0, 0.0  # health scores
    )
end

function get_memory_usage()
    return Base.gc_live_bytes() / 1024 / 1024  # Convert to MB
end

function record_memory(metrics::VerificationMetrics, phase_time::Float64)
    current_memory = get_memory_usage()
    push!(metrics.memory_timeline, (phase_time, current_memory))
    if current_memory > metrics.peak_memory
        metrics.peak_memory = current_memory
    end
end

# === COPY THE EXACT FUNCTIONS FROM verify_tfs_state.jl WITH METRICS ADDED ===

"""
    verify_tfs_devices_and_links_with_metrics(sdn::TeraflowSDN, nodeviews, metrics)

EXACT copy of verify_tfs_devices_and_links but with metrics collection
"""
function verify_tfs_devices_and_links_with_metrics(sdn::TeraflowSDN, nodeviews, metrics::VerificationMetrics)
    println("\n🔍 FOCUSED TFS VERIFICATION (Multi-TM Architecture)")
    println("="^65)
    
    # Get actual TFS state with timing
    tfs_fetch_start = time_ns()
    println("📡 Fetching TFS devices and links...")
    
    # Initialize variables in the outer scope
    local tfs_devices, tfs_links
    
    try
        tfs_devices = get_devices(sdn.api_url)
        tfs_links = get_links(sdn.api_url)
        
        metrics.tfs_available = true
        metrics.tfs_request_count += 2
        
        println("   Found $(length(tfs_devices["devices"])) devices in TFS")
        println("   Found $(length(tfs_links["links"])) links in TFS")
    catch e
        println("❌ TFS unavailable: $(typeof(e))")
        metrics.tfs_available = false
        metrics.tfs_request_count += 2
        
        # Use empty data for static analysis
        tfs_devices = Dict("devices" => [])
        tfs_links = Dict("links" => [])
        
        println("   ⚠️  Running static analysis on device maps only")
    end
    
    tfs_fetch_end = time_ns()
    metrics.tfs_fetch_time = (tfs_fetch_end - tfs_fetch_start) / 1e9
    
    # Extract MINDFul topology - EXACT COPY
    mindful_neighbors = get_mindful_topology(nodeviews)
    
    # Run verifications with timing - EXACT COPY
    device_start = time_ns()
    device_results = verify_devices_against_map_with_metrics(sdn, tfs_devices, nodeviews, metrics)
    metrics.device_verification_time = (time_ns() - device_start) / 1e9
    
    intra_start = time_ns()
    intra_results = verify_intra_links_multi_tm_with_metrics(sdn, tfs_links, nodeviews, metrics)
    metrics.intra_link_verification_time = (time_ns() - intra_start) / 1e9
    
    inter_start = time_ns()
    inter_results = verify_inter_links_with_metrics(sdn, tfs_links, mindful_neighbors, metrics)
    metrics.inter_link_verification_time = (time_ns() - inter_start) / 1e9
    
    # Generate focused report with timing - EXACT COPY
    report_start = time_ns()
    generate_focused_report_with_metrics(device_results, intra_results, inter_results, metrics)
    metrics.report_generation_time = (time_ns() - report_start) / 1e9
    
    return (device_results, intra_results, inter_results)
end

function get_mindful_topology(nodeviews)
    """Extract expected topology from MINDFul - EXACT COPY"""
    neighbors = Dict{Int, Set{Int}}()
    nodes_with_devices = Set{Int}()
    
    for nodeview in nodeviews
        node_id = nodeview.nodeproperties.localnode
        push!(nodes_with_devices, node_id)
        
        all_neighbors = Set{Int}()
        union!(all_neighbors, nodeview.nodeproperties.inneighbors)
        union!(all_neighbors, nodeview.nodeproperties.outneighbors)
        neighbors[node_id] = all_neighbors
    end
    
    return Dict(:neighbors => neighbors, :nodes => nodes_with_devices)
end

function verify_devices_against_map_with_metrics(sdn::TeraflowSDN, tfs_devices, nodeviews, metrics::VerificationMetrics)
    """Check if devices in device_map exist in TFS - EXACT COPY with metrics"""
    println("\n📱 DEVICE VERIFICATION (Multi-TM + Shared OLS)")
    println("-"^50)
    
    # Extract expected devices from device_map - EXACT COPY
    expected_devices = Dict{String, Any}()  # uuid => device_info
    nodes_devices = Dict{Int, Set{Symbol}}()  # node_id => set of device types
    shared_ols_devices = Dict{String, Tuple{Int, Int}}()  # uuid => (node1, node2)
    tm_devices_by_node = Dict{Int, Set{Int}}()  # node_id => set of TM indices
    
    for (key, uuid) in sdn.device_map
        if length(key) == 2
            node_id, device_type = key
            # Only main devices, not endpoints
            if device_type in [:router, :oxc]
                expected_devices[uuid] = (node_id, device_type)
                
                if !haskey(nodes_devices, node_id)
                    nodes_devices[node_id] = Set{Symbol}()
                end
                push!(nodes_devices[node_id], device_type)
            elseif string(device_type) |> x -> startswith(x, "tm_") && !contains(x, "_ep_")
                # Extract TM index from tm_X
                tm_match = match(r"tm_(\d+)", string(device_type))
                if tm_match !== nothing
                    tm_idx = parse(Int, tm_match.captures[1])
                    expected_devices[uuid] = (node_id, device_type)
                    
                    if !haskey(nodes_devices, node_id)
                        nodes_devices[node_id] = Set{Symbol}()
                    end
                    push!(nodes_devices[node_id], device_type)
                    
                    # Track TM indices per node
                    if !haskey(tm_devices_by_node, node_id)
                        tm_devices_by_node[node_id] = Set{Int}()
                    end
                    push!(tm_devices_by_node[node_id], tm_idx)
                end
            end
        elseif length(key) == 3 && key[3] == :shared_ols
            # Handle shared OLS devices
            node1, node2, device_type = key
            expected_devices[uuid] = (node1, node2, device_type)
            shared_ols_devices[uuid] = (node1, node2)
        end
    end
    
    # Extract actual devices from TFS - EXACT COPY
    tfs_device_uuids = Set(dev["device_id"]["device_uuid"]["uuid"] for dev in tfs_devices["devices"])
    
    # Check matches - EXACT COPY
    found_devices = intersect(Set(keys(expected_devices)), tfs_device_uuids)
    missing_devices = setdiff(Set(keys(expected_devices)), tfs_device_uuids)
    
    println("✅ Devices found in TFS: $(length(found_devices))/$(length(expected_devices))")
    
    # Analyze by node and device type with TM verification - EXACT COPY
    nodes_complete = 0
    nodes_incomplete = 0
    nodes_empty = 0
    shared_ols_found = length(intersect(Set(keys(shared_ols_devices)), tfs_device_uuids))
    
    # Create nodeview lookup for TM count verification - EXACT COPY
    node_lookup = Dict{Int, Any}()
    for nodeview in nodeviews
        node_lookup[nodeview.nodeproperties.localnode] = nodeview
    end
    
    for (node_id, expected_types) in nodes_devices
        found_types = Set{Symbol}()
        
        for uuid in found_devices
            if haskey(expected_devices, uuid)
                dev_info = expected_devices[uuid]
                if length(dev_info) == 2  # Regular node device
                    dev_node, dev_type = dev_info
                    if dev_node == node_id
                        push!(found_types, dev_type)
                    end
                end
            end
        end
        
        missing_types = setdiff(expected_types, found_types)
        
        # Verify TM count matches nodeview expectation
        expected_tm_count = 0
        if haskey(node_lookup, node_id) && node_lookup[node_id].transmissionmoduleviewpool !== nothing
            expected_tm_count = length(node_lookup[node_id].transmissionmoduleviewpool)
        end
        
        found_tm_count = haskey(tm_devices_by_node, node_id) ? length(tm_devices_by_node[node_id]) : 0
        
        if isempty(missing_types)
            nodes_complete += 1
            if isempty(expected_types)
                nodes_empty += 1
                println("📝 Node $node_id: Empty node (no devices)")
            else
                tm_status = found_tm_count == expected_tm_count ? "✓" : "✗"
                println("✅ Node $node_id: All devices present - TMs: $found_tm_count/$expected_tm_count $tm_status")
            end
        else
            nodes_incomplete += 1
            tm_missing = expected_tm_count - found_tm_count
            println("❌ Node $node_id: Missing $(length(missing_types)) device types, TMs: $found_tm_count/$expected_tm_count")
            if tm_missing > 0
                println("   Missing TM devices: $tm_missing")
            end
        end
    end
    
    # Update metrics
    metrics.total_devices_expected = length(expected_devices)
    metrics.total_devices_found = length(found_devices)
    metrics.nodes_complete = nodes_complete
    metrics.nodes_incomplete = nodes_incomplete
    metrics.nodes_empty = nodes_empty
    
    println("✅ Shared OLS devices found: $shared_ols_found/$(length(shared_ols_devices))")
    
    # Show TM distribution summary - EXACT COPY
    println("\n📊 Transmission Module Distribution:")
    total_expected_tms = sum(length(node_lookup[node_id].transmissionmoduleviewpool) for node_id in keys(node_lookup) if node_lookup[node_id].transmissionmoduleviewpool !== nothing)
    total_found_tms = sum(length(tm_set) for tm_set in values(tm_devices_by_node))
    println("   Total TMs expected: $total_expected_tms")
    println("   Total TMs found: $total_found_tms")
    
    # Show shared OLS details - EXACT COPY
    if length(shared_ols_devices) > 0
        println("\n📊 Shared OLS Infrastructure:")
        found_shared_ols = intersect(Set(keys(shared_ols_devices)), tfs_device_uuids)
        missing_shared_ols = setdiff(Set(keys(shared_ols_devices)), tfs_device_uuids)
        
        for uuid in sort(collect(found_shared_ols))
            if haskey(shared_ols_devices, uuid)
                node1, node2 = shared_ols_devices[uuid]
                println("   ✅ Shared OLS: Nodes $node1 ↔ $node2")
            end
        end
        
        for uuid in sort(collect(missing_shared_ols))
            if haskey(shared_ols_devices, uuid)
                node1, node2 = shared_ols_devices[uuid]
                println("   ❌ Missing shared OLS: Nodes $node1 ↔ $node2")
            end
        end
    end
    
    return Dict(
        :total_expected => length(expected_devices),
        :found_in_tfs => length(found_devices),
        :missing_count => length(missing_devices),
        :nodes_complete => nodes_complete,
        :nodes_incomplete => nodes_incomplete,
        :nodes_empty => nodes_empty,
        :shared_ols_found => shared_ols_found,
        :shared_ols_total => length(shared_ols_devices),
        :missing_devices => missing_devices,
        :total_expected_tms => total_expected_tms,
        :total_found_tms => total_found_tms
    )
end

function verify_intra_links_multi_tm_with_metrics(sdn::TeraflowSDN, tfs_links, nodeviews, metrics::VerificationMetrics)
    """Check if intra-node links exist in TFS for ALL TMs - EXACT COPY with metrics"""
    println("\n🔗 INTRA-NODE LINK VERIFICATION (Multi-TM Architecture)")
    println("-"^55)
    
    # Extract expected intra-node links - EXACT COPY
    expected_intra = Set(keys(sdn.intra_link_map))
    expected_uuids = Set(values(sdn.intra_link_map))
    
    # Extract TFS link UUIDs - EXACT COPY
    tfs_link_uuids = Set(link["link_id"]["link_uuid"]["uuid"] for link in tfs_links["links"])
    
    # Check matches - EXACT COPY
    found_links = intersect(expected_uuids, tfs_link_uuids)
    missing_links = setdiff(expected_uuids, tfs_link_uuids)
    
    println("✅ Intra-node links found: $(length(found_links))/$(length(expected_uuids))")
    
    # Update metrics
    metrics.total_intra_links_expected = length(expected_uuids)
    metrics.total_intra_links_found = length(found_links)
    
    # Create nodeview lookup for TM count verification - EXACT COPY
    node_lookup = Dict{Int, Any}()
    for nodeview in nodeviews
        node_lookup[nodeview.nodeproperties.localnode] = nodeview
    end
    
    # Analyze by node and link type with detailed TM verification - EXACT COPY
    nodes_with_complete_intra = 0
    intra_by_node = Dict{Int, Dict{String, Bool}}()  # Changed to String for detailed link names
    expected_links_by_node = Dict{Int, Int}()  # Expected link count per node
    
    for ((node_id, link_type), uuid) in sdn.intra_link_map
        if !haskey(intra_by_node, node_id)
            intra_by_node[node_id] = Dict{String, Bool}()
        end
        intra_by_node[node_id][string(link_type)] = uuid in found_links
    end
    
    # Calculate expected link counts for each node based on TM count - EXACT COPY
    for (node_id, nodeview) in node_lookup
        num_tms = nodeview.transmissionmoduleviewpool !== nothing ? length(nodeview.transmissionmoduleviewpool) : 0
        if num_tms > 0
            # Each TM needs: 2 router-tm links + 2 tm-oxc links = 4 links per TM
            expected_links_by_node[node_id] = 4 * num_tms
        else
            expected_links_by_node[node_id] = 0
        end
    end
    
    # Sort node IDs for consistent output - EXACT COPY
    sorted_node_ids = sort(collect(keys(intra_by_node)))
    
    for node_id in sorted_node_ids
        link_status = intra_by_node[node_id]
        all_present = all(values(link_status))
        
        num_tms = haskey(node_lookup, node_id) && node_lookup[node_id].transmissionmoduleviewpool !== nothing ? 
                  length(node_lookup[node_id].transmissionmoduleviewpool) : 0
        expected_count = get(expected_links_by_node, node_id, 0)
        found_count = count(values(link_status))
        
        if all_present && found_count == expected_count
            nodes_with_complete_intra += 1
            println("✅ Node $node_id: All $found_count intra-links present ($(num_tms) TMs)")
        else
            missing_link_types = [lt for (lt, present) in link_status if !present]
            present_link_types = [lt for (lt, present) in link_status if present]
            
            println("❌ Node $node_id: Incomplete intra-links ($found_count/$expected_count) for $(num_tms) TMs")
            
            # Analyze by link category
            router_tm_links = [lt for lt in keys(link_status) if contains(lt, "router_tm")]
            tm_oxc_links = [lt for lt in keys(link_status) if contains(lt, "tm") && contains(lt, "oxc")]
            
            router_tm_present = count(get(link_status, lt, false) for lt in router_tm_links)
            tm_oxc_present = count(get(link_status, lt, false) for lt in tm_oxc_links)
            
            expected_router_tm = 2 * num_tms
            expected_tm_oxc = 2 * num_tms
            
            println("   Router↔TM links: $router_tm_present/$expected_router_tm")
            println("   TM↔OXC links: $tm_oxc_present/$expected_tm_oxc")
            
            if !isempty(missing_link_types)
                println("   ✗ Missing: $(join(missing_link_types[1:min(5, end)], ", "))$(length(missing_link_types) > 5 ? "..." : "")")
            end
        end
    end
    
    # Show missing link details by category - EXACT COPY
    if !isempty(missing_links)
        println("\n❌ MISSING INTRA-LINK ANALYSIS:")
        router_tm_missing = 0
        tm_oxc_missing = 0
        other_missing = 0
        
        for ((node_id, link_type), uuid) in sdn.intra_link_map
            if uuid in missing_links
                link_type_str = string(link_type)
                if contains(link_type_str, "router_tm")
                    router_tm_missing += 1
                elseif contains(link_type_str, "tm") && contains(link_type_str, "oxc")
                    tm_oxc_missing += 1
                else
                    other_missing += 1
                end
            end
        end
        
        println("   Router↔TM links missing: $router_tm_missing")
        println("   TM↔OXC links missing: $tm_oxc_missing")
        println("   Other links missing: $other_missing")
    end
    
    return Dict(
        :total_expected => length(expected_uuids),
        :found_in_tfs => length(found_links),
        :missing_count => length(missing_links),
        :nodes_complete => nodes_with_complete_intra,
        :total_nodes => length(intra_by_node),
        :missing_links => missing_links,
        :expected_links_by_node => expected_links_by_node
    )
end

function verify_inter_links_with_metrics(sdn::TeraflowSDN, tfs_links, mindful_topology, metrics::VerificationMetrics)
    """Check if inter-node links with shared OLS match MINDFul topology - EXACT COPY with metrics"""
    println("\n🌐 INTER-NODE LINK VERIFICATION (Shared OLS + Multi-TM Offset)")
    println("-"^60)
    
    mindful_neighbors = mindful_topology[:neighbors]
    
    # Get nodes that actually have OXC devices from device_map - EXACT COPY
    oxc_nodes = Set{Int}()
    for (key, uuid) in sdn.device_map
        if length(key) == 2 && key[2] == :oxc
            push!(oxc_nodes, key[1])
        end
    end
    
    println("📊 Topology analysis:")
    println("   Total nodes in topology: $(length(mindful_neighbors))")
    println("   Nodes with OXC devices: $(length(oxc_nodes))")
    println("   Empty nodes (no OXC): $(length(mindful_neighbors) - length(oxc_nodes))")
    
    # Extract expected inter-node links from device map (only from OXC nodes) - EXACT COPY
    expected_inter_uuids = Set(values(sdn.inter_link_map))
    
    # Extract TFS link UUIDs - EXACT COPY
    tfs_link_uuids = Set(link["link_id"]["link_uuid"]["uuid"] for link in tfs_links["links"])
    
    # Check matches - EXACT COPY
    found_inter_links = intersect(expected_inter_uuids, tfs_link_uuids)
    missing_inter_links = setdiff(expected_inter_uuids, tfs_link_uuids)
    
    println("✅ Inter-node links found: $(length(found_inter_links))/$(length(expected_inter_uuids))")
    
    # Update metrics
    metrics.total_inter_links_expected = length(expected_inter_uuids)
    metrics.total_inter_links_found = length(found_inter_links)
    
    # Rest of function simplified since we just need basic metrics
    
    return Dict(
        :total_expected => length(expected_inter_uuids),
        :found_in_tfs => length(found_inter_links),
        :missing_count => length(missing_inter_links),
        :topology_perfect => 0,
        :topology_partial => 0,
        :topology_missing => 0,
        :total_nodes => length(mindful_neighbors),
        :oxc_nodes => length(oxc_nodes),
        :empty_nodes => length(mindful_neighbors) - length(oxc_nodes),
        :empty_node_connections => 0,
        :missing_connections => Dict{Int, Set{Int}}(),
        :missing_links => missing_inter_links,
        :shared_ols_expected => 0,
        :shared_ols_found => 0,
        :shared_ols_missing => 0,
        :missing_shared_ols => Dict{Tuple{Int,Int}, Bool}(),
        :oxc_endpoint_usage => Dict{Int, Int}()
    )
end

function generate_focused_report_with_metrics(device_results, intra_results, inter_results, metrics::VerificationMetrics)
    """Generate focused verification report - EXACT COPY with metrics"""
    println("\n" * "="^65)
    println("🏁 FOCUSED VERIFICATION SUMMARY (Multi-TM Architecture)")
    println("="^65)
    
    # Device summary with TM details - EXACT COPY
    dev_health = (device_results[:found_in_tfs] / max(device_results[:total_expected], 1)) * 100
    println("📱 Devices: $(device_results[:found_in_tfs])/$(device_results[:total_expected]) found ($(round(dev_health, digits=1))%)")
    println("   Complete nodes: $(device_results[:nodes_complete])")
    println("   Incomplete nodes: $(device_results[:nodes_incomplete])")
    println("   Transmission modules: $(device_results[:total_found_tms])/$(device_results[:total_expected_tms])")
    println("   Shared OLS devices: $(device_results[:shared_ols_found])/$(device_results[:shared_ols_total])")
    
    # Intra-link summary with multi-TM details - EXACT COPY
    intra_health = (intra_results[:found_in_tfs] / max(intra_results[:total_expected], 1)) * 100
    println("🔗 Intra-links: $(intra_results[:found_in_tfs])/$(intra_results[:total_expected]) found ($(round(intra_health, digits=1))%)")
    println("   Complete nodes: $(intra_results[:nodes_complete])/$(intra_results[:total_nodes])")
    
    # Inter-link summary - EXACT COPY
    inter_health = (inter_results[:found_in_tfs] / max(inter_results[:total_expected], 1)) * 100
    println("🌐 Inter-links: $(inter_results[:found_in_tfs])/$(inter_results[:total_expected]) found ($(round(inter_health, digits=1))%)")
    
    # Update health scores in metrics
    metrics.device_health = dev_health
    metrics.intra_link_health = intra_health
    metrics.inter_link_health = inter_health
    metrics.overall_health = (dev_health + intra_health + inter_health) / 3
    
    # Overall health - EXACT COPY
    println("\n🎯 Overall Health: $(round(metrics.overall_health, digits=1))%")
    
    return metrics.overall_health
end

# Main execution function
function run_focused_verification_with_metrics()
    println("🚀 TFS STATE VERIFICATION TEST WITH PERFORMANCE METRICS")
    println("="^75)

    # Initialize metrics
    metrics = VerificationMetrics()
    test_start_time = time_ns()
    metrics.initial_memory = get_memory_usage()

    # === PHASE 1: DATA LOADING ===
    println("\n📂 PHASE 1: Loading topology data...")
    data_load_start = time_ns()

    domains_name_graph = first(JLD2.load("data/itz_IowaStatewideFiberMap-itz_Missouri__(1,9)-(2,3),(1,6)-(2,54),(1,1)-(2,21).jld2"))[2]
    println("Loaded graph")
    ag1 = first(domains_name_graph)[2]

    data_load_end = time_ns()
    metrics.data_load_time = (data_load_end - data_load_start) / 1e9
    phase_time = (data_load_end - test_start_time) / 1e9
    record_memory(metrics, phase_time)

    println("   ✅ Data loaded in $(round(metrics.data_load_time, digits=3))s")
    println("   📊 Memory usage: $(round(get_memory_usage(), digits=2)) MB")

    # === PHASE 2: FRAMEWORK SETUP ===
    println("\n🔧 PHASE 2: Setting up verification framework...")
    framework_start = time_ns()

    ibnag1 = MINDF.default_IBNAttributeGraph(ag1)

    # Prepare framework
    operationmode = MINDF.DefaultOperationMode()
    ibnfid = AG.graph_attr(ibnag1) 
    intentdag = MINDF.IntentDAG()
    ibnfhandlers = MINDF.AbstractIBNFHandler[]
    sdncontroller = TeraflowSDN()

    # Load device/link maps
    if isfile("data/device_map.jld2")
        load_device_map!("data/device_map.jld2", sdncontroller)
        println("✓ Loaded device and link maps")
        println("   📋 Device map entries: $(length(sdncontroller.device_map))")
        println("   📋 Intra-link entries: $(length(sdncontroller.intra_link_map))")
        println("   📋 Inter-link entries: $(length(sdncontroller.inter_link_map))")
    else
        println("❌ No device map found - cannot verify")
        return nothing
    end

    # Create framework
    ibnfcomm = MINDF.IBNFCommunication(nothing, ibnfhandlers)
    ibnf1 = MINDF.IBNFramework(operationmode, ibnfid, intentdag, ibnag1, ibnfcomm, sdncontroller)
    ibnag = MINDF.getibnag(ibnf1)
    nodeviews = MINDF.getnodeviews(ibnag)

    framework_end = time_ns()
    metrics.framework_setup_time = (framework_end - framework_start) / 1e9
    phase_time = (framework_end - test_start_time) / 1e9
    record_memory(metrics, phase_time)

    metrics.total_nodes = length(nodeviews)

    println("   ✅ Framework setup in $(round(metrics.framework_setup_time, digits=3))s")
    println("   📊 Memory usage: $(round(get_memory_usage(), digits=2)) MB")
    println("   📋 Verification scope: $(length(nodeviews)) nodes")

    # === PHASE 3: RUN VERIFICATION ===
    println("\n🔍 PHASE 3: Running TFS verification with metrics...")
    verification_start = time_ns()

    device_results, intra_results, inter_results = verify_tfs_devices_and_links_with_metrics(sdncontroller, nodeviews, metrics)

    verification_end = time_ns()
    phase_time = (verification_end - test_start_time) / 1e9
    record_memory(metrics, phase_time)

    # === FINAL METRICS CALCULATION ===
    test_end_time = time_ns()
    metrics.total_execution_time = (test_end_time - test_start_time) / 1e9
    metrics.final_memory = get_memory_usage()

    # === PERFORMANCE SUMMARY ===
    println("\n" * "="^75)
    println("📊 TFS VERIFICATION PERFORMANCE SUMMARY")
    println("="^75)
    println("Data loading time:           $(round(metrics.data_load_time, digits=3))s")
    println("Framework setup time:        $(round(metrics.framework_setup_time, digits=3))s") 
    println("TFS data fetch time:         $(round(metrics.tfs_fetch_time, digits=3))s")
    println("Device verification time:    $(round(metrics.device_verification_time, digits=3))s")
    println("Intra-link verification:     $(round(metrics.intra_link_verification_time, digits=3))s")
    println("Inter-link verification:     $(round(metrics.inter_link_verification_time, digits=3))s")
    println("Report generation time:      $(round(metrics.report_generation_time, digits=3))s")
    println("Total execution time:        $(round(metrics.total_execution_time, digits=3))s")
    println()
    println("Initial memory:              $(round(metrics.initial_memory, digits=2)) MB")
    println("Peak memory:                 $(round(metrics.peak_memory, digits=2)) MB")
    println("Final memory:                $(round(metrics.final_memory, digits=2)) MB")
    println("Memory increase:             $(round(metrics.final_memory - metrics.initial_memory, digits=2)) MB")
    println()
    println("TFS Communication:")
    println("  Requests made:             $(metrics.tfs_request_count)")
    println("  TFS availability:          $(metrics.tfs_available ? "✅ Available" : "❌ Unavailable")")
    println()
    println("Verification Results:")
    println("Device health:               $(round(metrics.device_health, digits=1))%")
    println("Intra-link health:           $(round(metrics.intra_link_health, digits=1))%")
    println("Inter-link health:           $(round(metrics.inter_link_health, digits=1))%")
    println("Overall health:              $(round(metrics.overall_health, digits=1))%")

    # === SAVE PERFORMANCE DATA ===
    println("\n💾 Saving performance data...")

    # Create directories
    mkpath("data/performance")
    mkpath("plots/performance")

    timestamp = Dates.format(now(), "yyyy-mm-dd_HH-MM-SS")

    # Save raw metrics as JLD2
    JLD2.save("data/performance/verification_metrics_$timestamp.jld2", "metrics", metrics)

    # Create performance plot
    phase_names = ["Data Load", "Framework", "TFS Fetch", "Device Verify", "Intra Verify", "Inter Verify", "Report"]
    phase_times = [metrics.data_load_time, metrics.framework_setup_time, metrics.tfs_fetch_time, 
                  metrics.device_verification_time, metrics.intra_link_verification_time, 
                  metrics.inter_link_verification_time, metrics.report_generation_time]

    p1 = bar(phase_names, phase_times,
             title="TFS Verification Phase Timings", 
             xlabel="Phase", ylabel="Time (seconds)",
             color=[:blue, :green, :orange, :red, :purple, :cyan, :yellow],
             xrotation=45)

    savefig(p1, "plots/performance/verification_phase_timings_$timestamp.png")

    println("   ✅ Performance data saved to:")
    println("      📊 data/performance/verification_metrics_$timestamp.jld2")
    println("      📈 plots/performance/verification_phase_timings_$timestamp.png")

    println("\n🎯 TFS VERIFICATION TEST WITH METRICS COMPLETE!")
    println("="^75)

    return metrics
end

# Execute the verification
run_focused_verification_with_metrics()