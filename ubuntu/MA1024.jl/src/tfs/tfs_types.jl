module TFS

export TeraflowSDN, configure_router_in_tfs

using MINDFul
using JSON3

# Define the TeraFlowSDN struct
struct TeraflowSDN <: MINDFul.AbstractSDNController
end


# Convert RouterView to a TFS config rule (example for port 0)
function routerview_to_configrule(routerview::MINDFul.RouterView)
    port = routerview.portnumber
    return port
end

export routerview_to_configrule

end