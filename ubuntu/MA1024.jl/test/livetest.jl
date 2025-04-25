using MA1024

uuid = "c944aaeb-bbdf-5f2d-b31c-8cc8903045b6"
d = get_device(uuid)
print_device(d)

rule = ConfigRule(CONFIGACTION_SET,
        CustomRule("/interface[eth1]",
                JSON3.write(Dict("name"=>"eth1","description"=>"Ethernet"))))
new = DevicePayload(d.device_id, DeviceConfig([rule]))

put_device(uuid, new)

# function send_to_tfs(LLI)
#         mystruct =tfsprotostruct(LLI)
#         send(mystruct)
# end

