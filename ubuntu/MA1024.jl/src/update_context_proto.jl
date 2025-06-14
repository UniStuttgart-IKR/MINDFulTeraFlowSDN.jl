using ProtoBuf

local_proto_dir = "/home/kshpthk/controller/proto" # use original env variable
output_dir = "/home/kshpthk/ma1024/ubuntu/MA1024.jl/src/api/proto" # make it relative

# Ensure the output directory exists
if !isdir(output_dir)
    mkpath(output_dir)
end

# Run protojl: relative path to context.proto, search directory, output directory
cd(local_proto_dir) do
    ProtoBuf.protojl("context.proto", ".", output_dir)
end

println("ProtoBuf files generated in: ", output_dir)
