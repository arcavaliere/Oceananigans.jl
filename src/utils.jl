#####
##### Adapting structures to be able to pass them to GPU CUDA kernels.
#####

# Adapt an offset CuArray to work nicely with CUDA kernels.
Adapt.adapt_structure(to, x::OffsetArray) = OffsetArray(adapt(to, parent(x)), x.offsets)

# Need to adapt SubArray indices as well.
# See: https://github.com/JuliaGPU/Adapt.jl/issues/16
#Adapt.adapt_structure(to, A::SubArray{<:Any,<:Any,AT}) where {AT} =
#    SubArray(adapt(to, parent(A)), adapt.(Ref(to), parentindices(A)))

#####
##### Utilities that make it easier to juggle around Arrays and CuArrays.
#####

         array_type(::CPU) = Array
@hascuda array_type(::GPU) = CuArray

#####
##### Convenient macros
#####

macro loop_xyz(i, j, k, grid, expr)
    return esc(
        quote
            @loop for $k in (1:$grid.Nz; (blockIdx().z - 1) * blockDim().z + threadIdx().z)
                @loop for $j in (1:$grid.Ny; (blockIdx().y - 1) * blockDim().y + threadIdx().y)
                    @loop for $i in (1:$grid.Nx; (blockIdx().x - 1) * blockDim().x + threadIdx().x)
                        $expr
                    end
                end
            end
        end)
end

macro loop_xy(i, j, grid, expr)
    return esc(
        quote
            @loop for $j in (1:$grid.Ny; (blockIdx().y - 1) * blockDim().y + threadIdx().y)
                @loop for $i in (1:$grid.Nx; (blockIdx().x - 1) * blockDim().x + threadIdx().x)
                    $expr
                end
            end
        end)
end

macro loop_xz(i, k, grid, expr)
    return esc(
        quote
            @loop for $k in (1:$grid.Nz; (blockIdx().y - 1) * blockDim().y + threadIdx().y)
                @loop for $i in (1:$grid.Nx; (blockIdx().x - 1) * blockDim().x + threadIdx().x)
                    $expr
                end
            end
        end)
end

#####
##### Convenient definitions
#####

"""
    second

A `Float64` constant equal to 1.0. Useful for increasing the clarity of scripts, e.g. `Δt = 1second`.
"""
const second = 1.0

"""
    minute

A `Float64` constant equal to 60`second`. Useful for increasing the clarity of scripts, e.g. `Δt = 15minute`.
"""
const minute = 60second

"""
    hour

A `Float64` constant equal to 60`minute`. Useful for increasing the clarity of scripts, e.g. `Δt = 3hour`.
"""
const hour   = 60minute

"""
    day

A `Float64` constant equal to 24`hour`. Useful for increasing the clarity of scripts, e.g. `Δt = 0.5day`.
"""
const day    = 24hour

"""
    meter

A `Float64` constant equal to 1.0. Useful for increasing the clarity of scripts, e.g. `Lx = 100meter`.
"""
const meter = 1.0

"""
    kilometer

A `Float64` constant equal to 1000`meter`. Useful for increasing the clarity of scripts, e.g. `Lx = 250kilometer`.
"""
const kilometer = 1000meter

"""
    KiB

A `Float64` constant equal to 1024.0. Useful for increasing the clarity of scripts, e.g. `max_filesize = 250KiB`.
"""
const KiB = 1024.0

"""
    MiB

A `Float64` constant equal to 1024`KiB`. Useful for increasing the clarity of scripts, e.g. `max_filesize = 100MiB`.
"""
const MiB = 1024KiB

"""
    GiB

A `Float64` constant equal to 1024`MiB`. Useful for increasing the clarity of scripts, e.g. `max_filesize = 50GiB`.
"""
const GiB = 1024MiB

"""
    TiB

A `Float64` constant equal to 1024`GiB`. Useful for increasing the clarity of scripts, e.g. `max_filesize = 2TiB`.
"""
const TiB = 1024GiB

#####
##### Pretty printing
#####

"""
    prettytime(t)

Convert a floating point value `t` representing an amount of time in seconds to a more
human-friendly formatted string with three decimal places. Depending on the value of `t`
the string will be formatted to show `t` in nanoseconds (ns), microseconds (μs),
milliseconds (ms), seconds (s), minutes (min), hours (hr), or days (day).
"""
function prettytime(t)
    # Modified from: https://github.com/JuliaCI/BenchmarkTools.jl/blob/master/src/trials.jl
    iszero(t) && return "0.000 s"
    
    if t < 1e-6
        value, units = t * 1e9, "ns"
    elseif t < 1e-3
        value, units = t * 1e6, "μs"
    elseif t < 1
        value, units = t * 1e3, "ms"
    elseif t < minute
        value, units = t, "s"
    elseif t < hour
        value, units = t / minute, "min"
    elseif t < day
        value, units = t / hour, "hr"
    else
        value, units = t / day, "day"
    end

    return @sprintf("%.3f", value) * " " * units
end

"""
    pretty_filesize(s, suffix="B")

Convert a floating point value `s` representing a file size to a more human-friendly
formatted string with one decimal places with a `suffix` defaulting to "B". Depending on
the value of `s` the string will be formatted to show `s` using an SI prefix from bytes,
kiB (1024 bytes), MiB (1024² bytes), and so on up to YiB (1024⁸ bytes).
"""
function pretty_filesize(s, suffix="B")
    # Modified from: https://stackoverflow.com/a/1094933
    for unit in ["", "Ki", "Mi", "Gi", "Ti", "Pi", "Ei", "Zi"]
        abs(s) < 1024 && return @sprintf("%3.1f %s%s", s, unit, suffix)
        s /= 1024
    end
    return @sprintf("%.1f %s%s", s, "Yi", suffix)
end

#####
##### Creating fields by dispatching on architecture
#####

function OffsetArray(underlying_data, grid::AbstractGrid)
    # Starting and ending indices for the offset array.
    i1, i2 = 1 - grid.Hx, grid.Nx + grid.Hx
    j1, j2 = 1 - grid.Hy, grid.Ny + grid.Hy
    k1, k2 = 1 - grid.Hz, grid.Nz + grid.Hz

    return OffsetArray(underlying_data, i1:i2, j1:j2, k1:k2)
end

function Base.zeros(T, ::CPU, grid)
    underlying_data = zeros(T, grid.Tx, grid.Ty, grid.Tz)
    return OffsetArray(underlying_data, grid)
end

function Base.zeros(T, ::GPU, grid)
    underlying_data = CuArray{T}(undef, grid.Tx, grid.Ty, grid.Tz)
    underlying_data .= 0  # Gotta do this otherwise you might end up with a few NaN values!
    return OffsetArray(underlying_data, grid)
end

Base.zeros(T, ::CPU, grid, Nx, Ny, Nz) = zeros(T, Nx, Ny, Nz)
Base.zeros(T, ::GPU, grid, Nx, Ny, Nz) = zeros(T, Nx, Ny, Nz) |> CuArray

# Default to type of Grid
Base.zeros(arch, grid::AbstractGrid{T}) where T = zeros(T, arch, grid)
Base.zeros(arch, grid::AbstractGrid{T}, Nx, Ny, Nz) where T = zeros(T, arch, grid, Nx, Ny, Nz)

#####
##### Courant–Friedrichs–Lewy (CFL) condition number calculation
#####

# Note: these functions will have to be refactored to work on non-uniform grids.

"Returns the time-scale for advection on a regular grid across a single grid cell."
function cell_advection_timescale(u, v, w, grid)
    umax = maximum(abs, u)
    vmax = maximum(abs, v)
    wmax = maximum(abs, w)

    Δx = grid.Δx
    Δy = grid.Δy
    Δz = grid.Δz

    return min(Δx/umax, Δy/vmax, Δz/wmax)
end

cell_advection_timescale(model) =
    cell_advection_timescale(model.velocities.u.data.parent,
                             model.velocities.v.data.parent,
                             model.velocities.w.data.parent,
                             model.grid)

#####
##### Adaptive time stepping
#####

"""
    TimeStepWizard{T}

    TimeStepWizard(cfl=0.1, max_change=2.0, min_change=0.5, max_Δt=Inf)

A type for calculating adaptive time steps based on capping the CFL number at `cfl`.

On calling `update_Δt!(wizard, model)`, the `TimeStepWizard` computes a time-step such that
``cfl = max(u/Δx, v/Δy, w/Δz) Δt``, where ``max(u/Δx, v/Δy, w/Δz)`` is the maximum ratio
between model velocity and along-velocity grid spacing anywhere on the model grid. The new
`Δt` is constrained to change by a multiplicative factor no more than `max_change` or no
less than `min_change` from the previous `Δt`, and to be no greater in absolute magnitude
than `max_Δt`.
"""
Base.@kwdef mutable struct TimeStepWizard{T}
              cfl :: T = 0.1
    cfl_diffusion :: T = 2e-2
       max_change :: T = 2.0
       min_change :: T = 0.5
           max_Δt :: T = Inf
               Δt :: T = 0.01
end

"""
    update_Δt!(wizard, model)

Compute `wizard.Δt` given the velocities and diffusivities of `model`, and the parameters
of `wizard`.
"""
function update_Δt!(wizard, model)
    Δt = wizard.cfl * cell_advection_timescale(model)

    # Put the kibosh on if needed
    Δt = min(wizard.max_change * wizard.Δt, Δt)
    Δt = max(wizard.min_change * wizard.Δt, Δt)
    Δt = min(wizard.max_Δt, Δt)

    wizard.Δt = Δt

    return nothing
end

#####
##### Some utilities for tupling
#####

tupleit(t::Tuple) = t
tupleit(a::AbstractArray) = Tuple(a)
tupleit(nt) = tuple(nt)

parenttuple(obj) = Tuple(f.data.parent for f in obj)

@inline datatuple(obj::Nothing) = nothing
@inline datatuple(obj::AbstractArray) = obj
@inline datatuple(obj::Tuple) = Tuple(datatuple(o) for o in obj)
@inline datatuple(obj::NamedTuple) = NamedTuple{propertynames(obj)}(datatuple(o) for o in obj)
@inline datatuples(objs...) = (datatuple(obj) for obj in objs)

#####
##### Dynamic launch configuration
#####

function launch_config(grid, dims)
    return function (kernel)
        fun = kernel.fun
        config = launch_configuration(fun)

        # Adapt the suggested config from 1D to the requested grid dimensions
        if dims == :xyz
            t = floor(Int, cbrt(config.threads))
            threads = [t, t, t]
            blocks  = ceil.(Int, [grid.Nx, grid.Ny, grid.Nz] ./ t)
        elseif dims == :xy
            t = floor(Int, sqrt(config.threads))
            threads = [t, t]
            blocks  = ceil.(Int, [grid.Nx, grid.Ny] ./ t)
        elseif dims == :xz
            t = floor(Int, sqrt(config.threads))
            threads = [t, t]
            blocks  = ceil.(Int, [grid.Nx, grid.Nz] ./ t)
        else
            error("Unsupported launch configuration: $dims")
        end

        return (threads=Tuple(threads), blocks=Tuple(blocks))
    end
end

#####
##### Utilities shared between diagnostics and output writers
#####

defaultname(::AbstractDiagnostic, nelems) = Symbol(:diag, nelems+1)
defaultname(::AbstractOutputWriter, nelems) = Symbol(:writer, nelems+1)

const DiagOrWriterDict = OrderedDict{S, <:Union{AbstractDiagnostic, AbstractOutputWriter}} where S

function push!(container::DiagOrWriterDict, elem)
    name = defaultname(elem, length(container))
    container[name] = elem
    return nothing
end

getindex(container::DiagOrWriterDict, inds::Integer...) = getindex(container.vals, inds...)
setindex!(container::DiagOrWriterDict, newvals, inds::Integer...) = setindex!(container.vals, newvals, inds...)

function push!(container::DiagOrWriterDict, elems...)
    for elem in elems
        push!(container, elem)
    end
    return nothing
end

"""
    validate_interval(frequency, interval)

Ensure that frequency and interval are not both `nothing`.
"""
function validate_interval(frequency, interval)
    isnothing(frequency) && isnothing(interval) && @error "Must specify a frequency or interval!"
    return nothing
end

has_interval(obj) = :interval in propertynames(obj) && obj.interval != nothing
has_frequency(obj) = :frequency in propertynames(obj) && obj.frequency != nothing

function interval_is_ripe(clock, obj)
    if has_interval(obj) && clock.time >= obj.previous + obj.interval
        obj.previous = clock.time - rem(clock.time, obj.interval)
        return true
    else
        return false
    end
end

frequency_is_ripe(clock, obj) = has_frequency(obj) && clock.iteration % obj.frequency == 0

function time_to_run(clock, output_writer)

    interval_is_ripe(clock, output_writer) && return true
    frequency_is_ripe(clock, output_writer) && return true

    # If the output writer does not specify an interval or frequency,
    # it is unable to write output and we throw an error as a convenience.
    has_interval(output_writer) || has_frequency(output_writer) ||
        error("$(typeof(output_writer)) must have a frequency or interval specified!")

    return false
end

#####
##### Utils for models
#####

function ordered_dict_show(dict, padchar)
    if length(dict) == 0
        return string(typeof(dict), " with no entries")
    elseif length(dict) == 1
        return string(typeof(dict), " with 1 entry:", '\n',
                      padchar, "   └── ", dict.keys[1], " => ", typeof(dict.vals[1]))
    else
        return string(typeof(dict), " with $(length(dict)) entries:", '\n',
                      Tuple(string(padchar,
                                   "   ├── ", name, " => ", typeof(dict[name]), '\n')
                            for name in dict.keys[1:end-1]
                           )...,
                           padchar, "   └── ", dict.keys[end], " => ", typeof(dict.vals[end])
                      )
    end
end

"""
    with_tracers(tracers, initial_tuple, tracer_default)

Create a tuple corresponding to the solution variables `u`, `v`, `w`,
and `tracers`. `initial_tuple` is a `NamedTuple` that at least has
fields `u`, `v`, and `w`, and may have some fields corresponding to
the names in `tracers`. `tracer_default` is a function that produces
a default tuple value for each tracer if not included in `initial_tuple`.
"""
function with_tracers(tracers, initial_tuple::NamedTuple, tracer_default; with_velocities=false)
    solution_values = [] # Array{Any, 1}
    solution_names = []

    if with_velocities
        push!(solution_values, initial_tuple.u)
        push!(solution_values, initial_tuple.v)
        push!(solution_values, initial_tuple.w)

        append!(solution_names, [:u, :v, :w])
    end

    for name in tracers
        tracer_elem = name ∈ propertynames(initial_tuple) ?
                        getproperty(initial_tuple, name) :
                        tracer_default(tracers, initial_tuple)

        push!(solution_values, tracer_elem)
    end

    append!(solution_names, tracers)

    return NamedTuple{Tuple(solution_names)}(Tuple(solution_values))
end
