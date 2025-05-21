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

    # ───────────────────────────────── Router ───────────────────────────────
    if nodeview.routerview !== nothing
        key   = (node_id, :router)
        uuid  = get!(sdn.device_map, key) do
                    stable_uuid(node_id, :router)
                end
        dev   = Ctx.Device(
                   Ctx.DeviceId(Ctx.Uuid(uuid)),
                   "Router-$uuid",
                   "emu-packet-router",
                   Ctx.DeviceConfig([]),
                   Ctx.DeviceOperationalStatusEnum.DEVICEOPERATIONALSTATUS_ENABLED,
                   [Ctx.DeviceDriverEnum.DEVICEDRIVER_UNDEFINED],
                   Ctx.EndPoint[], Ctx.Component[], nothing)

        if ensure_post_device(sdn.api_url, dev)
            ports = nodeview.routerview.portnumber
            rule  = Ctx.ConfigRule(
                    Ctx.ConfigActionEnum.CONFIGACTION_SET,
                    OneOf(:custom,
                            Ctx.ConfigRule_Custom("/router-ports",
                                                JSON3.write(Dict("ports" => ports)))))

            ok = add_config_rule!(sdn.api_url, uuid, rule)
            !ok && @warn "Router rule update failed for $uuid"
        else
            @warn "Router device $uuid could not be created/updated"
        end
    end

    # ───────────────────────────────── OXC ──────────────────────────────────
    if nodeview.oxcview !== nothing
        key   = (node_id, :oxc)
        uuid  = get!(sdn.device_map, key) do
                    stable_uuid(node_id, :oxc)
                end
        dev   = Ctx.Device(
                   Ctx.DeviceId(Ctx.Uuid(uuid)),
                   "OXC-$uuid",
                   "emu-optical-roadm",
                   Ctx.DeviceConfig([]),
                   Ctx.DeviceOperationalStatusEnum.DEVICEOPERATIONALSTATUS_ENABLED,
                   [Ctx.DeviceDriverEnum.DEVICEDRIVER_UNDEFINED],
                   Ctx.EndPoint[], Ctx.Component[], nothing)

        if ensure_post_device(sdn.api_url, dev)
            adddrop = nodeview.oxcview.adddropportnumber
            rule    = Ctx.ConfigRule(
                        Ctx.ConfigActionEnum.CONFIGACTION_SET,
                        OneOf(:custom,
                              Ctx.ConfigRule_Custom("/oxc-adddropports",
                                                    JSON3.write(Dict("adddropports" => adddrop)))))
            ok = add_config_rule!(sdn.api_url, uuid, rule)
            !ok && @warn "Router rule update failed for $uuid"
        else
            @warn "OXC device $uuid could not be created/updated"
        end
    end

    # ─────────────────────────────── Transmission Modules ───────────────────
    if nodeview.transmissionmoduleviewpool !== nothing
        for tmview in nodeview.transmissionmoduleviewpool
            key   = (node_id, :tm)
            uuid  = get!(sdn.device_map, key) do
                        stable_uuid(node_id, :tm)
                    end
            dev   = Ctx.Device(
                       Ctx.DeviceId(Ctx.Uuid(uuid)),
                       "TM-$uuid",
                       "emu-optical-transponder",
                       Ctx.DeviceConfig([]),
                       Ctx.DeviceOperationalStatusEnum.DEVICEOPERATIONALSTATUS_ENABLED,
                       [Ctx.DeviceDriverEnum.DEVICEDRIVER_UNDEFINED],
                       Ctx.EndPoint[], Ctx.Component[], nothing)

            if ensure_post_device(sdn.api_url, dev)
                modes = tmview.transmissionmodes
                rule  = Ctx.ConfigRule(
                            Ctx.ConfigActionEnum.CONFIGACTION_SET,
                            OneOf(:custom,
                                  Ctx.ConfigRule_Custom("/transmission-modes",
                                                        JSON3.write(Dict("modes" => modes)))))
                ok = add_config_rule!(sdn.api_url, uuid, rule)
                !ok && @warn "Router rule update failed for $uuid"
            else
                @warn "TM device $uuid could not be created/updated"
            end
        end
    end
end

export routerview_to_configrule, minimal_tfs_context, minimal_tfs_topology, 
        push_node_devices_to_tfs, save_device_map, load_device_map!

end