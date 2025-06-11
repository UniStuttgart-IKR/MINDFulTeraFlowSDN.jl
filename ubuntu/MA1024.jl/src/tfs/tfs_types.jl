module TFS

export TFSRouter, TeraflowSDN
using MINDFul
using JSON3
using UUIDs
using JLD2
using ProtoBuf: OneOf 
import ..Ctx
# Add these lines:
include("../api/HTTPClient.jl")


const TFS_UUID_NAMESPACE = UUID("e2f3946f-1d0b-4aee-9e98-7d2b1862c287")

"""
    stable_uuid(node_id::Int, kind::Symbol) → String

Same (node_id, :router | :oxc | :tm) ⇒ same UUID on every run.
"""
function stable_uuid(node_id::Int, kind::Symbol)
    return string(UUIDs.uuid5(TFS_UUID_NAMESPACE, "$(node_id)-$(kind)"))
end

struct TFSRouter
    end
# Define the TeraFlowSDN struct with separate link maps
struct TeraflowSDN <: MINDFul.AbstractSDNController
    api_url::String
    device_map::Dict{Tuple{Int,Symbol},String}   # (node_id, :router/:oxc) → uuid
    intra_link_map::Dict{Tuple{Int,Symbol},String}  # (node_id, :router_oxc_link) → uuid
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

function oxc_endpoints_needed(nodeview)
    neighbors = Set{Int}()
    union!(neighbors, nodeview.nodeproperties.inneighbors)
    union!(neighbors, nodeview.nodeproperties.outneighbors)
    return length(neighbors) * 2 + 1
end


"""
    calculate_oxc_endpoint_needs(nodeviews) → Dict{Int,Int}

Returns a mapping from OXC node_id to total endpoints needed,
which is 2 × number of OXC neighbors (in + out).
"""
function calculate_oxc_endpoint_needs(nodeviews)
    needs = Dict{Int, Int}()
    for nodeview in nodeviews
        node_id = nodeview.nodeproperties.localnode
        if nodeview.oxcview !== nothing
            neighbors = Set{Int}()
            union!(neighbors, nodeview.nodeproperties.inneighbors)
            union!(neighbors, nodeview.nodeproperties.outneighbors)
            num_links = length(neighbors)
            needs[node_id] = num_links * 2 + 1  # 2 per neighbor + 1 for router-OXC
        end
    end
    for (node, n_endpoints) in sort(collect(needs))
        println("  Node $node: endpoints needed = $n_endpoints")
    end
    return needs
end


function create_oxc_endpoints(sdn::TeraflowSDN, node_id::Int, min_endpoints::Int = 2)
    """Create multiple endpoints for an OXC device with proper naming"""
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

function get_available_oxc_endpoint(sdn::TeraflowSDN, node_id::Int)
    # Find existing endpoints for this node
    existing_endpoints = []
    for (key, uuid) in sdn.device_map
        if key[1] == node_id && string(key[2]) |> x -> startswith(x, "oxc_ep_")
            push!(existing_endpoints, (key, uuid))
        end
    end
    
    # Check for available endpoint
    for (key, uuid) in existing_endpoints
        if !get(sdn.endpoint_usage, uuid, false)
            return key, uuid
        end
    end
    
    # NO dynamic creation allowed. Instead:
    error("No available OXC endpoint for node $node_id. Not enough endpoints were pre-created!")
end


function push_node_devices_to_tfs(nodeview, sdn::TeraflowSDN)

    node_id = nodeview.nodeproperties.localnode

    # ───────────────────────── Router ───────────────────────────────────────
    if nodeview.routerview !== nothing
        key  = (node_id, :router)
        uuid = get!(sdn.device_map, key) do
                    stable_uuid(node_id, :router)
                end

        # --- endpoint BEFORE device creation --------------------------------
        ep_uuid = stable_uuid(node_id, :router_ep)
        sdn.device_map[(node_id, :router_ep)] = ep_uuid
        sdn.endpoint_usage[ep_uuid] = false

        ep_rule = _custom_rule("_connect/settings",
                   Dict("endpoints" => [Dict("sample_types"=>Any[],
                                              "type"=>"copper",   # check with openconfig for line card port
                                              "uuid"=>ep_uuid)]) )

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
        # Always create the correct number of endpoints for this OXC node
        n_eps = oxc_endpoints_needed(nodeview)
        create_oxc_endpoints(sdn, node_id, n_eps)
        println("  [OXC $node_id] Created $n_eps OXC endpoints before posting device")

        key  = (node_id, :oxc)
        uuid = get!(sdn.device_map, key) do
            stable_uuid(node_id, :oxc)
        end

        # Use ALL endpoints now present for this node (which will be exactly n_eps)
        endpoint_uuids = [uuid for (k, uuid) in sdn.device_map
            if k[1] == node_id && startswith(string(k[2]), "oxc_ep_")]

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

    # ─────────────────────── Transmission Modules ───────────────────────────
    # if nodeview.transmissionmoduleviewpool !== nothing
    #     for (idx, tmview) in enumerate(nodeview.transmissionmoduleviewpool)
    #         key  = (node_id, (:tm, idx))             # one UUID per card
    #         uuid = get!(sdn.device_map, key) do
    #                    # include pool-index → stable & unique
    #                    stable_uuid(node_id * 10_000 + idx, :tm)
    #                end

    #         # --- endpoint BEFORE device creation --------------------------------
    #         ep_uuid = stable_uuid(node_id*10_000 + idx, :tm_ep)
    #         sdn.device_map[(node_id, (:tm_ep, idx))] = ep_uuid

    #         ep_rule = _custom_rule("_connect/settings",
    #                 Dict("endpoints" => [Dict("sample_types"=>Any[],
    #                                             "type"=>"copper",
    #                                             "uuid"=>ep_uuid)]) )
    #         dev  = Ctx.Device(
    #                   Ctx.DeviceId(Ctx.Uuid(uuid)),
    #                   "TM-Node-$(node_id)-$(idx)",
    #                   "emu-optical-transponder",
    #                   Ctx.DeviceConfig([ep_rule]),
    #                   Ctx.DeviceOperationalStatusEnum.DEVICEOPERATIONALSTATUS_ENABLED,
    #                   [Ctx.DeviceDriverEnum.DEVICEDRIVER_UNDEFINED],
    #                   Ctx.EndPoint[], Ctx.Component[], nothing)

    #         if ensure_post_device(sdn.api_url, dev)
    #             ep_uuid = stable_uuid(node_id*10_000 + idx, :tm_ep)
    #             sdn.device_map[(node_id, (:tm_ep, idx))] = ep_uuid
    #             rules   = build_config_rules(tmview; ep_uuid=ep_uuid)
    #             _push_rules(sdn.api_url, uuid, rules; kind=:TM)
    #         else
    #             @warn "TM device $uuid could not be created/updated"
    #         end
    #     end
    # end

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
function build_config_rules(tm::MINDFul.TransmissionModuleView)
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
Device-agnostic - works with any device types (router, oxc, tm, etc.)
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
    
    # Updated endpoint type mapping to handle numbered OXC endpoints
    device1_type = if ep1_type == :router_ep
        :router
    elseif ep1_type == :oxc_ep || (string(ep1_type) |> x -> startswith(x, "oxc_ep_"))
        :oxc
    elseif ep1_type isa Tuple && ep1_type[1] == :tm_ep
        (:tm, ep1_type[2])
    else
        error("Unknown endpoint type: $ep1_type")
    end
    
    device2_type = if ep2_type == :router_ep
        :router
    elseif ep2_type == :oxc_ep || (string(ep2_type) |> x -> startswith(x, "oxc_ep_"))
        :oxc
    elseif ep2_type isa Tuple && ep2_type[1] == :tm_ep
        (:tm, ep2_type[2])
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
    create_router_oxc_link(sdn::TeraflowSDN, node_id::Int) → Bool
Create intra-node link between router and OXC using specific endpoint management.
"""
function create_router_oxc_link(sdn::TeraflowSDN, node_id::Int; link_type::Symbol = :copper)
    # Get router endpoint
    router_ep_key = (node_id, :router_ep)
    if !haskey(sdn.device_map, router_ep_key)
        @warn "Router endpoint not found for node $node_id"
        return false
    end
    
    # Get first available OXC endpoint
    oxc_ep_key, oxc_ep_uuid = get_available_oxc_endpoint(sdn, node_id)
    router_ep_uuid = sdn.device_map[router_ep_key]
    
    # Mark endpoint as used
    sdn.endpoint_usage[oxc_ep_uuid] = true
    sdn.endpoint_usage[router_ep_uuid] = true
    
    # Generate link details
    link_uuid = stable_uuid(node_id, :router_oxc_link)
    link_name = "IntraLink-Router-$(node_id)-$(oxc_ep_key[2])"
    link_key = (node_id, :router_oxc_link)
    
    # Store in intra-link map
    sdn.intra_link_map[link_key] = link_uuid
    
    # Create the link
    success = create_link_between_devices(sdn, router_ep_key, oxc_ep_key, 
                                        link_name, link_uuid; link_type=link_type)
    
    if success
        println("✓ Created intra-node link: Router-$node_id ↔ $(oxc_ep_key[2])")
    else
        # Revert endpoint usage on failure
        sdn.endpoint_usage[oxc_ep_uuid] = false
        sdn.endpoint_usage[router_ep_uuid] = false
        @warn "✗ Failed to create intra-node link for node $node_id"
    end
    
    return success
end

"""
    create_inter_node_oxc_link(sdn::TeraflowSDN, node1_id::Int, node2_id::Int) → Bool
Create uni-directional inter-node link between two OXCs.
"""
function create_inter_node_oxc_link(sdn::TeraflowSDN, node1_id::Int, node2_id::Int; link_type::Symbol = :fiber)
    # Get available endpoints from both nodes
    node1_ep_key, node1_ep_uuid = get_available_oxc_endpoint(sdn, node1_id)
    node2_ep_key, node2_ep_uuid = get_available_oxc_endpoint(sdn, node2_id)
    
    # Mark endpoints as used
    sdn.endpoint_usage[node1_ep_uuid] = true
    sdn.endpoint_usage[node2_ep_uuid] = true
    
    # Generate stable UUID and naming
    sorted_nodes = sort([node1_id, node2_id])
    link_uuid = stable_uuid(sorted_nodes[1] * 10000 + sorted_nodes[2], Symbol("oxc_inter_link"))
    
    # Extract endpoint IDs from keys for naming
    node1_ep_id = string(node1_ep_key[2])  # e.g., "oxc_ep_1"
    node2_ep_id = string(node2_ep_key[2])  # e.g., "oxc_ep_2"
    
    link_name = "InterLink-$(node1_ep_id)-node-$(node1_id)-$(node2_ep_id)-node-$(node2_id)"
    
    # Create link key for inter-link map: (node1, ep1_id, node2, ep2_id, :link, :unidirectional)
    link_key = (node1_id, node1_ep_id, node2_id, node2_ep_id, :link, :unidirectional)
    
    # Store in inter-link map
    sdn.inter_link_map[link_key] = link_uuid
    
    # Create the actual link
    success = create_link_between_devices(sdn, node1_ep_key, node2_ep_key,
                                        link_name, link_uuid; link_type=link_type)
    
    if success
        println("✓ Created inter-node link: $(node1_ep_id)-node-$(node1_id) ↔ $(node2_ep_id)-node-$(node2_id)")
    else
        # Revert endpoint usage on failure
        sdn.endpoint_usage[node1_ep_uuid] = false
        sdn.endpoint_usage[node2_ep_uuid] = false
        delete!(sdn.inter_link_map, link_key)
        @warn "✗ Failed to create inter-node link: $node1_id ↔ $node2_id"
    end
    
    return success
end

"""
    connect_all_intra_node_devices(sdn::TeraflowSDN) → Int
Create all intra-node router-OXC connections.
"""
function connect_all_intra_node_devices(sdn::TeraflowSDN)
    links_created = 0
    
    # Find nodes with both router and OXC
    nodes_with_router = Set{Int}()
    nodes_with_oxc = Set{Int}()
    
    for (key, uuid) in sdn.device_map
        if key[2] == :router_ep
            push!(nodes_with_router, key[1])
        elseif string(key[2]) |> x -> startswith(x, "oxc_ep_")
            push!(nodes_with_oxc, key[1])
        end
    end
    
    nodes_for_connection = intersect(nodes_with_router, nodes_with_oxc)
    
    println("🔗 Found $(length(nodes_for_connection)) nodes for intra-node connections")
    
    for node_id in sort(collect(nodes_for_connection))
        # Skip if already connected
        if haskey(sdn.intra_link_map, (node_id, :router_oxc_link))
            println("⏭️  Node $node_id already has intra-node connection")
            continue
        end
        
        println("🔧 Creating intra-node connection for node $node_id...")
        if create_router_oxc_link(sdn, node_id; link_type=:copper)
            links_created += 1
        end
    end
    
    println("✅ Created $links_created new intra-node connections")
    return links_created
end

"""
    connect_all_oxcs_inter_node(sdn::TeraflowSDN, nodeviews) → Int
Create all inter-node OXC connections based on topology.
"""
function connect_all_oxcs_inter_node(sdn::TeraflowSDN, nodeviews)
    links_created = 0
    
    # Get all nodes that have OXC devices
    oxc_nodes = Set{Int}()
    for (key, uuid) in sdn.device_map
        if key[2] == :oxc
            push!(oxc_nodes, key[1])
        end
    end
    
    println("🌐 Found $(length(oxc_nodes)) nodes with OXC devices")
    
    # Track processed node pairs to avoid duplicates
    processed_pairs = Set{Tuple{Int,Int}}()
    
    for nodeview in nodeviews
        node_id = nodeview.nodeproperties.localnode
        
        if node_id in oxc_nodes
            # Get all neighbors
            all_neighbors = Set{Int}()
            union!(all_neighbors, nodeview.nodeproperties.inneighbors)
            union!(all_neighbors, nodeview.nodeproperties.outneighbors)
            
            for neighbor_id in all_neighbors
                if neighbor_id in oxc_nodes
                    # Create ordered pair to avoid duplicates
                    link_pair = node_id < neighbor_id ? (node_id, neighbor_id) : (neighbor_id, node_id)
                    
                    if link_pair ∉ processed_pairs
                        push!(processed_pairs, link_pair)
                        
                        # Check if link already exists
                        existing_links = [k for k in keys(sdn.inter_link_map) 
                                        if (k[1] == link_pair[1] && k[3] == link_pair[2]) ||
                                           (k[1] == link_pair[2] && k[3] == link_pair[1])]
                        
                        if isempty(existing_links)
                            println("🌉 Creating inter-node connection: $(link_pair[1]) ↔ $(link_pair[2])...")
                            if create_inter_node_oxc_link(sdn, link_pair[1], link_pair[2]; link_type=:fiber)
                                links_created += 1
                            end
                        else
                            println("⏭️  Inter-node connection already exists: $(link_pair[1]) ↔ $(link_pair[2])")
                        end
                    end
                end
            end
        end
    end
    
    println("✅ Created $links_created new inter-node connections")
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
        println("  Node $node_id: Router ↔ OXC ($uuid)")
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
    
    # Show used endpoints by node
    for node_id in sort(unique([k[1] for k in keys(sdn.device_map) if string(k[2]) |> x -> startswith(x, "oxc_ep_")]))
        node_eps = [(k, v) for (k, v) in sdn.device_map if k[1] == node_id && string(k[2]) |> x -> startswith(x, "oxc_ep_")]
        used_eps = [k[2] for (k, uuid) in node_eps if get(sdn.endpoint_usage, uuid, false)]
        total_eps = length(node_eps)
        println("    Node $node_id: $(length(used_eps))/$total_eps used $(used_eps)")
    end
    
    println("="^80)
end

"""
    create_all_network_links(sdn::TeraflowSDN, nodeviews) → Tuple{Int, Int}

Complete network linking function that:
1. Creates all intra-node Router-OXC links
2. Creates all inter-node OXC-OXC links based on network topology
Takes nodeviews directly to avoid MINDFul dependency in TFS module.
Returns (intra_links_processed, inter_links_processed)
"""
function create_all_network_links(sdn::TeraflowSDN, nodeviews)
    println("\n CREATING ALL NETWORK LINKS")
    println("="^50)
    
    # Phase 1: Intra-node links
    println("\n Phase 1: Intra-Node Links")
    intra_links = connect_all_intra_node_devices(sdn)
    
    # Phase 2: Inter-node links  
    println("\n Phase 2: Inter-Node Links")
    inter_links = connect_all_oxcs_inter_node(sdn, nodeviews)
    
    # Show final status
    print_link_status(sdn)
    
    return (intra_links, inter_links)
end

export create_all_network_links, calculate_oxc_endpoint_needs, create_oxc_endpoints, 
    print_link_status, push_node_devices_to_tfs, save_device_map, load_device_map!,
    create_router_oxc_link, create_inter_node_oxc_link
end