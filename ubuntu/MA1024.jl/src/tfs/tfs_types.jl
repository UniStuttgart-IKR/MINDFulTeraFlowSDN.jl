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
#    mapping::Dict{Int,Any} =Dict(ibnnodeid => Dict("router" => Dict(tfsuuid ... additional only tfs info)))
end

TeraflowSDN() = TeraflowSDN("http://127.0.0.1:80/tfs-api", Dict{Tuple{Int,Symbol},String}())

function save_device_map(path::AbstractString, sdn::TeraflowSDN)
    @save path device_map = sdn.device_map
end

function load_device_map!(path::AbstractString, sdn::TeraflowSDN)
    isfile(path) || return
    @load path device_map                # loads a Dict into local var

    empty!(sdn.device_map)               # wipe current contents
    merge!(sdn.device_map, device_map)   # copy entries in-place
end


function minimal_tfs_context(context_uuid::String)
    return Ctx.Context(
        Ctx.ContextId(Ctx.Uuid(context_uuid)),
        "",             # name (optional)
        Ctx.TopologyId[],   # topology_ids (optional)
        Ctx.ServiceId[],    # service_ids (optional)
        Ctx.SliceId[],      # slice_ids (optional)
        nothing             # controller (optional)
    )
end

function minimal_tfs_topology(context_uuid::String, topology_uuid::String)
    return Ctx.Topology(
        Ctx.TopologyId(
            Ctx.ContextId(Ctx.Uuid(context_uuid)),
            Ctx.Uuid(topology_uuid)
        ),
        "",             # name (optional)
        Ctx.DeviceId[], # device_ids (optional)
        Ctx.LinkId[],   # link_ids (optional)
        Ctx.LinkId[]    # optical_link_ids (optional)
    )
end

# Convert RouterView to a TFS config rule (example for port 0)
function routerview_to_configrule(routerview::MINDFul.RouterView)
    ports = routerview.portnumber
    return ports
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
                    "Router-$uuid",                     # name
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
                    "OXC-$uuid",
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
    #                   "TM-$uuid",
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

export routerview_to_configrule, minimal_tfs_context, minimal_tfs_topology, 
        push_node_devices_to_tfs, save_device_map, load_device_map!

end