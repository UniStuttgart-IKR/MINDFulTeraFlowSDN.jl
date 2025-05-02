print_device(d::Ctx.Device) = begin
    println("Device UUID: ", d.device_id.device_uuid.uuid)
    println(d)
    for r in d.device_config.config_rules
        println(r)
        println("  ", r.custom.resource_key, " => ", r.custom.resource_value)
    end
end
