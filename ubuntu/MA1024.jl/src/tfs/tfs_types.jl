"""
TeraFlow SDN integration module
"""

# Include all sub-modules in dependency order
include("core.jl")
include("config_rules.jl")
include("endpoints.jl") 
include("ols.jl")
include("devices.jl")
include("links/intra_node.jl")
include("links/inter_node.jl")
include("links/links.jl")
include("sdn_funcs.jl")