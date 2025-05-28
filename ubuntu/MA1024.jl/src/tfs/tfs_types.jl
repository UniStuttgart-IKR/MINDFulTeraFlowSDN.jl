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
# Define the TeraFlowSDN struct
struct TeraflowSDN <: MINDFul.AbstractSDNController
    api_url::String
    device_map::Dict{Tuple{Int,Symbol},String}   # (node_id, :router/:oxc/:tm) → uuid
    link_map::Dict{Any,String}                   # Separate storage for links
end

TeraflowSDN() = TeraflowSDN("http://127.0.0.1:80/tfs-api", Dict{Tuple{Int,Symbol},String}(), Dict{Any,String}())

function save_device_map(path::AbstractString, sdn::TeraflowSDN)
    @save path device_map = sdn.device_map link_map = sdn.link_map
end

function load_device_map!(path::AbstractString, sdn::TeraflowSDN)
    isfile(path) || return
    
    try
        # Try to load both device_map and link_map
        @load path device_map link_map
        
        # Both exist, load them
        empty!(sdn.device_map)
        merge!(sdn.device_map, device_map)
        
        empty!(sdn.link_map)
        merge!(sdn.link_map, link_map)
        
        println("✓ Loaded device_map with $(length(device_map)) entries and link_map with $(length(link_map)) entries")
        
    catch e
        if isa(e, KeyError) && e.key == "link_map"
            # File exists but doesn't have link_map (legacy format)
            @load path device_map
            
            empty!(sdn.device_map)
            merge!(sdn.device_map, device_map)
            
            # Initialize empty link_map
            empty!(sdn.link_map)
            
            println("✓ Loaded legacy device_map with $(length(device_map)) entries, initialized empty link_map")
        else
            # Re-throw if it's a different error
            rethrow(e)
        end
    end
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

        ep_rule = _custom_rule("_connect/settings",
                   Dict("endpoints" => [Dict("sample_types"=>Any[],
                                              "type"=>"copper",
                                              "uuid"=>ep_uuid)]) )

        dev  = Ctx.Device(
                    Ctx.DeviceId(Ctx.Uuid(uuid)),
                    "Router-Node-$(node_id)",                     # name
                    "emu-packet-router",                # device_type
                    Ctx.DeviceConfig([ep_rule]),               # empty config – rules follow
                    Ctx.DeviceOperationalStatusEnum.DEVICEOPERATIONALSTATUS_ENABLED,
                    [Ctx.DeviceDriverEnum.DEVICEDRIVER_UNDEFINED],
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
        key  = (node_id, :oxc)
        uuid = get!(sdn.device_map, key) do
                    stable_uuid(node_id, :oxc)
                end
        
        # --- endpoint BEFORE device creation --------------------------------
        ep_uuid = stable_uuid(node_id, :oxc_ep)
        sdn.device_map[(node_id, :oxc_ep)] = ep_uuid

        ep_rule = _custom_rule("_connect/settings",
                   Dict("endpoints" => [Dict("sample_types"=>Any[],
                                              "type"=>"copper",
                                              "uuid"=>ep_uuid)]) )

        dev  = Ctx.Device(
                    Ctx.DeviceId(Ctx.Uuid(uuid)),
                    "OXC-Node-$(node_id)",
                    "emu-optical-roadm",
                    Ctx.DeviceConfig([ep_rule]),
                    Ctx.DeviceOperationalStatusEnum.DEVICEOPERATIONALSTATUS_ENABLED,
                    [Ctx.DeviceDriverEnum.DEVICEDRIVER_UNDEFINED],
                    Ctx.EndPoint[], Ctx.Component[], nothing)

        if ensure_post_device(sdn.api_url, dev)
            rules   = build_config_rules(nodeview.oxcview)
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
    
    # Map endpoint types to device types
    device1_type = ep1_type == :router_ep ? :router : 
                   ep1_type == :oxc_ep ? :oxc : 
                   ep1_type isa Tuple && ep1_type[1] == :tm_ep ? (:tm, ep1_type[2]) : 
                   error("Unknown endpoint type: $ep1_type")
    
    device2_type = ep2_type == :router_ep ? :router : 
                   ep2_type == :oxc_ep ? :oxc : 
                   ep2_type isa Tuple && ep2_type[1] == :tm_ep ? (:tm, ep2_type[2]) : 
                   error("Unknown endpoint type: $ep2_type")
    
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
    
    # Determine link type enum
    tfs_link_type = if link_type == :copper
        Ctx.LinkTypeEnum.LINKTYPE_COPPER
    elseif link_type == :optical
        Ctx.LinkTypeEnum.LINKTYPE_OPTICAL
    elseif link_type == :virtual_copper
        Ctx.LinkTypeEnum.LINKTYPE_VIRTUAL_COPPER
    elseif link_type == :virtual_optical
        Ctx.LinkTypeEnum.LINKTYPE_VIRTUAL_OPTICAL
    else
        Ctx.LinkTypeEnum.LINKTYPE_COPPER
    end
    
    # Create link with empty attributes (as requested)
    link = Ctx.Link(
        Ctx.LinkId(Ctx.Uuid(link_uuid)),
        link_name,
        endpoint_ids,
        Ctx.LinkAttributes(0.0f0, 0.0f0),  # empty attributes: total_capacity=0, used_capacity=0
        tfs_link_type
    )
    
    # Use ensure_post_link for robust creation with verification
    return ensure_post_link(sdn.api_url, link)
end

"""
    create_router_oxc_link(sdn::TeraflowSDN, node_id::Int; link_type=:copper) → Bool

Create a link between the router and OXC on the same node.
Uses the general create_link_between_devices function.
"""
function create_router_oxc_link(sdn::TeraflowSDN, node_id::Int; 
                               link_type::Symbol = :copper)
    
    # Define endpoint keys
    router_ep_key = (node_id, :router_ep)
    oxc_ep_key = (node_id, :oxc_ep)
    
    # Generate stable UUID and name for the link
    link_uuid = stable_uuid(node_id, :router_oxc_link)
    link_name = "RouterOXC-Link-$(node_id)"
    link_key = (node_id, :router_oxc_link)
    
    # Store link UUID in link map
    sdn.link_map[link_key] = link_uuid
    
    # Use the general link creation function
    success = create_link_between_devices(sdn, router_ep_key, oxc_ep_key, 
                                        link_name, link_uuid; link_type=link_type)
    
    if success
        println("✓ Created/Updated link between Router-$(node_id) and OXC-$(node_id)")
    else
        @warn "✗ Failed to create link between Router-$(node_id) and OXC-$(node_id)"
    end
    
    return success
end

"""
    create_inter_node_link(sdn::TeraflowSDN, node1_id::Int, node2_id::Int, 
                          device1_type::Symbol, device2_type::Symbol; 
                          link_type::Symbol = :copper) → Bool

Create a link between devices on different nodes.
device_type can be :router_ep, :oxc_ep, or (:tm_ep, idx)
"""
function create_inter_node_link(sdn::TeraflowSDN, node1_id::Int, node2_id::Int,
                               device1_type::Symbol, device2_type::Symbol;
                               link_type::Symbol = :copper)
    
    # Build endpoint keys
    device1_key = (node1_id, device1_type)
    device2_key = (node2_id, device2_type)
    
    # Generate stable UUID and name for the inter-node link
    # Sort node IDs to ensure consistent naming regardless of order
    sorted_nodes = sort([node1_id, node2_id])
    link_uuid = stable_uuid(sorted_nodes[1] * 10000 + sorted_nodes[2], Symbol("$(device1_type)_$(device2_type)_link"))
    link_name = "InterNode-$(device1_type)-$(node1_id)-$(device2_type)-$(node2_id)"
    link_key = (:link, sorted_nodes[1], sorted_nodes[2], device1_type, device2_type)
    
    # Store link UUID in link map
    sdn.link_map[link_key] = link_uuid
    
    # Use the general link creation function
    success = create_link_between_devices(sdn, device1_key, device2_key,
                                        link_name, link_uuid; link_type=link_type)
    
    if success
        println("✓ Created/Updated inter-node link: $(device1_type)-$(node1_id) ↔ $(device2_type)-$(node2_id)")
    else
        @warn "✗ Failed to create inter-node link: $(device1_type)-$(node1_id) ↔ $(device2_type)-$(node2_id)"
    end
    
    return success
end

"""
    connect_all_intra_node_devices(sdn::TeraflowSDN) → Int

Connect all router-OXC pairs within each node using router-OXC links.
Returns the number of links processed.
"""
function connect_all_intra_node_devices(sdn::TeraflowSDN)
    links_created = 0
    
    # Find all nodes that have both router and OXC endpoints
    nodes_with_router_ep = Set{Int}()
    nodes_with_oxc_ep = Set{Int}()
    
    for (key, uuid) in sdn.device_map
        if length(key) >= 2 && key[2] == :router_ep
            push!(nodes_with_router_ep, key[1])
        elseif length(key) >= 2 && key[2] == :oxc_ep
            push!(nodes_with_oxc_ep, key[1])
        end
    end
    
    # Find nodes that have both router and OXC endpoints
    nodes_for_connection = intersect(nodes_with_router_ep, nodes_with_oxc_ep)
    
    println("Found $(length(nodes_for_connection)) nodes with both Router and OXC endpoints")
    
    for node_id in sort(collect(nodes_for_connection))
        println("\nCreating/Updating intra-node link for node $node_id...")
        if create_router_oxc_link(sdn, node_id; link_type=:copper)
            links_created += 1
        end
    end
    
    println("✓ Processed $links_created intra-node Router-OXC links")
    return links_created
end

"""
    connect_all_oxcs_inter_node(sdn::TeraflowSDN, nodeviews) → Int

Connect all OXCs with each other using inter-node links based on the network topology.
Takes nodeviews directly to avoid MINDFul dependency in TFS module.
Returns the number of links processed.
"""
function connect_all_oxcs_inter_node(sdn::TeraflowSDN, nodeviews)
    links_created = 0
    
    # Get all nodes that have OXC endpoints
    oxc_nodes = Set{Int}()
    for (key, uuid) in sdn.device_map
        if length(key) >= 2 && key[2] == :oxc_ep
            push!(oxc_nodes, key[1])
        end
    end
    
    println("Found $(length(oxc_nodes)) nodes with OXC endpoints")
    
    # Create a set to track which links we've already processed (to avoid duplicates)
    processed_links = Set{Tuple{Int,Int}}()
    
    # Iterate through all nodes and their neighbors to create inter-node OXC links
    for nodeview in nodeviews
        node_id = nodeview.nodeproperties.localnode
        
        # Only process nodes that have OXC endpoints
        if node_id in oxc_nodes
            # Get all neighbors (both in and out)
            all_neighbors = Set{Int}()
            union!(all_neighbors, nodeview.nodeproperties.inneighbors)
            union!(all_neighbors, nodeview.nodeproperties.outneighbors)
            
            for neighbor_id in all_neighbors
                # Only create links if neighbor also has OXC endpoint
                if neighbor_id in oxc_nodes
                    # Create ordered pair to avoid duplicates
                    link_pair = node_id < neighbor_id ? (node_id, neighbor_id) : (neighbor_id, node_id)
                    
                    # Only process if we haven't already processed this link
                    if link_pair ∉ processed_links
                        push!(processed_links, link_pair)
                        
                        println("\nCreating/Updating inter-node OXC link: $(link_pair[1]) ↔ $(link_pair[2])...")
                        if create_inter_node_link(sdn, link_pair[1], link_pair[2], :oxc_ep, :oxc_ep; link_type=:optical)
                            links_created += 1
                        end
                    end
                end
            end
        end
    end
    
    println("✓ Processed $links_created inter-node OXC links")
    return links_created
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
    println("\n=== Creating All Network Links ===")
    
    # First create all intra-node links
    println("\n--- Phase 1: Intra-Node Links ---")
    intra_links = connect_all_intra_node_devices(sdn)
    
    # Then create all inter-node links
    println("\n--- Phase 2: Inter-Node Links ---")
    inter_links = connect_all_oxcs_inter_node(sdn, nodeviews)
    
    println("\n=== Link Creation Summary ===")
    println("Intra-node Router-OXC links processed: $intra_links")
    println("Inter-node OXC-OXC links processed: $inter_links")
    println("Total links processed: $(intra_links + inter_links)")
    
    return (intra_links, inter_links)
end

export create_link_between_devices, create_router_oxc_link, create_inter_node_link,
       connect_all_intra_node_devices, connect_all_oxcs_inter_node, create_all_network_links

export routerview_to_configrule, minimal_tfs_context, minimal_tfs_topology, 
        push_node_devices_to_tfs, save_device_map, load_device_map!

end