using MINDFul: getoxcview
#import MINDFulMakie as MINDFM
using MINDFul, Test
using Graphs
import AttributeGraphs as AG
using JLD2, UUIDs
using Unitful, UnitfulData

const MINDF = MINDFul

#using GLMakie

## single domain

# load data
domains_name_graph = first(JLD2.load("data/itz_IowaStatewideFiberMap-itz_Missouri__(1,9)-(2,3),(1,6)-(2,54),(1,1)-(2,21).jld2"))[2]
println("Loaded graph")
ag1 = first(domains_name_graph)[2]

############
# Topology and devices known
ibnag1 = MINDF.default_IBNAttributeGraph(ag1)
# sdn = MINDFulTeraFlowSDN.TFSSDN("http://...", ibndag1)
# Obvi needs some MINDFul TFS property mapping
# Teraflow needs to be set up or be able to be set up with the next function call
# ibnf1 = MINDF.IBNFramework(ibnag1,sdn::TFSSDN)
ibnf1 = MINDF.IBNFramework(ibnag1)

# Get the NodeView for node 10
nodeview = MINDF.getnodeview(ibnf1, 10)
# println("NodeView for node 10:")
# println(nodeview)

# Extract the RouterView from the NodeView
tmview = nodeview.transmissionmoduleviewpool
tmview[1].transmissionmodes


###########
# TFS devices need to be available
# conintent1 = MINDF.ConnectivityIntent(MINDF.GlobalNode(MINDF.getibnfid(ibnf1), 4), MINDF.GlobalNode(MINDF.getibnfid(ibnf1), 8), u"100Gbps")
# MINDF.addintent!(ibnf1, conintent1, MINDF.NetworkOperator())

# plot
# MINDFM.ibngraphplot(ibnag1; layout = x -> MINDFM.coordlayout(ibnag1), nlabels=repr.(Graphs.vertices(ibnag1)))
# MINDFM.intentplot(ibnf1, UUID(1); showstate=true)

# MINDF.compileintent!(ibnf1, UUID(1), MINDF.KShorestPathFirstFitCompilation(10))

# nothing
