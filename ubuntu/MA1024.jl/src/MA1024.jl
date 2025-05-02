module MA1024
using ProtoBuf, JSON3, StructTypes, Oxygen, HTTP
include("api/api.jl")          # <- pulls every file above

using ProtoBuf: OneOf          # bring it into MA1024’s scope   

# public surface --------------------------------------------------------------
export OneOf, Ctx,
        get_devices, get_device, put_device,
        print_device,
        start, stop               # from Server.jl
end