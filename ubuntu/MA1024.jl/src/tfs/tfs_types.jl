"""
    stable_uuid(node_id::Int, kind::Symbol) → String

Same (node_id, :router | :oxc | :tm | :ols) ⇒ same UUID on every run.
"""
function stable_uuid(node_id::Int, kind::Symbol)
    return string(UUIDs.uuid5(TFS_UUID_NAMESPACE, "$(node_id)-$(kind)"))
end

struct TeraflowSDN <: MINDFul.AbstractSDNController
    api_url::String
    device_map::Dict{Tuple{Int,Symbol},String}   # (node_id, :router/:oxc/:ols/:tm_N) → uuid
    intra_link_map::Dict{Tuple{Int,Symbol},String}  # (node_id, :link_type) → uuid
    inter_link_map::Dict{NTuple{6,Any},String}    # (node1, ep1_id, node2, ep2_id, :link, direction) → uuid
    endpoint_usage::Dict{String,Bool}             # endpoint_uuid → is_used
end

TeraflowSDN() = TeraflowSDN(
    "http://127.0.0.1:80/tfs-api", 
    Dict{Tuple{Int,Symbol},String}(),
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

function ols_endpoints_needed(nodeview)
    neighbors = Set{Int}()
    union!(neighbors, nodeview.nodeproperties.inneighbors)
    union!(neighbors, nodeview.nodeproperties.outneighbors)
    # OLS needs: 2 endpoints to connect to OXC + 2 endpoints per neighbor for inter-node links
    return 2 + length(neighbors) * 2
end

"""
    calculate_ols_endpoint_needs(nodeviews) → Dict{Int,Int}

Returns a mapping from OLS node_id to total endpoints needed,
which is 2 for OXC connection + 2 × number of neighbors (in + out).
"""
function calculate_ols_endpoint_needs(nodeviews)
    needs = Dict{Int, Int}()
    for nodeview in nodeviews
        node_id = nodeview.nodeproperties.localnode
        # OLS is created for every node that has an OXC
        if nodeview.oxcview !== nothing
            neighbors = Set{Int}()
            union!(neighbors, nodeview.nodeproperties.inneighbors)
            union!(neighbors, nodeview.nodeproperties.outneighbors)
            num_links = length(neighbors)
            needs[node_id] = 2 + num_links * 2  # 2 for OXC + 2 per neighbor
        end
    end
    for (node, n_endpoints) in sort(collect(needs))
        println("  Node $node: OLS endpoints needed = $n_endpoints")
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

function create_ols_endpoints(sdn::TeraflowSDN, node_id::Int, min_endpoints::Int)
    """Create variable number of fiber endpoints for an OLS device"""
    endpoints = String[]
    
    for ep_id in 1:min_endpoints
        ep_uuid = stable_uuid(node_id * 1000 + ep_id + 100, Symbol("ols_ep_$(ep_id)"))
        ep_key = (node_id, Symbol("ols_ep_$(ep_id)"))
        
        sdn.device_map[ep_key] = ep_uuid
        sdn.endpoint_usage[ep_uuid] = false  # Initially unused
        push!(endpoints, ep_uuid)
    end
    
    return endpoints
end

function get_available_endpoint(sdn::TeraflowSDN, node_id::Int, prefix::String)
    """Generic function to get available endpoint with given prefix"""
    # Find existing endpoints for this node with the given prefix
    existing_endpoints = []
    for (key, uuid) in sdn.device_map
        if key[1] == node_id && string(key[2]) |> x -> startswith(x, prefix)
            push!(existing_endpoints, (key, uuid))
        end
    end
    
    # Check for available endpoint
    for (key, uuid) in existing_endpoints
        if !get(sdn.endpoint_usage, uuid, false)
            return key, uuid
        end
    end
    
    error("No available $prefix endpoint for node $node_id. Not enough endpoints were pre-created!")
end

function get_available_oxc_endpoint(sdn::TeraflowSDN, node_id::Int)
    return get_available_endpoint(sdn, node_id, "oxc_ep_")
end

function get_available_ols_endpoint(sdn::TeraflowSDN, node_id::Int)
    return get_available_endpoint(sdn, node_id, "ols_ep_")
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
        # Create fixed number of fiber endpoints for OXC (4 endpoints)
        endpoint_uuids = create_oxc_endpoints(sdn, node_id, 4)
        println("  [OXC $node_id] Created 4 fiber endpoints before posting device")

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
                    device_drivers,  # Use the properly constructed array
                    Ctx.EndPoint[], Ctx.Component[], nothing)

        if ensure_post_device(sdn.api_url, dev)
            rules = build_config_rules(nodeview.oxcview)
            _push_rules(sdn.api_url, uuid, rules; kind=:OXC)
        else
            @warn "OXC device $uuid could not be created/updated"
        end
    end

    # ───────────────────────── OLS (New Device) ──────────────────────────────
    # Calculate and create variable number of fiber endpoints for OLS
    n_eps = ols_endpoints_needed(nodeview)
    endpoint_uuids = create_ols_endpoints(sdn, node_id, n_eps)
    println("  [OLS $node_id] Created $n_eps fiber endpoints before posting device")

    key  = (node_id, :ols)
    uuid = get!(sdn.device_map, key) do
        stable_uuid(node_id, :ols)
    end

    endpoints_config = []
    for (i, ep_uuid) in enumerate(endpoint_uuids)
        push!(endpoints_config, Dict("sample_types"=>Any[],
                                    "type"=>"fiber",
                                    "uuid"=>ep_uuid,
                                    "name"=>"ols_ep_$(i)_node_$(node_id)"))
    end

    ep_rule = _custom_rule("_connect/settings", Dict("endpoints" => endpoints_config))

    device_drivers = Vector{Ctx.DeviceDriverEnum.T}()
    push!(device_drivers, Ctx.DeviceDriverEnum.DEVICEDRIVER_UNDEFINED)

    dev  = Ctx.Device(
                Ctx.DeviceId(Ctx.Uuid(uuid)),
                "OLS-Node-$(node_id)",
                "emu-open-line-system",  # New device type
                Ctx.DeviceConfig([ep_rule]),
                Ctx.DeviceOperationalStatusEnum.DEVICEOPERATIONALSTATUS_ENABLED,
                device_drivers,
                Ctx.EndPoint[], Ctx.Component[], nothing)

    if ensure_post_device(sdn.api_url, dev)
        # OLS doesn't have specific config rules for now, but we can add them later
        println("✓ OLS device $uuid created successfully")
    else
        @warn "OLS device $uuid could not be created/updated"
    end

    # ─────────────────────── Transmission Modules ───────────────────────────
    if nodeview.transmissionmoduleviewpool !== nothing
        for (idx, tmview) in enumerate(nodeview.transmissionmoduleviewpool)
            key  = (node_id, Symbol("tm_$idx"))             # Fixed: use Symbol instead of tuple
            uuid = get!(sdn.device_map, key) do
                    # include pool-index → stable & unique
                    stable_uuid(node_id * 10_000 + idx, :tm)
                end

            # Create 4 endpoints for TM (2 copper + 2 fiber)
            endpoint_uuids = create_tm_endpoints(sdn, node_id, idx)

            # Build endpoints config with mixed types
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
    
    return success_count == 2  # Both links should succeed
end

"""
    create_oxc_ols_link(sdn::TeraFlowSDN, node_id::Int) → Bool
Create intra-node link between OXC and OLS using fiber endpoints.
OXC ep3 ↔ OLS ep1, OXC ep4 ↔ OLS ep2
"""
function create_oxc_ols_link(sdn::TeraflowSDN, node_id::Int; link_type::Symbol = :fiber)
    success_count = 0
    
    # Create two links: OXC ep3 ↔ OLS ep1, OXC ep4 ↔ OLS ep2
    for ep_pair in [(3, 1), (4, 2)]
        oxc_ep_idx, ols_ep_idx = ep_pair
        
        oxc_ep_key = (node_id, Symbol("oxc_ep_$(oxc_ep_idx)"))
        ols_ep_key = (node_id, Symbol("ols_ep_$(ols_ep_idx)"))
        
        if !haskey(sdn.device_map, oxc_ep_key)
            @warn "OXC endpoint not found: $oxc_ep_key"
            continue
        end
        
        if !haskey(sdn.device_map, ols_ep_key)
            @warn "OLS endpoint not found: $ols_ep_key"
            continue
        end
        
        oxc_ep_uuid = sdn.device_map[oxc_ep_key]
        ols_ep_uuid = sdn.device_map[ols_ep_key]
        
        # Check if already used
        if get(sdn.endpoint_usage, oxc_ep_uuid, false) || get(sdn.endpoint_usage, ols_ep_uuid, false)
            @warn "Endpoints already in use for oxc-ols link: $oxc_ep_key ↔ $ols_ep_key"
            continue
        end
        
        # Generate link details
        link_uuid = stable_uuid(node_id * 300 + ep_pair[1], Symbol("oxc_ols_link_$(ep_pair[1])"))
        link_name = "IntraLink-OXC-ep$(oxc_ep_idx)-OLS-ep$(ols_ep_idx)-node-$(node_id)"
        link_key = (node_id, Symbol("oxc_ols_link_$(ep_pair[1])"))
        
        # Store in intra-link map
        sdn.intra_link_map[link_key] = link_uuid
        
        # Create the link
        success = create_link_between_devices(sdn, oxc_ep_key, ols_ep_key,
                                            link_name, link_uuid; link_type=link_type)
        
        if success
            # Mark endpoints as used
            sdn.endpoint_usage[oxc_ep_uuid] = true
            sdn.endpoint_usage[ols_ep_uuid] = true
            success_count += 1
            println("✓ Created OXC-OLS link: OXC-ep$(oxc_ep_idx) ↔ OLS-ep$(ols_ep_idx) (node $node_id)")
        else
            @warn "✗ Failed to create OXC-OLS link for endpoints $(ep_pair) (node $node_id)"
        end
    end
    
    return success_count == 2  # Both links should succeed
end

"""
    create_inter_node_ols_link(sdn::TeraFlowSDN, node1_id::Int, node2_id::Int) → Bool
Create bi-directional inter-node links between two OLS devices.
Creates 2 links: node1→node2 (outgoing) and node2→node1 (incoming)
"""
function create_inter_node_ols_link(sdn::TeraflowSDN, node1_id::Int, node2_id::Int; link_type::Symbol = :fiber)
    success_count = 0
    
    # Create 2 unidirectional links: node1→node2 and node2→node1
    for direction in [:outgoing, :incoming]
        # Determine source and destination based on direction
        if direction == :outgoing
            src_node, dst_node = node1_id, node2_id
            direction_label = "$(node1_id)→$(node2_id)"
        else
            src_node, dst_node = node2_id, node1_id
            direction_label = "$(node2_id)→$(node1_id)"
        end
        
        # Get available endpoints from both nodes
        try
            src_ep_key, src_ep_uuid = get_available_ols_endpoint(sdn, src_node)
            dst_ep_key, dst_ep_uuid = get_available_ols_endpoint(sdn, dst_node)
            
            # Generate stable UUID and naming
            # Use different multipliers for each direction to ensure unique UUIDs
            direction_multiplier = direction == :outgoing ? 1 : 2
            sorted_nodes = sort([src_node, dst_node])
            link_uuid = stable_uuid(sorted_nodes[1] * 10000 + sorted_nodes[2] * 10 + direction_multiplier, 
                                  Symbol("ols_inter_link_$(direction)"))
            
            # Extract endpoint IDs from keys for naming
            src_ep_id = string(src_ep_key[2])  # e.g., "ols_ep_3"
            dst_ep_id = string(dst_ep_key[2])  # e.g., "ols_ep_4"
            
            link_name = "InterLink-$(direction_label)-$(src_ep_id)-node-$(src_node)-$(dst_ep_id)-node-$(dst_node)"
            
            # Create link key for inter-link map: (src_node, src_ep_id, dst_node, dst_ep_id, :link, direction)
            link_key = (src_node, src_ep_id, dst_node, dst_ep_id, :link, direction)
            
            # Check if this specific link already exists
            if haskey(sdn.inter_link_map, link_key)
                println("⏭️  Link already exists: $direction_label")
                success_count += 1
                continue
            end
            
            # Store in inter-link map
            sdn.inter_link_map[link_key] = link_uuid
            
            # Create the actual link
            success = create_link_between_devices(sdn, src_ep_key, dst_ep_key,
                                                link_name, link_uuid; link_type=link_type)
            
            if success
                # Mark endpoints as used
                sdn.endpoint_usage[src_ep_uuid] = true
                sdn.endpoint_usage[dst_ep_uuid] = true
                success_count += 1
                println("✓ Created inter-node link ($direction): $(src_ep_id)-node-$(src_node) → $(dst_ep_id)-node-$(dst_node)")
            else
                # Revert on failure
                delete!(sdn.inter_link_map, link_key)
                @warn "✗ Failed to create inter-node link ($direction): $src_node → $dst_node"
            end
            
        catch e
            @warn "✗ Failed to get available endpoints for $direction_label: $e"
        end
    end
    
    return success_count == 2  # Both directions should succeed
end

"""
    connect_all_intra_node_devices(sdn::TeraflowSDN) → Int
Create all intra-node connections in the correct order:
1. Router ↔ TM1 (copper)
2. TM1 ↔ OXC (fiber) 
3. OXC ↔ OLS (fiber)
"""
function connect_all_intra_node_devices(sdn::TeraflowSDN)
    links_created = 0
    
    # Find nodes with complete device sets (router, tm, oxc, ols)
    nodes_with_router = Set{Int}()
    nodes_with_tm = Set{Int}()
    nodes_with_oxc = Set{Int}()
    nodes_with_ols = Set{Int}()
    
    for (key, uuid) in sdn.device_map
        if string(key[2]) |> x -> startswith(x, "router_ep_")
            push!(nodes_with_router, key[1])
        elseif key[2] == :tm_1
            push!(nodes_with_tm, key[1])
        elseif key[2] == :oxc
            push!(nodes_with_oxc, key[1])
        elseif key[2] == :ols
            push!(nodes_with_ols, key[1])
        end
    end
    
    nodes_for_connection = intersect(nodes_with_router, nodes_with_tm, nodes_with_oxc, nodes_with_ols)
    
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
        
        # Step 3: OXC ↔ OLS (fiber)
        if create_oxc_ols_link(sdn, node_id; link_type=:fiber)
            links_created += 2  # Two links created
        end
    end
    
    println("✅ Created $links_created total intra-node links")
    return links_created
end

"""
    connect_all_ols_inter_node(sdn::TeraFlowSDN, nodeviews) → Int
Create all inter-node OLS connections based on topology.
Each connection creates 2 unidirectional links (incoming + outgoing).
"""
function connect_all_ols_inter_node(sdn::TeraflowSDN, nodeviews)
    links_created = 0
    
    # Get all nodes that have OLS devices
    ols_nodes = Set{Int}()
    for (key, uuid) in sdn.device_map
        if key[2] == :ols
            push!(ols_nodes, key[1])
        end
    end
    
    println("🌐 Found $(length(ols_nodes)) nodes with OLS devices")
    
    # Track processed node pairs to avoid duplicates
    processed_pairs = Set{Tuple{Int,Int}}()
    
    for nodeview in nodeviews
        node_id = nodeview.nodeproperties.localnode
        
        if node_id in ols_nodes
            # Get all neighbors
            all_neighbors = Set{Int}()
            union!(all_neighbors, nodeview.nodeproperties.inneighbors)
            union!(all_neighbors, nodeview.nodeproperties.outneighbors)
            
            for neighbor_id in all_neighbors
                if neighbor_id in ols_nodes
                    # Create ordered pair to avoid duplicates
                    link_pair = node_id < neighbor_id ? (node_id, neighbor_id) : (neighbor_id, node_id)
                    
                    if link_pair ∉ processed_pairs
                        push!(processed_pairs, link_pair)
                        
                        # Check if links already exist in device map
                        existing_outgoing_key = nothing
                        existing_incoming_key = nothing
                        
                        for key in keys(sdn.inter_link_map)
                            if length(key) >= 6
                                if key[1] == link_pair[1] && key[3] == link_pair[2] && key[6] == :outgoing
                                    existing_outgoing_key = key
                                elseif key[1] == link_pair[2] && key[3] == link_pair[1] && key[6] == :incoming
                                    existing_incoming_key = key
                                end
                            end
                        end
                        
                        if existing_outgoing_key !== nothing && existing_incoming_key !== nothing
                            # Links exist in map - reuse existing info to post to TFS
                            println("📋 Reposting existing links: $(link_pair[1]) ↔ $(link_pair[2])...")
                            
                            # Post outgoing link using existing data
                            outgoing_uuid = sdn.inter_link_map[existing_outgoing_key]
                            src_node, src_ep_id, dst_node, dst_ep_id = existing_outgoing_key[1], existing_outgoing_key[2], existing_outgoing_key[3], existing_outgoing_key[4]
                            src_ep_key = (src_node, Symbol(src_ep_id))
                            dst_ep_key = (dst_node, Symbol(dst_ep_id))
                            link_name = "InterLink-$(src_node)→$(dst_node)-$(src_ep_id)-node-$(src_node)-$(dst_ep_id)-node-$(dst_node)"
                            
                            if create_link_between_devices(sdn, src_ep_key, dst_ep_key, link_name, outgoing_uuid; link_type=:fiber)
                                links_created += 1
                            end
                            
                            # Post incoming link using existing data
                            incoming_uuid = sdn.inter_link_map[existing_incoming_key]
                            src_node, src_ep_id, dst_node, dst_ep_id = existing_incoming_key[1], existing_incoming_key[2], existing_incoming_key[3], existing_incoming_key[4]
                            src_ep_key = (src_node, Symbol(src_ep_id))
                            dst_ep_key = (dst_node, Symbol(dst_ep_id))
                            link_name = "InterLink-$(src_node)→$(dst_node)-$(src_ep_id)-node-$(src_node)-$(dst_ep_id)-node-$(dst_node)"
                            
                            if create_link_between_devices(sdn, src_ep_key, dst_ep_key, link_name, incoming_uuid; link_type=:fiber)
                                links_created += 1
                            end
                        else
                            # Links don't exist in map - create new ones
                            println("🌉 Creating new inter-node connection: $(link_pair[1]) ↔ $(link_pair[2])...")
                            if create_inter_node_ols_link(sdn, link_pair[1], link_pair[2]; link_type=:fiber)
                                links_created += 2  # 2 unidirectional links created
                            end
                        end
                    end
                end
            end
        end
    end
    
    println("✅ Created/reposted $links_created inter-node links")
    return links_created
end

function print_link_status(sdn::TeraflowSDN)
    println("\n" * "="^80)
    println("🔗 NETWORK LINK STATUS")
    println("="^80)
    
    # Intra-node links
    println("\n📍 INTRA-NODE LINKS ($(length(sdn.intra_link_map)))")
    println("-"^50)
    for (key, uuid) in sort(collect(sdn.intra_link_map))
        node_id, link_type = key
        if string(link_type) |> x -> startswith(x, "router_tm_link")
            println("  Node $node_id: Router ↔ TM1 ($link_type)")
        elseif string(link_type) |> x -> startswith(x, "tm_oxc_link")
            println("  Node $node_id: TM1 ↔ OXC ($link_type)")
        elseif string(link_type) |> x -> startswith(x, "oxc_ols_link")
            println("  Node $node_id: OXC ↔ OLS ($link_type)")
        else
            println("  Node $node_id: $link_type ($uuid)")
        end
    end
    
    # Inter-node links  
    println("\n🌐 INTER-NODE LINKS ($(length(sdn.inter_link_map)))")
    println("-"^70)
    for (key, uuid) in sort(collect(sdn.inter_link_map))
        node1, ep1, node2, ep2, _, direction = key
        println("  $ep1-node-$node1 ↔ $ep2-node-$node2 [$direction] ($uuid)")
    end
    
    # Endpoint usage
    println("\n📡 ENDPOINT USAGE")
    println("-"^40)
    used_count = count(values(sdn.endpoint_usage))
    total_count = length(sdn.endpoint_usage)
    println("  Used: $used_count / $total_count endpoints")
    
    # Show used endpoints by node and device type
    for node_id in sort(unique([k[1] for k in keys(sdn.device_map)]))
        # Router endpoints
        router_eps = [(k, v) for (k, v) in sdn.device_map if k[1] == node_id && string(k[2]) |> x -> startswith(x, "router_ep_")]
        if !isempty(router_eps)
            used_router_eps = [k[2] for (k, uuid) in router_eps if get(sdn.endpoint_usage, uuid, false)]
            total_router_eps = length(router_eps)
            println("    Node $node_id Router: $(length(used_router_eps))/$total_router_eps used $(used_router_eps)")
        end
        
        # TM endpoints
        tm_eps = [(k, v) for (k, v) in sdn.device_map if k[1] == node_id && string(k[2]) |> x -> startswith(x, "tm_1_")]
        if !isempty(tm_eps)
            used_tm_eps = [k[2] for (k, uuid) in tm_eps if get(sdn.endpoint_usage, uuid, false)]
            total_tm_eps = length(tm_eps)
            println("    Node $node_id TM1: $(length(used_tm_eps))/$total_tm_eps used $(used_tm_eps)")
        end
        
        # OXC endpoints
        oxc_eps = [(k, v) for (k, v) in sdn.device_map if k[1] == node_id && string(k[2]) |> x -> startswith(x, "oxc_ep_")]
        if !isempty(oxc_eps)
            used_oxc_eps = [k[2] for (k, uuid) in oxc_eps if get(sdn.endpoint_usage, uuid, false)]
            total_oxc_eps = length(oxc_eps)
            println("    Node $node_id OXC: $(length(used_oxc_eps))/$total_oxc_eps used $(used_oxc_eps)")
        end
        
        # OLS endpoints
        ols_eps = [(k, v) for (k, v) in sdn.device_map if k[1] == node_id && string(k[2]) |> x -> startswith(x, "ols_ep_")]
        if !isempty(ols_eps)
            used_ols_eps = [k[2] for (k, uuid) in ols_eps if get(sdn.endpoint_usage, uuid, false)]
            total_ols_eps = length(ols_eps)
            println("    Node $node_id OLS: $(length(used_ols_eps))/$total_ols_eps used $(used_ols_eps)")
        end
    end
    
    println("="^80)
end

"""
    create_all_network_links(sdn::TeraFlowSDN, nodeviews) → Tuple{Int, Int}

Complete network linking function that:
1. Creates all intra-node connections: Router ↔ TM1 ↔ OXC ↔ OLS
2. Creates all inter-node OLS-OLS links based on network topology
Takes nodeviews directly to avoid MINDFul dependency in TFS module.
Returns (intra_links_processed, inter_links_processed)
"""
function create_all_network_links(sdn::TeraflowSDN, nodeviews)
    println("\n🔧 CREATING ALL NETWORK LINKS")
    println("="^50)
    
    # Phase 1: Intra-node links (Router ↔ TM1 ↔ OXC ↔ OLS)
    println("\n📍 Phase 1: Intra-Node Links")
    intra_links = connect_all_intra_node_devices(sdn)
    
    # Phase 2: Inter-node links (OLS ↔ OLS)
    println("\n🌐 Phase 2: Inter-Node Links")
    inter_links = connect_all_ols_inter_node(sdn, nodeviews)
    
    # Show final status
    print_link_status(sdn)
    
    return (intra_links, inter_links)
end