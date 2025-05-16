using MA1024, MA1024.TFS

context_uuid = "admin3"
topology_uuid = "topo2"

ctx = minimal_tfs_context(context_uuid)
topo = minimal_tfs_topology(context_uuid, topology_uuid)

# ok_ctx = post_context(ctx)
# println(ok_ctx ? "✓ Context POSTed" : "✗ Context POST failed")

ok_topo = post_topology_minimal(context_uuid, topo)
println(ok_topo ? "✓ Topology POSTed" : "✗ Topology POST failed")