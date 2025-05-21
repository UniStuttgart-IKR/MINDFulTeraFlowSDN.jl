using MA1024, MA1024.TFS

context_uuid = "admin3"
topology_uuid = "topo2"

ctx = minimal_tfs_context(context_uuid)
topo = minimal_tfs_topology(context_uuid, topology_uuid)

api_url = "http://127.0.0.1:80/tfs-api"

# contexts_json = get_contexts(api_url)
# println("Contexts: $contexts_json")
# contexts = contexts_json["contexts"]

# # Extract all context UUIDs
# context_uuids = [ctx["context_id"]["context_uuid"]["uuid"] for ctx in contexts]

# println("Context UUIDs: ", context_uuids)

# # For each context UUID, get and print its topologies
# for context_uuid in context_uuids
#     topologies = get_topologies(api_url, context_uuid)
#     println("Topologies for context $context_uuid: $topologies")
# end

ok_ctx = post_context(api_url, ctx)
println(ok_ctx ? "✓ Context POSTed" : "✗ Context POST failed")

# ok_topo = post_topology_minimal(context_uuid, topo)
# println(ok_topo ? "✓ Topology POSTed" : "✗ Topology POST failed")