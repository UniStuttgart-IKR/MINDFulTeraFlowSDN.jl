using MA1024, JSON3

uuid  = "c944aaeb-bbdf-5f2d-b31c-8cc8903045b6"
dev   = get_device(uuid)
print_device(dev)

# --- rule 1 : /network_instance[R1-NetInst] ---------------------------
rule_netinst = Ctx.ConfigRule(
    Ctx.ConfigActionEnum.CONFIGACTION_SET,
    OneOf(:custom,
            Ctx.ConfigRule_Custom(
                "/network_instance[R1-NetInst]",
                JSON3.write(Dict(
                    "description"        => "R1 Network Instance",
                    "name"               => "R1-NetInst",
                    "route_distinguisher"=> "0:0",
                    "type"               => "L3VRF"
                )))
))

# --- rule 2 : /interface[eth0] ---------------------------------------
rule_if_eth0 = Ctx.ConfigRule(
    Ctx.ConfigActionEnum.CONFIGACTION_SET,
    OneOf(:custom,
            Ctx.ConfigRule_Custom(
                "/interface[eth0]",
                JSON3.write(Dict(
                    "description" => "Ethernet Interface",
                    "mtu"         => 1500,
                    "name"        => "eth0"
                )))
))

# --- rule 3 : /interface[eth0]/subinterface[0] -----------------------
rule_subif = Ctx.ConfigRule(
    Ctx.ConfigActionEnum.CONFIGACTION_SET,
    OneOf(:custom,
            Ctx.ConfigRule_Custom(
                "/interface[eth0]/subinterface[0]",
                JSON3.write(Dict(
                    "address_ip"     => "192.168.1.1",
                    "address_prefix" => 24,
                    "description"    => "Subinterface 0",
                    "index"          => 0,
                    "name"           => "eth0",
                    "vlan_id"        => 100
                )))
))

# --- send all three rules in a single PUT ----------------------------
ok = add_config_rule!(uuid, [rule_netinst, rule_if_eth0, rule_subif])
println(ok ? "\n✓ rules added\n" : "\n✗ PUT failed\n")

# --- verify ----------------------------------------------------------
print_device(get_device(uuid))

# function send_to_tfs(LLI)
#         mystruct =tfsprotostruct(LLI)
#         send(mystruct)
# end

