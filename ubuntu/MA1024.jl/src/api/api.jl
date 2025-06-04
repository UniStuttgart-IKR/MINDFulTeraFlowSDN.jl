# ---- generated protobufs -----------------------------------------------------
include("proto/context/context.jl")            # defines module `context`
const Ctx = context                       # alias inside MA1024

# ---- StructTypes mapping -----------------------------------------------------
include("register_proto_structtypes.jl")

# ---- plain function files ----------------------------------------------------
include("HTTPClient.jl")   # defines get_device, put_device, …
