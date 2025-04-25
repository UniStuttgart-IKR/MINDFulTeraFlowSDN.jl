print_device(d::DevicePayload) = begin
    println("Device UUID: ", d.device_id.device_uuid.uuid)
    for r in d.device_config.config_rules
        println("  ", r.custom.resource_key, " => ", r.custom.resource_value)
    end
end
