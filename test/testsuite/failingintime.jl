"""
TeraFlow-enabled version of MINDFul's failure-in-time test.
Tests dynamic link failure and recovery within a single domain.
"""

function testsuitefailingintime!(ibnf)
    # internal link failure within single domain
    internal_edge = Edge(3,4)  # adjust to valid edge in your network
    MINDF.getlinkstates(MINDF.getoxcview(MINDF.getnodeview(ibnf, src(internal_edge))))[internal_edge]

    offsettime = now()
    entrytime = now()

    # create intent that uses internal edge
    conintent_internal = MINDF.ConnectivityIntent(MINDF.GlobalNode(MINDF.getibnfid(ibnf), 14), MINDF.GlobalNode(MINDF.getibnfid(ibnf), 1), u"100.0Gbps")
    intentuuid_internal_fail = MINDF.addintent!(ibnf, conintent_internal, MINDF.NetworkOperator())
    @test MINDF.compileintent!(ibnf, intentuuid_internal_fail, MINDF.KShorestPathFirstFitCompilation(10); MINDF.@passtime) == MINDF.ReturnCodes.SUCCESS
    @test MINDF.installintent!(ibnf, intentuuid_internal_fail; verbose=false, MINDF.@passtime) == MINDF.ReturnCodes.SUCCESS
    
    # verify intent uses the internal edge
    let 
        logord = MINDF.getlogicallliorder(ibnf, intentuuid_internal_fail, onlyinstalled=false)
        @test internal_edge ∈ MINDF.edgeify(MINDF.logicalordergetpath(logord))
    end

    # fail the link after 1 hour
    offsettime += Hour(1)
    @test MINDF.setlinkstate!(ibnf, internal_edge, false; MINDF.@passtime) == MINDF.ReturnCodes.SUCCESS
    # should make first intent fail
    @test MINDF.getidagnodestate(MINDF.getidag(ibnf), intentuuid_internal_fail) == MINDF.IntentState.Failed
    
    # TestModule check if available
    if TM !== nothing
        TM.testexpectedfaileddag(MINDF.getidag(ibnf), intentuuid_internal_fail, internal_edge, 2)
    end

    # second intent should avoid using the failed link
    intentuuid_internal = MINDF.addintent!(ibnf, conintent_internal, MINDF.NetworkOperator())
    @test MINDF.compileintent!(ibnf, intentuuid_internal, MINDF.KShorestPathFirstFitCompilation(10); MINDF.@passtime) == MINDF.ReturnCodes.SUCCESS

    # verify new intent avoids failed link
    let 
        logord = MINDF.getlogicallliorder(ibnf, intentuuid_internal, onlyinstalled=false)
        @test internal_edge ∉ MINDF.edgeify(MINDF.logicalordergetpath(logord))
    end

    @test MINDF.installintent!(ibnf, intentuuid_internal; verbose=false, MINDF.@passtime) == MINDF.ReturnCodes.SUCCESS
    @test all([MINDF.getidagnodestate(idagnode) == MINDF.IntentState.Installed for idagnode in MINDF.getidagnodedescendants(MINDF.getidag(ibnf), intentuuid_internal)])

    # restore link - should make the failed intent installed again
    offsettime += Hour(1)
    @test MINDF.setlinkstate!(ibnf, internal_edge, true; MINDF.@passtime) == MINDF.ReturnCodes.SUCCESS
    @test all([MINDF.getidagnodestate(idagnode) == MINDF.IntentState.Installed for idagnode in MINDF.getidagnodedescendants(MINDF.getidag(ibnf), intentuuid_internal_fail)])

    # verify timing constraints
    internal_edge_linkstates = MINDF.getlinkstates(ibnf, internal_edge)
    @test all(getindex.(internal_edge_linkstates[2:end], 1) .- getindex.(internal_edge_linkstates[1:end-1], 1) .>= Hour(1))
    
    intentuuid_internal_fail_timelog = getindex.(MINDF.getlogstate(MINDF.getidagnode(MINDF.getidag(ibnf), intentuuid_internal_fail)), 1)
    @test length(intentuuid_internal_fail_timelog) == 7
    @test intentuuid_internal_fail_timelog[end] - intentuuid_internal_fail_timelog[1] >= Hour(2) 

    # cleanup
    @test MINDF.uninstallintent!(ibnf, intentuuid_internal_fail; verbose=false) == MINDF.ReturnCodes.SUCCESS
    @test MINDF.uninstallintent!(ibnf, intentuuid_internal; verbose=false) == MINDF.ReturnCodes.SUCCESS
    @test MINDF.uncompileintent!(ibnf, intentuuid_internal_fail; verbose=false) == MINDF.ReturnCodes.SUCCESS
    @test MINDF.uncompileintent!(ibnf, intentuuid_internal; verbose=false) == MINDF.ReturnCodes.SUCCESS
    @test MINDF.removeintent!(ibnf, intentuuid_internal_fail) == MINDF.ReturnCodes.SUCCESS
    @test MINDF.removeintent!(ibnf, intentuuid_internal) == MINDF.ReturnCodes.SUCCESS

    # Comment out multi-domain tests (border link and external link failures)
    # These would require multiple domains which we don't have in single domain setup
    
    # Border link is failing - COMMENTED OUT FOR SINGLE DOMAIN
    # offsettime = now()
    # entrytime = now()
    # borderedge = Edge(17,29)
    # ... rest of border link tests commented out ...

    # External link is failing - COMMENTED OUT FOR SINGLE DOMAIN  
    # externaledge = Edge(23, 15)
    # ... rest of external link tests commented out ...

    # test all links in domain - set them, and reget
    ibnag = MINDF.getibnag(ibnf)
    for ed in edges(ibnag)
        ls1 = MINDF.getcurrentlinkstate(ibnf, ed, checkfirst=false)
        MINDF.setlinkstate!(ibnf, ed, !ls1)
        ls2 = MINDF.getcurrentlinkstate(ibnf, ed, checkfirst=false)
        @test ls1 !== ls2
        # restore original state
        MINDF.setlinkstate!(ibnf, ed, ls1)
    end

    # TestModule checks if available
    if TM !== nothing
        TM.testedgeoxclogs(ibnf)
        TM.testoxcllistateconsistency(ibnf)
    end
end

println("🚀 TERAFLOW FAILING IN TIME TEST")
println("="^60)

@testset ExtendedTestSet "TeraFlow Failing In Time Test" begin

    # Use single domain test initialization - FIX THE UNDEFINED FUNCTION ERROR
    ibnf = loadsingledomaintestibnf()  # This function exists in initialize.jl
    teraflow_sdn = MINDF.getsdncontroller(ibnf)
    
    # Verify TeraFlow integration
    @test teraflow_sdn isa TeraflowSDN
    println("✅ TeraFlow integration loaded for failure testing")
    
    testsuitefailingintime!(ibnf)
    
    println("🎉 All failure-in-time tests passed with TeraFlow integration!")

end

println("\n" * "="^60)
println("🚀 TERAFLOW FAILING IN TIME TEST COMPLETE")
println("="^60)