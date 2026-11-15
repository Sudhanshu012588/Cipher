module FEMColumn

using Ferrite, FerriteGmsh, SparseArrays, LinearAlgebra

export run_column_fem

function run_column_fem(
    msh_path::String,
    Pu_kN::Float64,
    bc_code::Int;
    eccentricity_mm::Float64=50.0,
    E_MPa::Float64=200e3,
    ν::Float64=0.3
)
    # 1. Load Gmsh mesh (in meters) and Physical Groups
    grid = togrid(msh_path)
    E = E_MPa * 1e6

    # Measure column bounding box (X = flange width, Y = column height L, Z = section depth)
    xs = [n.x[1] for n in grid.nodes]
    ys = [n.x[2] for n in grid.nodes]
    zs = [n.x[3] for n in grid.nodes]
    x_min, x_max = extrema(xs)
    y_min, y_max = extrema(ys)
    z_min, z_max = extrema(zs)

    B = max(x_max - x_min, 1e-6)
    L = max(y_max - y_min, 1e-6)
    D = max(z_max - z_min, 1e-6)
    x_mid = 0.5 * (x_min + x_max)

    # 2. 3D Linear Tetrahedral Interpolation & Quadrature
    ip = Lagrange{RefTetrahedron, 1}()^3
    qr = QuadratureRule{RefTetrahedron}(2)
    qr_face = FacetQuadratureRule{RefTetrahedron}(2)
    cv = CellValues(qr, ip)
    fv = FacetValues(qr_face, ip)

    dh = DofHandler(grid)
    add!(dh, :u, ip)
    close!(dh)

    # 3. Boundary Conditions (allow true end rotation for Pinned supports so column bows!)
    ch = ConstraintHandler(dh)
    bottom_set = getfacetset(grid, "bottom_face")
    top_set    = getfacetset(grid, "top_face")

    # Find nodes along the neutral web centerline (x ≈ x_mid) at bottom & top for true hinge rotation
    tol_y = 1e-3
    tol_x = max(0.06 * B, 5e-3)
    bottom_hinge = Set(filter(nid -> abs(grid.nodes[nid].x[2] - y_min) < tol_y && abs(grid.nodes[nid].x[1] - x_mid) <= tol_x, 1:getnnodes(grid)))
    top_hinge    = Set(filter(nid -> abs(grid.nodes[nid].x[2] - y_max) < tol_y && abs(grid.nodes[nid].x[1] - x_mid) <= tol_x, 1:getnnodes(grid)))

    if bc_code == 0
        # 0: Pinned-Pinned -> Y fixed at bottom, X & Z pinned along centerline at both ends (free to rotate & bow!)
        add!(ch, Dirichlet(:u, bottom_set, (x, t) -> [0.0], [2]))
        add!(ch, Dirichlet(:u, bottom_hinge, (x, t) -> [0.0, 0.0], [1, 3]))
        add!(ch, Dirichlet(:u, top_hinge, (x, t) -> [0.0, 0.0], [1, 3]))
    elseif bc_code == 1
        # 1: Fixed-Fixed -> Full bottom fixed, top X & Z clamped against rotation
        add!(ch, Dirichlet(:u, bottom_set, (x, t) -> [0.0, 0.0, 0.0], [1, 2, 3]))
        add!(ch, Dirichlet(:u, top_set, (x, t) -> [0.0, 0.0], [1, 3]))
    elseif bc_code == 2
        # 2: Fixed-Free (Cantilever) -> Full bottom fixed, top completely free to sway & rotate
        add!(ch, Dirichlet(:u, bottom_set, (x, t) -> [0.0, 0.0, 0.0], [1, 2, 3]))
    else
        # 3: Fixed-Pinned -> Full bottom fixed, top pinned along centerline (free to rotate)
        add!(ch, Dirichlet(:u, bottom_set, (x, t) -> [0.0, 0.0, 0.0], [1, 2, 3]))
        add!(ch, Dirichlet(:u, top_hinge, (x, t) -> [0.0, 0.0], [1, 3]))
    end
    close!(ch)

    # 4. Isotropic Steel Stiffness Tensor (Pa)
    λ = (E * ν) / ((1 + ν) * (1 - 2ν))
    μ = E / (2 * (1 + ν))
    δ(i, j) = i == j ? 1.0 : 0.0
    C = SymmetricTensor{4, 3}((i, j, k, l) -> λ * δ(i, j) * δ(k, l) + μ * (δ(i, k) * δ(j, l) + δ(i, l) * δ(j, k)))

    # 5. Compute Cross-Section Area A & Weak-Axis Second Moment of Area I_min from Top Facets
    top_area_m2 = 0.0
    I_yy_m4 = 0.0
    for facet in FacetIterator(dh, top_set)
        reinit!(fv, facet)
        for q in 1:getnquadpoints(fv)
            dΓ = getdetJdV(fv, q)
            x_q = spatial_coordinate(fv, q, getcoordinates(facet))
            top_area_m2 += dΓ
            I_yy_m4 += ((x_q[1] - x_mid)^2) * dΓ
        end
    end
    I_yy_m4 = max(I_yy_m4, 1e-9)

    P_N = Pu_kN * 1000.0
    sigma_axial_Pa = P_N / top_area_m2

    # Effective length factor k & Euler Critical Buckling Load P_cr (IS 800 Cl. 7.1.2)
    k_eff = bc_code == 1 ? 0.65 : (bc_code == 2 ? 2.0 : (bc_code == 3 ? 0.80 : 1.0))
    P_cr_N = (π^2 * E * I_yy_m4) / ((k_eff * L)^2)
    # Second-order P-Δ amplification factor: 1 / (1 - P / P_cr), capped at 6.0 for elastostatic stability
    amp_factor = clamp(1.0 / max(1.0 - (P_N / P_cr_N), 0.16), 1.0, 6.0)

    # Total eccentricity = user eccentricity + IS 800 initial bow (L / 1000)
    e_total_m = (eccentricity_mm / 1000.0) + (L / 1000.0)
    M_total_Nm = P_N * e_total_m * amp_factor

    bc_names = Dict(
        0 => "Pinned - Pinned (k = 1.0)",
        1 => "Fixed - Fixed (k = 0.65)",
        2 => "Fixed - Free / Cantilever (k = 2.0)",
        3 => "Fixed - Pinned (k = 0.80)"
    )

    # 6. Assemble Stiffness Matrix K & Load Vector f
    K = allocate_matrix(dh)
    f = zeros(ndofs(dh))
    assembler = start_assemble(K, f)
    n_base = getnbasefunctions(cv)
    Ke = zeros(n_base, n_base)
    fe_vol = zeros(n_base)

    # Equivalent distributed lateral load q_lat (N/m) producing second-order moment M_total
    q_lat = (bc_code == 2 ? 2.0 : (bc_code == 1 ? 12.0 : 8.0)) * M_total_Nm / (L^2)
    vol_m3 = top_area_m2 * L
    f_body_x = q_lat * L / vol_m3

    for cell in CellIterator(dh)
        fill!(Ke, 0.0)
        fill!(fe_vol, 0.0)
        reinit!(cv, cell)
        for q in 1:getnquadpoints(cv)
            dΩ = getdetJdV(cv, q)
            x_q = spatial_coordinate(cv, q, getcoordinates(cell))
            y_norm = clamp((x_q[2] - y_min) / L, 0.0, 1.0)
            shape_factor = bc_code == 2 ? (y_norm^2) : sin(π * y_norm)
            b_vec = Vec((f_body_x * shape_factor, 0.0, 0.0))

            for i in 1:n_base
                δε_i = shape_symmetric_gradient(cv, q, i)
                δu_i = shape_value(cv, q, i)
                fe_vol[i] += (δu_i ⋅ b_vec) * dΩ
                for j in 1:n_base
                    δε_j = shape_symmetric_gradient(cv, q, j)
                    Ke[i, j] += (δε_i ⊡ C ⊡ δε_j) * dΩ
                end
            end
        end
        assemble!(assembler, celldofs(cell), Ke, fe_vol)
    end

    # Apply eccentric axial compression on top face: σ(x) = -P/A - (M_end * (x - x_mid)) / I_yy
    M_end_Nm = (bc_code == 2) ? 0.0 : (P_N * (eccentricity_mm / 1000.0) * amp_factor)
    fe_face = zeros(n_base)
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

    # 7. Solve Linear System
    apply!(K, f, ch)
    u = K \ f

    # 8. Extract Axial Shortening, Lateral Bending Deflection, and Von Mises Stress Field
    n_cells = getncells(grid)
    n_nodes = getnnodes(grid)

    node_disp = Dict{Int, Vec{3, Float64}}()
    for cell in CellIterator(dh)
        dofs = celldofs(cell)
        for (local_i, nid) in enumerate(cell.nodes)
            if !haskey(node_disp, nid)
                base = 3 * (local_i - 1)
                node_disp[nid] = Vec((u[dofs[base + 1]], u[dofs[base + 2]], u[dofs[base + 3]]))
            end
        end
    end

    max_lateral_mm = maximum(hypot(d[1], d[3]) for d in values(node_disp)) * 1000.0
    max_axial_mm   = maximum(abs(d[2]) for d in values(node_disp)) * 1000.0
    max_disp_mm    = maximum(norm(d) for d in values(node_disp)) * 1000.0

    von_mises_MPa = zeros(n_cells)
    node_stress_sum = zeros(n_nodes)
    node_stress_count = zeros(Int, n_nodes)

    for (idx, cell) in enumerate(CellIterator(dh))
        reinit!(cv, cell)
        u_el = u[celldofs(cell)]
        ε = function_symmetric_gradient(cv, 1, u_el)
        σ = C ⊡ ε
        s_dev = dev(σ)
        vm = sqrt(1.5 * (s_dev ⊡ s_dev)) / 1e6
        von_mises_MPa[idx] = vm

        for node_id in cell.nodes
            node_stress_sum[node_id] += vm
            node_stress_count[node_id] += 1
        end
    end

    nodal_vm = [node_stress_count[i] > 0 ? node_stress_sum[i] / node_stress_count[i] : 0.0 for i in 1:n_nodes]
    min_vm, max_vm = extrema(nodal_vm)
    span_vm = max(max_vm - min_vm, 1e-6)

    function stress_rgb(val::Float64)
        t = clamp((val - min_vm) / span_vm, 0.0, 1.0)
        r = clamp(1.5 - abs(4.0 * t - 3.0), 0.0, 1.0)
        g = clamp(1.5 - abs(4.0 * t - 2.0), 0.0, 1.0)
        b = clamp(1.5 - abs(4.0 * t - 1.0), 0.0, 1.0)
        return (r, g, b)
    end

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
            if face_counts[key] == 1
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

    nominal_axial_MPa = sigma_axial_Pa / 1e6
    bending_stress_MPa = max(max_vm - nominal_axial_MPa, 0.0)

    return Dict(
        "top_area_mm2"              => round(top_area_m2 * 1e6, digits=2),
        "euler_buckling_kN"         => round(P_cr_N / 1000.0, digits=1),
        "p_delta_amplification"     => round(amp_factor, digits=2),
        "max_displacement_mm"       => round(max_disp_mm, digits=4),
        "max_axial_shortening_mm"   => round(max_axial_mm, digits=4),
        "max_lateral_deflection_mm" => round(max_lateral_mm, digits=4),
        "nominal_axial_MPa"         => round(nominal_axial_MPa, digits=2),
        "bending_stress_MPa"        => round(bending_stress_MPa, digits=2),
        "min_von_mises_MPa"         => round(min_vm, digits=2),
        "max_von_mises_MPa"         => round(max_vm, digits=2),
        "avg_von_mises_MPa"         => round(sum(von_mises_MPa) / length(von_mises_MPa), digits=2),
        "yield_ratio"               => round(max_vm / 250.0, digits=3),
        "boundary_condition_label"  => get(bc_names, bc_code, "Custom"),
        "mesh_nodes"                => n_nodes,
        "mesh_elements"             => n_cells,
        "positions"                 => positions,
        "displacements"             => displacements,
        "colors"                    => colors
    )
end

end