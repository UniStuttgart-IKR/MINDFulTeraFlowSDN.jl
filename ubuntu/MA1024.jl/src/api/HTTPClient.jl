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
