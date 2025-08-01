using MINDFulTeraFlowSDN, JSON3
using JLD2, UUIDs
using MINDFul
import AttributeGraphs as AG
using Statistics, Plots, DataFrames, CSV
using Dates

const MINDF = MINDFul

# Performance metrics collection
mutable struct GraphCreationMetrics
    # Timing metrics
    data_load_time::Float64
    graph_setup_time::Float64
    nodeview_creation_time::Float64
    total_execution_time::Float64
    
    # Memory metrics
    initial_memory::Float64
    peak_memory::Float64
    final_memory::Float64
    memory_timeline::Vector{Tuple{Float64, Float64}}  # (time, memory)
    
    # Data metrics
    nodes_count::Int
    nodeviews_count::Int
    graph_vertices::Int
    graph_edges::Int
    
    # Constructor
    GraphCreationMetrics() = new(0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 
                                Tuple{Float64, Float64}[], 0, 0, 0, 0)
end

function get_memory_usage()
    return Base.gc_live_bytes() / 1024 / 1024  # Convert to MB
end

function record_memory(metrics::GraphCreationMetrics, phase_time::Float64)
    current_memory = get_memory_usage()
    push!(metrics.memory_timeline, (phase_time, current_memory))
    if current_memory > metrics.peak_memory
        metrics.peak_memory = current_memory
    end
end

println("🚀 GRAPH CREATION TEST WITH PERFORMANCE METRICS")
println("="^60)

# Initialize metrics
metrics = GraphCreationMetrics()
test_start_time = time_ns()
metrics.initial_memory = get_memory_usage()

# === PHASE 1: DATA LOADING ===
println("\n📂 PHASE 1: Loading topology data...")
data_load_start = time_ns()

domains_name_graph = first(JLD2.load("data/itz_IowaStatewideFiberMap-itz_Missouri__(1,9)-(2,3),(1,6)-(2,54),(1,1)-(2,21).jld2"))[2]
println("Imported graph")
ag1 = first(domains_name_graph)[2]

data_load_end = time_ns()
metrics.data_load_time = (data_load_end - data_load_start) / 1e9
phase_time = (data_load_end - test_start_time) / 1e9
record_memory(metrics, phase_time)

println("   ✅ Data loaded in $(round(metrics.data_load_time, digits=3))s")
println("   📊 Memory usage: $(round(get_memory_usage(), digits=2)) MB")

# Collect graph statistics
try
    metrics.graph_vertices = AG.nv(ag1)
    metrics.graph_edges = AG.ne(ag1)
    println("   📈 Graph: $(metrics.graph_vertices) vertices, $(metrics.graph_edges) edges")
catch
    println("   ⚠️  Could not get graph statistics")
end

# === PHASE 2: GRAPH SETUP ===
println("\n🔧 PHASE 2: Setting up IBN framework...")
graph_setup_start = time_ns()

ibnag1 = MINDF.default_IBNAttributeGraph(ag1)

# Prepare all required arguments
operationmode = MINDF.DefaultOperationMode()
ibnfid = AG.graph_attr(ibnag1) 
intentdag = MINDF.IntentDAG()
ibnfhandlers = MINDF.AbstractIBNFHandler[]
sdncontroller = TeraflowSDN()

# Load existing device map if available
if isfile("data/device_map.jld2")
    load_device_map!("data/device_map.jld2", sdncontroller)
    println("   📋 Loaded existing device map with $(length(sdncontroller.device_map)) entries")
end

# Create IBNFCommunication from handlers (missing parameter)
ibnfcomm = MINDF.IBNFCommunication(nothing, ibnfhandlers)

graph_setup_end = time_ns()
metrics.graph_setup_time = (graph_setup_end - graph_setup_start) / 1e9
phase_time = (graph_setup_end - test_start_time) / 1e9
record_memory(metrics, phase_time)

println("   ✅ Framework setup in $(round(metrics.graph_setup_time, digits=3))s")
println("   📊 Memory usage: $(round(get_memory_usage(), digits=2)) MB")

# === PHASE 3: NODEVIEW CREATION ===
println("\n🏗️  PHASE 3: Creating IBN framework and nodeviews...")
nodeview_start = time_ns()

# Now call the full constructor with correct parameters
ibnf1 = MINDF.IBNFramework(operationmode, ibnfid, intentdag, ibnag1, ibnfcomm, sdncontroller)

ibnag = MINDF.getibnag(ibnf1)                       
nodeviews = MINDF.getnodeviews(ibnag)

nodeview_end = time_ns()
metrics.nodeview_creation_time = (nodeview_end - nodeview_start) / 1e9
phase_time = (nodeview_end - test_start_time) / 1e9
record_memory(metrics, phase_time)

metrics.nodeviews_count = length(nodeviews)
println("Loaded IBN graph with $(length(nodeviews)) nodeviews")

println("   ✅ Nodeviews created in $(round(metrics.nodeview_creation_time, digits=3))s")
println("   📊 Memory usage: $(round(get_memory_usage(), digits=2)) MB")
println("   📈 Total nodeviews: $(metrics.nodeviews_count)")

# === COMMENTED OUT PHASES (as in original) ===
println("\n=== Creating Devices ===")
for nodeview in nodeviews
    # If you want to see which node: 
    println("Processing node: ", nodeview.nodeproperties.localnode)  # if nodeview has a getnode method
    push_node_devices_to_tfs(nodeview, sdncontroller)
end

println("\n=== Saving Device Map ===")
save_device_map("data/device_map.jld2", sdncontroller)
println("✓ Device map saved with $(length(sdncontroller.device_map)) entries")

# Create all network links after devices are created
intra_links, inter_links = create_all_network_links(sdncontroller, nodeviews)

println("\n=== Final Save ===")
save_device_map("data/device_map.jld2", sdncontroller)
println("✓ Final device map saved with all devices and links")

println("\n=== Process Complete ===")
println("Total devices and endpoints: $(length(sdncontroller.device_map))")
println("Total intra-node links: $(length(sdncontroller.intra_link_map))")
println("Total inter-node links: $(length(sdncontroller.inter_link_map))")
println("Intra-node links created: $intra_links") 
println("Inter-node links created: $inter_links")
println("Link states applied to shared OLS devices")

# === FINAL METRICS CALCULATION ===
test_end_time = time_ns()
metrics.total_execution_time = (test_end_time - test_start_time) / 1e9
metrics.final_memory = get_memory_usage()

# === PERFORMANCE SUMMARY ===
println("\n" * "="^60)
println("📊 GRAPH CREATION PERFORMANCE SUMMARY")
println("="^60)
println("Data loading time:      $(round(metrics.data_load_time, digits=3))s")
println("Graph setup time:       $(round(metrics.graph_setup_time, digits=3))s") 
println("Nodeview creation time: $(round(metrics.nodeview_creation_time, digits=3))s")
println("Total execution time:   $(round(metrics.total_execution_time, digits=3))s")
println()
println("Initial memory:         $(round(metrics.initial_memory, digits=2)) MB")
println("Peak memory:            $(round(metrics.peak_memory, digits=2)) MB")
println("Final memory:           $(round(metrics.final_memory, digits=2)) MB")
println("Memory increase:        $(round(metrics.final_memory - metrics.initial_memory, digits=2)) MB")
println()
println("Graph vertices:         $(metrics.graph_vertices)")
println("Graph edges:            $(metrics.graph_edges)")
println("Nodeviews created:      $(metrics.nodeviews_count)")

# === SAVE PERFORMANCE DATA ===
println("\n💾 Saving performance data...")

# Create directories
mkpath("data/performance")
mkpath("plots/performance")

timestamp = Dates.format(now(), "yyyy-mm-dd_HH-MM-SS")

# Save raw metrics as JLD2
JLD2.save("data/performance/graph_creation_metrics_$timestamp.jld2", "metrics", metrics)

# Create CSV data
df = DataFrame(
    metric=String[],
    value=Float64[],
    unit=String[],
    category=String[]
)

# Timing metrics
push!(df, ("data_load_time", metrics.data_load_time, "seconds", "timing"))
push!(df, ("graph_setup_time", metrics.graph_setup_time, "seconds", "timing"))
push!(df, ("nodeview_creation_time", metrics.nodeview_creation_time, "seconds", "timing"))
push!(df, ("total_execution_time", metrics.total_execution_time, "seconds", "timing"))

# Memory metrics
push!(df, ("initial_memory", metrics.initial_memory, "MB", "memory"))
push!(df, ("peak_memory", metrics.peak_memory, "MB", "memory"))
push!(df, ("final_memory", metrics.final_memory, "MB", "memory"))
push!(df, ("memory_increase", metrics.final_memory - metrics.initial_memory, "MB", "memory"))

# Data metrics
push!(df, ("graph_vertices", Float64(metrics.graph_vertices), "count", "graph"))
push!(df, ("graph_edges", Float64(metrics.graph_edges), "count", "graph"))
push!(df, ("nodeviews_count", Float64(metrics.nodeviews_count), "count", "graph"))

# Memory timeline
for (i, (time, memory)) in enumerate(metrics.memory_timeline)
    push!(df, ("memory_timeline_$(i)_time", time, "seconds", "memory_timeline"))
    push!(df, ("memory_timeline_$(i)_memory", memory, "MB", "memory_timeline"))
end

CSV.write("data/performance/graph_creation_metrics_$timestamp.csv", df)

# === GENERATE PERFORMANCE PLOTS ===
println("📈 Generating performance plots...")

# Plot 1: Phase timing breakdown
p1 = bar(["Data Load", "Graph Setup", "Nodeviews"], 
         [metrics.data_load_time, metrics.graph_setup_time, metrics.nodeview_creation_time],
         title="Graph Creation Phase Timings", 
         xlabel="Phase", ylabel="Time (seconds)",
         color=[:blue, :green, :orange])

# Add time labels
annotate!(p1, 1, metrics.data_load_time + 0.01, text("$(round(metrics.data_load_time, digits=3))s", 10))
annotate!(p1, 2, metrics.graph_setup_time + 0.01, text("$(round(metrics.graph_setup_time, digits=3))s", 10))
annotate!(p1, 3, metrics.nodeview_creation_time + 0.01, text("$(round(metrics.nodeview_creation_time, digits=3))s", 10))

savefig(p1, "plots/performance/graph_creation_phase_timings_$timestamp.png")

# Plot 2: Memory usage timeline
if !isempty(metrics.memory_timeline)
    times = [t[1] for t in metrics.memory_timeline]
    memory_values = [t[2] for t in metrics.memory_timeline]
    
    p2 = plot(times, memory_values, 
              title="Memory Usage During Graph Creation", 
              xlabel="Time (seconds)", ylabel="Memory Usage (MB)",
              linewidth=3, color=:red, marker=:circle, markersize=4)
    
    # Add peak memory line
    hline!(p2, [metrics.peak_memory], 
           label="Peak: $(round(metrics.peak_memory, digits=2)) MB", 
           linestyle=:dash, color=:darkred, linewidth=2)
    
    # Add phase markers
    vline!(p2, [metrics.data_load_time], 
           label="Data Load Complete", linestyle=:dot, color=:blue)
    vline!(p2, [metrics.data_load_time + metrics.graph_setup_time], 
           label="Graph Setup Complete", linestyle=:dot, color=:green)
    
    savefig(p2, "plots/performance/graph_creation_memory_timeline_$timestamp.png")
end

# Plot 3: Performance dashboard
p_dashboard = plot(layout=(2, 2), size=(1200, 900))

# Phase timings
bar!(p_dashboard[1], ["Load", "Setup", "Nodeviews"], 
     [metrics.data_load_time, metrics.graph_setup_time, metrics.nodeview_creation_time],
     title="Phase Timings", subplot=1, color=[:blue, :green, :orange])

# Memory usage
if !isempty(metrics.memory_timeline)
    times = [t[1] for t in metrics.memory_timeline]
    memory_values = [t[2] for t in metrics.memory_timeline]
    plot!(p_dashboard[2], times, memory_values, title="Memory Usage", 
          subplot=2, color=:red, linewidth=2, marker=:circle)
end

# Graph statistics
bar!(p_dashboard[3], ["Vertices", "Edges", "Nodeviews"], 
     [metrics.graph_vertices, metrics.graph_edges, metrics.nodeviews_count],
     title="Graph Statistics", subplot=3, color=[:purple, :cyan, :yellow])

# Performance summary text
plot!(p_dashboard[4], [], [], title="Performance Summary", subplot=4, showaxis=false, grid=false)
annotate!(p_dashboard[4], 0.5, 0.9, text("Total Time: $(round(metrics.total_execution_time, digits=2))s", 12))
annotate!(p_dashboard[4], 0.5, 0.7, text("Peak Memory: $(round(metrics.peak_memory, digits=1)) MB", 12))
annotate!(p_dashboard[4], 0.5, 0.5, text("Memory Increase: $(round(metrics.final_memory - metrics.initial_memory, digits=1)) MB", 12))
annotate!(p_dashboard[4], 0.5, 0.3, text("Nodeviews: $(metrics.nodeviews_count)", 12))
annotate!(p_dashboard[4], 0.5, 0.1, text("Graph: $(metrics.graph_vertices)v, $(metrics.graph_edges)e", 12))

savefig(p_dashboard, "plots/performance/graph_creation_dashboard_$timestamp.png")

println("   ✅ Performance data saved to:")
println("      📊 data/performance/graph_creation_metrics_$timestamp.jld2")
println("      📊 data/performance/graph_creation_metrics_$timestamp.csv")
println("   ✅ Performance plots saved to:")
println("      📈 plots/performance/graph_creation_phase_timings_$timestamp.png")
println("      📈 plots/performance/graph_creation_memory_timeline_$timestamp.png")
println("      📈 plots/performance/graph_creation_dashboard_$timestamp.png")

println("\n🎯 GRAPH CREATION TEST WITH METRICS COMPLETE!")
println("="^60)

# Return metrics for further analysis if needed
metrics