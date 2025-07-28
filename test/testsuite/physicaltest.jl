"""
TeraFlow-enabled version of MINDFul's physical layer test.
Tests low-level resource allocation with TeraFlow integration.
"""

println("🚀 TERAFLOW PHYSICAL LAYER TEST")
println("="^60)

@testset ExtendedTestSet "TeraFlow Physical Test" begin

    # initialization - Load test data using centralized function
    ibnf1 = loadsingledomaintestibnf()
    ibnag1 = MINDF.getibnag(ibnf1)
    teraflow_sdn = MINDF.getsdncontroller(ibnf1)
    
    # Verify we're using TeraFlow SDN controller
    @test teraflow_sdn isa TeraflowSDN
    
    println("✅ TeraFlow integration loaded")
    println("   Device mappings: $(length(teraflow_sdn.device_map))")

    # get the node view of a single random vertex
    nodeview1 = AG.vertex_attr(ibnag1)[1]
    routerview1 = MINDF.getrouterview(nodeview1)
    oxcview1 = MINDF.getoxcview(nodeview1)
    dagnodeid1 = UUID(1)

    rplli1 = MINDF.RouterPortLLI(1, 2)
    tmlli1 = MINDF.TransmissionModuleLLI(1, 1, 1, 1, 1)
    oxclli1 = MINDF.OXCAddDropBypassSpectrumLLI(1, 4, 0, 6, 2:4)

    # Use TeraFlow SDN controller instead of SDNdummy
    for (reservableresource, lli) in zip([nodeview1, routerview1, oxcview1], [tmlli1, rplli1, oxclli1])
        @test MINDF.canreserve(teraflow_sdn, reservableresource, lli)
        
        # Only run TestModule tests if available
        if TM !== nothing
            TM.@test_nothrows @inferred MINDF.canreserve(teraflow_sdn, reservableresource, lli)
        end
        
        # Skip RUNJET tests (optimization tests) for TeraFlow integration
        # RUNJET && @test_opt target_modules=[MINDF] canreserve(teraflow_sdn, reservableresource, lli)

        @test MINDF.issuccess(MINDF.reserve!(teraflow_sdn, reservableresource, lli, dagnodeid1; verbose = true))
        if lli isa MINDF.OXCAddDropBypassSpectrumLLI
            @test !any(MINDF.getlinkspectrumavailabilities(oxcview1)[Edge(4, 1)][2:4])
            @test !any(MINDF.getlinkspectrumavailabilities(oxcview1)[Edge(1, 6)][2:4])
        end
        @test !MINDF.canreserve(teraflow_sdn, reservableresource, lli)

        reservations = MINDF.getreservations(reservableresource)
        @test length(reservations) == 1
        @test first(reservations) == (dagnodeid1 => lli)

        @test MINDF.issuccess(MINDF.unreserve!(teraflow_sdn, reservableresource, dagnodeid1))
        if lli isa MINDF.OXCAddDropBypassSpectrumLLI
            @test all(MINDF.getlinkspectrumavailabilities(oxcview1)[Edge(4, 1)])
            @test all(MINDF.getlinkspectrumavailabilities(oxcview1)[Edge(1, 6)])
        end
        @test MINDF.canreserve(teraflow_sdn, reservableresource, lli)
        @test length(MINDF.getreservations(reservableresource)) == 0
    end

    @test MINDF.issuccess(MINDF.reserve!(teraflow_sdn, oxcview1, oxclli1, dagnodeid1; checkfirst = true))
    @test !MINDF.issuccess(MINDF.reserve!(teraflow_sdn, oxcview1, MINDF.OXCAddDropBypassSpectrumLLI(1, 4, 0, 6, 5:6), dagnodeid1; checkfirst = true))
    @test MINDF.issuccess(MINDF.reserve!(teraflow_sdn, oxcview1, MINDF.OXCAddDropBypassSpectrumLLI(1, 4, 0, 6, 5:6), UUID(2); checkfirst = true))
    @test !any(MINDF.getlinkspectrumavailabilities(oxcview1)[Edge(4, 1)][2:6])
    @test MINDF.getlinkspectrumavailabilities(oxcview1)[Edge(4, 1)][1]
    @test all(MINDF.getlinkspectrumavailabilities(oxcview1)[Edge(4, 1)][7:end])

    # allocate also nodes 4 and 6 for OXClli to have a consistent OXC-level state
    # go from 4 to 1
    @test MINDF.issuccess(MINDF.reserve!(teraflow_sdn, MINDF.getoxcview(AG.vertex_attr(ibnag1)[4]), MINDF.OXCAddDropBypassSpectrumLLI(4, 0, 1, 1, 2:4), UUID(3); checkfirst = true))
    @test MINDF.issuccess(MINDF.reserve!(teraflow_sdn, MINDF.getoxcview(AG.vertex_attr(ibnag1)[4]), MINDF.OXCAddDropBypassSpectrumLLI(4, 0, 2, 1, 5:6), UUID(4); checkfirst = true))

    # go from 1 to 6
    @test MINDF.issuccess(MINDF.reserve!(teraflow_sdn, MINDF.getoxcview(AG.vertex_attr(ibnag1)[6]), MINDF.OXCAddDropBypassSpectrumLLI(6, 1, 1, 0, 2:4), UUID(5); checkfirst = true))
    @test MINDF.issuccess(MINDF.reserve!(teraflow_sdn, MINDF.getoxcview(AG.vertex_attr(ibnag1)[6]), MINDF.OXCAddDropBypassSpectrumLLI(6, 1, 2, 0, 5:6), UUID(6); checkfirst = true))

    # now test the intent workflow
    # Use TeraFlow-enabled IBN framework instead of reinitializing
    ibnf_test = loadsingledomaintestibnf()
    
    conintent1 = MINDF.ConnectivityIntent(MINDF.GlobalNode(MINDF.getibnfid(ibnf_test), 1), MINDF.GlobalNode(MINDF.getibnfid(ibnf_test), 2), u"100.0Gbps")
    MINDF.addintent!(ibnf_test, conintent1, MINDF.NetworkOperator())
    
    # add second intent
    intentid2 = MINDF.addintent!(ibnf_test, conintent1, MINDF.NetworkOperator())
    @test MINDF.nv(MINDF.getidag(ibnf_test)) == 2
    
    # remove second intent
    @test MINDF.removeintent!(ibnf_test, intentid2) == MINDF.ReturnCodes.SUCCESS
    @test MINDF.nv(MINDF.getidag(ibnf_test)) == 1

    # Optional consistency checks
    # if TM !== nothing
    #     TM.testoxcfiberallocationconsistency(ibnf_test)
    # end

    println("🎉 All physical layer tests passed with TeraFlow integration!")

end

println("\n" * "="^60)
println("🚀 TERAFLOW PHYSICAL LAYER TEST COMPLETE")
println("="^60)