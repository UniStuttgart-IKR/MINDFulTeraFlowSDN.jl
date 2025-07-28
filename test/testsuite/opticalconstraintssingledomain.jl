"""
TeraFlow-enabled version of MINDFul's optical constraints test.
Tests optical networking constraints within a single domain.
"""

println("🚀 TERAFLOW OPTICAL CONSTRAINTS TEST")
println("="^60)

@testset ExtendedTestSet "TeraFlow Optical Constraints Test" begin

    # Use single domain instead of multi-domain
    ibnf1 = loadsingledomaintestibnf()
    teraflow_sdn = MINDF.getsdncontroller(ibnf1)
    
    # Verify TeraFlow integration
    @test teraflow_sdn isa TeraflowSDN
    println("✅ TeraFlow integration loaded")
    
    # Optional TestModule consistency checks
    if TM !== nothing
        TM.testlocalnodeisindex(ibnf1)
        TM.testoxcfiberallocationconsistency(ibnf1)
    end

    # Basic intra-domain intent
    conintent_intra = MINDF.ConnectivityIntent(MINDF.GlobalNode(MINDF.getibnfid(ibnf1), 2), MINDF.GlobalNode(MINDF.getibnfid(ibnf1), 19), u"100.0Gbps")
    intentuuid1 = MINDF.addintent!(ibnf1, conintent_intra, MINDF.NetworkOperator())
    @test MINDF.compileintent!(ibnf1, intentuuid1, MINDF.KShorestPathFirstFitCompilation(10)) == MINDF.ReturnCodes.SUCCESS
    @test MINDF.issatisfied(ibnf1, intentuuid1; onlyinstalled=false, noextrallis=true)
    @test MINDF.installintent!(ibnf1, intentuuid1) == MINDF.ReturnCodes.SUCCESS
    @test MINDF.issatisfied(ibnf1, intentuuid1; onlyinstalled=true, noextrallis=true)

    # intradomain with `OpticalTerminateConstraint`
    conintent_intra_optterm = MINDF.ConnectivityIntent(MINDF.GlobalNode(MINDF.getibnfid(ibnf1), 8), MINDF.GlobalNode(MINDF.getibnfid(ibnf1), 22), u"100.0Gbps", [MINDF.OpticalTerminateConstraint(MINDF.GlobalNode(MINDF.getibnfid(ibnf1), 22))])
    intentuuid2 = MINDF.addintent!(ibnf1, conintent_intra_optterm, MINDF.NetworkOperator())
    @test MINDF.compileintent!(ibnf1, intentuuid2, MINDF.KShorestPathFirstFitCompilation(10)) == MINDF.ReturnCodes.SUCCESS
    orderedllis2 = MINDF.getlogicallliorder(ibnf1, intentuuid2; onlyinstalled=false)
    @test MINDF.issatisfied(ibnf1, intentuuid2, orderedllis2; noextrallis=true)
    vorletzteglobalsnode = MINDF.getglobalnode(MINDF.getibnag(ibnf1), MINDF.getlocalnode(orderedllis2[end]))
    spectrumslots = MINDF.getspectrumslotsrange(orderedllis2[end])
    transmode = MINDF.gettransmissionmode(ibnf1, orderedllis2[2])
    transmodulename = MINDF.getname(MINDF.gettransmissionmodule(ibnf1, orderedllis2[2]))
    @test MINDF.installintent!(ibnf1, intentuuid2) == MINDF.ReturnCodes.SUCCESS
    @test MINDF.issatisfied(ibnf1, intentuuid2; onlyinstalled=true, noextrallis=true)

    conintent_intra_optini_finishprevious = MINDF.ConnectivityIntent(MINDF.GlobalNode(MINDF.getibnfid(ibnf1), 22), MINDF.GlobalNode(MINDF.getibnfid(ibnf1), 22), u"100.0Gbps", [MINDF.OpticalInitiateConstraint(vorletzteglobalsnode, spectrumslots, u"10.0km", MINDF.TransmissionModuleCompatibility(MINDF.getrate(transmode), MINDF.getspectrumslotsneeded(transmode), transmodulename))])
    intentuuid_intra_optini_finishprevious = MINDF.addintent!(ibnf1, conintent_intra_optini_finishprevious, MINDF.NetworkOperator())
    @test MINDF.compileintent!(ibnf1, intentuuid_intra_optini_finishprevious, MINDF.KShorestPathFirstFitCompilation(10)) == MINDF.ReturnCodes.SUCCESS
    @test MINDF.issatisfied(ibnf1, intentuuid_intra_optini_finishprevious; onlyinstalled=false, noextrallis=true)
    @test MINDF.installintent!(ibnf1, intentuuid_intra_optini_finishprevious) == MINDF.ReturnCodes.SUCCESS
    @test MINDF.issatisfied(ibnf1, intentuuid_intra_optini_finishprevious; onlyinstalled=true, noextrallis=true)

    # intradomain with `OpticalInitiateConstraint`
    conintent_intra_optini = MINDF.ConnectivityIntent(MINDF.GlobalNode(MINDF.getibnfid(ibnf1), 8), MINDF.GlobalNode(MINDF.getibnfid(ibnf1), 22), u"100.0Gbps", [MINDF.OpticalInitiateConstraint(MINDF.GlobalNode(MINDF.getibnfid(ibnf1), 2), 21:26, u"500.0km", MINDF.TransmissionModuleCompatibility(u"300.0Gbps", 6, "DummyFlexiblePluggable"))])
    intentuuid3 = MINDF.addintent!(ibnf1, conintent_intra_optini, MINDF.NetworkOperator())
    @test MINDF.compileintent!(ibnf1, intentuuid3, MINDF.KShorestPathFirstFitCompilation(10)) == MINDF.ReturnCodes.SUCCESS
    @test MINDF.issatisfied(ibnf1, intentuuid3; onlyinstalled=false, noextrallis=true)
    @test MINDF.installintent!(ibnf1, intentuuid3) == MINDF.ReturnCodes.SUCCESS
    @test MINDF.issatisfied(ibnf1, intentuuid3; onlyinstalled=true, noextrallis=true)

    oxcview1_2 = MINDF.getoxcview(MINDF.getnodeview(ibnf1, 2))
    oxcllifinishprevious3 = MINDF.OXCAddDropBypassSpectrumLLI(2, 0, 2, 8, 21:26)
    @test MINDF.canreserve(teraflow_sdn, oxcview1_2, oxcllifinishprevious3)
    @test MINDF.issuccess(MINDF.reserve!(teraflow_sdn, oxcview1_2, oxcllifinishprevious3, UUID(0xfffffff); verbose = true))

    # intradomain with `OpticalInitiateConstraint and OpticalTerminateConstraint`
    conintent_intra_optseg = MINDF.ConnectivityIntent(MINDF.GlobalNode(MINDF.getibnfid(ibnf1), 8), MINDF.GlobalNode(MINDF.getibnfid(ibnf1), 22), u"100.0Gbps", [MINDF.OpticalTerminateConstraint(MINDF.GlobalNode(MINDF.getibnfid(ibnf1), 22)), MINDF.OpticalInitiateConstraint(MINDF.GlobalNode(MINDF.getibnfid(ibnf1), 2), 31:34, u"500.0km", MINDF.TransmissionModuleCompatibility(u"100.0Gbps", 4, "DummyFlexiblePluggable"))])
    intentuuid4 = MINDF.addintent!(ibnf1, conintent_intra_optseg, MINDF.NetworkOperator())
    @test MINDF.compileintent!(ibnf1, intentuuid4, MINDF.KShorestPathFirstFitCompilation(10)) == MINDF.ReturnCodes.SUCCESS
    orderedllis4 = MINDF.getlogicallliorder(ibnf1, intentuuid4; onlyinstalled=false)
    @test MINDF.issatisfied(ibnf1, intentuuid4, orderedllis4; noextrallis=true)
    vorletzteglobalsnode4 = MINDF.getlocalnode(orderedllis4[end])
    @test MINDF.installintent!(ibnf1, intentuuid4) == MINDF.ReturnCodes.SUCCESS
    @test MINDF.issatisfied(ibnf1, intentuuid4; onlyinstalled=true, noextrallis=true)

    oxcllifinishprevious4 = MINDF.OXCAddDropBypassSpectrumLLI(2, 0, 2, 8, 31:34)
    @test MINDF.canreserve(teraflow_sdn, oxcview1_2, oxcllifinishprevious4)
    @test MINDF.issuccess(MINDF.reserve!(teraflow_sdn, oxcview1_2, oxcllifinishprevious4, UUID(0xffffff1); verbose = true))

    oxcview1_22 = MINDF.getoxcview(MINDF.getnodeview(ibnf1, 22))
    oxcllifinishprevious4_1 = MINDF.OXCAddDropBypassSpectrumLLI(22, vorletzteglobalsnode4, 2, 0, 31:34)
    @test MINDF.canreserve(teraflow_sdn, oxcview1_22, oxcllifinishprevious4_1)
    @test MINDF.issuccess(MINDF.reserve!(teraflow_sdn, oxcview1_22, oxcllifinishprevious4_1, UUID(0xffffff2); verbose = true))

    # Final consistency checks
    if TM !== nothing
        TM.testlocalnodeisindex(ibnf1)
        TM.testoxcfiberallocationconsistency(ibnf1)
        TM.testzerostaged(ibnf1)
    end

    println("🎉 All optical constraint tests passed with TeraFlow integration!")

end

println("\n" * "="^60)
println("🚀 TERAFLOW OPTICAL CONSTRAINTS TEST COMPLETE")
println("="^60)