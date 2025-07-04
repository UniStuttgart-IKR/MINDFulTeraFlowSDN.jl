"""
Configuration rule building and helpers
"""

"""
    _jsonify(x) → Dict | Array | primitive

Convert MINDFul view/LLI/helper objects to plain JSON-serialisable data.
Everything falls back to `x` itself if we do not recognise the type.
"""
_jsonify(x) = x                     # primitive fallback

# ── primitives ────────────────────────────────────────────────────────────
_jsonify(u::UUID)                     = string(u)

# ── basic helper structs ─────────────────────────────────────────────────
_jsonify(p::MINDFul.RouterPort)       = Dict("rate" => p.rate)

_jsonify(t::MINDFul.TransmissionMode) = Dict(
    "opticalreach"        => t.opticalreach,
    "rate"                => t.rate,
    "spectrumslotsneeded" => t.spectrumslotsneeded,
)

# ── LLIs ──────────────────────────────────────────────────────────────────
_jsonify(lli::MINDFul.RouterPortLLI) = Dict(
    "localnode"       => lli.localnode,
    "routerportindex" => lli.routerportindex,
)

_jsonify(lli::MINDFul.TransmissionModuleLLI) = Dict(
    "localnode"                       => lli.localnode,
    "transmissionmoduleviewpoolindex" => lli.transmissionmoduleviewpoolindex,
    "transmissionmodesindex"          => lli.transmissionmodesindex,
    "routerportindex"                 => lli.routerportindex,
    "adddropport"                     => lli.adddropport,
)

_jsonify(lli::MINDFul.OXCAddDropBypassSpectrumLLI) = Dict(
    "localnode"        => lli.localnode,
    "localnode_input"  => lli.localnode_input,
    "adddropport"      => lli.adddropport,
    "localnode_output" => lli.localnode_output,
    "spectrumslots"    => [first(lli.spectrumslotsrange), last(lli.spectrumslotsrange)],
)

# convenience for Dicts/Sets of LLIs
function _jsonify_table(tbl::Dict)
    return [Dict("uuid" => string(k), "lli" => _jsonify(v)) for (k,v) in tbl]
end
_jsonify_table(set::Set) = [_jsonify(x) for x in set]


function _wrap_to_object(path::AbstractString, payload)
    
    if payload isa AbstractDict
        return payload
    end
    
    field = last(split(path, '/'; keepempty=false))   # e.g. "ports"
    return Dict(field => payload)
end


function _custom_rule(path::AbstractString, payload)::Ctx.ConfigRule
    wrapped = _wrap_to_object(path, payload)
    return Ctx.ConfigRule(
        Ctx.ConfigActionEnum.CONFIGACTION_SET,
        OneOf(:custom, Ctx.ConfigRule_Custom(path, JSON3.write(wrapped))),
    )
end


build_config_rules(view) = Ctx.ConfigRule[]   # fallback 


function _push_rules(api_url::String, uuid::String, rules::Vector{Ctx.ConfigRule};
                    kind::Symbol="")
    isempty(rules) && return true                     # nothing to do
    ok = add_config_rule!(api_url, uuid, rules)
    ok || @warn "$kind rule update failed for $uuid"
    return ok
end


function _rules_from_table(base::AbstractString, tbl)::Vector{Ctx.ConfigRule}
    out = Ctx.ConfigRule[]
    idx = 1
    for (k, v) in tbl
        push!(out, _custom_rule("$base/$(string(k))", _jsonify(v)))
    end
    # `tbl` could be a Set, iterate separately
    if tbl isa Set
        for lli in tbl
            push!(out, _custom_rule("$base/$(idx)", _jsonify(lli)))
            idx += 1
        end
    end
    return out
end

# ───────── RouterView ───────────────────────────────────────────────────────
function build_config_rules(rv::MINDFul.RouterView)
    rules = Ctx.ConfigRule[]

    # Add the router as a network-instance
    push!(rules, _custom_rule(
        "/network-instances/network-instance/$(rv.router)",
        Dict("config" => Dict(
            "name" => rv.router,
            "type" => "DEFAULT_INSTANCE"  # "DEFAULT_INSTANCE" or "L3VRF", etc.
        ))
    ))

    # Configure each interface based on port info
    for (i, p) in enumerate(rv.ports)
        ifname = "eth$(i)"  # could be any naming convention you follow
        push!(rules, _custom_rule(
            "/interfaces/interface/$ifname",
            Dict(
                "config" => Dict("name" => ifname, "enabled" => false),
                "ethernet" => Dict(
                    "config" => Dict("port-speed" => _to_speed_enum(p.rate))
                )
            )
        ))
    end

    # Now go through port reservations and enable the reserved ports
    for (uuid, lli) in rv.portreservations
        # Router port indices are typically 1-based, convert to interface name
        ifname = "eth$(lli.routerportindex)"
        
        # Override the enabled status for this specific port
        push!(rules, _custom_rule(
            "/interfaces/interface/$ifname/config",
            Dict("enabled" => true)
        ))
    end

    return rules
end

function _to_speed_enum(rate)
    # Convert to string and extract the numeric part
    rate_str = string(rate)
    
    # Extract numbers from the string (handles "100.0 Gbps", "100Gbps", "100.0", etc.)
    rate_match = match(r"(\d+(?:\.\d+)?)", rate_str)
    if rate_match === nothing
        error("Cannot extract numeric value from rate: $rate")
    end
    
    rate_val = parse(Float64, rate_match.captures[1])
    
    # Match based on the numeric value for known speeds
    if rate_val == 1.0
        return "SPEED_1GB"
    elseif rate_val == 2.5
        return "SPEED_2500MB"
    elseif rate_val == 5.0
        return "SPEED_5GB"
    elseif rate_val == 10.0
        return "SPEED_10GB"
    elseif rate_val == 25.0
        return "SPEED_25GB"
    elseif rate_val == 40.0
        return "SPEED_40GB"
    elseif rate_val == 50.0
        return "SPEED_50GB"
    elseif rate_val == 100.0
        return "SPEED_100GB"
    elseif rate_val == 200.0
        return "SPEED_200GB"
    elseif rate_val == 400.0
        return "SPEED_400GB"
    elseif rate_val == 600.0
        return "SPEED_600GB"
    elseif rate_val == 800.0
        return "SPEED_800GB"
    else
        # For unsupported speeds, create a dynamic enum
        # Convert to integer if it's a whole number, otherwise keep decimal
        if rate_val == floor(rate_val)
            return "SPEED_$(Int(rate_val))GB"
        else
            # Replace decimal point with underscore for valid identifier
            rate_str_clean = replace(string(rate_val), "." => "_")
            return "SPEED_$(rate_str_clean)GB"
        end
    end
end


# ───────── OXCView ─────────────────────────────────────────────────────────
function build_config_rules(oxc::MINDFul.OXCView, nodeview::MINDFul.NodeView)
    rules = Ctx.ConfigRule[]
    
    # Map OXC to wavelength-router media channel
    push!(rules, _custom_rule(
        "/wavelength-router/media-channels/channel/$(string(typeof(oxc.oxc)))/config",
        Dict("name" => string(typeof(oxc.oxc)))
    ))
    
    # Create port mapping dictionaries to store node-to-port mappings
    input_port_mapping = Dict{Int, String}()
    output_port_mapping = Dict{Int, String}()
    
    # Create input ports based on actual input neighbors
    for neighbor in nodeview.nodeproperties.inneighbors  # Assuming this is available
        port_name = "node-$(neighbor)-input"
        input_port_mapping[neighbor] = port_name
        push!(rules, _custom_rule(
            "/wavelength-router/port-spectrum-power-profiles/port/$(port_name)/config",
            Dict("name" => port_name)
        ))
    end
    
    # Create output ports based on actual output neighbors
    for neighbor in nodeview.nodeproperties.outneighbors  # Assuming this is available
        port_name = "node-$(neighbor)-output"
        output_port_mapping[neighbor] = port_name
        push!(rules, _custom_rule(
            "/wavelength-router/port-spectrum-power-profiles/port/$(port_name)/config",
            Dict("name" => port_name)
        ))
    end
    
    # Store the mappings in the OXC configuration for reference
    push!(rules, _custom_rule(
        "/port-mappings",
        Dict(
            "input-mappings" => input_port_mapping,
            "output-mappings" => output_port_mapping
        )
    ))
    
    # Create port spectrum power profiles for each add/drop port
    for port_idx in 1:oxc.adddropportnumber
        port_name = "port-$(port_idx)"
        push!(rules, _custom_rule(
            "/wavelength-router/port-spectrum-power-profiles/port/$(port_name)/config",
            Dict("name" => port_name)
        ))
    end
    
    # Map switch reservations to media channels
    for (uuid, lli) in oxc.switchreservations
        channel_name = string(uuid)
        
        # Create the media channel
        push!(rules, _custom_rule(
            "/wavelength-router/media-channels/channel/$(channel_name)/config",
            Dict("name" => channel_name)
        ))
        
        # Map source and destination ports based on LLI logic
        # Handle the four cases: (input, adddrop, output)
        
        if lli.localnode_input != 0 && lli.adddropport == 0 && lli.localnode_output != 0
            # Case: (x, 0, y) - optical bypass from localnode x to localnode y
            input_port = get(input_port_mapping, lli.localnode_input, "node-$(lli.localnode_input)-input")
            output_port = get(output_port_mapping, lli.localnode_output, "node-$(lli.localnode_output)-output")
            
            push!(rules, _custom_rule(
                "/wavelength-router/media-channels/channel/$(channel_name)/source/config",
                Dict("port-name" => input_port)
            ))
            push!(rules, _custom_rule(
                "/wavelength-router/media-channels/channel/$(channel_name)/dest/config",
                Dict("port-name" => output_port)
            ))
            
        elseif lli.localnode_input == 0 && lli.adddropport != 0 && lli.localnode_output != 0
            # Case: (0, x, y) - adding optical signal from add port x to localnode y
            output_port = get(output_port_mapping, lli.localnode_output, "node-$(lli.localnode_output)-output")
            
            push!(rules, _custom_rule(
                "/wavelength-router/media-channels/channel/$(channel_name)/source/config",
                Dict("port-name" => "port-$(lli.adddropport)")
            ))
            push!(rules, _custom_rule(
                "/wavelength-router/media-channels/channel/$(channel_name)/dest/config",
                Dict("port-name" => output_port)
            ))
            
        elseif lli.localnode_input != 0 && lli.adddropport != 0 && lli.localnode_output == 0
            # Case: (x, y, 0) - dropping optical signal from localnode x to drop port y
            input_port = get(input_port_mapping, lli.localnode_input, "node-$(lli.localnode_input)-input")
            
            push!(rules, _custom_rule(
                "/wavelength-router/media-channels/channel/$(channel_name)/source/config",
                Dict("port-name" => input_port)
            ))
            push!(rules, _custom_rule(
                "/wavelength-router/media-channels/channel/$(channel_name)/dest/config",
                Dict("port-name" => "port-$(lli.adddropport)")
            ))
            
        elseif lli.localnode_input == 0 && lli.adddropport != 0 && lli.localnode_output == 0
            # Case: (0, x, 0) - add/drop port reservation only
            push!(rules, _custom_rule(
                "/wavelength-router/media-channels/channel/$(channel_name)/config",
                Dict("reserved-port" => "port-$(lli.adddropport)")
            ))
        end
        
        # Map spectrum slots to frequencies
        # Assuming 12.5 GHz slots starting from 193.1 THz (C-band start)
        base_freq_thz = 184.5
        slot_width_ghz = 12.5
        lower_slot = first(lli.spectrumslotsrange)
        upper_slot = last(lli.spectrumslotsrange)
        
        lower_freq = base_freq_thz + (lower_slot - 1) * slot_width_ghz / 1000
        upper_freq = base_freq_thz + upper_slot * slot_width_ghz / 1000
        
        push!(rules, _custom_rule(
            "/wavelength-router/media-channels/channel/$(channel_name)/spectrum-power-profile/distribution/config",
            Dict(
                "lower-frequency" => lower_freq,
                "upper-frequency" => upper_freq
            )
        ))
    end

    return rules
end

# ───────── TransmissionModuleView ─────────────────────────────────────────
function build_config_rules(tm::MINDFul.TransmissionModuleView; node_id::Int, tm_idx::Int)
    rules = Ctx.ConfigRule[]
    
    # Use the same module name format as in devices.jl
    module_name = "TM-Node-$(node_id)-$(tm_idx)"
    
    # Create the component entry for this transmission module
    push!(rules, _custom_rule(
        "/components/component/$(module_name)/config",
        Dict("name" => module_name)
    ))
    
    # Set the transmission module status (disabled by default)
    push!(rules, _custom_rule(
        "/components/component/$(module_name)/transceiver/config/enabled",
        false
    ))
    
    # Set the description (name field)
    push!(rules, _custom_rule(
        "/components/component/$(module_name)/config/description",
        tm.name
    ))
    
    # Set the cost
    push!(rules, _custom_rule(
        "/components/component/$(module_name)/properties/property/COST/config",
        Dict("name" => "COST", "value" => tm.cost)
    ))
    
    # Create properties for each transmission mode
    for (idx, mode) in enumerate(tm.transmissionmodes)
        och_name = "$(module_name)-OCH$(idx)"

        # Create the optical-channel component
        push!(rules, _custom_rule(
            "/components/component/$(och_name)/config",
            Dict("name" => och_name)
        ))

        # Link it as a sub-component of the transceiver
        push!(rules, _custom_rule(
            "/components/component/$(module_name)/subcomponents/subcomponent/$(och_name)/config",
            Dict("name" => och_name)
        ))

        # Pre-configure the operational-mode (idx as mode-ID)
        push!(rules, _custom_rule(
            "/components/component/$(och_name)/optical-channel/config/operational-mode",
            idx
        ))

        # Per-channel enable flag (property bag) – default OFF
        push!(rules, _custom_rule(
            "/components/component/$(och_name)/properties/property/OCH_ENABLED/config",
            Dict("name" => "OCH_ENABLED", "value" => false)
        ))

        # Store mode metadata as properties of the channel
        meta = Dict(
            "RATE_GBPS" => string(mode.rate),
            "SLOTS"     => string(mode.spectrumslotsneeded),
            "REACH_KM"  => string(mode.opticalreach)
        )
        for (suffix, val) in meta
            push!(rules, _custom_rule(
                "/components/component/$(och_name)/properties/property/$(suffix)/config",
                Dict("name" => suffix, "value" => val)
            ))
        end
    end

    # Apply Low-Level Intents (reservations) if present
    if hasfield(typeof(tm), :reservations)
        for (uuid, lli) in tm.reservations
            # Power ON the whole module
            push!(rules, _custom_rule(
                "/components/component/$(module_name)/transceiver/config/enabled",
                true
            ))

            # Enable the selected optical channel
            if 1 ≤ lli.transmissionmodesindex ≤ length(tm.transmissionmodes)
                och_sel = "$(module_name)-OCH$(lli.transmissionmodesindex)"
                push!(rules, _custom_rule(
                    "/components/component/$(och_sel)/properties/property/OCH_ENABLED/config/value",
                    true
                ))
            end
            
            # # Mirror router port index as a property if needed
            # if lli.routerportindex != 0
            #     push!(rules, _custom_rule(
            #         "/components/component/$(och_name)/properties/property/IFINDEX/config",
            #         Dict(
            #             "name" => "IFINDEX",
            #             "value" => string(lli.routerportindex)
            #         )
            #     ))
            # end
            
            # # Handle add/drop port mapping if specified
            # if lli.adddropport != 0
            #     port_name = "AD_DROP_$(lli.adddropport)"
            #     push!(rules, _custom_rule(
            #         "/wavelength-router/ports/port/$(port_name)/config",
            #         Dict(
            #             "name" => port_name,
            #             "type" => "ADD_DROP"
            #         )
            #     ))
            # end
        end
    end

    return rules
end