"""
Core TeraFlow SDN types and utilities
"""

"""
    stable_uuid(node_id::Int, kind::Symbol) → String

Same (node_id, :router | :oxc | :tm | :ols) ⇒ same UUID on every run.
"""
function stable_uuid(node_id::Int, kind::Symbol)
    return string(UUIDs.uuid5(TFS_UUID_NAMESPACE, "$(node_id)-$(kind)"))
end

struct TeraflowSDN <: MINDFul.AbstractSDNController
    api_url::String
    device_map::Dict{Any,String}   # Changed from Dict{Tuple{Int,Symbol},String} to Dict{Any,String}
    intra_link_map::Dict{Tuple{Int,Symbol},String}  # (node_id, :link_type) → uuid
    inter_link_map::Dict{NTuple{6,Any},String}    # (node1, ep1_id, node2, ep2_id, :link, direction) → uuid
    endpoint_usage::Dict{String,Bool}             # endpoint_uuid → is_used
end

TeraflowSDN() = TeraflowSDN(
    "http://10.41.83.106:80/tfs-api", 
    Dict{Any,String}(),  # Changed from Dict{Tuple{Int,Symbol},String}()
    Dict{Tuple{Int,Symbol},String}(),
    Dict{NTuple{6,Any},String}(),
    Dict{String,Bool}()
)

function save_device_map(path::AbstractString, sdn::TeraflowSDN)
    @save path device_map = sdn.device_map intra_link_map = sdn.intra_link_map inter_link_map = sdn.inter_link_map endpoint_usage = sdn.endpoint_usage
end

function load_device_map!(path::AbstractString, sdn::TeraflowSDN)
    isfile(path) || return
    
    try
        @load path device_map intra_link_map inter_link_map endpoint_usage
        
        # Both exist, load them
        empty!(sdn.device_map)
        merge!(sdn.device_map, device_map)
        
        empty!(sdn.intra_link_map)
        merge!(sdn.intra_link_map, intra_link_map)
        
        empty!(sdn.inter_link_map)
        merge!(sdn.inter_link_map, inter_link_map)
        
        empty!(sdn.endpoint_usage)
        merge!(sdn.endpoint_usage, endpoint_usage)
        
        println("✓ Loaded device_map: $(length(device_map)), intra_links: $(length(intra_link_map)), inter_links: $(length(inter_link_map)), endpoint_usage: $(length(endpoint_usage))")
        
    catch e
        # Handle legacy format
        try
            @load path device_map
            empty!(sdn.device_map)
            merge!(sdn.device_map, device_map)
            println("✓ Loaded legacy device_map with $(length(device_map)) entries, initialized empty link maps")
        catch
            println("Could not load device map")
        end
    end
end