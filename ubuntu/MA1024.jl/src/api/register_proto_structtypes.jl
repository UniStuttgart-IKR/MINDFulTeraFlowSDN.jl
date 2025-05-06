#
#  Register StructTypes mappings so that JSON3 <-> protobuf structs works
#  AND teach JSON3 how to turn the NBI’s “flat” ConfigRule JSON into the
#  proper OneOf wrapper.
#
using StructTypes, ProtoBuf

# --- plain enums / messages ---------------------------------------------------
StructTypes.StructType(::Type{Ctx.ConfigActionEnum}) = StructTypes.StringType()

for T in (Ctx.Uuid, Ctx.DeviceId,
          Ctx.ConfigRule_Custom, Ctx.ConfigRule_ACL,
          Ctx.DeviceConfig,      Ctx.Device)
    StructTypes.StructType(::Type{T}) = StructTypes.Struct()
end

# ----------------------------------------------------------------------------- 
#  Custom constructor for ConfigRule
# ----------------------------------------------------------------------------- 
StructTypes.StructType(::Type{Ctx.ConfigRule}) = StructTypes.CustomStruct()

# ── 3. helpers ---------------------------------------------------------------
function _to_action(x)
    x isa Ctx.ConfigActionEnum.T && return x
    x isa Integer                && return Ctx.ConfigActionEnum.T(x)
    s   = String(x)                        # works for JSON3.String + normal str
    sym = Symbol(s)
    return hasproperty(Ctx.ConfigActionEnum, sym) ?
           getfield(Ctx.ConfigActionEnum, sym) :
           Ctx.ConfigActionEnum.CONFIGACTION_UNDEFINED
end

_struct_nt(d::Dict) = NamedTuple{Tuple(Symbol.(keys(d)))}(values(d))

# ── 4a. JSON  ➜  struct  (decode) --------------------------------------------
function _construct_cfg(raw)
    nt = raw isa Dict ? _struct_nt(raw) : raw

    act = haskey(nt, :action)      ? _to_action(nt.action) :
          haskey(nt, :action_enum) ? _to_action(nt.action_enum) :
                                    Ctx.ConfigActionEnum.CONFIGACTION_UNDEFINED

    # already wrapped
    if haskey(nt, :config_rule) && nt.config_rule !== nothing
        return Ctx.ConfigRule(act, nt.config_rule)
    end

    # nested custom / acl
    if haskey(nt, :custom) && nt.custom !== nothing
        c = nt.custom isa Dict ? _struct_nt(nt.custom) : nt.custom
        return Ctx.ConfigRule(act,
               OneOf(:custom,
                     Ctx.ConfigRule_Custom(c.resource_key,
                                           c.resource_value)))
    elseif haskey(nt, :acl) && nt.acl !== nothing
        a = nt.acl isa Dict ? _struct_nt(nt.acl) : nt.acl
        return Ctx.ConfigRule(act,
               OneOf(:acl,
                     Ctx.ConfigRule_ACL(a.endpoint_id,
                                        a.rule_set)))
    end

    # flat keys
    if haskey(nt, :resource_key) && haskey(nt, :resource_value)
        return Ctx.ConfigRule(act,
               OneOf(:custom,
                     Ctx.ConfigRule_Custom(nt.resource_key,
                                           nt.resource_value)))
    end

    return Ctx.ConfigRule(act, nothing)
end

StructTypes.construct(::Type{Ctx.ConfigRule}, nt::NamedTuple) = _construct_cfg(nt)
StructTypes.construct(::Type{Ctx.ConfigRule}, d::Dict)        = _construct_cfg(d)

# ── 4b. struct  ➜  JSON  (encode) --------------------------------------------
function StructTypes.lower(x::Ctx.ConfigRule)
    if x.config_rule === nothing
        return (; action = string(x.action))
    end

    if x.config_rule.name === :custom
        cr = x.config_rule[]
        return (; action = string(x.action),
                custom = (;
                    resource_key   = cr.resource_key,
                    resource_value = cr.resource_value))
    elseif x.config_rule.name === :acl
        ar = x.config_rule[]
        return (; action = string(x.action),
                acl = (;
                    endpoint_id = ar.endpoint_id,
                    rule_set    = ar.rule_set))
    end
end

# ── 5. struct → JSON for Location  (flatten oneof) ---------------------------
function StructTypes.lower(loc::Ctx.Location)
    # NB: only one arm is ever set; check in priority order
    if loc.region         != ""
        return (; region          = loc.region)
    elseif loc.gps_position !== nothing
        return (; gps_position    = loc.gps_position)
    elseif loc.interface    != ""
        return (; interface       = loc.interface)
    elseif loc.circuit_pack != ""
        return (; circuit_pack    = loc.circuit_pack)
    else
        return NamedTuple()   # empty object {}
    end
end