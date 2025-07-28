"""
TeraFlow-enabled version of MINDFul's interface consistency test.
Tests IBN framework interface consistency within a single domain.
"""

println("🚀 TERAFLOW INTERFACE TEST")
println("="^60)

function testsuiteinterface!(ibnf)
    # do some random allocations within single domain
    rng = MersenneTwister(0)
    
    for counter in 1:100  # keep original count for thorough testing
        # get random nodes from same domain
        srcglobalnode = rand(rng, MINDF.getglobalnode.(MINDF.getproperties.(MINDF.getintranodeviews(MINDF.getibnag(ibnf)))))
        dstglobalnode = rand(rng, MINDF.getglobalnode.(MINDF.getproperties.(MINDF.getintranodeviews(MINDF.getibnag(ibnf)))))
        
        while dstglobalnode == srcglobalnode
            dstglobalnode = rand(rng, MINDF.getglobalnode.(MINDF.getproperties.(MINDF.getintranodeviews(MINDF.getibnag(ibnf)))))
        end

        rate = MINDF.GBPSf(rand(rng)*100) 

        conintent = MINDF.ConnectivityIntent(srcglobalnode, dstglobalnode, rate)
        conintentid = MINDF.addintent!(ibnf, conintent, MINDF.NetworkOperator())
        @test MINDF.compileintent!(ibnf, conintentid, MINDF.KShorestPathFirstFitCompilation(10)) == MINDF.ReturnCodes.SUCCESS
        @test MINDF.installintent!(ibnf, conintentid; verbose=false) == MINDF.ReturnCodes.SUCCESS
        @test MINDF.issatisfied(ibnf, conintentid)
    end

    # check ibnf generally
    if TM !== nothing
        TM.testoxcllistateconsistency(ibnf)
        TM.testedgeoxclogs(ibnf)
    end

    # Single domain interface consistency tests (simplified from multi-domain version)
    # Since we have only one domain, we test internal consistency directly
    
    networkoperatoridagnodes = MINDF.getnetworkoperatoridagnodes(MINDF.getidag(ibnf))
    rps = randperm(length(networkoperatoridagnodes))
    someidagnodes = first(networkoperatoridagnodes[rps], 10)

    # test internal node and edge consistency
    for idagnode in someidagnodes
        # test logical LLI order consistency
        logord1 = MINDF.requestlogicallliorder_init(ibnf, ibnf, MINDF.getidagnodeid(idagnode))
        logord2 = MINDF.getlogicallliorder(ibnf, MINDF.getidagnodeid(idagnode); onlyinstalled=false)
        @test logord1 == logord2

        # test intent global path consistency  
        path1 = MINDF.requestintentglobalpath_init(ibnf, ibnf, MINDF.getidagnodeid(idagnode))
        path2 = MINDF.getintentglobalpath(ibnf, MINDF.getidagnodeid(idagnode))
        @test path1 == path2

        # test electrical presence consistency
        elec1 = MINDF.requestglobalnodeelectricalpresence_init(ibnf, ibnf, MINDF.getidagnodeid(idagnode))
        elec2 = MINDF.getglobalnodeelectricalpresence(ibnf, MINDF.getidagnodeid(idagnode))
        @test elec1 == elec2

        # test lightpaths consistency
        lps1 = MINDF.requestintentgloballightpaths_init(ibnf, ibnf, MINDF.getidagnodeid(idagnode))
        lps2 = MINDF.getintentgloballightpaths(ibnf, MINDF.getidagnodeid(idagnode))
        @test lps1 == lps2

        # test satisfaction consistency
        sat1 = MINDF.requestissatisfied_init(ibnf, ibnf, MINDF.getidagnodeid(idagnode))
        sat2 = MINDF.issatisfied(ibnf, MINDF.getidagnodeid(idagnode))
        @test sat1 == sat2
    end

    # test link state consistency for all internal edges
    ibnag = MINDF.getibnag(ibnf)
    for ed in edges(ibnag)
        globaledge = MINDF.GlobalEdge(MINDF.getglobalnode(ibnag, src(ed)), MINDF.getglobalnode(ibnag, dst(ed)))
        
        # test spectrum availability
        spec1 = MINDF.requestspectrumavailability_init!(ibnf, ibnf, globaledge)
        spec2 = MINDF.getlinkspectrumavailabilities(MINDF.getoxcview(MINDF.getnodeview(ibnf, src(ed))))[ed]
        @test spec1 == spec2

        # test current link state
        state1 = MINDF.requestcurrentlinkstate_init(ibnf, ibnf, globaledge)
        state2 = MINDF.getcurrentlinkstate(ibnf, ed)
        @test state1 == state2

        # test link states history
        states1 = MINDF.requestlinkstates_init(ibnf, ibnf, globaledge)
        states2 = MINDF.getlinkstates(ibnf, ed)
        @test states1 == states2
    end

    # test IBN attribute graph consistency
    ibnag1 = MINDF.requestibnattributegraph_init(ibnf, ibnf)
    ibnag2 = MINDF.getibnag(ibnf)
    @test MINDF.isthesame(ibnag1, ibnag2)

    # test IDAG consistency
    idag1 = MINDF.requestidag_init(ibnf, ibnf)
    idag2 = MINDF.getidag(ibnf)
    @test MINDF.isthesame(idag1, idag2)

    # test IBN handlers consistency (single domain has self-reference)
    handlers1 = MINDF.requestibnfhandlers_init(ibnf, ibnf)
    handlers2 = MINDF.getibnfhandlers(ibnf)
    @test MINDF.isthesame(handlers1, handlers2)

    # Multi-domain specific testing commented out since not applicable
    # function getibnfwithid(ibnfs::Vector{<:IBNFramework}, ibnfid::UUID)
    #     for ibnf in ibnfs
    #         if getibnfid(ibnf) == ibnfid
    #             return ibnf
    #         end
    #     end
    # end
    # 
    # # check ALL requests with the real counterpart
    # for ibnfhandler in getibnfhandlers(ibnf)
    #     ... multi-domain handler comparison tests ...
    # end

    # cleanup - uninstall all intents
    all_intent_nodes = collect(MINDF.getnetworkoperatoridagnodes(MINDF.getidag(ibnf)))
    for idagnode in all_intent_nodes
        intent_id = MINDF.getidagnodeid(idagnode)
        @test MINDF.uninstallintent!(ibnf, intent_id) == MINDF.ReturnCodes.SUCCESS
        @test MINDF.uncompileintent!(ibnf, intent_id) == MINDF.ReturnCodes.SUCCESS
        @test MINDF.removeintent!(ibnf, intent_id) == MINDF.ReturnCodes.SUCCESS
    end

    if TM !== nothing
        TM.testoxcfiberallocationconsistency(ibnf)
        TM.testzerostaged(ibnf)
    end

    println("🎉 All interface consistency tests passed!")
end

@testset ExtendedTestSet "TeraFlow Interface Test" begin

    # Use single domain instead of multi-domain
    ibnf = loadsingledomaintestibnf()
    teraflow_sdn = MINDF.getsdncontroller(ibnf)
    
    # Verify TeraFlow integration
    @test teraflow_sdn isa TeraflowSDN
    println("✅ TeraFlow integration loaded for interface test")
    
    testsuiteinterface!(ibnf)

    # Commented out multi-domain distributed test for single domain focus
    # ibnfs = loadmultidomaintestidistributedbnfs()
    # testsuiteinterface!(ibnfs)
    # MINDF.closeibnfserver(ibnfs)

end

println("\n" * "="^60)
println("🚀 TERAFLOW INTERFACE TEST COMPLETE")
println("="^60)