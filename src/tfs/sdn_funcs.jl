# Import required types from MINDFul
using MINDFul: AbstractSDNController, ReservableResourceView, LowLevelIntent
using MINDFul: RouterView, OXCView, NodeView, RouterPortLLI, TransmissionModuleLLI, OXCAddDropBypassSpectrumLLI
using MINDFul: ReturnCodes, UUID
using MINDFul: getreservations, getrouterportindex, getportnumber, getadddropport, getadddropportnumber
using MINDFul: getlocalnode_input, getlocalnode_output, getspectrumslotsrange, isreservationvalid
using MINDFul: gettransmissionmoduleviewpoolindex, gettransmissionmoduleviewpool, gettransmissionmodesindex, gettransmissionmodes
using MINDFul: Edge
using DocStringExtensions
using JSON3

# ═══════════════════════════════════════════════════════════════════════════════
# RESERVE FUNCTIONS - Enable/Configure Resources
# ═══════════════════════════════════════════════════════════════════════════════

"""
$(TYPEDSIGNATURES)
Router Port Reservation - enables router interface in TeraFlow
"""
function MINDFul.reserve!(sdn::TeraflowSDN, routerview::RouterView, routerportlli::RouterPortLLI, dagnodeid::UUID; checkfirst::Bool = true, verbose::Bool = false)
    verbose && println("TeraFlow: Reserving router port $(getrouterportindex(routerportlli))")
    checkfirst && !MINDFul.canreserve(sdn, routerview, routerportlli; verbose) && return ReturnCodes.FAIL
    return MINDFul.insertreservation!(sdn, routerview, dagnodeid, routerportlli; verbose)
end

"""
$(TYPEDSIGNATURES)
OXC Spectrum Reservation - configures wavelength routing in TeraFlow
"""
function MINDFul.reserve!(sdn::TeraflowSDN, oxcview::OXCView, oxclli::OXCAddDropBypassSpectrumLLI, dagnodeid::UUID; checkfirst::Bool = true, verbose::Bool = false)
    verbose && println("TeraFlow: Reserving OXC spectrum $(getspectrumslotsrange(oxclli))")
    checkfirst && !MINDFul.canreserve(sdn, oxcview, oxclli; verbose) && return ReturnCodes.FAIL
    return MINDFul.insertreservation!(sdn, oxcview, dagnodeid, oxclli; verbose)
end

"""
$(TYPEDSIGNATURES)
Transmission Module Reservation - enables TM and optical channels in TeraFlow
"""
function MINDFul.reserve!(sdn::TeraflowSDN, nodeview::NodeView, tmlli::TransmissionModuleLLI, dagnodeid::UUID; checkfirst::Bool = true, verbose::Bool = false)
    verbose && println("TeraFlow: Reserving transmission module $(gettransmissionmoduleviewpoolindex(tmlli))")
    checkfirst && !MINDFul.canreserve(sdn, nodeview, tmlli; verbose) && return ReturnCodes.FAIL
    return MINDFul.insertreservation!(sdn, nodeview, dagnodeid, tmlli; verbose)
end

# ═══════════════════════════════════════════════════════════════════════════════
# UNRESERVE FUNCTIONS - Disable/Unconfigure Resources
# ═══════════════════════════════════════════════════════════════════════════════

"""
$(TYPEDSIGNATURES)
Router Port Unreservation - disables router interface in TeraFlow
"""
function MINDFul.unreserve!(sdn::TeraflowSDN, routerview::RouterView, dagnodeid::UUID; verbose::Bool = false)
    verbose && println("TeraFlow: Unreserving router port")
    return MINDFul.deletereservation!(sdn, routerview, dagnodeid; verbose)
end

"""
$(TYPEDSIGNATURES)
OXC Spectrum Unreservation - removes wavelength routing configuration
"""
function MINDFul.unreserve!(sdn::TeraflowSDN, oxcview::OXCView, dagnodeid::UUID; verbose::Bool = false)
    verbose && println("TeraFlow: Unreserving OXC spectrum")
    return MINDFul.deletereservation!(sdn, oxcview, dagnodeid; verbose)
end

"""
$(TYPEDSIGNATURES)
Transmission Module Unreservation - disables TM and optical channels
"""
function MINDFul.unreserve!(sdn::TeraflowSDN, nodeview::NodeView, dagnodeid::UUID; verbose::Bool = false)
    verbose && println("TeraFlow: Unreserving transmission module")
    return MINDFul.deletereservation!(sdn, nodeview, dagnodeid; verbose)
end

# ═══════════════════════════════════════════════════════════════════════════════
# CANRESERVE FUNCTIONS - Validation/Availability Check
# ═══════════════════════════════════════════════════════════════════════════════

"""
$(TYPEDSIGNATURES)
Router Port Availability Check
"""
function MINDFul.canreserve(sdn::TeraflowSDN, routerview::RouterView, routerportlli::RouterPortLLI; verbose::Bool = false)
    max_ports = getportnumber(routerview)
    requested_port = getrouterportindex(routerportlli)
    
    # Check if port exists
    if requested_port > max_ports
        verbose && @warn "Router port $requested_port does not exist (max: $max_ports)"
        return false
    end
    
    # Check if port is already in use
    reservations = getreservations(routerview)
    used_ports = getrouterportindex.(values(reservations))
    if requested_port in used_ports
        verbose && @warn "Router port $requested_port already in use"
        return false
    end
    
    return true
end

"""
$(TYPEDSIGNATURES)
OXC Spectrum Availability Check
"""
function MINDFul.canreserve(sdn::TeraflowSDN, oxcview::OXCView, oxcswitchreservationentry::OXCAddDropBypassSpectrumLLI; verbose::Bool = false)
    if !isreservationvalid(oxcswitchreservationentry)
        verbose && @warn "OXC reservation entry is invalid"
        return false
    end
    
    if getadddropport(oxcswitchreservationentry) > getadddropportnumber(oxcview)
        verbose && @warn "Add/drop port $(getadddropport(oxcswitchreservationentry)) does not exist (max: $(getadddropportnumber(oxcview)))"
        return false
    end
    
    # Check spectrum conflicts
    for registeredoxcswitchentry in values(getreservations(oxcview))
        if getlocalnode_input(registeredoxcswitchentry) == getlocalnode_input(oxcswitchreservationentry) &&
                getadddropport(registeredoxcswitchentry) == getadddropport(oxcswitchreservationentry) &&
                getlocalnode_output(registeredoxcswitchentry) == getlocalnode_output(oxcswitchreservationentry)
            spectrumslotintersection = intersect(getspectrumslotsrange(registeredoxcswitchentry), getspectrumslotsrange(oxcswitchreservationentry))
            if length(spectrumslotintersection) > 0
                verbose && @warn "Spectrum conflict detected in slots $spectrumslotintersection"
                return false
            end
        end
    end
    
    return true
end

"""
$(TYPEDSIGNATURES)
Transmission Module Availability Check
"""
function MINDFul.canreserve(sdn::TeraflowSDN, nodeview::NodeView, transmissionmodulelli::TransmissionModuleLLI; verbose::Bool = false)
    transmissionmodulereservations = values(getreservations(nodeview))
    transmissionmoduleviewpool = gettransmissionmoduleviewpool(nodeview)
    reserve2do_transmissionmoduleviewpoolindex = gettransmissionmoduleviewpoolindex(transmissionmodulelli)

    # Check if transmission module already in use
    used_indices = gettransmissionmoduleviewpoolindex.(transmissionmodulereservations)
    if reserve2do_transmissionmoduleviewpoolindex in used_indices
        verbose && @warn "Transmission module $reserve2do_transmissionmoduleviewpoolindex already in use"
        return false
    end
    
    # Check if transmission module exists
    if reserve2do_transmissionmoduleviewpoolindex > length(transmissionmoduleviewpool)
        verbose && @warn "Transmission module $reserve2do_transmissionmoduleviewpoolindex does not exist (max: $(length(transmissionmoduleviewpool)))"
        return false
    end
    
    # Check if transmission mode index is available
    tm_view = transmissionmoduleviewpool[reserve2do_transmissionmoduleviewpoolindex]
    if gettransmissionmodesindex(transmissionmodulelli) > length(gettransmissionmodes(tm_view))
        verbose && @warn "Transmission mode $(gettransmissionmodesindex(transmissionmodulelli)) not available for TM $reserve2do_transmissionmoduleviewpoolindex"
        return false
    end

    return true
end

# ═══════════════════════════════════════════════════════════════════════════════
# INSERTRESERVATION FUNCTIONS - Apply Reservations with TeraFlow Hooks
# ═══════════════════════════════════════════════════════════════════════════════

"""
$(TYPEDSIGNATURES)
Router Port Insertion - enables interface via TeraFlow hook
"""
function MINDFul.insertreservation!(sdn::TeraflowSDN, routerview::RouterView, dagnodeid::UUID, routerportlli::RouterPortLLI; verbose::Bool = false)
    verbose && println("TeraFlow: Inserting router port reservation")
    hook_result = MINDFul.insertreservationhook!(sdn, routerview, dagnodeid, routerportlli; verbose)
    MINDFul.issuccess(hook_result) || return ReturnCodes.FAIL
    
    reservationsdict = getreservations(routerview)
    if haskey(reservationsdict, dagnodeid)
        verbose && @warn "Reservation for DAG node $dagnodeid already exists – aborting"
        return ReturnCodes.FAIL
    end
    reservationsdict[dagnodeid] = routerportlli
    return ReturnCodes.SUCCESS
end

"""
$(TYPEDSIGNATURES)
OXC Spectrum Insertion - configures wavelength routing via TeraFlow hook
"""
function MINDFul.insertreservation!(sdn::TeraflowSDN, oxcview::OXCView, dagnodeid::UUID, oxclli::OXCAddDropBypassSpectrumLLI; verbose::Bool = false)
    verbose && println("TeraFlow: Inserting OXC spectrum reservation")
    hook_result = MINDFul.insertreservationhook!(sdn, oxcview, dagnodeid, oxclli; verbose)
    MINDFul.issuccess(hook_result) || return ReturnCodes.FAIL
    
    reservationsdict = getreservations(oxcview)
    if haskey(reservationsdict, dagnodeid)
        verbose && @warn "Reservation for DAG node $dagnodeid already exists – aborting"
        return ReturnCodes.FAIL
    end
    reservationsdict[dagnodeid] = oxclli
    return ReturnCodes.SUCCESS
end

"""
$(TYPEDSIGNATURES)
Transmission Module Insertion - enables TM via TeraFlow hook
"""
function MINDFul.insertreservation!(sdn::TeraflowSDN, nodeview::NodeView, dagnodeid::UUID, tmlli::TransmissionModuleLLI; verbose::Bool = false)
    verbose && println("TeraFlow: Inserting transmission module reservation")
    hook_result = MINDFul.insertreservationhook!(sdn, nodeview, dagnodeid, tmlli; verbose)
    MINDFul.issuccess(hook_result) || return ReturnCodes.FAIL
    
    reservationsdict = getreservations(nodeview)
    if haskey(reservationsdict, dagnodeid)
        verbose && @warn "Reservation for DAG node $dagnodeid already exists – aborting"
        return ReturnCodes.FAIL
    end    
    reservationsdict[dagnodeid] = tmlli
    return ReturnCodes.SUCCESS
end

# ═══════════════════════════════════════════════════════════════════════════════
# DELETERESERVATION FUNCTIONS - Remove Reservations with TeraFlow Hooks
# ═══════════════════════════════════════════════════════════════════════════════

"""
$(TYPEDSIGNATURES)
Router Port Deletion - disables interface via TeraFlow hook
"""
function MINDFul.deletereservation!(sdn::TeraflowSDN, routerview::RouterView, dagnodeid::UUID; verbose::Bool = false)
    verbose && println("TeraFlow: Deleting router port reservation")
    hook_result = MINDFul.deletereservationhook!(sdn, routerview, dagnodeid; verbose)
    MINDFul.issuccess(hook_result) || return ReturnCodes.FAIL
    
    reservationsdict = getreservations(routerview)
    # Safely attempt deletion even if key is missing
    if haskey(reservationsdict, dagnodeid)
        delete!(reservationsdict, dagnodeid)
    end
    return ReturnCodes.SUCCESS  # ← Always return SUCCESS, not the dict
end

"""
$(TYPEDSIGNATURES)
OXC Spectrum Deletion - removes wavelength routing via TeraFlow hook
"""
function MINDFul.deletereservation!(sdn::TeraflowSDN, oxcview::OXCView, dagnodeid::UUID; verbose::Bool = false)
    verbose && println("TeraFlow: Deleting OXC spectrum reservation")
    hook_result = MINDFul.deletereservationhook!(sdn, oxcview, dagnodeid; verbose)
    MINDFul.issuccess(hook_result) || return ReturnCodes.FAIL
    
    reservationsdict = getreservations(oxcview)
    # Safely attempt deletion even if key is missing
    if haskey(reservationsdict, dagnodeid)
        delete!(reservationsdict, dagnodeid)
    end
    return ReturnCodes.SUCCESS  # ← Always return SUCCESS, not the dict
end

"""
$(TYPEDSIGNATURES)
Transmission Module Deletion - disables TM via TeraFlow hook
"""
function MINDFul.deletereservation!(sdn::TeraflowSDN, nodeview::NodeView, dagnodeid::UUID; verbose::Bool = false)
    verbose && println("TeraFlow: Deleting transmission module reservation")
    hook_result = MINDFul.deletereservationhook!(sdn, nodeview, dagnodeid; verbose)
    MINDFul.issuccess(hook_result) || return ReturnCodes.FAIL
    
    reservationsdict = getreservations(nodeview)
    # Safely attempt deletion even if key is missing
    if haskey(reservationsdict, dagnodeid)
        delete!(reservationsdict, dagnodeid)
    end
    return ReturnCodes.SUCCESS  # ← Always return SUCCESS, not the dict
end

# ═══════════════════════════════════════════════════════════════════════════════
# TERAFLOW RESERVATION HOOKS - Device Configuration via TeraFlow API
# ═══════════════════════════════════════════════════════════════════════════════

"""
$(TYPEDSIGNATURES)
Router Port Installation Hook - enables interface (matches config_rules.jl paths)
"""
function MINDFul.insertreservationhook!(sdn::TeraflowSDN, routerview::RouterView, dagnodeid::UUID, routerportlli::RouterPortLLI; verbose::Bool = false)
    verbose && println("TeraFlow: Configuring router interface")
    
    node_id = routerportlli.localnode
    router_key = (node_id, :router)
    
    if !haskey(sdn.device_map, router_key)
        verbose && @warn "Router device not found for node $node_id"
        return ReturnCodes.FAIL
    end
    
    router_uuid = sdn.device_map[router_key]
    ifname = "eth$(getrouterportindex(routerportlli))"
    
    # Get port info to maintain speed configuration
    port_idx = getrouterportindex(routerportlli)
    if port_idx > length(routerview.ports)
        verbose && @warn "Port index $port_idx out of range"
        return ReturnCodes.FAIL
    end
    
    port_info = routerview.ports[port_idx]
    
    # Use EXACT structure from config_rules.jl creation/reservation
    enable_rule = _custom_rule(
        "/interfaces/interface/$ifname",
        Dict(
            "config" => Dict("name" => ifname, "enabled" => true),
            "ethernet" => Dict(
                "config" => Dict("port-speed" => _to_speed_enum(port_info.rate))  # ← Use exported function
            )
        )
    )
    
    success = add_config_rule!(sdn.api_url, router_uuid, [enable_rule])
    
    if success
        verbose && println("✓ TeraFlow: Enabled router interface $ifname")
        return ReturnCodes.SUCCESS
    else
        verbose && @warn "✗ TeraFlow: Failed to enable router interface $ifname"
        return ReturnCodes.FAIL
    end
end

"""
$(TYPEDSIGNATURES)
Router Port Uninstallation Hook - disables interface (matches config_rules.jl paths)
"""
function MINDFul.deletereservationhook!(sdn::TeraflowSDN, routerview::RouterView, dagnodeid::UUID; verbose::Bool = false)
    verbose && println("TeraFlow: Removing router interface configuration")
    
    reservations = getreservations(routerview)
    if !haskey(reservations, dagnodeid)
        verbose && @warn "No reservation found for DAG node $dagnodeid"
        return ReturnCodes.SUCCESS
    end
    
    routerportlli = reservations[dagnodeid]
    node_id = routerportlli.localnode
    router_key = (node_id, :router)
    
    if !haskey(sdn.device_map, router_key)
        verbose && @warn "Router device not found for node $node_id"
        return ReturnCodes.FAIL
    end
    
    router_uuid = sdn.device_map[router_key]
    ifname = "eth$(getrouterportindex(routerportlli))"
    
    # Get port info to maintain speed configuration
    port_idx = getrouterportindex(routerportlli)
    if port_idx > length(routerview.ports)
        verbose && @warn "Port index $port_idx out of range"
        return ReturnCodes.FAIL
    end
    
    port_info = routerview.ports[port_idx]
    
    # Use EXACT structure from config_rules.jl, just disable
    disable_rule = _custom_rule(
        "/interfaces/interface/$ifname",
        Dict(
            "config" => Dict("name" => ifname, "enabled" => false),
            "ethernet" => Dict(
                "config" => Dict("port-speed" => _to_speed_enum(port_info.rate))  # ← Use exported function
            )
        )
    )
    
    success = add_config_rule!(sdn.api_url, router_uuid, [disable_rule])
    
    if success
        verbose && println("✓ TeraFlow: Disabled router interface $ifname")
        return ReturnCodes.SUCCESS
    else
        verbose && @warn "✗ TeraFlow: Failed to disable router interface $ifname"
        return ReturnCodes.FAIL
    end
end

"""
$(TYPEDSIGNATURES)
OXC Installation Hook - configures wavelength routing (matches config_rules.jl paths)
"""
function MINDFul.insertreservationhook!(sdn::TeraflowSDN, oxcview::OXCView, dagnodeid::UUID, oxclli::OXCAddDropBypassSpectrumLLI; verbose::Bool = false)
    verbose && println("TeraFlow: Configuring OXC wavelength routing")
    
    node_id = oxclli.localnode
    oxc_key = (node_id, :oxc)
    
    if !haskey(sdn.device_map, oxc_key)
        verbose && @warn "OXC device not found for node $node_id"
        return ReturnCodes.FAIL
    end
    
    oxc_uuid = sdn.device_map[oxc_key]

    # Generate channel name using EXACT same logic as config_rules.jl
    if oxclli.localnode_input != 0 && oxclli.adddropport == 0 && oxclli.localnode_output != 0
        # Optical bypass: input node to output node
        channel_name = "bypass-node-$(oxclli.localnode_input)-input-port-node-$(oxclli.localnode_output)-output-port"
    elseif oxclli.localnode_input == 0 && oxclli.adddropport != 0 && oxclli.localnode_output != 0
        # Add: adddrop port to output node
        channel_name = "add-adddrop-port-$(oxclli.adddropport)-to-node-$(oxclli.localnode_output)-output-port"
    elseif oxclli.localnode_input != 0 && oxclli.adddropport != 0 && oxclli.localnode_output == 0
        # Drop: input node to adddrop port
        channel_name = "drop-node-$(oxclli.localnode_input)-input-port-to-adddrop-port-$(oxclli.adddropport)"
    elseif oxclli.localnode_input == 0 && oxclli.adddropport != 0 && oxclli.localnode_output == 0
        # Add/drop port reservation only
        channel_name = "adddrop-$(oxclli.adddropport)"
    else
        # Fallback to uuid if schema is unknown
        channel_name = string(dagnodeid)
    end
    
    # Calculate frequency range (matches config_rules.jl logic)
    base_freq_thz = 184.5
    slot_width_ghz = 12.5
    lower_slot = first(getspectrumslotsrange(oxclli))
    upper_slot = last(getspectrumslotsrange(oxclli))
    
    lower_freq = base_freq_thz + (lower_slot - 1) * slot_width_ghz / 1000
    upper_freq = base_freq_thz + upper_slot * slot_width_ghz / 1000
    
    rules = []
    
    # Create media channel with admin-status ENABLED (matches config_rules.jl)
    push!(rules, _custom_rule(
        "/wavelength-router/media-channels/channel/$(channel_name)/config",
        Dict(
            "name" => channel_name,
            "admin-status" => "ENABLED"
        )
    ))
    
    # Configure source and destination (matches config_rules.jl logic)
    if oxclli.localnode_input != 0 && oxclli.adddropport == 0 && oxclli.localnode_output != 0
        # Optical bypass
        push!(rules, _custom_rule(
            "/wavelength-router/media-channels/channel/$(channel_name)/source/config",
            Dict("port-name" => "node-$(oxclli.localnode_input)-input")
        ))
        push!(rules, _custom_rule(
            "/wavelength-router/media-channels/channel/$(channel_name)/dest/config",
            Dict("port-name" => "node-$(oxclli.localnode_output)-output")
        ))
    elseif oxclli.localnode_input == 0 && oxclli.adddropport != 0 && oxclli.localnode_output != 0
        # Add operation
        push!(rules, _custom_rule(
            "/wavelength-router/media-channels/channel/$(channel_name)/source/config",
            Dict("port-name" => "port-$(oxclli.adddropport)")
        ))
        push!(rules, _custom_rule(
            "/wavelength-router/media-channels/channel/$(channel_name)/dest/config",
            Dict("port-name" => "node-$(oxclli.localnode_output)-output")
        ))
    elseif oxclli.localnode_input != 0 && oxclli.adddropport != 0 && oxclli.localnode_output == 0
        # Drop operation
        push!(rules, _custom_rule(
            "/wavelength-router/media-channels/channel/$(channel_name)/source/config",
            Dict("port-name" => "node-$(oxclli.localnode_input)-input")
        ))
        push!(rules, _custom_rule(
            "/wavelength-router/media-channels/channel/$(channel_name)/dest/config",
            Dict("port-name" => "port-$(oxclli.adddropport)")
        ))
    end
    
    # Set spectrum range (matches config_rules.jl)
    push!(rules, _custom_rule(
        "/wavelength-router/media-channels/channel/$(channel_name)/spectrum-power-profile/distribution/config",
        Dict(
            "lower-frequency" => lower_freq,
            "upper-frequency" => upper_freq
        )
    ))
    
    success = add_config_rule!(sdn.api_url, oxc_uuid, rules)
    
    if success
        verbose && println("✓ TeraFlow: Configured OXC channel $channel_name")
        return ReturnCodes.SUCCESS
    else
        verbose && @warn "✗ TeraFlow: Failed to configure OXC channel $channel_name"
        return ReturnCodes.FAIL
    end
end

"""
$(TYPEDSIGNATURES)
OXC Uninstallation Hook - removes wavelength routing configuration by clearing exact paths
"""
function MINDFul.deletereservationhook!(sdn::TeraflowSDN, oxcview::OXCView, dagnodeid::UUID; verbose::Bool = false)
    verbose && println("TeraFlow: Removing OXC wavelength routing")
    
    reservations = getreservations(oxcview)
    if !haskey(reservations, dagnodeid)
        verbose && @warn "No OXC reservation found for DAG node $dagnodeid"
        return ReturnCodes.SUCCESS
    end
    
    oxclli = reservations[dagnodeid]
    node_id = oxclli.localnode
    oxc_key = (node_id, :oxc)
    
    if !haskey(sdn.device_map, oxc_key)
        verbose && @warn "OXC device not found for node $node_id"
        return ReturnCodes.FAIL
    end
    
    oxc_uuid = sdn.device_map[oxc_key]
    # Generate channel name using EXACT same logic as config_rules.jl
    if oxclli.localnode_input != 0 && oxclli.adddropport == 0 && oxclli.localnode_output != 0
        # Optical bypass: input node to output node
        channel_name = "bypass-node-$(oxclli.localnode_input)-input-port-node-$(oxclli.localnode_output)-output-port"
    elseif oxclli.localnode_input == 0 && oxclli.adddropport != 0 && oxclli.localnode_output != 0
        # Add: adddrop port to output node
        channel_name = "add-adddrop-port-$(oxclli.adddropport)-to-node-$(oxclli.localnode_output)-output-port"
    elseif oxclli.localnode_input != 0 && oxclli.adddropport != 0 && oxclli.localnode_output == 0
        # Drop: input node to adddrop port
        channel_name = "drop-node-$(oxclli.localnode_input)-input-port-to-adddrop-port-$(oxclli.adddropport)"
    elseif oxclli.localnode_input == 0 && oxclli.adddropport != 0 && oxclli.localnode_output == 0
        # Add/drop port reservation only
        channel_name = "adddrop-$(oxclli.adddropport)"
    else
        # Fallback to uuid if schema is unknown
        channel_name = string(dagnodeid)
    end
    
    rules = []
    
    # Disable the media channel first
    push!(rules, _custom_rule(
        "/wavelength-router/media-channels/channel/$(channel_name)/config",
        Dict(
            "name" => channel_name,
            "admin-status" => "DISABLED"
        )
    ))
    
    # Clear source and destination paths (set to empty strings)
    if oxclli.localnode_input != 0 && oxclli.adddropport == 0 && oxclli.localnode_output != 0
        # Optical bypass - clear both source and dest
        push!(rules, _custom_rule(
            "/wavelength-router/media-channels/channel/$(channel_name)/source/config",
            Dict("port-name" => "")
        ))
        push!(rules, _custom_rule(
            "/wavelength-router/media-channels/channel/$(channel_name)/dest/config",
            Dict("port-name" => "")
        ))
    elseif oxclli.localnode_input == 0 && oxclli.adddropport != 0 && oxclli.localnode_output != 0
        # Add operation - clear both source and dest
        push!(rules, _custom_rule(
            "/wavelength-router/media-channels/channel/$(channel_name)/source/config",
            Dict("port-name" => "")
        ))
        push!(rules, _custom_rule(
            "/wavelength-router/media-channels/channel/$(channel_name)/dest/config",
            Dict("port-name" => "")
        ))
    elseif oxclli.localnode_input != 0 && oxclli.adddropport != 0 && oxclli.localnode_output == 0
        # Drop operation - clear both source and dest
        push!(rules, _custom_rule(
            "/wavelength-router/media-channels/channel/$(channel_name)/source/config",
            Dict("port-name" => "")
        ))
        push!(rules, _custom_rule(
            "/wavelength-router/media-channels/channel/$(channel_name)/dest/config",
            Dict("port-name" => "")
        ))
    end
    
    # Clear spectrum range
    push!(rules, _custom_rule(
        "/wavelength-router/media-channels/channel/$(channel_name)/spectrum-power-profile/distribution/config",
        Dict(
            "lower-frequency" => 0.0,
            "upper-frequency" => 0.0
        )
    ))
    
    success = add_config_rule!(sdn.api_url, oxc_uuid, rules)
    
    if success
        verbose && println("✓ TeraFlow: Removed OXC channel $channel_name")
        return ReturnCodes.SUCCESS
    else
        verbose && @warn "✗ TeraFlow: Failed to remove OXC channel $channel_name"
        return ReturnCodes.FAIL
    end
end

"""
$(TYPEDSIGNATURES)
Transmission Module Installation Hook - enables TM and optical channel (matches config_rules.jl paths)
"""
function MINDFul.insertreservationhook!(sdn::TeraflowSDN, nodeview::NodeView, dagnodeid::UUID, tmlli::TransmissionModuleLLI; verbose::Bool = false)
    verbose && println("TeraFlow: Configuring transmission module")
    
    node_id = tmlli.localnode
    tm_idx = gettransmissionmoduleviewpoolindex(tmlli)
    mode_idx = gettransmissionmodesindex(tmlli)
    
    tm_key = (node_id, Symbol("tm_$tm_idx"))
    if !haskey(sdn.device_map, tm_key)
        verbose && @warn "TM device not found: $tm_key"
        return ReturnCodes.FAIL
    end
    
    tm_uuid = sdn.device_map[tm_key]
    # Use exact naming from config_rules.jl build_config_rules(TransmissionModuleView)
    module_name = "TM-Node-$(node_id)-$(tm_idx)"
    och_name = "$(module_name)-OCH$(mode_idx)"
    
    rules = []
    
    # Use exact paths from config_rules.jl
    push!(rules, _custom_rule(
        "/components/component/$(module_name)/transceiver/config/enabled",
        true
    ))
    
    # Enable specific optical channel (matches config_rules.jl format)
    push!(rules, _custom_rule(
        "/components/component/$(och_name)/properties/property/OCH_ENABLED/config",
        Dict("name" => "OCH_ENABLED", "value" => true)
    ))
    
    success = add_config_rule!(sdn.api_url, tm_uuid, rules)
    
    if success
        verbose && println("✓ TeraFlow: Enabled TM $tm_idx optical channel $mode_idx")
        return ReturnCodes.SUCCESS
    else
        verbose && @warn "✗ TeraFlow: Failed to enable TM $tm_idx optical channel $mode_idx"
        return ReturnCodes.FAIL
    end
end

"""
$(TYPEDSIGNATURES)
Transmission Module Uninstallation Hook - disables TM and optical channel
"""
function MINDFul.deletereservationhook!(sdn::TeraflowSDN, nodeview::NodeView, dagnodeid::UUID; verbose::Bool = false)
    verbose && println("TeraFlow: Removing transmission module configuration")
    
    reservations = getreservations(nodeview)
    if !haskey(reservations, dagnodeid)
        verbose && @warn "No TM reservation found for DAG node $dagnodeid"
        return ReturnCodes.SUCCESS
    end
    
    tmlli = reservations[dagnodeid]
    node_id = tmlli.localnode
    tm_idx = gettransmissionmoduleviewpoolindex(tmlli)
    mode_idx = gettransmissionmodesindex(tmlli)
    
    tm_key = (node_id, Symbol("tm_$tm_idx"))
    if !haskey(sdn.device_map, tm_key)
        verbose && @warn "TM device not found: $tm_key"
        return ReturnCodes.FAIL
    end
    
    tm_uuid = sdn.device_map[tm_key]
    # Use exact naming from config_rules.jl
    module_name = "TM-Node-$(node_id)-$(tm_idx)"
    och_name = "$(module_name)-OCH$(mode_idx)"
    
    rules = []
    
    # Disable specific optical channel (matches config_rules.jl format)
    push!(rules, _custom_rule(
        "/components/component/$(och_name)/properties/property/OCH_ENABLED/config",
        Dict("name" => "OCH_ENABLED", "value" => false)
    ))
    
    # Disable transmission module (matches config_rules.jl path)
    push!(rules, _custom_rule(
        "/components/component/$(module_name)/transceiver/config/enabled",
        false
    ))
    
    success = add_config_rule!(sdn.api_url, tm_uuid, rules)
    
    if success
        verbose && println("✓ TeraFlow: Disabled TM $tm_idx optical channel $mode_idx")
        return ReturnCodes.SUCCESS
    else
        verbose && @warn "✗ TeraFlow: Failed to disable TM $tm_idx optical channel $mode_idx"
        return ReturnCodes.FAIL
    end
end

# ═══════════════════════════════════════════════════════════════════════════════
# LINK STATE MANAGEMENT - Enable/Disable Link Operating States
# ═══════════════════════════════════════════════════════════════════════════════

"""
$(TYPEDSIGNATURES)
Set Link Operating State Hook - enables/disables link via TeraFlow
"""
function MINDFul.setlinkstate!(sdn::TeraflowSDN, oxcview::OXCView, edge::Edge, operatingstate::Bool)

    src_node = Graphs.src(edge)
    dst_node = Graphs.dst(edge)

    # 1. locate the shared OLS device that belongs to this node pair
    a, b = sort((src_node, dst_node))                 # low, high
    ols_key = (a, b, :shared_ols)

    if !haskey(sdn.device_map, ols_key)
        @warn "Shared OLS device not found for nodes $src_node, $dst_node"
        return ReturnCodes.FAIL
    end
    ols_uuid = sdn.device_map[ols_key]

    # 2. build a human-readable key for the list-entry
    path = "/link-state/edge-$(src_node)-$(dst_node)/config"

    # 3. push the rule
    rule = _custom_rule(path,
        Dict("src"     => src_node,
             "dest"    => dst_node,
             "enabled" => operatingstate))

    ok = add_config_rule!(sdn.api_url, ols_uuid, [rule])

    println(ok ? "✓" : "✗",
            " TeraFlow: link $src_node → $dst_node set ",
            operatingstate ? "UP" : "DOWN")

    return ok ? ReturnCodes.SUCCESS : ReturnCodes.FAIL
end

# ═══════════════════════════════════════════════════════════════════════════════
# FALLBACK HOOKS - Catch unhandled cases
# ═══════════════════════════════════════════════════════════════════════════════

"""
$(TYPEDSIGNATURES)
Fallback installation hook for unhandled resource types
"""
function MINDFul.insertreservationhook!(sdn::TeraflowSDN, resourceview, dagnodeid::UUID, reservationdescription; verbose::Bool = false)
    verbose && @warn "Fallback hook called for $(typeof(resourceview)) with $(typeof(reservationdescription))"
    return ReturnCodes.SUCCESS
end

"""
$(TYPEDSIGNATURES)
Fallback uninstallation hook for unhandled resource types
"""
function MINDFul.deletereservationhook!(sdn::TeraflowSDN, resourceview, dagnodeid::UUID; verbose::Bool = false)
    verbose && @warn "Fallback deletion hook called for $(typeof(resourceview))"
    return ReturnCodes.SUCCESS
end
