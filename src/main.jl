
"""
$(TYPEDSIGNATURES)
main() function to initialize the MINDFul IBN framework.
It expects the path of the configuration file in TOML format, in order to set up the IBNFrameworks for each domain
and start the HTTP server that enables communication between domains.
The path can be absolute or relative to the current working directory.
The paths of the files referenced in the configuration file can be absolute or relative to the directory of the configuration file.
"""
function main()
    verbose = false
    MAINDIR = pwd()
    if length(ARGS) < 2
        error("Usage: julia MINDFulTeraFlowSDN.main() <path/to/configX.toml> <controller_IP_address>")
    end

    configpath = ARGS[1]
    @show configpath
    finalconfigpath = MINDF.checkfilepath(MAINDIR, configpath)
    CONFIGDIR = dirname(finalconfigpath)
    config = TOML.parsefile(finalconfigpath)

    domainfile = config["domainfile"]
    finaldomainfile = MINDF.checkfilepath(CONFIGDIR, domainfile)
    domains_name_graph = first(JLD2.load(finaldomainfile))[2]

    encryption = config["encryption"]
    if encryption
        urischeme = "https"
        MINDF.generateTLScertificate()
    else
        urischeme = "http"
    end

    localip = config["local"]["ip"]
    localport = config["local"]["port"]
    localid = config["local"]["ibnfid"]
    localprivatekeyfile = config["local"]["rsaprivatekey"]
    finallocalprivatekeyfile = MINDF.checkfilepath(CONFIGDIR, localprivatekeyfile)
    localprivatekey = MINDF.readb64keys(finallocalprivatekeyfile)
    localdevicemapfile = MINDF.checkfilepath(CONFIGDIR, config["local"]["devicemapfile"])
    localcontrollerip = ARGS[2]
    @show localcontrollerip
    localcontrollerurl = string(HTTP.URI(; scheme = "http", host = localcontrollerip, port = string(80), path="/tfs-api"))

    neighboursconfig = config["remote"]["neighbours"]
    neighbourips = [n["ip"] for n in neighboursconfig]
    neighbourports = [n["port"] for n in neighboursconfig]
    neighbourids = [n["ibnfid"] for n in neighboursconfig]
    neigbhbourpermissions = [n["permission"] for n in neighboursconfig]
    neighbourpublickeyfiles = [n["rsapublickey"] for n in neighboursconfig]
    neighbourpublickeys = [MINDF.readb64keys(MINDF.checkfilepath(CONFIGDIR, pkfile)) for pkfile in neighbourpublickeyfiles]


    hdlr = Vector{MINDF.RemoteHTTPHandler}()
    localURI = HTTP.URI(; scheme = urischeme, host = localip, port = string(localport))
    localURIstring = string(localURI)
    push!(hdlr, MINDF.RemoteHTTPHandler(UUID(localid), localURIstring, "full", localprivatekey, "", "", ""))
    for i in eachindex(neighbourips)
        URI = HTTP.URI(; scheme = urischeme, host = neighbourips[i], port = string(neighbourports[i]))
        URIstring = string(URI)
        push!(hdlr, MINDF.RemoteHTTPHandler(UUID(neighbourids[i]), URIstring, neigbhbourpermissions[i], neighbourpublickeys[i], "", "", ""))
    end

    
    sdncontroller = TeraflowSDN(
        localcontrollerurl, 
        Dict{Any,String}(),
        Dict{Tuple{Int,Symbol},String}(),
        Dict{NTuple{6,Any},String}(),
        Dict{String,Bool}()
    )

    ibnfsdict = Dict{Int, MINDF.IBNFramework}()
    ibnf = nothing
    for name_graph in domains_name_graph
        ag = name_graph[2]
        ibnag = MINDF.default_IBNAttributeGraph(ag)
        if MINDF.getibnfid(ibnag) == UUID(localid)
            context = get_contexts(localcontrollerurl)["contexts"]
            if isempty(context)
                setup_context_topology(sdncontroller)
                create_graph_with_devices(ibnag, localdevicemapfile, sdncontroller)
            end

            if !isfile(localdevicemapfile)
                save_device_map(localdevicemapfile, sdncontroller)
            end

            load_device_map!(localdevicemapfile, sdncontroller)

            ibnf = MINDF.IBNFramework(ibnag, hdlr, encryption, neighbourips, sdncontroller, ibnfsdict; verbose)
            break
        end
    end

    if ibnf === nothing
        error("No matching ibnf found for ibnfid $localid")
    else
        return ibnf
    end
end
