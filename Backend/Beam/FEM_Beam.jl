module FEMBeam

using Ferrite, FerriteGmsh, SparseArrays, LinearAlgebra

export run_beam_fem

"""
    run_beam_fem(msh_path, wu_kNm, Wu_kN, b1_mm; E_MPa, ν)

Solves a 3D elastostatic beam bending problem using Ferrite.jl with linear tetrahedra.
The mesh (from Mesh.jl) has: cross-section in Y-Z plane at X=0, extruded along +X by span L.
Supports: simply supported (pinned at left, roller at right).
Loads: uniformly distributed load (downward Y) + mid-span point load.
Returns Dict compatible with the frontend FEM viewer schema.
"""
function run_beam_fem(
    msh_path::String,
    wu_kNm::Float64,
    Wu_kN::Float64,
    b1_mm::Float64=100.0;
    E_MPa::Float64=200e3,
    ν::Float64=0.3
)

    # ── 1. Load Gmsh mesh (in meters) ────────────────────────────────────
    grid = togrid(msh_path)
    E = E_MPa * 1e6   # Pa

    xs = [n.x[1] for n in grid.nodes]
    ys = [n.x[2] for n in grid.nodes]
    zs = [n.x[3] for n in grid.nodes]
    x_min, x_max = extrema(xs)
    y_min, y_max = extrema(ys)
    z_min, z_max = extrema(zs)

    L_beam = max(x_max - x_min, 1e-6)   # span (m) along X
    D_sec  = max(y_max - y_min, 1e-6)   # depth (m)
    B_sec  = max(z_max - z_min, 1e-6)   # width (m)

    x_mid = 0.5 * (x_min + x_max)       # mid-span X
    y_mid = 0.5 * (y_min + y_max)       # depth center Y
    z_mid = 0.5 * (z_min + z_max)       # width center Z

    @info "Beam bbox: L=$L_beam m, D=$D_sec m, B=$B_sec m"

    # ── 2. Interpolation & quadrature ───────────────────────────────────
    ip = Lagrange{RefTetrahedron, 1}()^3
    qr = QuadratureRule{RefTetrahedron}(2)
    qr_face = FacetQuadratureRule{RefTetrahedron}(2)
    cv = CellValues(qr, ip)
    fv = FacetValues(qr_face, ip)

    dh = DofHandler(grid)
    add!(dh, :u, ip)
    close!(dh)

    # ── 3. Boundary Conditions (using coordinate-based node sets) ───────
    ch = ConstraintHandler(dh)
    tol_y = L_beam * 0.03   # tolerance along span for end detection

    # Left support: pinned → fix Y and Z displacements at centroid line
    left_nodes = Set{Int}()
    for nid in 1:getnnodes(grid)
        x = grid.nodes[nid].x
        if abs(x[1] - x_min) < tol_y && abs(x[2] - y_mid) < D_sec * 0.4 && abs(x[3] - z_mid) < B_sec * 0.4
            push!(left_nodes, nid)
        end
    end

    # Right support: roller → fix only Y displacement at centroid line (allows axial slip in X)
    right_nodes = Set{Int}()
    for nid in 1:getnnodes(grid)
        x = grid.nodes[nid].x
        if abs(x[1] - x_max) < tol_y && abs(x[2] - y_mid) < D_sec * 0.4 && abs(x[3] - z_mid) < B_sec * 0.4
            push!(right_nodes, nid)
        end
    end

    # Also try named physical groups if they exist (from future Mesh.jl updates)
    left_facet_set = getfacetset(grid, "left_face")
    right_facet_set = getfacetset(grid, "right_face")

    # Apply left pinned support: fix Y (2) and Z (3) at centroid nodes
    if !isempty(left_nodes)
        add!(ch, Dirichlet(:u, left_nodes, (x,t) -> [0.0, 0.0], [2, 3]))
    end

    # Apply right roller support: fix only Y (2) at centroid nodes
    if !isempty(right_nodes)
        add!(ch, Dirichlet(:u, right_nodes, (x,t) -> [0.0], [2]))
    end

    # Fall back to facet-based BCs if centroid node sets are empty
    if isempty(left_facet_set) && isempty(left_nodes)
        error("Could not find left support face for beam FEM boundary conditions.")
    end
    if isempty(right_facet_set) && isempty(right_nodes)
        error("Could not find right support face for beam FEM boundary conditions.")
    end

    close!(ch)

    # ── 4. Material Stiffness Tensor (isotropic steel, Pa) ───────────────
    λ = (E * ν) / ((1 + ν) * (1 - 2ν))
    μ = E / (2 * (1 + ν))
    δ(i, j) = i == j ? 1.0 : 0.0
    C = SymmetricTensor{4, 3}((i, j, k, l) -> λ * δ(i,j) * δ(k,l) + μ * (δ(i,k) * δ(j,l) + δ(i,l) * δ(j,k)))

    # ── 5. Compute cross-section properties from left end face ───────────
    left_area_m2 = 0.0
    I_strong_m4  = 0.0   # I_zz: bending about Z-axis (strong axis, σ = My/I)

    if !isempty(left_facet_set)
        for facet in FacetIterator(dh, left_facet_set)
            reinit!(fv, facet)
            for q in 1:getnquadpoints(fv)
                dΓ = getdetJdV(fv, q)
                x_q = spatial_coordinate(fv, q, getcoordinates(facet))
                left_area_m2 += dΓ
                I_strong_m4 += ((x_q[2] - y_mid)^2) * dΓ   # ∫(y - y_mid)² dA
            end
        end
    elseif !isempty(left_nodes)
        # Approximate from bbox (rectangle)
        left_area_m2 = D_sec * B_sec
        I_strong_m4 = B_sec * D_sec^3 / 12.0
    else
        left_area_m2 = D_sec * B_sec
        I_strong_m4 = B_sec * D_sec^3 / 12.0
    end
    I_strong_m4 = max(I_strong_m4, 1e-15)

    @info "Beam section: A=$(left_area_m2) m^2, I_strong=$(I_strong_m4) m^4"

    # ── 6. Assemble K and f ──────────────────────────────────────────────
    K = allocate_matrix(dh)
    f = zeros(ndofs(dh))
    assembler = start_assemble(K, f)
    n_base = getnbasefunctions(cv)
    Ke = zeros(n_base, n_base)
    fe_vol = zeros(n_base)

    # Convert loads to SI units
    w_Nm = wu_kNm * 1000.0      # UDL in N/m (downward, -Y direction)
    P_N  = Wu_kN * 1000.0       # Point load at mid-span in N

    # ── 7. Apply distributed load as traction on top face ────────────────
    has_top_facets = false
    for facet in FacetIterator(dh)
        reinit!(fv, facet)
        center_y = zero(Float64)
        np = 0
        for q in 1:getnquadpoints(fv)
            xp = spatial_coordinate(fv, q, getcoordinates(facet))
            center_y += xp[2]
            np += 1
        end
        center_y /= np

        # Top face: y ≈ y_max (top of beam flange/web)
        if abs(center_y - y_max) < D_sec * 0.05
            has_top_facets = true
            for q in 1:getnquadpoints(fv)
                dΓ = getdetJdV(fv, q)
                x_q = spatial_coordinate(fv, q, getcoordinates(facet))
                # Force per unit area: w_Nm / L_beam (UDL distributed along span)
                traction = Vec((0.0, -w_Nm / L_beam, 0.0))   # N/m²
                for i in 1:n_base
                    δu_i = shape_value(fv, q, i)
                    fe_vol[i] += (δu_i ⋅ traction) * dΓ
                end
            end
        end
    end

    # ── 8. Apply point load as concentrated force on nodes near mid-span top ─
    if Wu_kN > 0
        bearing_span = max(min(b1_mm / 1000.0, L_beam * 0.05), L_beam * 0.005)
        for cell in CellIterator(dh)
            reinit!(cv, cell)
            c = zero(Vec{3})
            nq = getnquadpoints(cv)
            for q in 1:nq
                c += spatial_coordinate(cv, q, getcoordinates(cell))
            end
            c /= nq

            # Check if cell is near mid-span and top of beam
            if abs(c[1] - x_mid) < bearing_span * 3 && abs(c[2] - y_max) < D_sec * 0.3
                share = max(0, 1.0 - abs(c[1] - x_mid) / (bearing_span * 3))
                P_cell = P_N * share
                # Spread over this cell proportionally to its volume
                vol = zero(Float64)
                for q in 1:nq
                    vol += getdetJdV(cv, q)
                end
                f_body_y = P_cell / max(vol, 1e-15)   # N/m³

                fill!(fe_vol, 0.0)
                for q in 1:nq
                    dΩ = getdetJdV(cv, q)
                    b_vec = Vec((0.0, f_body_y, 0.0))
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
        end
    end

    # ── 9. Assemble distributed load if not applied as face traction ─────
    if !has_top_facets && Wu_kN == 0
        # Pure UDL: apply as body force proportional to cross-sectional area
        vol_m3 = left_area_m2 * L_beam
        q_body_y = -w_Nm / vol_m3   # N/m³ (uniform)

        for cell in CellIterator(dh)
            fill!(Ke, 0.0)
            fill!(fe_vol, 0.0)
            reinit!(cv, cell)
            for q in 1:getnquadpoints(cv)
                dΩ = getdetJdV(cv, q)
                x_q = spatial_coordinate(cv, q, getcoordinates(cell))
                # Shape function for simply supported beam deflection profile
                y_norm = (x_q[1] - x_min) / L_beam
                shape_factor = sin(π * y_norm)   # parabolic load distribution along span
                b_vec = Vec((0.0, q_body_y * shape_factor, 0.0))

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
    else
        # Face traction already applied above; also add body force if no point load
        if Wu_kN == 0
            for cell in CellIterator(dh)
                fill!(Ke, 0.0)
                fill!(fe_vol, 0.0)
                reinit!(cv, cell)
                for q in 1:getnquadpoints(cv)
                    dΩ = getdetJdV(cv, q)
                    x_q = spatial_coordinate(cv, q, getcoordinates(cell))
                    y_norm = (x_q[1] - x_min) / L_beam
                    shape_factor = sin(π * y_norm)
                    b_vec = Vec((0.0, -(w_Nm / left_area_m2) * shape_factor, 0.0))

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
        end
    end

    # ── 10. Solve linear system ──────────────────────────────────────────
    apply!(K, f, ch)
    u = K \ f

    # ── 11. Post-process: nodal displacements, von Mises stress, colors ──
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

    # Element-wise von Mises stress → nodal averaging
    von_mises_MPa = zeros(n_cells)
    node_stress_sum = zeros(n_nodes)
    node_stress_count = zeros(Int, n_nodes)

    for (idx, cell) in enumerate(CellIterator(dh))
        reinit!(cv, cell)
        u_el = u[celldofs(cell)]
        ε = function_symmetric_gradient(cv, 1, u_el)
        σ = C ⊡ ε
        s_dev = dev(σ)
        vm = sqrt(1.5 * (s_dev ⊡ s_dev)) / 1e6   # convert to MPa
        von_mises_MPa[idx] = vm

        for nid in cell.nodes
            node_stress_sum[nid] += vm
            node_stress_count[nid] += 1
        end
    end

    nodal_vm = [node_stress_count[i] > 0 ? node_stress_sum[i] / node_stress_count[i] : 0.0 for i in 1:n_nodes]
    min_vm, max_vm = extrema(nodal_vm)
    span_vm = max(max_vm - min_vm, 1e-6)

    # Flexural stress estimate (Euler-Bernoulli for simply supported beam)
    M_max_Nm = (w_Nm * L_beam^2 / 8.0) + (P_N * L_beam / 4.0)
    y_max_dist = max(abs(y_max - y_mid), D_sec * 0.5)
    flexural_MPa = M_max_Nm * y_max_dist / I_strong_m4 / 1e6

    # Stress coloring (same "fire" colormap as column FEM)
    function stress_rgb(val::Float64)
        t = clamp((val - min_vm) / span_vm, 0.0, 1.0)
        r = clamp(1.5 - abs(4.0*t - 3.0), 0.0, 1.0)
        g = clamp(1.5 - abs(4.0*t - 2.0), 0.0, 1.0)
        b = clamp(1.5 - abs(4.0*t - 1.0), 0.0, 1.0)
        return (r, g, b)
    end

    # Build deformed mesh face arrays for Three.js rendering
    positions     = Float32[]
    displacements = Float32[]
    colors        = Float32[]

    tet_faces = ((1, 3, 2), (1, 2, 4), (2, 3, 4), (1, 4, 3))

    # Deduplicate shared faces
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
        "nominal_flexural_MPa"        => round(flexural_MPa, digits=2),
        "min_von_mises_MPa"           => round(min_vm, digits=2),
        "max_von_mises_MPa"           => round(max_vm, digits=2),
        "avg_von_mises_MPa"           => round(sum(von_mises_MPa) / length(von_mises_MPa), digits=2),
        "yield_ratio"                 => round(max_vm / 250.0, digits=3),
        "boundary_condition_label"    => "Simply Supported (Pinned-Pinned)",
        "mesh_nodes"                  => n_nodes,
        "mesh_elements"               => n_cells,
        "positions"                   => positions,
        "displacements"               => displacements,
        "colors"                      => colors,
        "applied_load_udl_kNm"        => wu_kNm,
        "applied_point_load_kN"       => Wu_kN,
    )
end

end  # module FEMBeam
