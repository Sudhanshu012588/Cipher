module FEM_Lacing

using Ferrite, FerriteGmsh, SparseArrays, LinearAlgebra

export run_lacing_column_fem

"""
    run_lacing_column_fem(msh_path, Pu_kN, bc_code; E_MPa, nu)

Solves 3D elastostatic compression for a built-up lacing column.
Loads Gmsh .msh mesh (two channel chords + diagonal lacing bars).
Returns Dict compatible with the frontend FEM viewer schema.
"""
function run_lacing_column_fem(
    msh_path::String,
    Pu_kN::Float64,
    bc_code::Int;
    E_MPa::Float64=200e3,
    nu::Float64=0.3,
    eccentricity_mm::Float64=50.0
)

    # ── 1. Load Gmsh mesh ────────────────────────────────────────
    grid = togrid(msh_path)
    E = E_MPa * 1e6   # Pa

    xs = [n.x[1] for n in grid.nodes]
    ys = [n.x[2] for n in grid.nodes]
    zs = [n.x[3] for n in grid.nodes]
    x_min, x_max = extrema(xs)
    y_min, y_max = extrema(ys)
    z_min, z_max = extrema(zs)

    col_width   = max(x_max - x_min, 1e-6)   # overall width (X direction)
    col_length  = max(y_max - y_min, 1e-6)   # column height (Y direction) — span L
    col_depth   = max(z_max - z_min, 1e-6)   # overall depth (Z direction)

    x_mid = 0.5 * (x_min + x_max)
    y_mid = 0.5 * (y_min + y_max)

    @info "Lacing column bbox: W=$(col_width) m, H=$(col_length) m, D=$(col_depth) m"

    # ── 2. Interpolation & quadrature (same as column FEM) ─────────
    ip = Lagrange{RefTetrahedron, 1}()^3
    qr = QuadratureRule{RefTetrahedron}(2)
    qr_face = FacetQuadratureRule{RefTetrahedron}(2)
    cv = CellValues(qr, ip)
    fv = FacetValues(qr_face, ip)

    dh = DofHandler(grid)
    add!(dh, :u, ip)
    close!(dh)

    # ── 3. Boundary Conditions (same as column FEM) ────────────────
    ch = ConstraintHandler(dh)

    bottom_set = getfacetset(grid, "bottom_face")
    top_set    = getfacetset(grid, "top_face")

    # Find centroid hinge nodes at both ends (for rotational freedom)
    tol_y = col_length * 0.03
    tol_x = max(0.06 * col_width, 5e-3)

    bottom_hinge = Set(filter(nid -> abs(grid.nodes[nid].x[2] - y_min) < tol_y && abs(grid.nodes[nid].x[1] - x_mid) <= tol_x, 1:getnnodes(grid)))
    top_hinge    = Set(filter(nid -> abs(grid.nodes[nid].x[2] - y_max) < tol_y && abs(grid.nodes[nid].x[1] - x_mid) <= tol_x, 1:getnnodes(grid)))

    if bc_code == 0
        # Pinned-Pinned: Y fixed at bottom, X&Z pinned at hinge lines both ends
        add!(ch, Dirichlet(:u, bottom_set, (x, t) -> [0.0], [2]))
        add!(ch, Dirichlet(:u, bottom_hinge, (x, t) -> [0.0, 0.0], [1, 3]))
        add!(ch, Dirichlet(:u, top_hinge, (x, t) -> [0.0, 0.0], [1, 3]))
    elseif bc_code == 1
        # Fixed-Fixed: full bottom fixed, top X&Z clamped at end face
        add!(ch, Dirichlet(:u, bottom_set, (x, t) -> [0.0, 0.0, 0.0], [1, 2, 3]))
        add!(ch, Dirichlet(:u, top_set, (x, t) -> [0.0, 0.0], [1, 3]))
    elseif bc_code == 2
        # Fixed-Free: full bottom fixed
        add!(ch, Dirichlet(:u, bottom_set, (x, t) -> [0.0, 0.0, 0.0], [1, 2, 3]))
    else
        # Fixed-Pinned: full bottom fixed, top hinge pinned
        add!(ch, Dirichlet(:u, bottom_set, (x, t) -> [0.0, 0.0, 0.0], [1, 2, 3]))
        add!(ch, Dirichlet(:u, top_hinge, (x, t) -> [0.0, 0.0], [1, 3]))
    end

    close!(ch)

    # ── 4. Stiffness Tensor (same as column FEM) ──────────────────
    λ = (E * nu) / ((1 + nu) * (1 - 2*nu))
    μ = E / (2 * (1 + nu))
    δ(i, j) = i == j ? 1.0 : 0.0
    C = SymmetricTensor{4, 3}((i, j, k, l) -> λ * δ(i,j) * δ(k,l) + μ * (δ(i,k) * δ(j,l) + δ(i,l) * δ(j,k)))

    # ── 5. Compute cross-section area and I for eccentricity ───────
    top_area_m2 = 0.0
    I_yy_m4     = 0.0   # weak axis (X-direction) second moment

    if !isempty(top_set)
        for facet in FacetIterator(dh, top_set)
            reinit!(fv, facet)
            for q in 1:getnquadpoints(fv)
                dΓ = getdetJdV(fv, q)
                x_q = spatial_coordinate(fv, q, getcoordinates(facet))
                top_area_m2 += dΓ
                I_yy_m4 += ((x_q[1] - x_mid)^2) * dΓ
            end
        end
    end

    I_yy_m4 = max(I_yy_m4, 1e-9)

    P_N = Pu_kN * 1000.0   # load in Newtons
    sigma_axial_Pa = P_N / top_area_m2

    # Effective length factor & Euler buckling (same as column FEM)
    k_eff = bc_code == 1 ? 0.65 : (bc_code == 2 ? 2.0 : (bc_code == 3 ? 0.80 : 1.0))
    P_cr_N = (π^2 * E * I_yy_m4) / ((k_eff * col_length)^2)

    # Second-order P-Δ amplification factor
    amp_factor = clamp(1.0 / max(1.0 - (P_N / P_cr_N), 0.16), 1.0, 6.0)

    # Total eccentricity = user input + IS 800 Cl. 7.1.2 initial bow
    e_total_m = (eccentricity_mm / 1000.0) + (col_length / 1000.0)
    M_total_Nm = P_N * e_total_m * amp_factor

    # Lateral load to produce equivalent moment
    bc_names = Dict(
        0 => "Pinned - Pinned (k = 1.0)",
        1 => "Fixed - Fixed (k = 0.65)",
        2 => "Fixed - Free / Cantilever (k = 2.0)",
        3 => "Fixed - Pinned (k = 0.80)"
    )

    q_lat = (bc_code == 2 ? 2.0 : (bc_code == 1 ? 12.0 : 8.0)) * M_total_Nm / (col_length^2)
    vol_m3 = top_area_m2 * col_length
    f_body_x = q_lat * col_length / vol_m3   # equivalent body force in X direction

    # ── 6. Assemble K & f ────────────────────────────────────────
    K = allocate_matrix(dh)
    f = zeros(ndofs(dh))
    assembler = start_assemble(K, f)
    n_base = getnbasefunctions(cv)
    Ke = zeros(n_base, n_base)
    fe_vol = zeros(n_base)

    # ── 7. Body force for lateral bending (P-Δ effect) ───────────
    for cell in CellIterator(dh)
        fill!(Ke, 0.0)
        fill!(fe_vol, 0.0)
        reinit!(cv, cell)
        for q in 1:getnquadpoints(cv)
            dΩ = getdetJdV(cv, q)
            x_q = spatial_coordinate(cv, q, getcoordinates(cell))
            y_norm = clamp((x_q[2] - y_min) / col_length, 0.0, 1.0)
            shape_factor = bc_code == 2 ? (y_norm^2) : sin(π * y_norm)

            b_vec = Vec((f_body_x * shape_factor, 0.0, 0.0))

            for i in 1:n_base
                δu_i = shape_value(cv, q, i)
                fe_vol[i] += (δu_i ⋅ b_vec) * dΩ
                for j in 1:n_base
                    δε_j = shape_symmetric_gradient(cv, q, j)
                    Ke[i,j] += (shape_symmetric_gradient(cv, q, i) ⊡ C ⊡ δε_j) * dΩ
                end
            end
        end
        assemble!(assembler, celldofs(cell), Ke, fe_vol)
    end

    # ── 8. Eccentric axial load on top face (same as column FEM) ──
    M_end_Nm = (bc_code == 2) ? 0.0 : (P_N * (eccentricity_mm / 1000.0) * amp_factor)
    fe_face = zeros(n_base)

    if !isempty(top_set)
        for facet in FacetIterator(dh, top_set)
            fill!(fe_face, 0.0)
            reinit!(fv, facet)
            for q in 1:getnquadpoints(fv)
                dΓ = getdetJdV(fv, q)
                x_q = spatial_coordinate(fv, q, getcoordinates(facet))
                sigma_bend_Pa = (M_end_Nm * (x_q[1] - x_mid)) / I_yy_m4
                traction = Vec((0.0, -(sigma_axial_Pa + sigma_bend_Pa), 0.0))

                for i in 1:n_base
                    δu_i = shape_value(fv, q, i)
                    fe_face[i] += (δu_i ⋅ traction) * dΓ
                end
            end
            assemble!(f, celldofs(facet), fe_face)
        end
    end

    # ── 9. Solve ─────────────────────────────────────────────────
    apply!(K, f, ch)
    u = K \ f

    # ── 10. Post-process: displacements + von Mises stress field ──
    n_cells = getncells(grid)
    n_nodes = getnnodes(grid)

    node_disp = Dict{Int, Vec{3, Float64}}()
    for cell in CellIterator(dh)
        dofs = celldofs(cell)
        for (local_i, nid) in enumerate(cell.nodes)
            base = 3 * (local_i - 1)
            if !haskey(node_disp, nid)
                node_disp[nid] = Vec((u[dofs[base+1]], u[dofs[base+2]], u[dofs[base+3]]))
            end
        end
    end

    max_deflection_mm = maximum(norm(d) for d in values(node_disp)) * 1000.0
    max_downward_mm   = maximum(abs(d[2]) for d in values(node_disp)) * 1000.0
    max_lateral_mm    = maximum(hypot(d[1], d[3]) for d in values(node_disp)) * 1000.0

    von_mises_MPa = zeros(n_cells)
    node_stress_sum = zeros(n_nodes)
    node_stress_count = zeros(Int, n_nodes)

    for (idx, cell) in enumerate(CellIterator(dh))
        reinit!(cv, cell)
        u_el = u[celldofs(cell)]
        ε = function_symmetric_gradient(cv, 1, u_el)
        σ = C ⊡ ε
        s_dev = dev(σ)
        vm = sqrt(1.5 * (s_dev ⊡ s_dev)) / 1e6   # MPa
        von_mises_MPa[idx] = vm

        for nid in cell.nodes
            node_stress_sum[nid] += vm
            node_stress_count[nid] += 1
        end
    end

    nodal_vm = [node_stress_count[i] > 0 ? node_stress_sum[i] / node_stress_count[i] : 0.0 for i in 1:n_nodes]
    min_vm, max_vm = extrema(nodal_vm)
    span_vm = max(max_vm - min_vm, 1e-6)

    nominal_axial_MPa = sigma_axial_Pa / 1e6
    bending_stress_MPa = max(max_vm - nominal_axial_MPa, 0.0)

    # ── 11. Stress coloring (same "fire" colormap as column FEM) ───
    function stress_rgb(val::Float64)
        t = clamp((val - min_vm) / span_vm, 0.0, 1.0)
        r = clamp(1.5 - abs(4.0*t - 3.0), 0.0, 1.0)
        g = clamp(1.5 - abs(4.0*t - 2.0), 0.0, 1.0)
        b = clamp(1.5 - abs(4.0*t - 1.0), 0.0, 1.0)
        return (r, g, b)
    end

    # ── 12. Build deformed mesh face arrays for Three.js ───────────
    positions     = Float32[]
    displacements = Float32[]
    colors        = Float32[]

    tet_faces = ((1, 3, 2), (1, 2, 4), (2, 3, 4), (1, 4, 3))

    face_counts = Dict{NTuple{3, Int}, Int}()
    for cell in grid.cells
        for f_idx in tet_faces
            tri = (cell.nodes[f_idx[1]], cell.nodes[f_idx[2]], cell.nodes[f_idx[3]])
            key = Tuple(sort(collect(tri)))
            face_counts[key] = get(face_counts, key, 0) + 1
        end
    end

    for cell in grid.cells
        for f_idx in tet_faces
            tri = (cell.nodes[f_idx[1]], cell.nodes[f_idx[2]], cell.nodes[f_idx[3]])
            key = Tuple(sort(collect(tri)))
            if get(face_counts, key, 0) == 1
                for nid in tri
                    coord = grid.nodes[nid].x
                    disp  = get(node_disp, nid, Vec((0.0, 0.0, 0.0)))
                    push!(positions, Float32(coord[1]), Float32(coord[2]), Float32(coord[3]))
                    push!(displacements, Float32(disp[1]), Float32(disp[2]), Float32(disp[3]))
                    r, g, b = stress_rgb(nodal_vm[nid])
                    push!(colors, Float32(r), Float32(g), Float32(b))
                end
            end
        end
    end

    return Dict(
        "max_deflection_mm"           => round(max_deflection_mm, digits=4),
        "max_downward_deflection"     => round(max_downward_mm, digits=4),
        "max_lateral_deflection"      => round(max_lateral_mm, digits=4),
        "nominal_axial_MPa"           => round(nominal_axial_MPa, digits=2),
        "bending_stress_MPa"          => round(bending_stress_MPa, digits=2),
        "min_von_mises_MPa"           => round(min_vm, digits=2),
        "max_von_mises_MPa"           => round(max_vm, digits=2),
        "avg_von_mises_MPa"           => round(sum(von_mises_MPa) / length(von_mises_MPa), digits=2),
        "yield_ratio"                 => round(max_vm / 250.0, digits=3),
        "boundary_condition_label"    => get(bc_names, bc_code, "Custom"),
        "euler_buckling_kN"           => round(P_cr_N / 1000.0, digits=1),
        "p_delta_amplification"       => round(amp_factor, digits=2),
        "mesh_nodes"                  => n_nodes,
        "mesh_elements"               => n_cells,
        "positions"                   => positions,
        "displacements"               => displacements,
        "colors"                      => colors,
    )
end

end  # module FEM_Lacing
