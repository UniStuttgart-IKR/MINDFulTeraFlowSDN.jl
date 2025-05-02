using Oxygen, HTTP

# ---- Protobuf in / out -------------------------------------------------------

@put "/device/{uuid}" function(req::HTTP.Request, uuid::String)
    dev = protobuf(req, Ctx.Device)             # decode binary body
    uuid != dev.device_id.device_uuid.uuid && return Oxygen.error(400)
    put_device(uuid, dev) || return Oxygen.error(500, "NBI error")
    return protobuf(dev)                        # echo back
end

@get "/device/{uuid}" function(_::HTTP.Request, uuid::String)
    return protobuf(get_device(uuid))           # binary protobuf response
end

@get "/" (_) -> "MA1024 proto API — see /docs"

start(; host="0.0.0.0", port=8080, kw...) =
    serve(; host, port, serialize=false, kw...)

stop() = terminate()
