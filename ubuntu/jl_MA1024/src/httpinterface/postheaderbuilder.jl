function buildheader(data)
println("Still need to build data")
end
"""

Function signature
$(TYPEDSIGNATURES)
"""
function get_devices(url)
   
    response = HTTP.get(url::String)
    if response.status == 200
        println("Devices fetched successfully\n")
        devices = JSON.parse(String(response.body))
        return devices
    else
        error("Failed to fetch devices. HTTP status: $(response.status)")
    end
end

# Function to print device details
function print_devices(devices)
    println("Devices retrieved from TeraFlowSDN API:")
    for device in devices["devices"]
        uuid = device["device_id"]["device_uuid"]["uuid"]
        dev_type = device["device_type"]
        println("Device UUID: $uuid")
        println("  Type: $dev_type")
        for rule in device["device_config"]["config_rules"]
            key = rule["custom"]["resource_key"]
            value = rule["custom"]["resource_value"]
            println("    $key => $value")
        end
        println("  Operational Status: $(device["device_operational_status"])")
        println("------------------------------------------------")
    end
end
