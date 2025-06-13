module MA1024
using ProtoBuf, JSON3, StructTypes, Oxygen, HTTP, UUIDs
include("api/api.jl")          # <- pulls every file above
include("tfs/tfs_types.jl")    # <- pulls every file above
using ProtoBuf: OneOf          # bring it into MA1024's scope   

# public surface --------------------------------------------------------------
export TeraFlowSDN, OneOf, Ctx,
        get_devices, get_device, get_contexts, get_topologies, put_device,
        print_device, add_config_rule!, post_context, post_topology_minimal,
        push_node_devices_to_tfs, post_device, ensure_post_device,
        get_links, get_link, post_link, ensure_post_link,  # Add link functions
        connect_all_intra_node_devices, connect_all_ols_inter_node, create_all_network_links, # Updated network linking functions
        save_device_map, load_device_map!,  # Add device map functions
        start, stop               # from Server.jl
end