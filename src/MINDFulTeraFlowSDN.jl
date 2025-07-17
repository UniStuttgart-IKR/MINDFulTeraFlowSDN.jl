module MINDFulTeraFlowSDN

# 1. All imports at the top level
using ProtoBuf, JSON3, StructTypes, Oxygen, HTTP, UUIDs, JLD2, MINDFul
using ProtoBuf: OneOf  # for public export

# 2. All constants at the top level
const TFS_UUID_NAMESPACE = UUID("e2f3946f-1d0b-4aee-9e98-7d2b1862c287")

# 3. Public API exports
export TeraflowSDN, OneOf, Ctx,
       get_devices, get_device, get_contexts, get_topologies, put_device,
       print_device, add_config_rule!, post_context, post_topology_minimal,
       push_node_devices_to_tfs, post_device, ensure_post_device,
       get_links, get_link, post_link, ensure_post_link,
       connect_all_intra_node_devices, connect_all_inter_node_with_shared_ols, create_all_network_links,
       save_device_map, load_device_map!, stable_uuid,
       create_router_tm_link, create_tm_oxc_link, create_inter_node_connection_with_shared_ols,
       calculate_oxc_endpoint_needs, create_shared_ols_device, _to_speed_enum

# 4. Include sub-modules (order matters)
include("api/api.jl")
include("tfs/tfs_types.jl")

end # module MINDFulTeraFlowSDN
