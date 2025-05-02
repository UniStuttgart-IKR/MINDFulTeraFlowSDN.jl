using MA1024

uuid  = "c944aaeb-bbdf-5f2d-b31c-8cc8903045b6"
dev   = get_device(uuid)
print_device(dev)
new_rule = Ctx.ConfigRule(
      Ctx.ConfigActionEnum.CONFIGACTION_SET,        # ← full path
      MA1024.OneOf(:custom, Ctx.ConfigRule_Custom(
            "/interface[eth0]",
            "{\"name\":\"eth0\",\"description\":\"Ethernet\"}"
      ))
)

# push!(dev.device_config.config_rules, new_rule)
put_device(uuid, new_rule)


# function send_to_tfs(LLI)
#         mystruct =tfsprotostruct(LLI)
#         send(mystruct)
# end

