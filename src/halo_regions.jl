#####
##### Halo filling for flux, periodic, and no-penetration boundary conditions.
#####

# For flux boundary conditions we fill halos as for a *no-flux* boundary condition, and add the
# flux divergence associated with the flux boundary condition in a separate step. Note that
# ranges are used to reference the data copied into halos, as this produces views of the correct
# dimension (eg size = (1, Ny, Nz) for the west halos).

  _fill_west_halo!(c, ::FBC, H, N) = @views @. c.parent[1:H, :, :] = c.parent[1+H:1+H,  :, :]
 _fill_south_halo!(c, ::FBC, H, N) = @views @. c.parent[:, 1:H, :] = c.parent[:, 1+H:1+H,  :]
_fill_bottom_halo!(c, ::FBC, H, N) = @views @. c.parent[:, :, 1:H] = c.parent[:, :,  1+H:1+H]

 _fill_east_halo!(c, ::FBC, H, N) = @views @. c.parent[N+H+1:N+2H, :, :] = c.parent[N+H:N+H, :, :]
_fill_north_halo!(c, ::FBC, H, N) = @views @. c.parent[:, N+H+1:N+2H, :] = c.parent[:, N+H:N+H, :]
  _fill_top_halo!(c, ::FBC, H, N) = @views @. c.parent[:, :, N+H+1:N+2H] = c.parent[:, :, N+H:N+H]

# Periodic boundary conditions
  _fill_west_halo!(c, ::PBC, H, N) = @views @. c.parent[1:H, :, :] = c.parent[N+1:N+H, :, :]
 _fill_south_halo!(c, ::PBC, H, N) = @views @. c.parent[:, 1:H, :] = c.parent[:, N+1:N+H, :]
_fill_bottom_halo!(c, ::PBC, H, N) = @views @. c.parent[:, :, 1:H] = c.parent[:, :, N+1:N+H]

 _fill_east_halo!(c, ::PBC, H, N) = @views @. c.parent[N+H+1:N+2H, :, :] = c.parent[1+H:2H, :, :]
_fill_north_halo!(c, ::PBC, H, N) = @views @. c.parent[:, N+H+1:N+2H, :] = c.parent[:, 1+H:2H, :]
  _fill_top_halo!(c, ::PBC, H, N) = @views @. c.parent[:, :, N+H+1:N+2H] = c.parent[:, :, 1+H:2H]

# Recall that, by convention, the first grid point (k=1) in an array with a no-penetration boundary
# condition lies on the boundary, where as the last grid point (k=Nz) lies in the domain.

  _fill_west_halo!(c, ::NPBC, H, N) = @views @. c.parent[1:1+H, :, :] = 0
 _fill_south_halo!(c, ::NPBC, H, N) = @views @. c.parent[:, 1:1+H, :] = 0
_fill_bottom_halo!(c, ::NPBC, H, N) = @views @. c.parent[:, :, 1:1+H] = 0

 _fill_east_halo!(c, ::NPBC, H, N) = @views @. c.parent[N+H+1:N+2H, :, :] = 0
_fill_north_halo!(c, ::NPBC, H, N) = @views @. c.parent[:, N+H+1:N+2H, :] = 0
  _fill_top_halo!(c, ::NPBC, H, N) = @views @. c.parent[:, :, N+H+1:N+2H] = 0

# Generate functions that implement flux, periodic, and no-penetration boundary conditions
sides = (:west, :east, :south, :north, :top, :bottom)
coords = (:x, :x, :y, :y, :z, :z)

for (x, side) in zip(coords, sides)
    outername = Symbol(:fill_, side, :_halo!)
    innername = Symbol(:_fill_, side, :_halo!)
    H = Symbol(:H, x)
    N = Symbol(:N, x)
    @eval begin
        $outername(c, bc::Union{FBC, PBC, NPBC}, arch::AbstractArchitecture, grid::AbstractGrid, args...) =
            $innername(c, bc, grid.$(H), grid.$(N))
    end
end

#####
##### Halo filling for value and gradient boundary conditions
#####

@inline linearly_extrapolate(c₀, ∇c, Δ) = c₀ + ∇c * Δ

@inline bottom_gradient(bc::GBC, c¹, Δ, i, j, args...) = getbc(bc, i, j, args...)
@inline top_gradient(bc::GBC, cᴺ, Δ, i, j, args...) = getbc(bc, i, j, args...)

@inline south_gradient(bc::GBC, c¹, Δ, i, k, args...) = getbc(bc, i, k, args...)
@inline north_gradient(bc::GBC, cᴺ, Δ, i, k, args...) = getbc(bc, i, k, args...)

@inline bottom_gradient(bc::VBC, c¹, Δ, i, j, args...) = ( c¹ - getbc(bc, i, j, args...) ) / (Δ/2)
@inline top_gradient(bc::VBC, cᴺ, Δ, i, j, args...) =    ( getbc(bc, i, j, args...) - cᴺ ) / (Δ/2)

@inline left_gradient(bc::VBC, c¹, Δ, i, k, args...) =  ( c¹ - getbc(bc, i, k, args...) ) / (Δ/2)
@inline right_gradient(bc::VBC, cᴺ, Δ, i, k, args...) = ( getbc(bc, i, k, args...) - cᴺ ) / (Δ/2)

function fill_bottom_halo!(c, bc::Union{VBC, GBC}, arch, grid, args...)
    @launch device(arch) config=launch_config(grid, :xy) _fill_bottom_halo!(c, bc, grid, args...)
    return nothing
end

function fill_top_halo!(c, bc::Union{VBC, GBC}, arch, grid, args...)
    @launch device(arch) config=launch_config(grid, :xy) _fill_top_halo!(c, bc, grid, args...)
    return nothing
end

function fill_south_halo!(c, bc::Union{VBC, GBC}, arch, grid, args...)
    @launch device(arch) config=launch_config(grid, :xz) _fill_south_halo!(c, bc, grid, args...)
    return nothing
end

function fill_north_halo!(c, bc::Union{VBC, GBC}, arch, grid, args...)
    @launch device(arch) config=launch_config(grid, :xz) _fill_north_halo!(c, bc, grid, args...)
    return nothing
end

function _fill_bottom_halo!(c, bc::Union{VBC, GBC}, grid, args...)
    @loop_xy i j grid begin
        @inbounds ∇c = bottom_gradient(bc, c[i, j, 1], grid.Δz, i, j, grid, args...)
        @unroll for k in (1 - grid.Hz):0
            Δ = (k - 1) * grid.Δz  # separation between bottom grid cell and halo is negative
            @inbounds c[i, j, k] = linearly_extrapolate(c[i, j, 1], ∇c, Δ)
        end
    end
    return nothing
end

function _fill_top_halo!(c, bc::Union{VBC, GBC}, grid, args...)
    @loop_xy i j grid begin
        @inbounds ∇c = top_gradient(bc, c[i, j, grid.Nz], grid.Δz, i, j, grid, args...)
        @unroll for k in (grid.Nz + 1) : (grid.Nz + grid.Hz)
            Δ = (k - grid.Nz) * grid.Δz
            @inbounds c[i, j, k] = linearly_extrapolate(c[i, j, grid.Nz], ∇c, Δ)
        end
    end
    return nothing
end

function _fill_south_halo!(c, bc::Union{VBC, GBC}, grid, args...)
    @loop_xz i k grid begin
        @inbounds ∇c = south_gradient(bc, c[i, 1, k], grid.Δy, i, k, grid, args...)
        @unroll for j in (1 - grid.Hy):0
            Δ = (j - 1) * grid.Δy  # separation between southern-most grid cell and halo is negative
            @inbounds c[i, j, k] = linearly_extrapolate(c[i, 1, k], ∇c, Δ)
        end
    end
    return nothing
end

function _fill_north_halo!(c, bc::Union{VBC, GBC}, grid, args...)
    @loop_xz i k grid begin
        @inbounds ∇c = north_gradient(bc, c[i, grid.Ny, k], grid.Δy, i, k, grid, args...)
        @unroll for j in (grid.Ny + 1) : (grid.Ny + grid.Hy)
            Δ = (k - grid.Ny) * grid.Δy
            @inbounds c[i, j, k] = linearly_extrapolate(c[i, grid.Ny, k], ∇c, Δ)
        end
    end
    return nothing
end

#####
##### General halo filling functions
#####

"Fill halo regions in x, y, and z for a given field."
function fill_halo_regions!(c::AbstractArray, fieldbcs, arch, grid, args...)
      fill_west_halo!(c, fieldbcs.x.left,  arch, grid, args...)
      fill_east_halo!(c, fieldbcs.x.right, arch, grid, args...)

     fill_south_halo!(c, fieldbcs.y.left,  arch, grid, args...)
     fill_north_halo!(c, fieldbcs.y.right, arch, grid, args...)

     fill_bottom_halo!(c, fieldbcs.z.bottom, arch, grid, args...)
        fill_top_halo!(c, fieldbcs.z.top,    arch, grid, args...)
    return nothing
end

"""
    fill_halo_regions!(fields, bcs, arch, grid)

Fill halo regions for all fields in the `NamedTuple` `fields` according
to the corresponding `NamedTuple` of `bcs`.
"""
function fill_halo_regions!(fields::NamedTuple{S}, bcs::NamedTuple{S}, arch, grid, args...) where S
    for (field, fieldbcs) in zip(fields, bcs)
        fill_halo_regions!(field, fieldbcs, arch, grid, args...)
    end
    return nothing
end

"""
    fill_halo_regions!(fields, bcs, arch, grid)

Fill halo regions for each field in the tuple `fields` according
to the single instance of `FieldBoundaryConditions` in `bcs`, possibly recursing into
`fields` if it is a nested tuple-of-tuples.
"""
function fill_halo_regions!(fields::Union{Tuple, NamedTuple}, bcs::FieldBoundaryConditions, arch, grid, args...)
    for field in fields
        fill_halo_regions!(field, bcs, arch, grid, args...)
    end
    return nothing
end

fill_halo_regions!(::Nothing, args...) = nothing

#####
##### Halo zeroing functions
#####

  zero_west_halo!(c, H, N) = @views @. c[1:H, :, :] = 0
 zero_south_halo!(c, H, N) = @views @. c[:, 1:H, :] = 0
zero_bottom_halo!(c, H, N) = @views @. c[:, :, 1:H] = 0

 zero_east_halo!(c, H, N) = @views @. c[N+H+1:N+2H, :, :] = 0
zero_north_halo!(c, H, N) = @views @. c[:, N+H+1:N+2H, :] = 0
  zero_top_halo!(c, H, N) = @views @. c[:, :, N+H+1:N+2H] = 0

function zero_halo_regions!(c::AbstractArray, grid)
      zero_west_halo!(c, grid.Hx, grid.Nx)
      zero_east_halo!(c, grid.Hx, grid.Nx)
     zero_south_halo!(c, grid.Hy, grid.Ny)
     zero_north_halo!(c, grid.Hy, grid.Ny)
       zero_top_halo!(c, grid.Hz, grid.Nz)
    zero_bottom_halo!(c, grid.Hz, grid.Nz)
    return nothing
end

function zero_halo_regions!(fields::Tuple, grid)
    for field in fields
        zero_halo_regions!(field, grid)
    end
    return nothing
end
