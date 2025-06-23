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
    "http://127.0.0.1:80/tfs-api", 
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

# Remove OLS-related functions from individual nodes
# function ols_endpoints_needed(nodeview) - REMOVE
# function create_ols_endpoints(sdn::TeraflowSDN, node_id::Int, min_endpoints::Int) - REMOVE
# function get_available_ols_endpoint(sdn::TeraflowSDN, node_id::Int) - REMOVE

# Add new functions for shared OLS devices
function create_shared_ols_device(sdn::TeraflowSDN, node1_id::Int, node2_id::Int)
    """Create a shared OLS device between two nodes with 4 fiber endpoints"""
    # Generate stable UUID for OLS device based on both nodes
    sorted_nodes = sort([node1_id, node2_id])
    ols_key = (sorted_nodes[1], sorted_nodes[2], :shared_ols)
    ols_uuid = get!(sdn.device_map, ols_key) do
        stable_uuid(sorted_nodes[1] * 1000 + sorted_nodes[2], :shared_ols)
    end
    
    # Create 4 fiber endpoints for the shared OLS
    endpoints = String[]
    for ep_id in 1:4
        ep_uuid = stable_uuid(sorted_nodes[1] * 10000 + sorted_nodes[2] * 100 + ep_id, Symbol("shared_ols_ep_$(ep_id)"))
        ep_key = (sorted_nodes[1], sorted_nodes[2], Symbol("shared_ols_ep_$(ep_id)"))
        
        sdn.device_map[ep_key] = ep_uuid
        sdn.endpoint_usage[ep_uuid] = false
        push!(endpoints, ep_uuid)
    end
    
    # Create endpoints config
    endpoints_config = []
    for (i, ep_uuid) in enumerate(endpoints)
        push!(endpoints_config, Dict("sample_types"=>Any[],
                                    "type"=>"fiber",
                                    "uuid"=>ep_uuid,
                                    "name"=>"shared_ols_ep_$(i)_nodes_$(sorted_nodes[1])_$(sorted_nodes[2])"))
    end

    ep_rule = _custom_rule("_connect/settings", Dict("endpoints" => endpoints_config))

    device_drivers = Vector{Ctx.DeviceDriverEnum.T}()
    push!(device_drivers, Ctx.DeviceDriverEnum.DEVICEDRIVER_UNDEFINED)

    dev = Ctx.Device(
        Ctx.DeviceId(Ctx.Uuid(ols_uuid)),
        "SharedOLS-Nodes-$(sorted_nodes[1])-$(sorted_nodes[2])",
        "emu-open-line-system",
        Ctx.DeviceConfig([ep_rule]),
        Ctx.DeviceOperationalStatusEnum.DEVICEOPERATIONALSTATUS_ENABLED,
        device_drivers,
        Ctx.EndPoint[], Ctx.Component[], nothing)

    if ensure_post_device(sdn.api_url, dev)
        println("✓ Shared OLS device $ols_uuid created successfully for nodes $(sorted_nodes[1]) ↔ $(sorted_nodes[2])")
        return ols_uuid, endpoints
    else
        @warn "Shared OLS device $ols_uuid could not be created/updated"
        return nothing, []
    end
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

function push_node_devices_to_tfs(nodeview, sdn::TeraflowSDN)


    node_id = nodeview.nodeproperties.localnode

    # ───────────────────────── Router ───────────────────────────────────────
    if nodeview.routerview !== nothing
        key  = (node_id, :router)
        uuid = get!(sdn.device_map, key) do
                    stable_uuid(node_id, :router)
                end

        # Create 2 copper endpoints for router
        endpoint_uuids = create_router_endpoints(sdn, node_id)

        endpoints_config = []
        for (i, ep_uuid) in enumerate(endpoint_uuids)
            push!(endpoints_config, Dict("sample_types"=>Any[],
                                        "type"=>"copper",
                                        "uuid"=>ep_uuid,
                                        "name"=>"router_ep_$(i)_node_$(node_id)"))
        end

        ep_rule = _custom_rule("_connect/settings", Dict("endpoints" => endpoints_config))

        # Fix: Use proper array constructor for device_drivers
        device_drivers = Vector{Ctx.DeviceDriverEnum.T}()
        push!(device_drivers, Ctx.DeviceDriverEnum.DEVICEDRIVER_UNDEFINED)

        dev  = Ctx.Device(
                    Ctx.DeviceId(Ctx.Uuid(uuid)),
                    "Router-Node-$(node_id)",                     # name
                    "emu-packet-router",                # device_type
                    Ctx.DeviceConfig([ep_rule]),               # empty config – rules follow
                    Ctx.DeviceOperationalStatusEnum.DEVICEOPERATIONALSTATUS_ENABLED,
                    device_drivers,  # Use the properly constructed array
                    Ctx.EndPoint[], Ctx.Component[], nothing)

        if ensure_post_device(sdn.api_url, dev)
            rules = build_config_rules(nodeview.routerview)
            _push_rules(sdn.api_url, uuid, rules; kind=:Router)
        else
            @warn "Router device $uuid could not be created/updated"
        end
    end

    # ───────────────────────── OXC ───────────────────────────────────────────
    if nodeview.oxcview !== nothing
        # Calculate and create variable number of fiber endpoints for OXC based on neighbors
        n_eps = oxc_endpoints_needed(nodeview)
        endpoint_uuids = create_oxc_endpoints(sdn, node_id, n_eps)
        println("  [OXC $node_id] Created $n_eps fiber endpoints before posting device")

        key  = (node_id, :oxc)
        uuid = get!(sdn.device_map, key) do
            stable_uuid(node_id, :oxc)
        end

        endpoints_config = []
        for (i, ep_uuid) in enumerate(endpoint_uuids)
            push!(endpoints_config, Dict("sample_types"=>Any[],
                                        "type"=>"fiber",
                                        "uuid"=>ep_uuid,
                                        "name"=>"oxc_ep_$(i)_node_$(node_id)"))
        end

        ep_rule = _custom_rule("_connect/settings", Dict("endpoints" => endpoints_config))

        device_drivers = Vector{Ctx.DeviceDriverEnum.T}()
        push!(device_drivers, Ctx.DeviceDriverEnum.DEVICEDRIVER_UNDEFINED)

        dev  = Ctx.Device(
                    Ctx.DeviceId(Ctx.Uuid(uuid)),
                    "OXC-Node-$(node_id)",
                    "emu-optical-roadm",
                    Ctx.DeviceConfig([ep_rule]),
                    Ctx.DeviceOperationalStatusEnum.DEVICEOPERATIONALSTATUS_ENABLED,
                    device_drivers,
                    Ctx.EndPoint[], Ctx.Component[], nothing)

        if ensure_post_device(sdn.api_url, dev)
            rules = build_config_rules(nodeview.oxcview)
            _push_rules(sdn.api_url, uuid, rules; kind=:OXC)
        else
            @warn "OXC device $uuid could not be created/updated"
        end
    end

    # Remove OLS creation from individual nodes - it will be created during inter-node linking

    # ─────────────────────── Transmission Modules ───────────────────────────
    if nodeview.transmissionmoduleviewpool !== nothing
        for (idx, tmview) in enumerate(nodeview.transmissionmoduleviewpool)
            key  = (node_id, Symbol("tm_$idx"))
            uuid = get!(sdn.device_map, key) do
                    stable_uuid(node_id * 10_000 + idx, :tm)
                end

            # Create 4 endpoints for TM (2 copper + 2 fiber)
            endpoint_uuids = create_tm_endpoints(sdn, node_id, idx)

            endpoints_config = []
            for i in 1:2  # First 2 are copper
                ep_uuid = endpoint_uuids[i]
                push!(endpoints_config, Dict("sample_types"=>Any[],
                                            "type"=>"copper",
                                            "uuid"=>ep_uuid,
                                            "name"=>"tm_$(idx)_copper_ep_$(i)_node_$(node_id)"))
            end
            for i in 3:4  # Next 2 are fiber
                ep_uuid = endpoint_uuids[i]
                push!(endpoints_config, Dict("sample_types"=>Any[],
                                            "type"=>"fiber",
                                            "uuid"=>ep_uuid,
                                            "name"=>"tm_$(idx)_fiber_ep_$(i-2)_node_$(node_id)"))
            end

            ep_rule = _custom_rule("_connect/settings", Dict("endpoints" => endpoints_config))

            dev  = Ctx.Device(
                    Ctx.DeviceId(Ctx.Uuid(uuid)),
                    "TM-Node-$(node_id)-$(idx)",
                    "emu-optical-transponder",
                    Ctx.DeviceConfig([ep_rule]),
                    Ctx.DeviceOperationalStatusEnum.DEVICEOPERATIONALSTATUS_ENABLED,
                    [Ctx.DeviceDriverEnum.DEVICEDRIVER_UNDEFINED],
                    Ctx.EndPoint[], Ctx.Component[], nothing)

            if ensure_post_device(sdn.api_url, dev)
                # Use first copper endpoint for TM rules
                first_copper_ep_uuid = endpoint_uuids[1]
                rules = build_config_rules(tmview; ep_uuid=first_copper_ep_uuid)
                _push_rules(sdn.api_url, uuid, rules; kind=:TM)
            else
                @warn "TM device $uuid could not be created/updated"
            end
        end
    end

    println("Pushed node devices to TFS")

end


"""
    _jsonify(x) → Dict | Array | primitive

Convert MINDFul view/LLI/helper objects to plain JSON-serialisable data.
Everything falls back to `x` itself if we do not recognise the type.
"""
_jsonify(x) = x                     # primitive fallback

# ── primitives ────────────────────────────────────────────────────────────
_jsonify(u::UUID)                     = string(u)

# ── basic helper structs ─────────────────────────────────────────────────
_jsonify(p::MINDFul.RouterPort)       = Dict("rate" => p.rate)

_jsonify(t::MINDFul.TransmissionMode) = Dict(
    "opticalreach"        => t.opticalreach,
    "rate"                => t.rate,
    "spectrumslotsneeded" => t.spectrumslotsneeded,
)

# ── LLIs ──────────────────────────────────────────────────────────────────
_jsonify(lli::MINDFul.RouterPortLLI) = Dict(
    "localnode"       => lli.localnode,
    "routerportindex" => lli.routerportindex,
)

_jsonify(lli::MINDFul.TransmissionModuleLLI) = Dict(
    "localnode"                       => lli.localnode,
    "transmissionmoduleviewpoolindex" => lli.transmissionmoduleviewpoolindex,
    "transmissionmodesindex"          => lli.transmissionmodesindex,
    "routerportindex"                 => lli.routerportindex,
    "adddropport"                     => lli.adddropport,
)

_jsonify(lli::MINDFul.OXCAddDropBypassSpectrumLLI) = Dict(
    "localnode"        => lli.localnode,
    "localnode_input"  => lli.localnode_input,
    "adddropport"      => lli.adddropport,
    "localnode_output" => lli.localnode_output,
    "spectrumslots"    => [first(lli.spectrumslotsrange), last(lli.spectrumslotsrange)],
)

# convenience for Dicts/Sets of LLIs
function _jsonify_table(tbl::Dict)
    return [Dict("uuid" => string(k), "lli" => _jsonify(v)) for (k,v) in tbl]
end
_jsonify_table(set::Set) = [_jsonify(x) for x in set]


function _wrap_to_object(path::AbstractString, payload)
    
    if payload isa AbstractDict
        return payload
    end
    
    field = last(split(path, '/'; keepempty=false))   # e.g. "ports"
    return Dict(field => payload)
end


function _custom_rule(path::AbstractString, payload)::Ctx.ConfigRule
    wrapped = _wrap_to_object(path, payload)
    return Ctx.ConfigRule(
        Ctx.ConfigActionEnum.CONFIGACTION_SET,
        OneOf(:custom, Ctx.ConfigRule_Custom(path, JSON3.write(wrapped))),
    )
end


build_config_rules(view) = Ctx.ConfigRule[]   # fallback 


function _push_rules(api_url::String, uuid::String, rules::Vector{Ctx.ConfigRule};
                    kind::Symbol="")
    isempty(rules) && return true                     # nothing to do
    ok = add_config_rule!(api_url, uuid, rules)
    ok || @warn "$kind rule update failed for $uuid"
    return ok
end


function _rules_from_table(base::AbstractString, tbl)::Vector{Ctx.ConfigRule}
    out = Ctx.ConfigRule[]
    idx = 1
    for (k, v) in tbl
        push!(out, _custom_rule("$base/$(string(k))", _jsonify(v)))
    end
    # `tbl` could be a Set, iterate separately
    if tbl isa Set
        for lli in tbl
            push!(out, _custom_rule("$base/$(idx)", _jsonify(lli)))
            idx += 1
        end
    end
    return out
end

# ───────── RouterView ───────────────────────────────────────────────────────
function build_config_rules(rv::MINDFul.RouterView)
    rules = Ctx.ConfigRule[]
    push!(rules, _custom_rule("/router",        string(typeof(rv.router))))
    push!(rules, _custom_rule("/portnumber",    length(rv.ports)))
    push!(rules, _custom_rule("/ports",         [_jsonify(p) for p in rv.ports]))

    append!(rules, _rules_from_table("/portreservations", rv.portreservations))
    append!(rules, _rules_from_table("/portstaged",       rv.portstaged))

    return rules
end

# ───────── OXCView ─────────────────────────────────────────────────────────
function build_config_rules(oxc::MINDFul.OXCView)
    rules = Ctx.ConfigRule[]
    push!(rules, _custom_rule("/oxc",                 string(typeof(oxc.oxc))))
    push!(rules, _custom_rule("/adddropportnumber",   oxc.adddropportnumber))

    append!(rules, _rules_from_table("/switchreservations", oxc.switchreservations))
    append!(rules, _rules_from_table("/switchstaged",       oxc.switchstaged))

    return rules
end


# ───────── TransmissionModuleView ─────────────────────────────────────────
function build_config_rules(tm::MINDFul.TransmissionModuleView; ep_uuid::Union{String,Nothing}=nothing)
    rules = Ctx.ConfigRule[]
    push!(rules, _custom_rule("/transmissionmodule", string(typeof(tm.transmissionmodule))))
    push!(rules, _custom_rule("/name",               tm.name))
    push!(rules, _custom_rule("/cost",               tm.cost))

    for (idx, mode) in enumerate(tm.transmissionmodes)
        push!(rules, _custom_rule("/transmissionmodes/$idx", _jsonify(mode)))
    end

    return rules
end

"""
    create_link_between_devices(sdn::TeraflowSDN, device1_key::Tuple, device2_key::Tuple, 
                               link_name::String, link_uuid::String; 
                               link_type::Symbol = :copper) → Bool

General function to create a link between any two devices using their endpoint keys.
Device-agnostic - works with any device types (router, oxc, tm, ols, etc.)
"""
function create_link_between_devices(sdn::TeraflowSDN, device1_key::Tuple, device2_key::Tuple,
                                   link_name::String, link_uuid::String;
                                   link_type::Symbol = :copper)
    
    # Check if both endpoints exist in device map
    if !haskey(sdn.device_map, device1_key)
        @warn "Device endpoint not found: $device1_key"
        return false
    end
    
    if !haskey(sdn.device_map, device2_key)
        @warn "Device endpoint not found: $device2_key"
        return false
    end
    
    endpoint1_uuid = sdn.device_map[device1_key]
    endpoint2_uuid = sdn.device_map[device2_key]
    
    # Find the corresponding device UUIDs
    # Extract node_id and device type from endpoint keys
    node1_id, ep1_type = device1_key
    node2_id, ep2_type = device2_key
    
    # Updated endpoint type mapping to handle all device types
    device1_type = if string(ep1_type) |> x -> startswith(x, "router_ep_")
        :router
    elseif ep1_type == :oxc_ep || (string(ep1_type) |> x -> startswith(x, "oxc_ep_"))
        :oxc
    elseif string(ep1_type) |> x -> startswith(x, "ols_ep_")
        :ols
    elseif string(ep1_type) |> x -> startswith(x, "tm_")
        Symbol(replace(string(ep1_type), r"_copper_ep_\d+|_fiber_ep_\d+" => ""))
    else
        error("Unknown endpoint type: $ep1_type")
    end
    
    device2_type = if string(ep2_type) |> x -> startswith(x, "router_ep_")
        :router
    elseif ep2_type == :oxc_ep || (string(ep2_type) |> x -> startswith(x, "oxc_ep_"))
        :oxc
    elseif string(ep2_type) |> x -> startswith(x, "ols_ep_")
        :ols
    elseif string(ep2_type) |> x -> startswith(x, "tm_")
        Symbol(replace(string(ep2_type), r"_copper_ep_\d+|_fiber_ep_\d+" => ""))
    else
        error("Unknown endpoint type: $ep2_type")
    end
    
    # Get device UUIDs
    device1_key_lookup = (node1_id, device1_type)
    device2_key_lookup = (node2_id, device2_type)
    
    if !haskey(sdn.device_map, device1_key_lookup)
        @warn "Device not found: $device1_key_lookup"
        return false
    end
    
    if !haskey(sdn.device_map, device2_key_lookup)
        @warn "Device not found: $device2_key_lookup"
        return false
    end
    
    device1_uuid = sdn.device_map[device1_key_lookup]
    device2_uuid = sdn.device_map[device2_key_lookup]
    
    # Create EndPointIds for the link endpoints with proper device_id
    endpoint_ids = [
        Ctx.EndPointId(
            nothing,  # topology_id
            Ctx.DeviceId(Ctx.Uuid(device1_uuid)),  # device_id
            Ctx.Uuid(endpoint1_uuid)  # endpoint_uuid
        ),
        Ctx.EndPointId(
            nothing,  # topology_id
            Ctx.DeviceId(Ctx.Uuid(device2_uuid)),  # device_id
            Ctx.Uuid(endpoint2_uuid)  # endpoint_uuid
        )
    ]
    
    # Updated link type enum mapping to match new proto of TFS 5.0.0
    tfs_link_type = if link_type == :copper
        Ctx.LinkTypeEnum.LINKTYPE_COPPER
    elseif link_type == :fiber || link_type == :optical  # Map :optical to :fiber
        Ctx.LinkTypeEnum.LINKTYPE_FIBER
    elseif link_type == :radio
        Ctx.LinkTypeEnum.LINKTYPE_RADIO
    elseif link_type == :virtual
        Ctx.LinkTypeEnum.LINKTYPE_VIRTUAL
    elseif link_type == :management
        Ctx.LinkTypeEnum.LINKTYPE_MANAGEMENT
    else
        Ctx.LinkTypeEnum.LINKTYPE_COPPER  # Default fallback
    end
    
    # Create link with proper structure
    link = Ctx.Link(
        Ctx.LinkId(Ctx.Uuid(link_uuid)),
        link_name,
        tfs_link_type,           # link_type moved to position 3
        endpoint_ids,            # link_endpoint_ids moved to position 4
        Ctx.LinkAttributes(0.0f0, 0.0f0)  # attributes moved to position 5
    )
    
    # Use ensure_post_link for robust creation with verification
    return ensure_post_link(sdn.api_url, link)
end

"""
    create_router_tm_link(sdn::TeraflowSDN, node_id::Int) → Bool
Create intra-node link between router and first TM using copper endpoints.
Router ep1 (incoming) → TM copper ep1, Router ep2 (outgoing) → TM copper ep2
"""
function create_router_tm_link(sdn::TeraflowSDN, node_id::Int; link_type::Symbol = :copper)
    # Check if first TM exists
    tm_key = (node_id, :tm_1)
    if !haskey(sdn.device_map, tm_key)
        @warn "First TM device not found for node $node_id"
        return false
    end
    
    success_count = 0
    
    # Create two links: Router ep1 ↔ TM copper ep1, Router ep2 ↔ TM copper ep2
    for ep_pair in [(1, 1), (2, 2)]
        router_ep_idx, tm_ep_idx = ep_pair
        
        router_ep_key = (node_id, Symbol("router_ep_$(router_ep_idx)"))
        tm_ep_key = (node_id, Symbol("tm_1_copper_ep_$(tm_ep_idx)"))
        
        if !haskey(sdn.device_map, router_ep_key)
            @warn "Router endpoint not found: $router_ep_key"
            continue
        end
        
        if !haskey(sdn.device_map, tm_ep_key)
            @warn "TM endpoint not found: $tm_ep_key"
            continue
        end
        
        router_ep_uuid = sdn.device_map[router_ep_key]
        tm_ep_uuid = sdn.device_map[tm_ep_key]
        
        # Check if already used
        if get(sdn.endpoint_usage, router_ep_uuid, false) || get(sdn.endpoint_usage, tm_ep_uuid, false)
            @warn "Endpoints already in use for router-tm link: $router_ep_key ↔ $tm_ep_key"
            continue
        end
        
        # Generate link details
        link_uuid = stable_uuid(node_id * 100 + ep_pair[1], Symbol("router_tm_link_$(ep_pair[1])"))
        link_name = "IntraLink-Router-ep$(router_ep_idx)-TM1-copper-ep$(tm_ep_idx)-node-$(node_id)"
        link_key = (node_id, Symbol("router_tm_link_$(ep_pair[1])"))
        
        # Store in intra-link map
        sdn.intra_link_map[link_key] = link_uuid
        
        # Create the link
        success = create_link_between_devices(sdn, router_ep_key, tm_ep_key, 
                                            link_name, link_uuid; link_type=link_type)
        
        if success
            # Mark endpoints as used
            sdn.endpoint_usage[router_ep_uuid] = true
            sdn.endpoint_usage[tm_ep_uuid] = true
            success_count += 1
            println("✓ Created router-TM link: Router-ep$(router_ep_idx) ↔ TM1-copper-ep$(tm_ep_idx) (node $node_id)")
        else
            @warn "✗ Failed to create router-TM link for endpoints $(ep_pair) (node $node_id)"
        end
    end
    
    return success_count == 2  # Both links should succeed
end

"""
    create_tm_oxc_link(sdn::TeraFlowSDN, node_id::Int) → Bool
Create intra-node link between first TM and OXC using fiber endpoints.
TM fiber ep1 ↔ OXC ep1, TM fiber ep2 ↔ OXC ep2
"""
function create_tm_oxc_link(sdn::TeraflowSDN, node_id::Int; link_type::Symbol = :fiber)
    success_count = 0
    
    # Create two links: TM fiber ep1 ↔ OXC ep1, TM fiber ep2 ↔ OXC ep2
    for ep_pair in [(1, 1), (2, 2)]
        tm_ep_idx, oxc_ep_idx = ep_pair
        
        tm_ep_key = (node_id, Symbol("tm_1_fiber_ep_$(tm_ep_idx)"))
        oxc_ep_key = (node_id, Symbol("oxc_ep_$(oxc_ep_idx)"))
        
        if !haskey(sdn.device_map, tm_ep_key)
            @warn "TM fiber endpoint not found: $tm_ep_key"
            continue
        end
        
        if !haskey(sdn.device_map, oxc_ep_key)
            @warn "OXC endpoint not found: $oxc_ep_key"
            continue
        end
        
        tm_ep_uuid = sdn.device_map[tm_ep_key]
        oxc_ep_uuid = sdn.device_map[oxc_ep_key]
        
        # Check if already used
        if get(sdn.endpoint_usage, tm_ep_uuid, false) || get(sdn.endpoint_usage, oxc_ep_uuid, false)
            @warn "Endpoints already in use for tm-oxc link: $tm_ep_key ↔ $oxc_ep_key"
            continue
        end
        
        # Generate link details
        link_uuid = stable_uuid(node_id * 200 + ep_pair[1], Symbol("tm_oxc_link_$(ep_pair[1])"))
        link_name = "IntraLink-TM1-fiber-ep$(tm_ep_idx)-OXC-ep$(oxc_ep_idx)-node-$(node_id)"
        link_key = (node_id, Symbol("tm_oxc_link_$(ep_pair[1])"))
        
        # Store in intra-link map
        sdn.intra_link_map[link_key] = link_uuid
        
        # Create the link
        success = create_link_between_devices(sdn, tm_ep_key, oxc_ep_key,
                                            link_name, link_uuid; link_type=link_type)
        
        if success
            # Mark endpoints as used
            sdn.endpoint_usage[tm_ep_uuid] = true
            sdn.endpoint_usage[oxc_ep_uuid] = true
            success_count += 1
            println("✓ Created TM-OXC link: TM1-fiber-ep$(tm_ep_idx) ↔ OXC-ep$(oxc_ep_idx) (node $node_id)")
        else
            @warn "✗ Failed to create TM-OXC link for endpoints $(ep_pair) (node $node_id)"
        end
    end
    
    return success_count == 2
end

# Remove create_oxc_ols_link function as OLS is no longer per-node

# Update inter-node linking to create shared OLS and connect OXCs to it
"""
    create_inter_node_connection_with_shared_ols(sdn::TeraflowSDN, node1_id::Int, node2_id::Int) → Bool
Create inter-node connection with shared OLS device.
Creates shared OLS between two nodes and connects each node's OXC to it with 2 links each (if OXC exists).
"""
function create_inter_node_connection_with_shared_ols(sdn::TeraflowSDN, node1_id::Int, node2_id::Int; link_type::Symbol = :fiber)
    println("🌉 Creating inter-node connection with shared OLS: $node1_id ↔ $node2_id")
    
    # Check if nodes have OXC
    node1_has_oxc = haskey(sdn.device_map, (node1_id, :oxc))
    node2_has_oxc = haskey(sdn.device_map, (node2_id, :oxc))
    
    # Create shared OLS device
    ols_uuid, ols_endpoints = create_shared_ols_device(sdn, node1_id, node2_id)
    if ols_uuid === nothing
        @warn "Failed to create shared OLS device for nodes $node1_id ↔ $node2_id"
        return false
    end
    
    success_count = 0
    sorted_nodes = sort([node1_id, node2_id])
    
    # Connect node1's OXC to shared OLS (2 links) - only if node1 has OXC
    if node1_has_oxc
        for ep_idx in 1:2
            try
                # Get available OXC endpoint from node1
                oxc_ep_key, oxc_ep_uuid = get_available_oxc_endpoint(sdn, node1_id)
                
                # Get available shared OLS endpoint
                ols_ep_key, ols_ep_uuid = get_available_shared_ols_endpoint(sdn, node1_id, node2_id)
                
                # Generate link details
                link_uuid = stable_uuid(sorted_nodes[1] * 10000 + sorted_nodes[2] * 100 + ep_idx, 
                                      Symbol("oxc_sharedols_link_node$(node1_id)_ep$(ep_idx)"))
                
                oxc_ep_id = string(oxc_ep_key[2])
                ols_ep_id = string(ols_ep_key[3])
                link_name = "InterLink-OXC-$(oxc_ep_id)-node-$(node1_id)-SharedOLS-$(ols_ep_id)-nodes-$(sorted_nodes[1])-$(sorted_nodes[2])"
                
                # Create link key for inter-link map
                link_key = (node1_id, oxc_ep_id, sorted_nodes[1], sorted_nodes[2], ols_ep_id, :shared_ols_link)
                
                # Store in inter-link map
                sdn.inter_link_map[link_key] = link_uuid
                
                # Create the actual link
                success = create_link_between_devices_shared_ols(sdn, oxc_ep_key, ols_ep_key,
                                                              link_name, link_uuid; link_type=link_type)
                
                if success
                    # Mark endpoints as used
                    sdn.endpoint_usage[oxc_ep_uuid] = true
                    sdn.endpoint_usage[ols_ep_uuid] = true
                    success_count += 1
                    println("✓ Connected OXC node $node1_id ($(oxc_ep_id)) to shared OLS ($(ols_ep_id))")
                else
                    delete!(sdn.inter_link_map, link_key)
                    @warn "✗ Failed to connect OXC node $node1_id to shared OLS"
                end
                
            catch e
                @warn "✗ Failed to get available endpoints for node $node1_id: $e"
            end
        end
    else
        println("⚠️  Node $node1_id has no OXC device - shared OLS created for future connection")
    end
    
    # Connect node2's OXC to shared OLS (2 links) - only if node2 has OXC
    if node2_has_oxc
        for ep_idx in 1:2
            try
                # Get available OXC endpoint from node2
                oxc_ep_key, oxc_ep_uuid = get_available_oxc_endpoint(sdn, node2_id)
                
                # Get available shared OLS endpoint
                ols_ep_key, ols_ep_uuid = get_available_shared_ols_endpoint(sdn, node1_id, node2_id)
                
                # Generate link details
                link_uuid = stable_uuid(sorted_nodes[1] * 10000 + sorted_nodes[2] * 100 + ep_idx + 10, 
                                      Symbol("oxc_sharedols_link_node$(node2_id)_ep$(ep_idx)"))
                
                oxc_ep_id = string(oxc_ep_key[2])
                ols_ep_id = string(ols_ep_key[3])
                link_name = "InterLink-OXC-$(oxc_ep_id)-node-$(node2_id)-SharedOLS-$(ols_ep_id)-nodes-$(sorted_nodes[1])-$(sorted_nodes[2])"
                
                # Create link key for inter-link map
                link_key = (node2_id, oxc_ep_id, sorted_nodes[1], sorted_nodes[2], ols_ep_id, :shared_ols_link)
                
                # Store in inter-link map
                sdn.inter_link_map[link_key] = link_uuid
                
                # Create the actual link
                success = create_link_between_devices_shared_ols(sdn, oxc_ep_key, ols_ep_key,
                                                              link_name, link_uuid; link_type=link_type)
                
                if success
                    # Mark endpoints as used
                    sdn.endpoint_usage[oxc_ep_uuid] = true
                    sdn.endpoint_usage[ols_ep_uuid] = true
                    success_count += 1
                    println("✓ Connected OXC node $node2_id ($(oxc_ep_id)) to shared OLS ($(ols_ep_id))")
                else
                    delete!(sdn.inter_link_map, link_key)
                    @warn "✗ Failed to connect OXC node $node2_id to shared OLS"
                end
                
            catch e
                @warn "✗ Failed to get available endpoints for node $node2_id: $e"
            end
        end
    else
        println("⚠️  Node $node2_id has no OXC device - shared OLS created for future connection")
    end
    
    # Expected success count depends on how many nodes have OXC
    expected_links = (node1_has_oxc ? 2 : 0) + (node2_has_oxc ? 2 : 0)
    return success_count == expected_links
end

# Add helper function for shared OLS linking
function create_link_between_devices_shared_ols(sdn::TeraflowSDN, oxc_ep_key::Tuple, ols_ep_key::Tuple,
                                               link_name::String, link_uuid::String;
                                               link_type::Symbol = :fiber)
    
    if !haskey(sdn.device_map, oxc_ep_key)
        @warn "OXC endpoint not found: $oxc_ep_key"
        return false
    end
    
    if !haskey(sdn.device_map, ols_ep_key)
        @warn "Shared OLS endpoint not found: $ols_ep_key"
        return false
    end
    
    oxc_ep_uuid = sdn.device_map[oxc_ep_key]
    ols_ep_uuid = sdn.device_map[ols_ep_key]
    
    # Get OXC device UUID
    node_id = oxc_ep_key[1]
    oxc_device_key = (node_id, :oxc)
    if !haskey(sdn.device_map, oxc_device_key)
        @warn "OXC device not found: $oxc_device_key"
        return false
    end
    oxc_device_uuid = sdn.device_map[oxc_device_key]
    
    # Get shared OLS device UUID
    ols_device_key = (ols_ep_key[1], ols_ep_key[2], :shared_ols)
    if !haskey(sdn.device_map, ols_device_key)
        @warn "Shared OLS device not found: $ols_device_key"
        return false
    end
    ols_device_uuid = sdn.device_map[ols_device_key]
    
    # Create EndPointIds
    endpoint_ids = [
        Ctx.EndPointId(
            nothing,
            Ctx.DeviceId(Ctx.Uuid(oxc_device_uuid)),
            Ctx.Uuid(oxc_ep_uuid)
        ),
        Ctx.EndPointId(
            nothing,
            Ctx.DeviceId(Ctx.Uuid(ols_device_uuid)),
            Ctx.Uuid(ols_ep_uuid)
        )
    ]
    
    # Create link
    link = Ctx.Link(
        Ctx.LinkId(Ctx.Uuid(link_uuid)),
        link_name,
        Ctx.LinkTypeEnum.LINKTYPE_FIBER,
        endpoint_ids,
        Ctx.LinkAttributes(0.0f0, 0.0f0)
    )
    
    return ensure_post_link(sdn.api_url, link)
end

# Update intra-node connection function to only do Router ↔ TM ↔ OXC
"""
    connect_all_intra_node_devices(sdn::TeraflowSDN) → Int
Create all intra-node connections in the correct order:
1. Router ↔ TM1 (copper)
2. TM1 ↔ OXC (fiber) 
Note: OXC ↔ OLS connections are now handled in inter-node linking with shared OLS
"""
function connect_all_intra_node_devices(sdn::TeraflowSDN)
    links_created = 0
    
    # Find nodes with complete device sets (router, tm, oxc)
    nodes_with_router = Set{Int}()
    nodes_with_tm = Set{Int}()
    nodes_with_oxc = Set{Int}()
    
    for (key, uuid) in sdn.device_map
        if string(key[2]) |> x -> startswith(x, "router_ep_")
            push!(nodes_with_router, key[1])
        elseif key[2] == :tm_1
            push!(nodes_with_tm, key[1])
        elseif key[2] == :oxc
            push!(nodes_with_oxc, key[1])
        end
    end
    
    nodes_for_connection = intersect(nodes_with_router, nodes_with_tm, nodes_with_oxc)
    
    println("🔗 Found $(length(nodes_for_connection)) nodes for complete intra-node connections")
    
    for node_id in sort(collect(nodes_for_connection))
        println("🔧 Creating intra-node connections for node $node_id...")
        
        # Step 1: Router ↔ TM1 (copper)
        if create_router_tm_link(sdn, node_id; link_type=:copper)
            links_created += 2  # Two links created (ep1↔ep1, ep2↔ep2)
        end
        
        # Step 2: TM1 ↔ OXC (fiber)
        if create_tm_oxc_link(sdn, node_id; link_type=:fiber)
            links_created += 2  # Two links created
        end
        
        # Note: OXC ↔ OLS connections are now handled in inter-node linking
    end
    
    println("✅ Created $links_created total intra-node links")
    return links_created
end

"""
    connect_all_inter_node_with_shared_ols(sdn::TeraflowSDN, nodeviews) → Int
Create all inter-node connections with shared OLS devices.
Creates shared OLS for all node pairs, but only creates links for nodes that have OXC devices.
"""
function connect_all_inter_node_with_shared_ols(sdn::TeraflowSDN, nodeviews)
    links_created = 0
    
    # Get all nodes that have OXC devices
    oxc_nodes = Set{Int}()
    for (key, uuid) in sdn.device_map
        if length(key) == 2 && key[2] == :oxc
            push!(oxc_nodes, key[1])
        end
    end
    
    # Get all nodes (including those without OXC)
    all_nodes = Set{Int}()
    for nodeview in nodeviews
        push!(all_nodes, nodeview.nodeproperties.localnode)
    end
    
    println("🌐 Found $(length(oxc_nodes)) nodes with OXC devices out of $(length(all_nodes)) total nodes")
    
    # Track processed node pairs to avoid duplicates
    processed_pairs = Set{Tuple{Int,Int}}()
    
    for nodeview in nodeviews
        node_id = nodeview.nodeproperties.localnode
        
        # Get all neighbors for this node (regardless of whether it has OXC)
        all_neighbors = Set{Int}()
        union!(all_neighbors, nodeview.nodeproperties.inneighbors)
        union!(all_neighbors, nodeview.nodeproperties.outneighbors)
        
        for neighbor_id in all_neighbors
            if neighbor_id in all_nodes  # Make sure neighbor exists in our nodeviews
                # Create ordered pair to avoid duplicates
                link_pair = node_id < neighbor_id ? (node_id, neighbor_id) : (neighbor_id, node_id)
                
                if link_pair ∉ processed_pairs
                    push!(processed_pairs, link_pair)
                    
                    # Check if both nodes have OXC devices
                    node1_has_oxc = link_pair[1] in oxc_nodes
                    node2_has_oxc = link_pair[2] in oxc_nodes
                    
                    if node1_has_oxc || node2_has_oxc
                        # At least one node has OXC, proceed with connection
                        # But modify the existing function to handle missing OXC gracefully
                        if create_inter_node_connection_with_shared_ols(sdn, link_pair[1], link_pair[2]; link_type=:fiber)
                            expected_links = (node1_has_oxc ? 2 : 0) + (node2_has_oxc ? 2 : 0)
                            links_created += expected_links
                        end
                    else
                        # Neither node has OXC, just create the shared OLS device for future use
                        println("🔧 Creating shared OLS for future use: $(link_pair[1]) ↔ $(link_pair[2]) (no OXC devices)")
                        create_shared_ols_device(sdn, link_pair[1], link_pair[2])
                    end
                end
            end
        end
    end
    
    println("✅ Created $links_created inter-node links with shared OLS devices")
    return links_created
end

"""
    create_all_network_links(sdn::TeraFlowSDN, nodeviews) → Tuple{Int, Int}

Complete network linking function that:
1. Creates all intra-node connections: Router ↔ TM1 ↔ OXC
2. Creates all inter-node connections with shared OLS devices between OXC pairs
"""
function create_all_network_links(sdn::TeraflowSDN, nodeviews)
    println("\n🔧 CREATING ALL NETWORK LINKS")
    println("="^50)
    
    # Phase 1: Intra-node links (Router ↔ TM1 ↔ OXC)
    println("\n📍 Phase 1: Intra-Node Links")
    intra_links = connect_all_intra_node_devices(sdn)
    
    # Phase 2: Inter-node links with shared OLS (OXC ↔ SharedOLS ↔ OXC)
    println("\n🌐 Phase 2: Inter-Node Links with Shared OLS")
    inter_links = connect_all_inter_node_with_shared_ols(sdn, nodeviews)
    
    return (intra_links, inter_links)
end