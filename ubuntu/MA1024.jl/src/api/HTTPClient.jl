using HTTP, JSON3

const BASE = "http://127.0.0.1:80/tfs-api"

get_devices() = JSON3.read(String(HTTP.get("$BASE/devices").body))

function get_device(uuid)::Ctx.Device
    JSON3.read(String(HTTP.get("$BASE/device/$uuid").body), Ctx.Device)
end

function put_device(uuid::String, dev::Ctx.Device)
    HTTP.put("$BASE/device/$uuid";
            headers = ["Content-Type"=>"application/json"],
            body = JSON3.write(dev)).status == 200
end

function add_config_rule!(uuid::AbstractString, rules)
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

    return put_device(uuid, payload)          # HTTP PUT via existing helper
end