module FEM_Lacing

using Ferrite, FerriteGmsh, SparseArrays, LinearAlgebra

export run_lacing_column_fem

# Nodes of a facet set
function _facetset_nodes(grid, fset)
    ns = Set{Int}()
    for fi in fset
        for nid in Ferrite.facets(grid.cells[fi[1]])[fi[2]]
            push!(ns, nid)
        end
    end
    return ns
end

# Nodes of `nset` within radius r of (xc, zc); falls back to the 4 nearest nodes
function _pin_patch(grid, nset, xc, zc, r)
    dist(nid) = hypot(grid.nodes[nid].x[1] - xc, grid.nodes[nid].x[3] - zc)
    sel = [nid for nid in nset if dist(nid) <= r]
    if length(sel) < 3
        sel = sort(collect(nset), by = dist)[1:min(4, length(nset))]
    end
    return Set(sel)
end

"""
    run_lacing_column_fem(msh_path, Pu_kN, bc_code; E_MPa, nu, end_plate_m, chord_depth_m)

Linear elastostatic analysis of the laced column mesh from Mesh_Lacing.jl (Y = column axis).

Load case (IS 800:2007):
  * factored axial load Pu as uniform pressure on the outer face of the cap plate
  * transverse shear Vt = 2.5 % Pu (Cl. 7.6.6.1) applied in X (the lacing plane) as a body force
    on a short band of the column: 2·Vt at mid-height (pinned / fixed ends, giving shear Vt over
    the whole length) or Vt at the free end (cantilever); multiplied by the P-Δ factor 1/(1 - P/Pcr)

Supports (outer faces of the end plates):
  0 pinned-pinned : bottom patch fixed in X,Y,Z; top patch fixed in X,Z       (rotation free)
  1 fixed-fixed   : bottom face fixed; top face fixed in X,Z and tied in Y     (no rotation, axial slip)
  2 fixed-free    : bottom face fixed
  3 fixed-pinned  : bottom face fixed; top patch fixed in X,Z

`end_plate_m` must equal END_PLATE_MM/1000 in Mesh_Lacing.jl. Pass `chord_depth_m` (Chord_Depth_mm/1000)
so area / inertia are taken from the chords only (excluding lacing and tie plates).
Stress statistics ignore cells inside the end plates, where the support idealisation is not meaningful.
"""
function run_lacing_column_fem(
    msh_path::String,
    Pu_kN::Float64,
    bc_code::Int;
    E_MPa::Float64 = 200e3,
    nu::Float64 = 0.3,
    end_plate_m::Float64 = 0.020,
    chord_depth_m::Union{Nothing,Float64} = nothing,
    kwargs...,
)
    # ── 1. Mesh and geometry ─────────────────────────────────────────────
    grid = togrid(msh_path)
    E = E_MPa * 1e6
    n_nodes = getnnodes(grid)
    n_cells = getncells(grid)

    xs = [n.x[1] for n in grid.nodes]
    ys = [n.x[2] for n in grid.nodes]
    zs = [n.x[3] for n in grid.nodes]
    x_min, x_max = extrema(xs)
    y_min, y_max = extrema(ys)
    z_min, z_max = extrema(zs)
    x_c = 0.5 * (x_min + x_max)
    z_c = 0.5 * (z_min + z_max)

    y_col_lo = y_min + end_plate_m
    y_col_hi = y_max - end_plate_m
    L_col = y_col_hi - y_col_lo
    y_mid = 0.5 * (y_col_lo + y_col_hi)
    @info "Lacing column FEM" L_col width = x_max - x_min depth = z_max - z_min

    # ── 2. Interpolation, quadrature, dofs ───────────────────────────────
    ip = Lagrange{RefTetrahedron, 1}()^3
    qr = QuadratureRule{RefTetrahedron}(2)
    qr_face = FacetQuadratureRule{RefTetrahedron}(2)
    cv = CellValues(qr, ip)
    fv = FacetValues(qr_face, ip)

    dh = DofHandler(grid)
    add!(dh, :u, ip)
    close!(dh)

    node_dofs = Dict{Int, NTuple{3, Int}}()
    for cell in CellIterator(dh)
        dofs = celldofs(cell)
        for (i, nid) in enumerate(cell.nodes)
            haskey(node_dofs, nid) || (node_dofs[nid] = (dofs[3i - 2], dofs[3i - 1], dofs[3i]))
        end
    end

    # ── 3. Boundary conditions ───────────────────────────────────────────
    bottom_set = getfacetset(grid, "bottom_face")
    top_set    = getfacetset(grid, "top_face")
    (isempty(bottom_set) || isempty(top_set)) &&
        error("Mesh must contain physical groups 'bottom_face' and 'top_face'. Regenerate with Mesh_Lacing.jl.")

    bottom_nodes = _facetset_nodes(grid, bottom_set)
    top_nodes    = _facetset_nodes(grid, top_set)
    r_pin = 1.5 * end_plate_m
    bottom_patch = _pin_patch(grid, bottom_nodes, x_c, z_c, r_pin)
    top_patch    = _pin_patch(grid, top_nodes, x_c, z_c, r_pin)

    ch = ConstraintHandler(dh)
    if bc_code == 0
        add!(ch, Dirichlet(:u, bottom_patch, (x, t) -> [0.0, 0.0, 0.0], [1, 2, 3]))
        add!(ch, Dirichlet(:u, top_patch, (x, t) -> [0.0, 0.0], [1, 3]))
    elseif bc_code == 1
        add!(ch, Dirichlet(:u, bottom_set, (x, t) -> [0.0, 0.0, 0.0], [1, 2, 3]))
        add!(ch, Dirichlet(:u, top_set, (x, t) -> [0.0, 0.0], [1, 3]))
        # keep the cap plate face planar in Y (no end rotation) while it can still shorten axially
        master = argmin(nid -> hypot(grid.nodes[nid].x[1] - x_c, grid.nodes[nid].x[3] - z_c), collect(top_nodes))
        m_dof = node_dofs[master][2]
        for nid in top_nodes
            nid == master && continue
            add!(ch, AffineConstraint(node_dofs[nid][2], [m_dof => 1.0], 0.0))
        end
    elseif bc_code == 2
        add!(ch, Dirichlet(:u, bottom_set, (x, t) -> [0.0, 0.0, 0.0], [1, 2, 3]))
    else
        add!(ch, Dirichlet(:u, bottom_set, (x, t) -> [0.0, 0.0, 0.0], [1, 2, 3]))
        add!(ch, Dirichlet(:u, top_patch, (x, t) -> [0.0, 0.0], [1, 3]))
    end
    close!(ch)

    # ── 4. Material ──────────────────────────────────────────────────────
    λ = (E * nu) / ((1 + nu) * (1 - 2nu))
    μ = E / (2 * (1 + nu))
    δ(i, j) = i == j ? 1.0 : 0.0
    C = SymmetricTensor{4, 3}((i, j, k, l) -> λ * δ(i, j) * δ(k, l) + μ * (δ(i, k) * δ(j, l) + δ(i, l) * δ(j, k)))

    # ── 5. Cell pre-pass: centroids, volumes, interior flags, section properties ──
    cx = zeros(n_cells); cy = zeros(n_cells); cz = zeros(n_cells); cvol = zeros(n_cells)
    for cell in CellIterator(dh)
        reinit!(cv, cell)
        cid = cellid(cell)
        X = getcoordinates(cell)
        nv = length(X)
        cx[cid] = sum(p[1] for p in X) / nv
        cy[cid] = sum(p[2] for p in X) / nv
        cz[cid] = sum(p[3] for p in X) / nv
        cvol[cid] = sum(getdetJdV(cv, q) for q in 1:getnquadpoints(cv))
    end

    interior = [y_col_lo <= cy[i] <= y_col_hi for i in 1:n_cells]
    chord_cell = chord_depth_m === nothing ? interior :
        [interior[i] && abs(cz[i] - z_c) <= 0.5 * chord_depth_m for i in 1:n_cells]

    A_col  = sum(cvol[i] for i in 1:n_cells if chord_cell[i]) / L_col                         # m²
    I_weak = sum(cvol[i] * (cx[i] - x_c)^2 for i in 1:n_cells if chord_cell[i]) / L_col       # m⁴, about Z

    P_N = Pu_kN * 1000.0
    k_eff = bc_code == 1 ? 0.65 : (bc_code == 2 ? 2.0 : (bc_code == 3 ? 0.80 : 1.0))
    P_cr_N = π^2 * E * I_weak / (k_eff * L_col)^2
    amp = clamp(1.0 / max(1.0 - P_N / P_cr_N, 1 / 6), 1.0, 6.0)

    # IS 800 Cl. 7.6.6.1: transverse shear Vt = 2.5 % of axial force
    V_t_N = 0.025 * P_N
    F_lat = (bc_code == 2 ? 1.0 : 2.0) * V_t_N * amp
    band = max(0.05 * L_col, 0.10)
    in_band = bc_code == 2 ?
        [interior[i] && cy[i] >= y_col_hi - band for i in 1:n_cells] :
        [interior[i] && abs(cy[i] - y_mid) <= 0.5 * band for i in 1:n_cells]
    vol_band = sum(cvol[i] for i in 1:n_cells if in_band[i])
    vol_band > 0 || error("Lateral load band contains no cells; mesh too coarse.")
    bx = F_lat / vol_band     # N/m³ in +X

    # ── 6. Assemble K and body force ─────────────────────────────────────
    K = allocate_matrix(dh, ch)
    f = zeros(ndofs(dh))
    assembler = start_assemble(K, f)
    n_base = getnbasefunctions(cv)
    Ke = zeros(n_base, n_base)
    fe = zeros(n_base)
    b_vec = Vec((bx, 0.0, 0.0))

    for cell in CellIterator(dh)
        reinit!(cv, cell)
        cid = cellid(cell)
        fill!(Ke, 0.0)
        fill!(fe, 0.0)
        for q in 1:getnquadpoints(cv)
            dΩ = getdetJdV(cv, q)
            for i in 1:n_base
                δε_i = shape_symmetric_gradient(cv, q, i)
                if in_band[cid]
                    fe[i] += (shape_value(cv, q, i) ⋅ b_vec) * dΩ
                end
                for j in 1:n_base
                    Ke[i, j] += (δε_i ⊡ C ⊡ shape_symmetric_gradient(cv, q, j)) * dΩ
                end
            end
        end
        assemble!(assembler, celldofs(cell), Ke, fe)
    end

    # ── 7. Axial load: uniform pressure on the cap plate outer face ───────
    top_area = 0.0
    for facet in FacetIterator(dh, top_set)
        reinit!(fv, facet)
        for q in 1:getnquadpoints(fv)
            top_area += getdetJdV(fv, q)
        end
    end
    traction = Vec((0.0, -P_N / top_area, 0.0))
    fe_face = zeros(n_base)
    for facet in FacetIterator(dh, top_set)
        reinit!(fv, facet)
        fill!(fe_face, 0.0)
        for q in 1:getnquadpoints(fv)
            dΓ = getdetJdV(fv, q)
            for i in 1:n_base
                fe_face[i] += (shape_value(fv, q, i) ⋅ traction) * dΓ
            end
        end
        assemble!(f, celldofs(facet), fe_face)
    end

    # ── 8. Solve ─────────────────────────────────────────────────────────
    apply!(K, f, ch)
    u = K \ f
    apply!(u, ch)     # fills slave dofs of the affine (rigid cap) constraint
    if any(!isfinite, u) || maximum(abs, u) > 0.5 * L_col
        error("FEM solution is not physical (disconnected parts or rigid-body modes). Check the mesh and supports.")
    end

    # ── 9. Post-processing ───────────────────────────────────────────────
    node_disp = Dict{Int, Vec{3, Float64}}()
    for (nid, d) in node_dofs
        node_disp[nid] = Vec((u[d[1]], u[d[2]], u[d[3]]))
    end

    max_deflection_mm = maximum(norm(d) for d in values(node_disp)) * 1000.0
    max_downward_mm   = maximum(abs(d[2]) for d in values(node_disp)) * 1000.0
    max_lateral_mm    = maximum(hypot(d[1], d[3]) for d in values(node_disp)) * 1000.0

    von_mises_MPa = zeros(n_cells)
    node_sum = zeros(n_nodes)
    node_cnt = zeros(Int, n_nodes)
    node_in  = falses(n_nodes)
    for cell in CellIterator(dh)
        reinit!(cv, cell)
        cid = cellid(cell)
        ε = function_symmetric_gradient(cv, 1, u[celldofs(cell)])
        s_dev = dev(C ⊡ ε)
        vm = sqrt(1.5 * (s_dev ⊡ s_dev)) / 1e6
        von_mises_MPa[cid] = vm
        for nid in cell.nodes
            node_sum[nid] += vm
            node_cnt[nid] += 1
            interior[cid] && (node_in[nid] = true)
        end
    end
    nodal_vm = [node_cnt[i] > 0 ? node_sum[i] / node_cnt[i] : 0.0 for i in 1:n_nodes]
    min_vm, max_vm = extrema(nodal_vm[node_in])
    span_vm = max(max_vm - min_vm, 1e-6)

    nominal_axial_MPa = P_N / A_col / 1e6
    bending_stress_MPa = max(max_vm - nominal_axial_MPa, 0.0)

    stress_rgb(val) = begin
        t = clamp((val - min_vm) / span_vm, 0.0, 1.0)
        (clamp(1.5 - abs(4t - 3), 0.0, 1.0), clamp(1.5 - abs(4t - 2), 0.0, 1.0), clamp(1.5 - abs(4t - 1), 0.0, 1.0))
    end

    # Outer skin triangles (faces used by exactly one tet)
    tet_faces = ((1, 3, 2), (1, 2, 4), (2, 3, 4), (1, 4, 3))
    face_counts = Dict{NTuple{3, Int}, Int}()
    for cell in grid.cells
        for fidx in tet_faces
            key = Tuple(sort([cell.nodes[fidx[1]], cell.nodes[fidx[2]], cell.nodes[fidx[3]]]))
            face_counts[key] = get(face_counts, key, 0) + 1
        end
    end

    positions = Float32[]; displacements = Float32[]; colors = Float32[]
    for cell in grid.cells
        for fidx in tet_faces
            tri = (cell.nodes[fidx[1]], cell.nodes[fidx[2]], cell.nodes[fidx[3]])
            face_counts[Tuple(sort(collect(tri)))] == 1 || continue
            for nid in tri
                c = grid.nodes[nid].x
                d = node_disp[nid]
                push!(positions, Float32(c[1]), Float32(c[2]), Float32(c[3]))
                push!(displacements, Float32(d[1]), Float32(d[2]), Float32(d[3]))
                r, g, b = stress_rgb(nodal_vm[nid])
                push!(colors, Float32(r), Float32(g), Float32(b))
            end
        end
    end

    bc_names = Dict(
        0 => "Pinned - Pinned (k = 1.0)",
        1 => "Fixed - Fixed (k = 0.65)",
        2 => "Fixed - Free / Cantilever (k = 2.0)",
        3 => "Fixed - Pinned (k = 0.80)",
    )

    return Dict(
        "max_deflection_mm"        => round(max_deflection_mm, digits = 4),
        "max_downward_deflection"  => round(max_downward_mm, digits = 4),
        "max_lateral_deflection"   => round(max_lateral_mm, digits = 4),
        "nominal_axial_MPa"        => round(nominal_axial_MPa, digits = 2),
        "bending_stress_MPa"       => round(bending_stress_MPa, digits = 2),
        "min_von_mises_MPa"        => round(min_vm, digits = 2),
        "max_von_mises_MPa"        => round(max_vm, digits = 2),
        "avg_von_mises_MPa"        => round(sum(von_mises_MPa[interior]) / count(interior), digits = 2),
        "yield_ratio"              => round(max_vm / 250.0, digits = 3),
        "boundary_condition_label" => get(bc_names, bc_code, "Custom"),
        "euler_buckling_kN"        => round(P_cr_N / 1000.0, digits = 1),
        "p_delta_amplification"    => round(amp, digits = 2),
        "transverse_shear_kN"      => round(V_t_N / 1000.0, digits = 2),
        "lateral_load_kN"          => round(F_lat / 1000.0, digits = 2),
        "mesh_nodes"               => n_nodes,
        "mesh_elements"            => n_cells,
        "positions"                => positions,
        "displacements"            => displacements,
        "colors"                   => colors,
    )
end

end  # module FEM_Lacing