"""
TeraFlow-enabled version of MINDFul's grooming test.
Tests traffic grooming (sharing lightpaths between intents) with TeraFlow integration.
Single domain only.
"""

println("🚀 TERAFLOW GROOMING TEST")
println("="^60)

function testsuitegrooming!(ibnf)
    # internal
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

    groomconintent1 = MINDF.ConnectivityIntent(MINDF.GlobalNode(MINDF.getibnfid(ibnf), 4), MINDF.GlobalNode(MINDF.getibnfid(ibnf), 8), u"30.0Gbps")
    groomintentuuid1 = MINDF.addintent!(ibnf, groomconintent1, MINDF.NetworkOperator())
    groomconintent1idn = MINDF.getidagnode(MINDF.getidag(ibnf), groomintentuuid1)
    @test MINDF.prioritizegrooming_default(ibnf, groomconintent1idn, MINDF.KShorestPathFirstFitCompilation(4)) == [[UUID(0x2)]]
    MINDF.compileintent!(ibnf, groomintentuuid1, MINDF.KShorestPathFirstFitCompilation(10))
    @test MINDF.getidagnodestate(groomconintent1idn) == MINDF.IntentState.Compiled
    @test length(installedlightpathsibnf) == 1
    @test MINDF.getresidualbandwidth(ibnf, UUID(0x2); onlyinstalled=true) == MINDF.GBPSf(70)
    @test MINDF.getresidualbandwidth(ibnf, UUID(0x2); onlyinstalled=false) == MINDF.GBPSf(40)
    
    if TM !== nothing
        TM.testcompilation(ibnf, groomintentuuid1; withremote=false)
        TM.testinstallation(ibnf, intentuuid1; withremote=false)
    end

    @test MINDF.installintent!(ibnf, groomintentuuid1) == MINDF.ReturnCodes.SUCCESS
    
    if TM !== nothing
        TM.testinstallation(ibnf, intentuuid1; withremote=false)
        TM.testinstallation(ibnf, groomintentuuid1; withremote=false)
    end

    # uninstall one
    @test MINDF.uninstallintent!(ibnf, groomintentuuid1) == MINDF.ReturnCodes.SUCCESS
    @test MINDF.getidagnodestate(groomconintent1idn) == MINDF.IntentState.Compiled
    # all other remain installed
    @test all(x -> MINDF.getidagnodestate(x) == MINDF.IntentState.Installed, MINDF.getidagnodedescendants(MINDF.getidag(ibnf), intentuuid1; includeroot=true))
    
    if TM !== nothing
        TM.testinstallation(ibnf, intentuuid1; withremote=false)
    end

    # uninstall also the other one
    @test MINDF.uninstallintent!(ibnf, intentuuid1) == MINDF.ReturnCodes.SUCCESS
    @test all(x -> MINDF.getidagnodestate(x) == MINDF.IntentState.Compiled, MINDF.getidagnodes(MINDF.getidag(ibnf)))
    @test length(installedlightpathsibnf) == 0
    
    if TM !== nothing
        TM.testcompilation(ibnf, groomintentuuid1; withremote=false)
        TM.testcompilation(ibnf, intentuuid1; withremote=false)
    end

    # install the second
    @test MINDF.installintent!(ibnf, groomintentuuid1) == MINDF.ReturnCodes.SUCCESS
    @test all(x -> MINDF.getidagnodestate(x) == MINDF.IntentState.Installed, MINDF.getidagnodedescendants(MINDF.getidag(ibnf), groomintentuuid1; includeroot=true))
    @test MINDF.getidagnodestate(conintent1idn) == MINDF.IntentState.Compiled
    @test length(installedlightpathsibnf) == 1

    # uncompile the first one
    @test MINDF.uncompileintent!(ibnf, intentuuid1) == MINDF.ReturnCodes.SUCCESS
    @test MINDF.getidagnodestate(conintent1idn) == MINDF.IntentState.Uncompiled
    @test isempty(Graphs.neighbors(MINDF.getidag(ibnf), MINDF.getidagnodeidx(MINDF.getidag(ibnf), intentuuid1)))

    # compile again 
    @test MINDF.compileintent!(ibnf, intentuuid1, MINDF.KShorestPathFirstFitCompilation(10)) == MINDF.ReturnCodes.SUCCESS

    # uninstall the second
    @test MINDF.uninstallintent!(ibnf, groomintentuuid1) == MINDF.ReturnCodes.SUCCESS

    # uncompile the first one
    @test MINDF.uncompileintent!(ibnf, intentuuid1) == MINDF.ReturnCodes.SUCCESS

    # uncompile the second one
    @test MINDF.uncompileintent!(ibnf, groomintentuuid1) == MINDF.ReturnCodes.SUCCESS
    @test length(MINDF.getidagnodes(MINDF.getidag(ibnf))) == 2
    @test all(x -> MINDF.getidagnodestate(x) == MINDF.IntentState.Uncompiled, MINDF.getidagnodes(MINDF.getidag(ibnf)))

    # compile install the first one
    @test MINDF.compileintent!(ibnf, intentuuid1, MINDF.KShorestPathFirstFitCompilation(10)) == MINDF.ReturnCodes.SUCCESS
    @test MINDF.installintent!(ibnf, intentuuid1) == MINDF.ReturnCodes.SUCCESS

    # try grooming with lightpath and a new intent
    groomandnewconintent1 = MINDF.ConnectivityIntent(MINDF.GlobalNode(MINDF.getibnfid(ibnf), 22), MINDF.GlobalNode(MINDF.getibnfid(ibnf), 8), u"30.0Gbps")
    groomandnewconintent1id = MINDF.addintent!(ibnf, groomandnewconintent1, MINDF.NetworkOperator())
    @test MINDF.compileintent!(ibnf, groomandnewconintent1id, MINDF.KShorestPathFirstFitCompilation(10)) == MINDF.ReturnCodes.SUCCESS
    
    if TM !== nothing
        TM.testcompilation(ibnf, groomandnewconintent1id; withremote=false)
    end
    
    @test MINDF.issatisfied(ibnf, groomandnewconintent1id; onlyinstalled=false)
    @test MINDF.installintent!(ibnf, groomandnewconintent1id) == MINDF.ReturnCodes.SUCCESS
    
    if TM !== nothing
        TM.testinstallation(ibnf, groomandnewconintent1id; withremote=false)
    end
    
    @test MINDF.issatisfied(ibnf, groomandnewconintent1id; onlyinstalled=true)
    @test MINDF.issubdaggrooming(MINDF.getidag(ibnf), groomandnewconintent1id)
    @test length(installedlightpathsibnf) == 2

    # should be separate intent
    nogroomandnewconintent1 = MINDF.ConnectivityIntent(MINDF.GlobalNode(MINDF.getibnfid(ibnf), 5), MINDF.GlobalNode(MINDF.getibnfid(ibnf), 8), u"30.0Gbps")
    nogroomandnewconintent1id = MINDF.addintent!(ibnf, nogroomandnewconintent1, MINDF.NetworkOperator())
    @test MINDF.compileintent!(ibnf, nogroomandnewconintent1id, MINDF.KShorestPathFirstFitCompilation(10)) == MINDF.ReturnCodes.SUCCESS
    @test MINDF.installintent!(ibnf, nogroomandnewconintent1id) == MINDF.ReturnCodes.SUCCESS
    @test MINDF.issatisfied(ibnf, nogroomandnewconintent1id; onlyinstalled=true)
    @test !MINDF.issubdaggrooming(MINDF.getidag(ibnf), nogroomandnewconintent1id)

    nogroomandnewconintent1lpid = MINDF.getidagnodeid(MINDF.getfirst(x -> MINDF.getintent(x) isa MINDF.LightpathIntent, MINDF.getidagnodedescendants(MINDF.getidag(ibnf), nogroomandnewconintent1id)))
    @test MINDF.getresidualbandwidth(ibnf, nogroomandnewconintent1lpid) == MINDF.GBPSf(70)

    nogroomandnewconintent1_over = MINDF.ConnectivityIntent(MINDF.GlobalNode(MINDF.getibnfid(ibnf), 5), MINDF.GlobalNode(MINDF.getibnfid(ibnf), 8), u"80.0Gbps")
    nogroomandnewconintent1_overid = MINDF.addintent!(ibnf, nogroomandnewconintent1_over, MINDF.NetworkOperator())
    @test MINDF.compileintent!(ibnf, nogroomandnewconintent1_overid, MINDF.KShorestPathFirstFitCompilation(10)) == MINDF.ReturnCodes.SUCCESS
    @test MINDF.installintent!(ibnf, nogroomandnewconintent1_overid) == MINDF.ReturnCodes.SUCCESS
    @test !MINDF.issubdaggrooming(MINDF.getidag(ibnf), nogroomandnewconintent1_overid)

    nogroomandnewconintent1_down = MINDF.ConnectivityIntent(MINDF.GlobalNode(MINDF.getibnfid(ibnf), 5), MINDF.GlobalNode(MINDF.getibnfid(ibnf), 10), u"10.0Gbps")
    nogroomandnewconintent1_downid = MINDF.addintent!(ibnf, nogroomandnewconintent1_down, MINDF.NetworkOperator())
    @test MINDF.compileintent!(ibnf, nogroomandnewconintent1_downid, MINDF.KShorestPathFirstFitCompilation(10)) == MINDF.ReturnCodes.SUCCESS
    @test MINDF.installintent!(ibnf, nogroomandnewconintent1_downid) == MINDF.ReturnCodes.SUCCESS
    @test MINDF.issubdaggrooming(MINDF.getidag(ibnf), nogroomandnewconintent1_downid)

    if TM !== nothing
        TM.testzerostaged(ibnf)
    end

    # uncompile uninstall remove all
    for idagnode in MINDF.getnetworkoperatoridagnodes(MINDF.getidag(ibnf))
        if MINDF.getidagnodestate(idagnode) == MINDF.IntentState.Installed
            @test MINDF.uninstallintent!(ibnf, MINDF.getidagnodeid(idagnode)) == MINDF.ReturnCodes.SUCCESS
        end
        if MINDF.getidagnodestate(idagnode) == MINDF.IntentState.Compiled
            @test MINDF.uncompileintent!(ibnf, MINDF.getidagnodeid(idagnode)) == MINDF.ReturnCodes.SUCCESS
        end
        if MINDF.getidagnodestate(idagnode) == MINDF.IntentState.Uncompiled
            @test MINDF.removeintent!(ibnf, MINDF.getidagnodeid(idagnode)) == MINDF.ReturnCodes.SUCCESS
        end
    end

    @test iszero(MINDF.nv(MINDF.getidag(ibnf)))
    @test iszero(MINDF.ne(MINDF.getidag(ibnf)))

    # Multi-domain sections commented out for single domain testing
    # border intent 
    # cdintent1 = MINDF.ConnectivityIntent(MINDF.GlobalNode(MINDF.getibnfid(ibnf), 21), MINDF.GlobalNode(UUID(3), 25), u"10.0Gbps")
    # ... rest of multi-domain tests commented out ...

    if TM !== nothing
        TM.testoxcfiberallocationconsistency(ibnf)
        TM.testzerostaged(ibnf)
        TM.nothingisallocated(ibnf)
    end
    
    @test iszero(MINDF.nv(MINDF.getidag(ibnf)))
    @test iszero(MINDF.ne(MINDF.getidag(ibnf)))
end

@testset ExtendedTestSet "TeraFlow Grooming Test" begin
    # to test the following:
    # - do not groom if external lightpath is failed

    # Use single domain instead of multi-domain
    ibnf = loadsingledomaintestibnf()
    teraflow_sdn = MINDF.getsdncontroller(ibnf)
    
    # Verify TeraFlow integration
    @test teraflow_sdn isa TeraflowSDN
    println("✅ TeraFlow integration loaded for grooming test")
    
    testsuitegrooming!(ibnf)

    # Commented out multi-domain distributed test for single domain focus
    # ibnfs = loadmultidomaintestidistributedbnfs()
    # testsuitegrooming!(ibnfs)
    # MINDF.closeibnfserver(ibnfs)

    println("🎉 All grooming tests passed with TeraFlow integration!")

end

println("\n" * "="^60)
println("🚀 TERAFLOW GROOMING TEST COMPLETE")
println("="^60)