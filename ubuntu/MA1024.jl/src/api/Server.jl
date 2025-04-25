using Oxygen, JSON3, HTTP 

# === north-bound routes ============================================

@get "/device/{device_uuid}" function(_req::HTTP.Request, device_uuid::String)
    return get_device(device_uuid)          # -> DevicePayload, auto-JSON
end

@put "/device/{device_uuid}" function(_req::HTTP.Request,
                                    device_uuid::String,
                                    body::Body{DevicePayload})
    payload = body[]

    if device_uuid != payload.device_id.device_uuid.uuid
        return Oxygen.error(400, "UUID mismatch")
    end

    put_device(device_uuid, payload) || return Oxygen.error(500, "NBI error")
    return Dict("status" => "ok")
end

@get "/" (_) -> "MA1024 Oxygen API – see /docs"

start(; host="0.0.0.0", port=8080, kw...) =
    serve(; host, port, serialize=true, kw...)

stop() = terminate()
