using MINDFulTeraFlowSDN
using MINDFul
using Test, TestSetExtensions
using Graphs
import AttributeGraphs as AG
using JLD2, UUIDs
using Unitful, UnitfulData
import Dates: now, Hour
import Random: MersenneTwister, randperm
using TOML, HTTP, MbedTLS

import MINDFul: ReturnCodes, IBNFramework, getibnfhandlers, GlobalNode, ConnectivityIntent, addintent!, NetworkOperator, compileintent!, KShorestPathFirstFitCompilation, installintent!, uninstallintent!, uncompileintent!, getidag, getrouterview, getoxcview, RouterPortLLI, TransmissionModuleLLI, OXCAddDropBypassSpectrumLLI, canreserve, reserve!, getlinkspectrumavailabilities, getreservations, unreserve!, getibnfid, getidagnodestate, IntentState, getidagnodechildren, getidagnode, OpticalTerminateConstraint, getlogicallliorder, issatisfied, getglobalnode, getibnag, getlocalnode, getspectrumslotsrange, gettransmissionmode, getname, gettransmissionmodule, TransmissionModuleCompatibility, getrate, getspectrumslotsneeded, OpticalInitiateConstraint, getnodeview, getnodeview, getsdncontroller, getrouterview, removeintent!, getlinkstates, getcurrentlinkstate, setlinkstate!, logicalordercontainsedge, logicalordergetpath, edgeify, getintent, RemoteIntent, getisinitiator, getidagnodeid, getibnfhandler, getidagnodes, @passtime, getlinkstates, issuccess, getstaged, getidaginfo,getinstalledlightpaths, LightpathRepresentation, GBPSf, getresidualbandwidth, getidagnodeidx, getidagnodedescendants, CrossLightpathIntent, GlobalEdge, getfirst

const MINDF = MINDFul

import JET
import JET: @test_opt

TESTDIR = @__DIR__

# if you don't want JET tests do `push!(ARGS, "--nojet")` before `include`ing
RUNJET = !any(==("--nojet"), ARGS)

# get the test module from MINDFul
TM = Base.get_extension(MINDFul, :TestModule)
@test !isnothing(TM)

# some boilerplate functions

function loadmultidomaintestibnfs()
    domains_name_graph = first(JLD2.load(TESTDIR*"/data/itz_IowaStatewideFiberMap-itz_Missouri-itz_UsSignal_addedge_24-23,23-15__(1,9)-(2,3),(1,6)-(2,54),(1,1)-(2,21),(1,16)-(3,18),(1,17)-(3,25),(2,27)-(3,11).jld2"))[2]

    # Create all domains with proper initialization
    ibnfs = [
        let
            ag = name_graph[2]
            ibnag = MINDF.default_IBNAttributeGraph(ag)
            
            # Prepare all required arguments
            operationmode = MINDF.DefaultOperationMode()
            ibnfid = AG.graph_attr(ibnag)
            intentdag = MINDF.IntentDAG()
            
            # Use TeraFlow for domain 1, dummy for others
            if i == 1
                sdncontroller = TeraflowSDN()
                # Load existing device mappings if available
                if isfile(TESTDIR*"/data/device_map.jld2")
                    load_device_map!(TESTDIR*"/data/device_map.jld2", sdncontroller)
                end
            else
                sdncontroller = MINDF.SDNdummy()
            end
            
            # Initialize with empty handlers first
            ibnfhandlers = MINDF.AbstractIBNFHandler[]
            ibnfcomm = MINDF.IBNFCommunication(nothing, ibnfhandlers)
            
            MINDF.IBNFramework(operationmode, ibnfid, intentdag, ibnag, ibnfcomm, sdncontroller)
        end for (i, name_graph) in enumerate(domains_name_graph)
    ]

    # Properly set up cross-domain handlers
    for i in eachindex(ibnfs)
        handlers = getibnfhandlers(ibnfs[i])
        empty!(handlers)  # Clear any existing handlers
        for j in eachindex(ibnfs)
            if i != j
                push!(handlers, ibnfs[j])
            end
        end
    end

    # Validate that all frameworks have proper handlers
    for (i, ibnf) in enumerate(ibnfs)
        handlers = getibnfhandlers(ibnf)
        @assert length(handlers) == length(ibnfs) - 1 "Domain $i should have $(length(ibnfs)-1) handlers, got $(length(handlers))"
    end

    return ibnfs
end



function loadmultidomaintestidistributedbnfs()
    configfilepath = joinpath(TESTDIR, "data/config.toml")
    config = TOML.parsefile(configfilepath)
    CONFIGDIR = dirname(configfilepath)

    domainfile = config["domainfile"]
    finaldomainfile = MINDF.checkfilepath(CONFIGDIR, domainfile)
    domains_name_graph = first(JLD2.load(finaldomainfile))[2]

    MINDF.generateRSAkeys(CONFIGDIR)

    domainsconfig = config["domains"]["config"]
    ips = [n["ip"] for n in domainsconfig]
    ports = [n["port"] for n in domainsconfig]
    ibnfids = [n["ibnfid"] for n in domainsconfig]
    permissions = [perm for n in domainsconfig for perm in n["permissions"]]
    privatekeysfiles = [n["rsaprivatekey"] for n in domainsconfig]
    privatekeys = [MINDF.readb64keys(MINDF.checkfilepath(CONFIGDIR, pkfile)) for pkfile in privatekeysfiles]
    publickeysfiles = [n["rsapublickey"] for n in domainsconfig]
    publickeys = [MINDF.readb64keys(MINDF.checkfilepath(CONFIGDIR, pkfile)) for pkfile in publickeysfiles]

    encryption = config["encryption"]
    if encryption
        urischeme = "https"
        MINDF.generateTLScertificate()
    else
        urischeme = "http"
    end

    ibnfsdict = Dict{Int, IBNFramework}()
    index = 1
    ibnfs = [
        let
                hdlr = Vector{MINDF.RemoteHTTPHandler}()
                localURI = HTTP.URI(; scheme = urischeme, host = ips[i], port = ports[i])
                localURIstring = string(localURI)
                push!(hdlr, MINDF.RemoteHTTPHandler(UUID(ibnfids[i]), localURIstring, "full", privatekeys[i], "", "", ""))
                for j in eachindex(ibnfids)
                    i == j && continue
                    URI = HTTP.URI(; scheme = urischeme, host = ips[j], port = ports[j])
                    URIstring = string(URI)
                    push!(hdlr, MINDF.RemoteHTTPHandler(UUID(ibnfids[j]), URIstring, permissions[index], publickeys[j], "", "", ""))
                    index += 1
                end
                
                if i==1
                    sdncontroller = TeraflowSDN()
                    # Load existing device mappings if available
                    if isfile(TESTDIR*"/data/device_map.jld2")
                        load_device_map!(TESTDIR*"/data/device_map.jld2", sdncontroller)
                    end
                else
                    sdncontroller = MINDF.SDNdummy()  # Use dummy for other domains
                end

                ag = name_graph[2]
                ibnag = MINDF.default_IBNAttributeGraph(ag)
                ibnf = MINDF.IBNFramework(ibnag, hdlr, encryption, ips, sdncontroller, ibnfsdict; verbose = false)
        end for (i, name_graph) in enumerate(domains_name_graph)
    ]


    return ibnfs
end


function loadpermissionedbnfs()
    configfilepath = joinpath(TESTDIR, "data/config.toml")
    config = TOML.parsefile(configfilepath)
    CONFIGDIR = dirname(configfilepath)

    domainfile = config["domainfile"]
    finaldomainfile = MINDF.checkfilepath(CONFIGDIR, domainfile)
    domains_name_graph = first(JLD2.load(finaldomainfile))[2]

    MINDF.generateRSAkeys(CONFIGDIR)

    domainsconfig = config["domains"]["config"]
    ips = [n["ip"] for n in domainsconfig]
    ports = [n["port"] for n in domainsconfig]
    ibnfids = [n["ibnfid"] for n in domainsconfig]
    permissions = ["limited", "limited", "full", "none", "full", "full"]
    privatekeysfiles = [n["rsaprivatekey"] for n in domainsconfig]
    privatekeys = [MINDF.readb64keys(MINDF.checkfilepath(CONFIGDIR, pkfile)) for pkfile in privatekeysfiles]
    publickeysfiles = [n["rsapublickey"] for n in domainsconfig]
    publickeys = [MINDF.readb64keys(MINDF.checkfilepath(CONFIGDIR, pkfile)) for pkfile in publickeysfiles]

    encryption = config["encryption"]
    if encryption
        urischeme = "https"
        MINDF.generateTLScertificate()
    else
        urischeme = "http"
    end

    ibnfsdict = Dict{Int, IBNFramework}()
    index = 1
    ibnfs = [
            let
                hdlr = Vector{MINDF.RemoteHTTPHandler}()
                localURI = HTTP.URI(; scheme = urischeme, host = ips[i], port = ports[i])
                localURIstring = string(localURI)
                push!(hdlr, MINDF.RemoteHTTPHandler(UUID(ibnfids[i]), localURIstring, "full", privatekeys[i], "", "", ""))
                for j in eachindex(ibnfids)
                    i == j && continue
                    URI = HTTP.URI(; scheme = urischeme, host = ips[j], port = ports[j])
                    URIstring = string(URI)
                    push!(hdlr, MINDF.RemoteHTTPHandler(UUID(ibnfids[j]), URIstring, permissions[index], publickeys[j], "", "", ""))
                    index += 1
            end

            if i==1
                sdncontroller = TeraflowSDN()
                # Load existing device mappings if available
                if isfile(TESTDIR*"/data/device_map.jld2")
                    load_device_map!(TESTDIR*"/data/device_map.jld2", sdncontroller)
                end
            else
                sdncontroller = MINDF.SDNdummy()  # Use dummy for other domains
            end

            ag = name_graph[2]
            ibnag = MINDF.default_IBNAttributeGraph(ag)
            ibnf = MINDF.IBNFramework(ibnag, hdlr, encryption, ips, sdncontroller, ibnfsdict; verbose = false)
        end for (i, name_graph) in enumerate(domains_name_graph)
    ]

    return ibnfs
end