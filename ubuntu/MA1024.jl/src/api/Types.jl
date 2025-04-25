using StructTypes, JSON3

struct Uuid; uuid::String; end
struct DeviceId; device_uuid::Uuid; end

struct CustomRule
    resource_key::String
    resource_value::String
end

@enum ConfigAction CONFIGACTION_UNSPECIFIED=0 CONFIGACTION_SET=1 CONFIGACTION_DELETE=2   
StructTypes.StructType(::Type{ConfigAction}) = StructTypes.StringType()                   

struct ConfigRule
    action::ConfigAction
    custom::CustomRule
end

struct DeviceConfig; config_rules::Vector{ConfigRule}; end
struct DevicePayload
    device_id::DeviceId
    device_config::DeviceConfig
end

# register the *other* structs
for T in (Uuid, DeviceId, CustomRule, ConfigRule, DeviceConfig, DevicePayload)
    StructTypes.StructType(::Type{T}) = StructTypes.Struct()
end