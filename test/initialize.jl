import JET
import JET: @test_opt
using Test, TestSetExtensions

using MINDFul
using MINDFulTeraFlowSDN
using Graphs
import AttributeGraphs as AG
using JLD2, UUIDs
using Unitful, UnitfulData
import Dates: now, Hour
import Random: MersenneTwister, randperm

const MINDF = MINDFul

import MINDFul: ReturnCodes, IBNFramework, getibnfhandlers, GlobalNode, ConnectivityIntent, addintent!, NetworkOperator, compileintent!, KShorestPathFirstFitCompilation, installintent!, uninstallintent!, uncompileintent!, getidag, getrouterview, getoxcview, RouterPortLLI, TransmissionModuleLLI, OXCAddDropBypassSpectrumLLI, canreserve, reserve!, getlinkspectrumavailabilities, getreservations, unreserve!, getibnfid, getidagnodestate, IntentState, getidagnodechildren, getidagnode, OpticalTerminateConstraint, getlogicallliorder, issatisfied, getglobalnode, getibnag, getlocalnode, getspectrumslotsrange, gettransmissionmode, getname, gettransmissionmodule, TransmissionModuleCompatibility, getrate, getspectrumslotsneeded, OpticalInitiateConstraint, getnodeview, getsdncontroller, removeintent!, getlinkstates, getcurrentlinkstate, setlinkstate!, logicalordercontainsedge, logicalordergetpath, edgeify, getintent, getidagnodeid, @passtime, getstaged, getidaginfo, getinstalledlightpaths, LightpathRepresentation, GBPSf, getresidualbandwidth, getfirst


TESTDIR = @__DIR__

# if you don't want JET tests do `push!(ARGS, "--nojet")` before `include`ing
RUNJET = !any(==("--nojet"), ARGS)

# get the test module from MINDFul
TM = Base.get_extension(MINDFul, :TestModule)
@test !isnothing(TM)

# Single domain test initialization for TeraFlow
function loadsingledomaintestibnf()
    # Load single domain data (same as MINDFul basic test)
    domains_name_graph = first(JLD2.load(TESTDIR*"/data/itz_IowaStatewideFiberMap-itz_Missouri__(1,9)-(2,3),(1,6)-(2,54),(1,1)-(2,21).jld2"))[2]
    ag1 = first(domains_name_graph)[2]
    ibnag1 = MINDF.default_IBNAttributeGraph(ag1)
    
    # Create TeraFlow SDN controller
    teraflow_sdn = TeraflowSDN()
    
    # Load existing device mappings if available
    if isfile(TESTDIR*"/data/device_map.jld2")
        load_device_map!(TESTDIR*"/data/device_map.jld2", teraflow_sdn)
    end
    
    # Create IBN framework with TeraFlow SDN controller
    operationmode = MINDF.DefaultOperationMode()
    ibnfid = AG.graph_attr(ibnag1)
    intentdag = MINDF.IntentDAG()
    ibnfhandlers = MINDF.AbstractIBNFHandler[]
    
    ibnf = MINDF.IBNFramework(operationmode, ibnfid, intentdag, ibnag1, ibnfhandlers, teraflow_sdn)
    
    return ibnf
end

function loadmultidomaintestibnfs()
    domains_name_graph = first(JLD2.load(TESTDIR*"/data/itz_IowaStatewideFiberMap-itz_Missouri-itz_UsSignal_addedge_24-23,23-15__(1,9)-(2,3),(1,6)-(2,54),(1,1)-(2,21),(1,16)-(3,18),(1,17)-(3,25),(2,27)-(3,11).jld2"))[2]

    ibnfs = [
        let
            ag = name_graph[2]
            ibnag = MINDF.default_IBNAttributeGraph(ag)
            
            # Use TeraFlow SDN for first domain, dummy for others
            if i == 1
                # Create TeraFlow SDN controller for first domain
                teraflow_sdn = TeraflowSDN()
                
                # Load existing device mappings if available
                if isfile(TESTDIR*"/data/device_map.jld2")
                    load_device_map!(TESTDIR*"/data/device_map.jld2", teraflow_sdn)
                end
                
                # Create IBN framework with TeraFlow SDN controller
                operationmode = MINDF.DefaultOperationMode()
                ibnfid = AG.graph_attr(ibnag)
                intentdag = MINDF.IntentDAG()
                ibnfhandlers = MINDF.AbstractIBNFHandler[]
                
                ibnf = MINDF.IBNFramework(operationmode, ibnfid, intentdag, ibnag, ibnfhandlers, teraflow_sdn)
            else
                # Use default (dummy) SDN controller for other domains
                ibnf = IBNFramework(ibnag)
            end
        end for (i, name_graph) in enumerate(domains_name_graph)
    ]

    # add ibnf handlers
    for i in eachindex(ibnfs)
        for j in eachindex(ibnfs)
            i == j && continue
            push!(getibnfhandlers(ibnfs[i]), ibnfs[j])
        end
    end

    return ibnfs
end

function loadmultidomaintestidistributedbnfs()
    domains_name_graph = first(JLD2.load(TESTDIR*"/data/itz_IowaStatewideFiberMap-itz_Missouri-itz_UsSignal_addedge_24-23,23-15__(1,9)-(2,3),(1,6)-(2,54),(1,1)-(2,21),(1,16)-(3,18),(1,17)-(3,25),(2,27)-(3,11).jld2"))[2]

    # MA1069 instantiate with HTTPHandler
    ibnfs = [
        let
            ag = name_graph[2]
            ibnag = MINDF.default_IBNAttributeGraph(ag)
            
            # Use TeraFlow SDN for first domain, dummy for others
            if i == 1
                # Create TeraFlow SDN controller for first domain
                teraflow_sdn = TeraflowSDN()
                
                # Load existing device mappings if available
                if isfile(TESTDIR*"/data/device_map.jld2")
                    load_device_map!(TESTDIR*"/data/device_map.jld2", teraflow_sdn)
                end
                
                # Create IBN framework with TeraFlow SDN controller
                operationmode = MINDF.DefaultOperationMode()
                ibnfid = AG.graph_attr(ibnag)
                intentdag = MINDF.IntentDAG()
                ibnfhandlers = MINDF.AbstractIBNFHandler[]
                
                ibnf = MINDF.IBNFramework(operationmode, ibnfid, intentdag, ibnag, ibnfhandlers, teraflow_sdn)
            else
                # Use default (dummy) SDN controller for other domains
                ibnf = IBNFramework(ibnag)
            end
        end for (i, name_graph) in enumerate(domains_name_graph)
    ]

    return ibnfs
end