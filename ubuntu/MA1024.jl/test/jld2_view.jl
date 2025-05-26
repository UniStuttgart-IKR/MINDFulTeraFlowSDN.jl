using JLD2

# Open the JLD2 file
jldopen("data/device_map.jld2", "r") do file
    println("Keys in file: ", keys(file))

    # Access and print the contents of the "device_map" dataset
    device_map = file["device_map"]
    println(rpad("Node", 10), rpad("Type", 10), "UUID")
    println("-"^50)

    for ((node, dtype), uuid) in sort(collect(device_map))
        println(rpad(string(node), 10), rpad(string(dtype), 10), uuid)
    end
end
