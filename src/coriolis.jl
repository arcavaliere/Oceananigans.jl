using Printf

using Oceananigans.Operators: ℑxyᶜᶠᵃ, ℑxyᶠᶜᵃ

#####
##### Physical constants
#####

const Ω_Earth = 7.292115e-5 # [s⁻¹] https://en.wikipedia.org/wiki/Earth%27s_rotation#Angular_speed
const R_Earth = 6371.0e3    # Mean radius of the Earth [m] https://en.wikipedia.org/wiki/Earth

#####
##### Functions for non-rotating models
#####

@inline x_f_cross_U(i, j, k, grid::AbstractGrid{FT}, ::Nothing, U) where FT = zero(FT)
@inline y_f_cross_U(i, j, k, grid::AbstractGrid{FT}, ::Nothing, U) where FT = zero(FT)
@inline z_f_cross_U(i, j, k, grid::AbstractGrid{FT}, ::Nothing, U) where FT = zero(FT)

#####
##### The 'FPlane' approximation. This is equivalent to a model with a constant
##### rotation rate around its vertical axis.
#####

"""
    FPlane{FT} <: AbstractRotation

A parameter object for constant rotation around a vertical axis.
"""
struct FPlane{FT} <: AbstractRotation
    f :: FT
end

"""
    FPlane([FT=Float64;] f=nothing, rotation_rate=Ω_Earth, latitude=nothing)

Returns a parameter object for constant rotation at the angular frequency
`f/2`, and therefore with background vorticity `f`, around a vertical axis.
If `f` is not specified, it is calculated from `rotation_rate` and
`latitude` according to the relation `f = 2*rotation_rate*sind(latitude).

By default, `rotation_rate` is assumed to be Earth's.

Also called `FPlane`, after the "f-plane" approximation for the local effect of
a planet's rotation in a planar coordinate system tangent to the planet's surface.
"""
function FPlane(FT::DataType=Float64; f=nothing, rotation_rate=Ω_Earth, latitude=nothing)

    use_f = !isnothing(f)
    use_planet_parameters = !isnothing(latitude)

    if !xor(use_f, use_planet_parameters)
        throw(ArgumentError("Either both keywords rotation_rate and latitude must be " *
                            "specified, *or* only f must be specified."))
    end

    if use_f
        return FPlane{FT}(f)
    elseif use_planet_parameters
        return FPlane{FT}(2rotation_rate*sind(latitude))
    end
end

@inline x_f_cross_U(i, j, k, grid, coriolis::FPlane, U) = - coriolis.f * ℑxyᶠᶜᵃ(i, j, k, grid, U.v)
@inline y_f_cross_U(i, j, k, grid, coriolis::FPlane, U) =   coriolis.f * ℑxyᶜᶠᵃ(i, j, k, grid, U.u)
@inline z_f_cross_U(i, j, k, grid::AbstractGrid{FT}, coriolis::FPlane, U) where FT = zero(FT)

Base.show(io::IO, f_plane::FPlane{FT}) where FT =
    println(io, "FPlane{$FT}: f = ", @sprintf("%.2e", f_plane.f))

#####
##### βeta Plane
#####

"""
    BetaPlane{T} <: AbstractRotation

A parameter object for meridionally increasing Coriolis parameter (`f = f₀ + βy`).
"""
struct BetaPlane{T} <: AbstractRotation
    f₀ :: T
     β :: T
end

"""
    BetaPlane([T=Float64;] f₀=nothing, β=nothing,
                           rotation_rate=Ω_Earth, latitude=nothing, radius=R_Earth)

A parameter object for meridionally increasing Coriolis parameter (`f = f₀ + βy`).

The user may specify both `f₀` and `β`, or the three parameters `rotation_rate`,
`latitude`, and `radius` that specify the rotation rate and radius of a planet, and
the central latitude at which the `β`-plane approximation is to be made.

By default, the `rotation_rate` and planet `radius` is assumed to be Earth's.
"""
function BetaPlane(T=Float64; f₀=nothing, β=nothing,
                              rotation_rate=Ω_Earth, latitude=nothing, radius=R_Earth)

    use_f_and_β = !isnothing(f₀) && !isnothing(β)
    use_planet_parameters = !isnothing(latitude)

    if !xor(use_f_and_β, use_planet_parameters)
        throw(ArgumentError("Either both keywords f₀ and β must be specified, " *
                            "*or* all of rotation_rate, latitude, and radius."))
    end

    if use_planet_parameters
        f₀ = 2rotation_rate * sind(latitude)
         β = 2rotation_rate * cosd(latitude) / radius
     end

    return BetaPlane{T}(f₀, β)
end

@inline x_f_cross_U(i, j, k, grid, coriolis::BetaPlane, U) =
    @inbounds - (coriolis.f₀ + coriolis.β * grid.yC[j]) * ℑxyᶠᶜᵃ(i, j, k, grid, U.v)
@inline y_f_cross_U(i, j, k, grid, coriolis::BetaPlane, U) =
    @inbounds   (coriolis.f₀ + coriolis.β * grid.yF[j]) * ℑxyᶜᶠᵃ(i, j, k, grid, U.u)
@inline z_f_cross_U(i, j, k, grid::AbstractGrid{FT}, coriolis::BetaPlane, U) where FT = zero(FT)

Base.show(io::IO, β_plane::BetaPlane{FT}) where FT =
    println(io, "BetaPlane{$FT}: ", @sprintf("f₀ = %.2e, β = %.2e", β_plane.f₀, β_plane.β))
