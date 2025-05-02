using StructTypes

StructTypes.StructType(::Type{Ctx.ConfigActionEnum}) = StructTypes.StringType()

for T in (Ctx.Uuid, Ctx.DeviceId, Ctx.ConfigRule_Custom,
          Ctx.ConfigRule, Ctx.DeviceConfig, Ctx.Device)
    StructTypes.StructType(::Type{T}) = StructTypes.Struct()
end
