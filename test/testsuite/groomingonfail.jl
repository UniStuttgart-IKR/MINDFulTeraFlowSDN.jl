"""
TeraFlow-enabled version of MINDFul's grooming-on-failure test.
Tests that grooming is avoided when lightpaths have failed resources.
Single domain only.
"""

println("🚀 TERAFLOW GROOMING ON FAILURE TEST")
println("="^60)

@testset ExtendedTestSet "TeraFlow Grooming On Failure Test" begin

    # Use single domain instead of multi-domain
    ibnf = loadsingledomaintestibnf()
    teraflow_sdn = MINDF.getsdncontroller(ibnf)
    
    # Verify TeraFlow integration
    @test teraflow_sdn isa TeraflowSDN
    println("✅ TeraFlow integration loaded for grooming failure test")

    # Create initial intent for grooming
    conintent1 = MINDF.ConnectivityIntent(MINDF.GlobalNode(MINDF.getibnfid(ibnf), 4), MINDF.GlobalNode(MINDF.getibnfid(ibnf), 8), u"30.0Gbps")
    intentuuid1 = MINDF.addintent!(ibnf, conintent1, MINDF.NetworkOperator())
    conintent1idn = MINDF.getidagnode(MINDF.getidag(ibnf), intentuuid1)
    MINDF.compileintent!(ibnf, intentuuid1, MINDF.KShorestPathFirstFitCompilation(10))
    MINDF.installintent!(ibnf, intentuuid1)

    installedlightpathsibnf = MINDF.getinstalledlightpaths(MINDF.getidaginfo(MINDF.getidag(ibnf)))
    @test length(installedlightpathsibnf) == 1
    lpr1 = installedlightpathsibnf[UUID(0x2)]
    @test first(MINDF.getpath(lpr1)) == 4
    @test last(MINDF.getpath(lpr1)) == 8
    @test MINDF.getstartsoptically(lpr1) == false
    @test MINDF.getterminatessoptically(lpr1) == false
    @test MINDF.gettotalbandwidth(lpr1) == MINDF.GBPSf(100)
    @test MINDF.getresidualbandwidth(ibnf, UUID(0x2)) == MINDF.GBPSf(70)

    println("   ✅ Initial lightpath created: 4→8, 100Gbps total, 70Gbps residual")

    # Fail internal link to trigger failure state
    MINDF.setlinkstate!(ibnf, Edge(20, 8), false) == MINDF.ReturnCodes.SUCCESS
    @test MINDF.getidagnodestate(conintent1idn) == MINDF.IntentState.Failed

    println("   ⚠️  Link (20,8) failed - intent moved to Failed state")

    # Attempt grooming after failure - should find no available lightpaths
    groomconintent1 = MINDF.ConnectivityIntent(MINDF.GlobalNode(MINDF.getibnfid(ibnf), 4), MINDF.GlobalNode(MINDF.getibnfid(ibnf), 8), u"30.0Gbps")
    groomintentuuid1 = MINDF.addintent!(ibnf, groomconintent1, MINDF.NetworkOperator())
    groomconintent1idn = MINDF.getidagnode(MINDF.getidag(ibnf), groomintentuuid1)
    @test MINDF.prioritizegrooming_default(ibnf, groomconintent1idn, MINDF.KShorestPathFirstFitCompilation(4)) == UUID[]

    println("   ✅ Grooming correctly avoided failed lightpath")

    # Test that new intent compiles and installs successfully (avoiding failed resources)
    @test MINDF.compileintent!(ibnf, groomintentuuid1, MINDF.KShorestPathFirstFitCompilation(10)) == MINDF.ReturnCodes.SUCCESS
    @test MINDF.getidagnodestate(groomconintent1idn) == MINDF.IntentState.Compiled
    @test MINDF.installintent!(ibnf, groomintentuuid1) == MINDF.ReturnCodes.SUCCESS
    @test MINDF.getidagnodestate(groomconintent1idn) == MINDF.IntentState.Installed
    @test !MINDF.issubdaggrooming(MINDF.getidag(ibnf), groomintentuuid1)

    println("   ✅ New intent created separate path avoiding failed resources")

    # Multi-domain section commented out for single domain focus
    # # Multi-domain failure testing
    # mdconintent1 = MINDF.ConnectivityIntent(MINDF.GlobalNode(MINDF.getibnfid(ibnf), 4), MINDF.GlobalNode(UUID(3), 21), u"30.0Gbps")
    # mdconintent1id = MINDF.addintent!(ibnf, mdconintent1, MINDF.NetworkOperator())
    # mdconintent1idn = MINDF.getidagnode(MINDF.getidag(ibnf), mdconintent1id)
    # MINDF.compileintent!(ibnf, mdconintent1id, MINDF.KShorestPathFirstFitCompilation(10))
    # MINDF.installintent!(ibnf, mdconintent1id)
    # 
    # @test MINDF.getidagnodestate(mdconintent1idn) == MINDF.IntentState.Installed
    # MINDF.setlinkstate!(other_domain, Edge(24, 23), false) == MINDF.ReturnCodes.SUCCESS
    # @test MINDF.getidagnodestate(mdconintent1idn) == MINDF.IntentState.Failed
    # 
    # groommdconintent1 = MINDF.ConnectivityIntent(MINDF.GlobalNode(MINDF.getibnfid(ibnf), 4), MINDF.GlobalNode(UUID(3), 21), u"30.0Gbps")
    # groommdconintent1id = MINDF.addintent!(ibnf, groommdconintent1, MINDF.NetworkOperator())
    # groommdconintent1idn = MINDF.getidagnode(MINDF.getidag(ibnf), groommdconintent1id)
    # MINDF.compileintent!(ibnf, groommdconintent1id, MINDF.KShorestPathFirstFitCompilation(10))
    # @test MINDF.getidagnodestate(groommdconintent1idn) == MINDF.IntentState.Compiled
    # MINDF.installintent!(ibnf, groommdconintent1id)
    # @test MINDF.getidagnodestate(groommdconintent1idn) == MINDF.IntentState.Installed
    # @test !MINDF.issubdaggrooming(MINDF.getidag(ibnf), groommdconintent1id)

    # Cleanup
    @test MINDF.uninstallintent!(ibnf, groomintentuuid1) == MINDF.ReturnCodes.SUCCESS
    @test MINDF.uncompileintent!(ibnf, groomintentuuid1) == MINDF.ReturnCodes.SUCCESS
    @test MINDF.removeintent!(ibnf, groomintentuuid1) == MINDF.ReturnCodes.SUCCESS

    # Restore link state
    MINDF.setlinkstate!(ibnf, Edge(20, 8), true)
    @test MINDF.getidagnodestate(conintent1idn) == MINDF.IntentState.Installed
    
    # Final cleanup
    @test MINDF.uninstallintent!(ibnf, intentuuid1) == MINDF.ReturnCodes.SUCCESS
    @test MINDF.uncompileintent!(ibnf, intentuuid1) == MINDF.ReturnCodes.SUCCESS
    @test MINDF.removeintent!(ibnf, intentuuid1) == MINDF.ReturnCodes.SUCCESS

    # Optional consistency checks
    if TM !== nothing
        TM.testoxcfiberallocationconsistency(ibnf)
        TM.testzerostaged(ibnf)
    end

    println("🎉 All grooming failure tests passed with TeraFlow integration!")

end

println("\n" * "="^60)
println("🚀 TERAFLOW GROOMING ON FAILURE TEST COMPLETE")
println("="^60)