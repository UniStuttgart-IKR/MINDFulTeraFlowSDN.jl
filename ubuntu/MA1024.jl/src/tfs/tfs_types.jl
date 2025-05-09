module TFS

export TeraflowSDN, configure_router_in_tfs

using MINDFul
using JSON3

struct TFSRouter
    end
# Define the TeraFlowSDN struct
struct TeraflowSDN <: MINDFul.AbstractSDNController
#    mapping::Dict{Int,Any} =Dict(ibnnodeid => Dict("router" => Dict(tfsuuid ... additional only tfs info)))
end


# Convert RouterView to a TFS config rule (example for port 0)
function routerview_to_configrule(routerview::MINDFul.RouterView)
    ports = routerview.portnumber
    return ports
end

export routerview_to_configrule

end