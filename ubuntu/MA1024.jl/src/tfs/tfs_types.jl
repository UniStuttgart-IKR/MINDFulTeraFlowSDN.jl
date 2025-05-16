module TFS

export TFSRouter, TeraflowSDN
using MINDFul
using JSON3
using UUIDs
import ..Ctx
# Add these lines:
include("../api/HTTPClient.jl")

struct TFSRouter
    end
# Define the TeraFlowSDN struct
struct TeraflowSDN <: MINDFul.AbstractSDNController
    api_url::String

#    mapping::Dict{Int,Any} =Dict(ibnnodeid => Dict("router" => Dict(tfsuuid ... additional only tfs info)))
end

TeraflowSDN() = TeraflowSDN("http://127.0.0.1:80/tfs-api")

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

function push_node_devices_to_tfs(nodeview, sdncontroller, context_uuid, topology_uuid)
    # Push router if present
    if nodeview.routerview !== nothing
        routerview = nodeview.routerview
        device_uuid = string(UUIDs.uuid4())
        device = Ctx.Device(
            Ctx.DeviceId(Ctx.Uuid(device_uuid)),
            "Router-$(device_uuid)",
            "emu-packet-router",
            Ctx.DeviceConfig([]),
            Ctx.DeviceOperationalStatusEnum.DEVICEOPERATIONALSTATUS_ENABLED,
            Ctx.DeviceDriverEnum.T[],
            Ctx.EndPoint[],
            Ctx.Component[],
            nothing
        )
        # 1. POST to create device
        post_device(sdncontroller.api_url, device)
        # 2. PUT to add config rules
        ports = routerview.portnumber
        rule = Ctx.ConfigRule(
            Ctx.ConfigActionEnum.CONFIGACTION_SET,
            OneOf(:custom, Ctx.ConfigRule_Custom("/router-ports", JSON3.write(Dict("ports" => ports))))
        )
        device.device_config = Ctx.DeviceConfig([rule])
        put_device(sdncontroller.api_url, device_uuid, device)
    end

    # Push OXC if present
    if nodeview.oxcview !== nothing
        oxcview = nodeview.oxcview
        device_uuid = string(UUIDs.uuid4())
        device = Ctx.Device(
            Ctx.DeviceId(Ctx.Uuid(device_uuid)),
            "OXC-$(device_uuid)",
            "emu-optical-roadm",
            Ctx.DeviceConfig([]),
            Ctx.DeviceOperationalStatusEnum.DEVICEOPERATIONALSTATUS_ENABLED,
            Ctx.DeviceDriverEnum.T[],
            Ctx.EndPoint[],
            Ctx.Component[],
            nothing
        )
        post_device(sdncontroller.api_url, device)
        adddropports = oxcview.adddropportnumber
        rule = Ctx.ConfigRule(
            Ctx.ConfigActionEnum.CONFIGACTION_SET,
            OneOf(:custom, Ctx.ConfigRule_Custom("/oxc-adddropports", JSON3.write(Dict("adddropports" => adddropports))))
        )
        device.device_config = Ctx.DeviceConfig([rule])
        put_device(sdncontroller.api_url, device_uuid, device)
    end

    # Push transmission modules if present
    if nodeview.transmissionmoduleviewpool !== nothing
        for tmview in nodeview.transmissionmoduleviewpool
            device_uuid = string(UUIDs.uuid4())
            device = Ctx.Device(
                Ctx.DeviceId(Ctx.Uuid(device_uuid)),
                "TM-$(device_uuid)",
                "emu-optical-transponder",
                Ctx.DeviceConfig([]),
                Ctx.DeviceOperationalStatusEnum.DEVICEOPERATIONALSTATUS_ENABLED,
                Ctx.DeviceDriverEnum.T[],
                Ctx.EndPoint[],
                Ctx.Component[],
                nothing
            )
            post_device(sdncontroller.api_url, device)
            modes = tmview.transmissionmodes
            rule = Ctx.ConfigRule(
                Ctx.ConfigActionEnum.CONFIGACTION_SET,
                OneOf(:custom, Ctx.ConfigRule_Custom("/transmission-modes", JSON3.write(Dict("modes" => modes))))
            )
            device.device_config = Ctx.DeviceConfig([rule])
            put_device(sdncontroller.api_url, device_uuid, device)
        end
    end
end

export routerview_to_configrule, minimal_tfs_context, minimal_tfs_topology, 
        push_node_devices_to_tfs

end