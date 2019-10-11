module AbstractOperations

export ∂x, ∂y, ∂z

using Base: @propagate_inbounds

using Oceananigans

using Oceananigans: AbstractModel, AbstractField, AbstractLocatedField, Face, Cell, 
                    device, launch_config, architecture, location,
                    HorizontalAverage, zero_halo_regions!, normalize_horizontal_sum!

import Oceananigans: data, architecture

import Oceananigans.TurbulenceClosures: ∂x_caa, ∂x_faa, ∂y_aca, ∂y_afa, ∂z_aac, ∂z_aaf, 
                                        ▶x_caa, ▶x_faa, ▶y_aca, ▶y_afa, ▶z_aac, ▶z_aaf

using GPUifyLoops: @launch, @loop

import Base: *, -, +, /, getindex

abstract type AbstractOperation{X, Y, Z, G} <: AbstractLocatedField{X, Y, Z, Nothing, G} end

data(op::AbstractOperation) = op
Base.parent(op::AbstractOperation) = op

function validate_grid(a::F, b::F) where F<:AbstractField
    a.grid === b.grid || throw(ArgumentError("Two fields in a BinaryOperation must be on the same grid."))
    return a.grid
end

validate_grid(a::AbstractField, b) = a.grid
validate_grid(a, b::AbstractField) = b.grid
validate_grid(a, b) = nothing

function validate_grid(a, b, c...)
    grids = []
    push!(grids, validate_grid(a, b))
    append!(grids, [validate_grid(a, ci) for ci in c])

    for g in grids
        if !(g === nothing)
            return g
        end
    end

    return nothing
end

@inline identity(i, j, k, grid, ϕ) = @inbounds ϕ[i, j, k]
@inline identity(i, j, k, grid, ϕ::Number) = ϕ

interp_code(::Type{Face}) = :f
interp_code(::Type{Cell}) = :c
interp_code(to::L, from::L) where L = :a
interp_code(to, from) = interp_code(to)

for ξ in (:x, :y, :z)
    ▶sym = Symbol(:▶, ξ, :sym)
    @eval begin
        $▶sym(s::Symbol) = $▶sym(Val(s))
        $▶sym(::Union{Val{:f}, Val{:c}}) = string(ξ)
        $▶sym(::Val{:a}) = ""
    end
end

function interp_operator(from, to)
    x, y, z = (interp_code(t, f) for (t, f) in zip(to, from))

    if all(ξ === :a for ξ in (x, y, z))
        return identity
    else 
        return eval(Symbol(:▶, ▶xsym(x), ▶ysym(y), ▶zsym(z), :_, x, y, z))
    end
end

const operators = [:+, :-, :*, :/, :∂x, :∂y, :∂z]

function insert_location!(ex::Expr, location)
    if ex.head === :call && ex.args[1] ∈ operators
        push!(ex.args, ex.args[end])
        ex.args[3:end] .= ex.args[2:end-1]
        ex.args[2] = location
    end

    [insert_location!(arg, location) for arg in ex.args]

    return nothing
end

insert_location!(anything, location) = nothing

macro at(location, ex)
    insert_location!(ex, location)
    return esc(ex)
end

include("binary_operations.jl")
include("polynary_operations.jl")
include("derivatives.jl")
include("computations.jl")
include("function_fields.jl")

end # module
