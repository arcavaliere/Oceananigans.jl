#####
##### Navier-Stokes and tracer advection equations
#####

""" Calculate the right-hand-side of the u-momentum equation. """
function calculate_Gu!(Gu, grid, coriolis, surface_waves, closure, U, C, K, F, pHY′, parameters, time)
    @loop_xyz i j k grid begin
        @inbounds Gu[i, j, k] = ( - div_ũu(i, j, k, grid, U)
                                  - x_f_cross_U(i, j, k, grid, coriolis, U)
                                  - ∂xᶠᵃᵃ(i, j, k, grid, pHY′)
                                  + ∂ⱼ_2ν_Σ₁ⱼ(i, j, k, grid, closure, U, K)
                                  + x_curl_Uˢ_cross_U(i, j, k, grid, surface_waves, U, time)
                                  + ∂t_uˢ(i, j, k, grid, surface_waves, time)
                                  + F.u(i, j, k, grid, time, U, C, parameters)
        )
    end
    return nothing
end

""" Calculate the right-hand-side of the v-momentum equation. """
function calculate_Gv!(Gv, grid, coriolis, surface_waves, closure, U, C, K, F, pHY′, parameters, time)
    @loop_xyz i j k grid begin
        @inbounds Gv[i, j, k] = ( - div_ũv(i, j, k, grid, U)
                                  - y_f_cross_U(i, j, k, grid, coriolis, U)
                                  - ∂yᵃᶠᵃ(i, j, k, grid, pHY′)
                                  + ∂ⱼ_2ν_Σ₂ⱼ(i, j, k, grid, closure, U, K)
                                  + y_curl_Uˢ_cross_U(i, j, k, grid, surface_waves, U, time)
                                  + ∂t_vˢ(i, j, k, grid, surface_waves, time)
                                  + F.v(i, j, k, grid, time, U, C, parameters))
    end
    return nothing
end

""" Calculate the right-hand-side of the w-momentum equation. """
function calculate_Gw!(Gw, grid, coriolis, surface_waves, closure, U, C, K, F, parameters, time)
    @loop_xyz i j k grid begin
        @inbounds Gw[i, j, k] = ( - div_ũw(i, j, k, grid, U)
                                  - z_f_cross_U(i, j, k, grid, coriolis, U)
                                  + ∂ⱼ_2ν_Σ₃ⱼ(i, j, k, grid, closure, U, K)
                                  + z_curl_Uˢ_cross_U(i, j, k, grid, surface_waves, U, time)
                                  + ∂t_wˢ(i, j, k, grid, surface_waves, time)
                                  + F.w(i, j, k, grid, time, U, C, parameters))
    end
    return nothing
end

""" Calculate the right-hand-side of the tracer advection-diffusion equation. """
function calculate_Gc!(Gc, grid, c, tracer_index, closure, buoyancy, U, C, K, Fc, parameters, time)
    @loop_xyz i j k grid begin
        @inbounds Gc[i, j, k] = (- div_uc(i, j, k, grid, U, c)
                                 + ∇_κ_∇c(i, j, k, grid, closure, c, tracer_index, K, C, buoyancy)
                                 + Fc(i, j, k, grid, time, U, C, parameters))
    end
    return nothing
end

""" Store previous value of the source term and calculate current source term. """
function calculate_interior_source_terms!(G, arch, grid, coriolis, buoyancy, surface_waves, closure, U, C, pHY′, K, F, parameters, time)
    # Manually choose thread-block layout here as it's ~20% faster.
    # See: https://github.com/climate-machine/Oceananigans.jl/pull/308
    Tx, Ty = 16, 16 # CUDA threads per block
    Bx, By, Bz = floor(Int, grid.Nx/Tx), floor(Int, grid.Ny/Ty), grid.Nz  # Blocks in grid

    @launch(device(arch), threads=(Tx, Ty), blocks=(Bx, By, Bz),
            calculate_Gu!(G.u, grid, coriolis, surface_waves, closure, U, C, K, F, pHY′, parameters, time))

    @launch(device(arch), threads=(Tx, Ty), blocks=(Bx, By, Bz),
            calculate_Gv!(G.v, grid, coriolis, surface_waves, closure, U, C, K, F, pHY′, parameters, time))

    @launch(device(arch), threads=(Tx, Ty), blocks=(Bx, By, Bz),
            calculate_Gw!(G.w, grid, coriolis, surface_waves, closure, U, C, K, F, parameters, time))

    for tracer_index in 1:length(C)
        @inbounds Gc = G[tracer_index+3]
        @inbounds Fc = F[tracer_index+3]
        @inbounds  c = C[tracer_index]

        @launch(device(arch), threads=(Tx, Ty), blocks=(Bx, By, Bz),
                calculate_Gc!(Gc, grid, c, Val(tracer_index), closure, buoyancy, U, C, K, Fc, parameters, time))
    end

    return nothing
end

""" Apply boundary conditions by adding flux divergences to the right-hand-side. """
function calculate_boundary_source_terms!(Gⁿ, bcs, arch, grid, args...)

    # Velocity fields
    for i in 1:3
        ubcs = bcs[i]
        apply_z_bcs!(Gⁿ[i], arch, grid, ubcs.z.bottom, ubcs.z.top,   args...)
        apply_y_bcs!(Gⁿ[i], arch, grid, ubcs.y.left,   ubcs.y.right, args...)
    end

    # Tracer fields
    for i in 4:length(bcs)
        cbcs = bcs[i]
        apply_z_bcs!(Gⁿ[i], arch, grid, cbcs.z.bottom, cbcs.z.top,   args...)
        apply_y_bcs!(Gⁿ[i], arch, grid, cbcs.y.left,   cbcs.y.right, args...)
    end

    return nothing
end

#####
##### Pressure-related functions
#####

"Solve the Poisson equation for non-hydrostatic pressure on the CPU."
function solve_for_pressure!(pressure, ::CPU, grid, poisson_solver, ϕ)
    solve_poisson_3d!(poisson_solver, grid)
    view(pressure, 1:grid.Nx, 1:grid.Ny, 1:grid.Nz) .= real.(ϕ)
    return nothing
end

"Solve the Poisson equation for non-hydrostatic pressure on the GPU."
function solve_for_pressure!(pressure, ::GPU, grid, poisson_solver, ϕ)
    solve_poisson_3d!(poisson_solver, grid)
    @launch device(GPU()) config=launch_config(grid, :xyz) idct_permute!(pressure, grid, poisson_solver.bcs, ϕ)
    return nothing
end

"""
Update the hydrostatic pressure perturbation pHY′. This is done by integrating
the `buoyancy_perturbation` downwards:

    `pHY′ = ∫ buoyancy_perturbation dz` from `z=0` down to `z=-Lz`
"""
function update_hydrostatic_pressure!(pHY′, grid, buoyancy, C)
    @loop for j in (1:grid.Ny; (blockIdx().y - 1) * blockDim().y + threadIdx().y)
        @loop for i in (1:grid.Nx; (blockIdx().x - 1) * blockDim().x + threadIdx().x)
            @inbounds pHY′[i, j, grid.Nz] = - ℑzᵃᵃᶠ(i, j, grid.Nz, grid, buoyancy_perturbation, buoyancy, C) * ΔzF(i, j, grid.Nz, grid)
            @unroll for k in grid.Nz-1 : -1 : 1
                @inbounds pHY′[i, j, k] =
                    pHY′[i, j, k+1] - ℑzᵃᵃᶠ(i, j, k+1, grid, buoyancy_perturbation, buoyancy, C) * ΔzF(i, j, k, grid)
            end
        end
    end
    return nothing
end

"""
Calculate the right-hand-side of the Poisson equation for the non-hydrostatic
pressure

    `∇²ϕ_{NH}^{n+1} = (∇·u^n)/Δt + ∇·(Gu, Gv, Gw)`
"""
function calculate_poisson_right_hand_side!(RHS, ::CPU, grid, ::PoissonBCs, U, G, Δt)
    @loop_xyz i j k grid begin
            @inbounds RHS[i, j, k] = divᶜᶜᶜ(i, j, k, grid, U.u, U.v, U.w) / Δt +
                                     divᶜᶜᶜ(i, j, k, grid, G.u, G.v, G.w)
    end

    return nothing
end

"""
Calculate the right-hand-side of the Poisson equation for the non-hydrostatic
pressure and in the process apply the permutation

    [a, b, c, d, e, f, g, h] -> [a, c, e, g, h, f, d, b]

in the z-direction which is required by the GPU fast cosine transform algorithm for
horizontally periodic model configurations.
"""
function calculate_poisson_right_hand_side!(RHS, ::GPU, grid, ::PPN, U, G, Δt)
    Nz = grid.Nz
    @loop_xyz i j k grid begin
        if (k & 1) == 1  # isodd(k)
            k′ = convert(UInt32, CUDAnative.floor(k/2) + 1)
        else
            k′ = convert(UInt32, Nz - CUDAnative.floor((k-1)/2))
        end

        @inbounds RHS[i, j, k′] = divᶜᶜᶜ(i, j, k, grid, U.u, U.v, U.w) / Δt +
                                  divᶜᶜᶜ(i, j, k, grid, G.u, G.v, G.w)
    end
    return nothing
end

"""
Calculate the right-hand-side of the Poisson equation for the non-hydrostatic
pressure and in the process apply the permutation

    [a, b, c, d, e, f, g, h] -> [a, c, e, g, h, f, d, b]

in the y- and z-directions which is required by the GPU fast cosine transform algorithm for
reentrant channel model configurations.
"""
function calculate_poisson_right_hand_side!(RHS, ::GPU, grid, ::PNN, U, G, Δt)
    Ny, Nz = grid.Ny, grid.Nz
    @loop_xyz i j k grid begin
        if (k & 1) == 1  # isodd(k)
            k′ = convert(UInt32, CUDAnative.floor(k/2) + 1)
        else
            k′ = convert(UInt32, Nz - CUDAnative.floor((k-1)/2))
        end

        if (j & 1) == 1  # isodd(j)
            j′ = convert(UInt32, CUDAnative.floor(j/2) + 1)
        else
            j′ = convert(UInt32, Ny - CUDAnative.floor((j-1)/2))
        end

        @inbounds RHS[i, j′, k′] = divᶜᶜᶜ(i, j, k, grid, U.u, U.v, U.w) / Δt +
                                   divᶜᶜᶜ(i, j, k, grid, G.u, G.v, G.w)
    end
    return nothing
end

"""
Copy the non-hydrostatic pressure into `pNHS` and undo the permutation

    [a, b, c, d, e, f, g, h] -> [a, c, e, g, h, f, d, b]

along the z-direction.
"""
function idct_permute!(pNHS, grid, ::PPN, ϕ)
    Nz = grid.Nz
    @loop_xyz i j k grid begin
        if k <= Nz/2
            @inbounds pNHS[i, j, 2k-1] = real(ϕ[i, j, k])
        else
            @inbounds pNHS[i, j, 2(Nz-k+1)] = real(ϕ[i, j, k])
        end
    end
    return nothing
end

"""
Copy the non-hydrostatic pressure into `pNHS` and undo the permutation

    [a, b, c, d, e, f, g, h] -> [a, c, e, g, h, f, d, b]

along the y- and z-direction.
"""
function idct_permute!(pNHS, grid, ::PNN, ϕ)
    Ny, Nz = grid.Ny, grid.Nz
    @loop_xyz i j k grid begin
        if k <= Nz/2
            k′ = 2k-1
        else
            k′ = 2(Nz-k+1)
        end

        if j <= Ny/2
            j′ = 2j-1
        else
            j′ = 2(Ny-j+1)
        end

        @inbounds pNHS[i, j′, k′] = real(ϕ[i, j, k])
    end
    return nothing
end

"""
Update the horizontal velocities u and v via

    `u^{n+1} = u^n + (Gu^{n+½} - δₓp_{NH} / Δx) Δt`

Note that the vertical velocity is not explicitly time stepped.
"""
function update_velocities!(U, grid, Δt, G, pNHS)
    @loop_xyz i j k grid begin
        @inbounds U.u[i, j, k] += (G.u[i, j, k] - ∂xᶠᵃᵃ(i, j, k, grid, pNHS)) * Δt
        @inbounds U.v[i, j, k] += (G.v[i, j, k] - ∂yᵃᶠᵃ(i, j, k, grid, pNHS)) * Δt
    end
    return nothing
end

"""
Update the horizontal velocities u and v via

    `u^{n+1} = u^n + Gu^{n+½} / Δt`

Note that the vertical velocity is not explicitly time stepped.
"""
function update_velocities!(U, grid, Δt, G, ::Nothing)
    @loop_xyz i j k grid begin
        @inbounds U.u[i, j, k] += G.u[i, j, k] * Δt
        @inbounds U.v[i, j, k] += G.v[i, j, k] * Δt
    end
    return nothing
end

"""
Update tracers via

    `c^{n+1} = c^n + Gc^{n+½} Δt`
"""
function update_tracer!(c, grid, Δt, Gc)
    @loop_xyz i j k grid begin
        @inbounds c[i, j, k] += Gc[i, j, k] * Δt
    end
    return nothing
end

"Update the solution variables (velocities and tracers)."
function update_solution!(U, C, arch, grid, Δt, G, pNHS)
    @launch device(arch) config=launch_config(grid, :xyz) update_velocities!(U, grid, Δt, G, pNHS)

    for i in 1:length(C)
        @inbounds c = C[i]
        @inbounds Gc = G[i+3]
        @launch device(arch) config=launch_config(grid, :xyz) update_tracer!(c, grid, Δt, Gc)
    end

    return nothing
end

"""
Compute the vertical velocity w by integrating the continuity equation from the bottom upwards

    `w^{n+1} = -∫ [∂/∂x (u^{n+1}) + ∂/∂y (v^{n+1})] dz`
"""
function compute_w_from_continuity!(model)
    @launch(device(model.architecture), config=launch_config(model.grid, :xy),
            _compute_w_from_continuity!(datatuple(model.velocities), model.grid))
    return nothing
end

function _compute_w_from_continuity!(U, grid)
    @loop for j in (1:grid.Ny; (blockIdx().y - 1) * blockDim().y + threadIdx().y)
        @loop for i in (1:grid.Nx; (blockIdx().x - 1) * blockDim().x + threadIdx().x)
            # U.w[i, j, 1] = 0 is enforced via halo regions.
            @unroll for k in 2:grid.Nz
                @inbounds U.w[i, j, k] = U.w[i, j, k-1] - ΔzC(i, j, k, grid) * hdivᶜᶜᵃ(i, j, k-1, grid, U.u, U.v)
            end
        end
    end

    return nothing
end
