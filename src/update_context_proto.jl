using ProtoBuf

local_proto_dir = "/home/fbgmrtnz/controller/proto" # use original env variable
output_dir = "/home/fbgmrtnz/workspace1069/MINDFulTeraFlowSDN.jl/src/api/proto" # make it relative

# Ensure the output directory exists
if !isdir(output_dir)
    mkpath(output_dir)
end

# Run protojl: relative path to context.proto, search directory, output directory
cd(local_proto_dir) do
    ProtoBuf.protojl("context.proto", ".", output_dir)
end

println("ProtoBuf files generated in: ", output_dir)
