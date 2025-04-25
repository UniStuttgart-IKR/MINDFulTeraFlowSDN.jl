module MA1024
using HTTP, JSON3, StructTypes, Oxygen
export JSON3  

include("api/api.jl")

# choose what to export publicly
export DevicePayload, DeviceConfig, ConfigRule, CustomRule, 
        CONFIGACTION_SET, CONFIGACTION_DELETE, CONFIGACTION_UNSPECIFIED,
        get_devices, get_device, put_device,
        print_device, start, stop
end