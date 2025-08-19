using MINDFul

# Get the path to MINDFul package
mindful_path = dirname(dirname(pathof(MINDFul)))
@show mindful_path
testsuite_path = joinpath(mindful_path, "test", "testsuite")

include("initialize.jl")
# include(joinpath(testsuite_path, "utils.jl"))
# include(joinpath(testsuite_path, "physicaltest.jl"))
# include(joinpath(testsuite_path, "basicintenttest.jl"))
# include(joinpath(testsuite_path, "opticalconstraintssingledomain.jl"))
include(joinpath(testsuite_path, "multidomain.jl"))
# include(joinpath(testsuite_path, "failingintime.jl"))
# include(joinpath(testsuite_path, "grooming.jl"))
# include(joinpath(testsuite_path, "groomingonfail.jl"))
# include(joinpath(testsuite_path, "interface.jl"))
# include(joinpath(testsuite_path, "permissions.jl"))
# include(joinpath(testsuite_path, "rsaauthentication.jl"))

nothing
