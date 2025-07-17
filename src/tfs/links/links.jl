"""
General function to create all network links
"""

"""
    create_all_network_links(sdn::TeraFlowSDN, nodeviews) → Tuple{Int, Int}

Complete network linking function that:
1. Creates all intra-node connections: Router ↔ TM1 ↔ OXC
2. Creates all inter-node connections with shared OLS devices between OXC pairs
3. Applies link states from OXC views to shared OLS devices
"""
function create_all_network_links(sdn::TeraflowSDN, nodeviews)
    println("\n🔧 CREATING ALL NETWORK LINKS")
    println("="^50)
    
    # Phase 1: Intra-node links (Router ↔ TM1 ↔ OXC)
    println("\n📍 Phase 1: Intra-Node Links")
    intra_links = connect_all_intra_node_devices(sdn)
    
    # Phase 2: Inter-node links with shared OLS (OXC ↔ SharedOLS ↔ OXC)
    println("\n🌐 Phase 2: Inter-Node Links with Shared OLS")
    inter_links = connect_all_inter_node_with_shared_ols(sdn, nodeviews)
    
    # Phase 3: Apply link states to shared OLS devices
    println("\n🔗 Phase 3: Link State Configuration")
    linkstate_count = build_and_apply_linkstate_rules!(sdn, nodeviews)
    
    return (intra_links, inter_links)
end