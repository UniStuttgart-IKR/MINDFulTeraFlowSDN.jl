"""
    print_device(dev::Ctx.Device)

Pretty‑prints everything in a `Device` message, handling both JSON‑parsed and
binary‑parsed `ConfigRule`s.
"""
function print_device(dev::Ctx.Device)
    println("────────────────────────────────────────────")
    println("Device UUID        : ", dev.device_id.device_uuid.uuid)
    println("Name               : ", dev.name)
    println("Type               : ", dev.device_type)
    println("Operational Status : ", dev.device_operational_status)

    !isempty(dev.device_drivers) &&
        println("Drivers            : ",
                join(string.(dev.device_drivers), ", "))

    # ---------------- Config rules ------------------------------------------
    rules = dev.device_config.config_rules
    println("\nConfig Rules (", length(rules), ")")

    for r in rules
        # A) OneOf present (binary path)
        if r.config_rule !== nothing
            tag   = r.config_rule.name
            value = r.config_rule[]
        # B) Has extra-field :custom (JSON path, nested)
        elseif hasproperty(r, :custom) && getproperty(r, :custom) !== nothing
            tag   = :custom
            value = getproperty(r, :custom)
        # C) Flat keys resource_key / resource_value (real NBI shape)
        elseif hasproperty(r, :resource_key)
            tag   = :custom
            value = (resource_key = getproperty(r, :resource_key),
                     resource_value = getproperty(r, :resource_value))
        else
            println("  [", r.action, "]  (no sub‑field set)")
            continue
        end

        if tag === :custom
            println("  [", r.action, "]  ",
                    value.resource_key, " => ", value.resource_value)
        elseif tag === :acl
            println("  [", r.action, "]  ACL on endpoint ",
                    value.endpoint_id.endpoint_uuid.uuid,
                    "  (", length(value.rule_set.rules), " rules)")
        end
    end

    # ---------------- Endpoints --------------------------------------------
    if !isempty(dev.device_endpoints)
        println("\nEndpoints (", length(dev.device_endpoints), ")")
        for ep in dev.device_endpoints
            eid = ep.endpoint_id
            println("  • ", eid.endpoint_uuid.uuid,
                    "  [", ep.endpoint_type, "]  name=\"", ep.name, "\"")
        end
    end

    # ---------------- Components -------------------------------------------
    if !isempty(dev.components)
        println("\nInventory Components (", length(dev.components), ")")
        for c in dev.components
            println("  • ", c.component_uuid.uuid,
                    "  ", c.type, "  name=\"", c.name, "\"")
            !isempty(c.attributes) &&
              println("      attrs: ", join(keys(c.attributes), ", "))
            !isempty(c.parent) && println("      parent: ", c.parent)
        end
    end

    # ---------------- Controller ------------------------------------------
    cid = dev.controller_id
    if cid !== nothing && cid.device_uuid !== nothing &&
       !isempty(cid.device_uuid.uuid)
        println("\nController Node    : ", cid.device_uuid.uuid)
    end
    println("────────────────────────────────────────────")
end