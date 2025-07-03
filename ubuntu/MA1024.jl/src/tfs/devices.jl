"""
Device creation and TFS posting
"""

function push_node_devices_to_tfs(nodeview, sdn::TeraflowSDN)


    node_id = nodeview.nodeproperties.localnode

    # ───────────────────────── Router ───────────────────────────────────────
    if nodeview.routerview !== nothing
        key  = (node_id, :router)
        uuid = get!(sdn.device_map, key) do
                    stable_uuid(node_id, :router)
                end

        # Create 2 copper endpoints for router
        endpoint_uuids = create_router_endpoints(sdn, node_id)

        endpoints_config = []
        for (i, ep_uuid) in enumerate(endpoint_uuids)
            push!(endpoints_config, Dict("sample_types"=>Any[],
                                        "type"=>"copper",
                                        "uuid"=>ep_uuid,
                                        "name"=>"router_ep_$(i)_node_$(node_id)"))
        end

        ep_rule = _custom_rule("_connect/settings", Dict("endpoints" => endpoints_config))

        # Fix: Use proper array constructor for device_drivers
        device_drivers = Vector{Ctx.DeviceDriverEnum.T}()
        push!(device_drivers, Ctx.DeviceDriverEnum.DEVICEDRIVER_UNDEFINED)

        dev  = Ctx.Device(
                    Ctx.DeviceId(Ctx.Uuid(uuid)),
                    "Router-Node-$(node_id)",                     # name
                    "emu-packet-router",                # device_type
                    Ctx.DeviceConfig([ep_rule]),               # empty config – rules follow
                    Ctx.DeviceOperationalStatusEnum.DEVICEOPERATIONALSTATUS_ENABLED,
                    device_drivers,  # Use the properly constructed array
                    Ctx.EndPoint[], Ctx.Component[], nothing)

        if ensure_post_device(sdn.api_url, dev)
            rules = build_config_rules(nodeview.routerview)
            _push_rules(sdn.api_url, uuid, rules; kind=:Router)
        else
            @warn "Router device $uuid could not be created/updated"
        end
    end

    # ───────────────────────── OXC ───────────────────────────────────────────
    if nodeview.oxcview !== nothing
        # Calculate and create variable number of fiber endpoints for OXC based on neighbors
        n_eps = oxc_endpoints_needed(nodeview)
        endpoint_uuids = create_oxc_endpoints(sdn, node_id, n_eps)
        println("  [OXC $node_id] Created $n_eps fiber endpoints before posting device")

        key  = (node_id, :oxc)
        uuid = get!(sdn.device_map, key) do
            stable_uuid(node_id, :oxc)
        end

        endpoints_config = []
        for (i, ep_uuid) in enumerate(endpoint_uuids)
            push!(endpoints_config, Dict("sample_types"=>Any[],
                                        "type"=>"fiber",
                                        "uuid"=>ep_uuid,
                                        "name"=>"oxc_ep_$(i)_node_$(node_id)"))
        end

        ep_rule = _custom_rule("_connect/settings", Dict("endpoints" => endpoints_config))

        device_drivers = Vector{Ctx.DeviceDriverEnum.T}()
        push!(device_drivers, Ctx.DeviceDriverEnum.DEVICEDRIVER_UNDEFINED)

        dev  = Ctx.Device(
                    Ctx.DeviceId(Ctx.Uuid(uuid)),
                    "OXC-Node-$(node_id)",
                    "emu-optical-roadm",
                    Ctx.DeviceConfig([ep_rule]),
                    Ctx.DeviceOperationalStatusEnum.DEVICEOPERATIONALSTATUS_ENABLED,
                    device_drivers,
                    Ctx.EndPoint[], Ctx.Component[], nothing)

        if ensure_post_device(sdn.api_url, dev)
            rules = build_config_rules(nodeview.oxcview, nodeview)  # Pass both oxcview and nodeview
            _push_rules(sdn.api_url, uuid, rules; kind=:OXC)
        else
            @warn "OXC device $uuid could not be created/updated"
        end
    end

    # Remove OLS creation from individual nodes - it will be created during inter-node linking

    # ─────────────────────── Transmission Modules ───────────────────────────
    if nodeview.transmissionmoduleviewpool !== nothing
        for (idx, tmview) in enumerate(nodeview.transmissionmoduleviewpool)
            key  = (node_id, Symbol("tm_$idx"))
            uuid = get!(sdn.device_map, key) do
                    stable_uuid(node_id * 10_000 + idx, :tm)
                end

            # Create 4 endpoints for TM (2 copper + 2 fiber)
            endpoint_uuids = create_tm_endpoints(sdn, node_id, idx)

            endpoints_config = []
            for i in 1:2  # First 2 are copper
                ep_uuid = endpoint_uuids[i]
                push!(endpoints_config, Dict("sample_types"=>Any[],
                                            "type"=>"copper",
                                            "uuid"=>ep_uuid,
                                            "name"=>"tm_$(idx)_copper_ep_$(i)_node_$(node_id)"))
            end
            for i in 3:4  # Next 2 are fiber
                ep_uuid = endpoint_uuids[i]
                push!(endpoints_config, Dict("sample_types"=>Any[],
                                            "type"=>"fiber",
                                            "uuid"=>ep_uuid,
                                            "name"=>"tm_$(idx)_fiber_ep_$(i-2)_node_$(node_id)"))
            end

            ep_rule = _custom_rule("_connect/settings", Dict("endpoints" => endpoints_config))

            dev  = Ctx.Device(
                    Ctx.DeviceId(Ctx.Uuid(uuid)),
                    "TM-Node-$(node_id)-$(idx)",
                    "emu-optical-transponder",
                    Ctx.DeviceConfig([ep_rule]),
                    Ctx.DeviceOperationalStatusEnum.DEVICEOPERATIONALSTATUS_ENABLED,
                    [Ctx.DeviceDriverEnum.DEVICEDRIVER_UNDEFINED],
                    Ctx.EndPoint[], Ctx.Component[], nothing)

            if ensure_post_device(sdn.api_url, dev)
                # Use first copper endpoint for TM rules
                first_copper_ep_uuid = endpoint_uuids[1]
                rules = build_config_rules(tmview; ep_uuid=first_copper_ep_uuid)
                _push_rules(sdn.api_url, uuid, rules; kind=:TM)
            else
                @warn "TM device $uuid could not be created/updated"
            end
        end
    end

    println("Pushed node devices to TFS")

end