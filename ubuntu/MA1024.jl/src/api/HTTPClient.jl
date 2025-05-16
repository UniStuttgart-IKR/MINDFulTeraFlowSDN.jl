using HTTP, JSON3

function get_devices(api_url::String) 
    JSON3.read(String(HTTP.get("$api_url/devices").body))
end

function get_device(api_url:: String, uuid)::Ctx.Device
    JSON3.read(String(HTTP.get("$api_url/device/$uuid").body), Ctx.Device)
end

function get_contexts(api_url::String)
    resp = HTTP.get("$api_url/contexts")
    return JSON3.read(String(resp.body))
end

function get_topologies(api_url::String, context_uuid::String)
    resp = HTTP.get("$api_url/context/$context_uuid/topologies")
    return JSON3.read(String(resp.body))
end

function put_device(api_url:: String, uuid::String, dev::Ctx.Device)
    HTTP.put("$api_url/device/$uuid";
            headers = ["Content-Type"=>"application/json"],
            body = JSON3.write(dev)).status == 200
end

function add_config_rule!(api_url:: String, uuid::AbstractString, rules)
    # normalise to Vector{ConfigRule}
    rules_vec = rules isa Ctx.ConfigRule ? [rules] : collect(rules)

    payload = Ctx.Device(
        Ctx.DeviceId(Ctx.Uuid(uuid)),         # 1. device_id
        "",                                   # 2. name  (unused)
        "",                                   # 3. device_type (unused)
        Ctx.DeviceConfig(rules_vec),          # 4. device_config with rules
        Ctx.DeviceOperationalStatusEnum.DEVICEOPERATIONALSTATUS_UNDEFINED,
        Ctx.DeviceDriverEnum.T[],             # 6. drivers  (empty)
        Ctx.EndPoint[],                       # 7. endpoints (empty)
        Ctx.Component[],                      # 8. components (empty)
        nothing                               # 9. controller_id
    )
    return put_device(api_url, uuid, payload)
end

function post_context(api_url::String, ctx::Ctx.Context)
    url = "$api_url/contexts"
    body_json = JSON3.write(Dict("contexts" => [ctx]))
    println("Request JSON: ", body_json)
    resp = HTTP.post(url;
        headers = ["Content-Type"=>"application/json"],
        body = body_json)
    return resp.status == 200
end

function minimal_topology_json(topo::Ctx.Topology)
    d = JSON3.read(JSON3.write(topo), Dict{String,Any})
    for field in ("device_ids", "link_ids", "optical_link_ids", "name")
        if haskey(d, field)
            delete!(d, field)
        end
    end
    return d
end

function post_topology_minimal(api_url::String, context_uuid::String, topo::Ctx.Topology)
    url = "$api_url/context/$context_uuid/topologies"
    body = JSON3.write(Dict("topologies" => [minimal_topology_json(topo)]))
    println("Request JSON: ", body)
    resp = HTTP.post(url;
        headers = ["Content-Type"=>"application/json"],
        body = body
    )
    return resp.status == 200
end

function post_device(api_url::String, device::Ctx.Device)
    url = "$api_url/devices"
    body_json = JSON3.write(Dict("devices" => [device]))
    println("Request JSON: ", body_json)
    resp = HTTP.post(url;
        headers = ["Content-Type"=>"application/json"],
        body = body_json)
    return resp.status == 200
end