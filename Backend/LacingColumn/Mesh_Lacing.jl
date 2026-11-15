module LacingMesh

using Gmsh

export create_lacing_column_mesh, END_PLATE_MM

# Base / cap plate thickness. Must match `end_plate_m` in FEM_Lacing.jl (20 mm = 0.020 m).
const END_PLATE_MM = 20.0

"""
    create_lacing_column_mesh(result; output_file, stl_file, mesh_size_mm)

Builds a conformal tetrahedral mesh of the laced column returned by `Design_Lacing_Column`.

Coordinates (metres): X across the two chords, Y = column axis (0 … L), Z = channel depth.
Parts, all fragmented with the OpenCASCADE kernel so touching faces share nodes:
  * two ISMC chords (web + two flanges each), back-to-back, clear gap s, flanges outward
  * single zig-zag flat-bar lacing on both flange faces (z = ±h/2)
  * end tie plates on both flange faces
  * a base plate and a cap plate under/over the whole section (load/support plates)

Physical groups: steel_volume, bottom_face (outer face of base plate), top_face (outer face of
cap plate), outer_surface (remaining outside skin, used for the STL).
"""
function create_lacing_column_mesh(result;
        output_file = "LacingColumn.msh",
        stl_file = "LacingColumn.stl",
        mesh_size_mm = nothing)

    haskey(result, "error") && error("Cannot mesh a failed design: $(result["error"])")

    mm(key) = Float64(result[key]) / 1000.0
    L     = Float64(result["Length_m"])          # metres
    s     = mm("Channel_Spacing_mm")
    h_c   = mm("Chord_Depth_mm")
    b_f   = mm("Chord_Width_mm")
    t_f   = mm("tf_mm")
    t_w   = mm("tw_mm")
    n     = Int(result["Num_Lacing_Panels"])
    y0    = mm("Lacing_Start_mm")
    w_lac = mm("Lacing_Bar_Width_mm")
    t_lac = mm("Lacing_Bar_Thickness_mm")
    tie_len = mm("Tie_Plate_Length_mm")
    tie_t   = mm("Tie_Plate_Thickness_mm")
    t_bp    = END_PLATE_MM / 1000.0

    X  = s / 2 + b_f                  # half overall width
    Zp = h_c / 2 + tie_t              # half depth of base/cap plates (covers tie plates)
    x_bolt = s / 2 + b_f / 2          # lacing bolt line on each chord (mid-flange)
    a = (L - 2 * y0) / n              # axial advance per panel

    h_mesh = mesh_size_mm === nothing ? clamp(min(b_f / 3, h_c / 6), 0.015, 0.04) : mesh_size_mm / 1000.0

    gmsh.initialize()
    try
        gmsh.option.setNumber("General.Terminal", 0)
        gmsh.model.add("LacingColumn")
        occ = gmsh.model.occ

        objs = Tuple{Cint,Cint}[]
        function box!(x0, y0_, z0, dx, dy, dz)
            tag = occ.addBox(x0, y0_, z0, dx, dy, dz)
            push!(objs, (3, tag))
            return tag
        end

        # ── Chords: web + two flanges per channel (back-to-back) ─────────
        for dir in (-1.0, 1.0)
            x_back = dir * s / 2
            x_web  = dir * (s / 2 + t_w)
            x_tip  = dir * (s / 2 + b_f)
            box!(min(x_back, x_web), 0.0, -h_c / 2, abs(x_web - x_back), L, h_c)
            for zs in (-1.0, 1.0)
                z0 = zs > 0 ? h_c / 2 - t_f : -h_c / 2
                box!(min(x_web, x_tip), 0.0, z0, abs(x_tip - x_web), L, t_f)
            end
        end

        # ── Base and cap plates ──────────────────────────────────────────
        box!(-X, -t_bp, -Zp, 2X, t_bp, 2Zp)
        box!(-X, L, -Zp, 2X, t_bp, 2Zp)

        # ── End tie plates on both flange faces ──────────────────────────
        for zs in (-1.0, 1.0)
            z0 = zs > 0 ? h_c / 2 : -h_c / 2 - tie_t
            box!(-X, 0.0, z0, 2X, tie_len, tie_t)
            box!(-X, L - tie_len, z0, 2X, tie_len, tie_t)
        end

        # ── Single (zig-zag) lacing on both flange faces ─────────────────
        for zs in (-1.0, 1.0)
            z0 = zs > 0 ? h_c / 2 : -h_c / 2 - t_lac
            for p in 0:(n - 1)
                ya = y0 + p * a
                yb = ya + a
                xa, xb = iseven(p) ? (-x_bolt, x_bolt) : (x_bolt, -x_bolt)
                len = hypot(xb - xa, yb - ya)
                phi = atan(yb - ya, xb - xa)
                # bar axis runs bolt-to-bolt; ends extend w/2 past each bolt centre
                tag = occ.addBox(xa - w_lac / 2, ya - w_lac / 2, z0, len + w_lac, w_lac, t_lac)
                occ.rotate(Tuple{Cint,Cint}[(3, tag)], xa, ya, 0.0, 0.0, 0.0, 1.0, phi)
                push!(objs, (3, tag))
            end
        end

        # ── Make everything conformal ────────────────────────────────────
        occ.fragment(objs, Tuple{Cint,Cint}[])
        occ.synchronize()

        vols = [t for (_, t) in gmsh.model.getEntities(3)]
        isempty(vols) && error("Geometry produced no volumes")

        # ── Physical groups ──────────────────────────────────────────────
        tol = 1e-4
        bot = [t for (_, t) in gmsh.model.getEntitiesInBoundingBox(-1.0, -t_bp - tol, -1.0, 1.0, -t_bp + tol, 1.0, 2)]
        top = [t for (_, t) in gmsh.model.getEntitiesInBoundingBox(-1.0, L + t_bp - tol, -1.0, 1.0, L + t_bp + tol, 1.0, 2)]
        (isempty(bot) || isempty(top)) && error("Could not locate base/cap plate outer faces")

        skin  = [t for (_, t) in gmsh.model.getBoundary(Tuple{Cint,Cint}[(3, v) for v in vols], true, false, false)]
        outer = setdiff(skin, bot, top)

        gmsh.model.addPhysicalGroup(3, vols, -1, "steel_volume")
        gmsh.model.addPhysicalGroup(2, bot, -1, "bottom_face")
        gmsh.model.addPhysicalGroup(2, top, -1, "top_face")
        gmsh.model.addPhysicalGroup(2, outer, -1, "outer_surface")

        # ── Mesh ─────────────────────────────────────────────────────────
        gmsh.option.setNumber("Mesh.MeshSizeFromPoints", 0)
        gmsh.option.setNumber("Mesh.MeshSizeFromCurvature", 0)
        gmsh.option.setNumber("Mesh.MeshSizeExtendFromBoundary", 0)
        gmsh.option.setNumber("Mesh.MeshSizeMin", 0.4 * h_mesh)
        gmsh.option.setNumber("Mesh.MeshSizeMax", h_mesh)
        gmsh.option.setNumber("Mesh.Algorithm3D", 1)
        gmsh.option.setNumber("Mesh.MshFileVersion", 4.1)
        gmsh.model.mesh.generate(3)

        gmsh.write(output_file)
        gmsh.write(stl_file)          # only physical surface groups are written -> outside skin

        @info "Lacing column mesh written" output_file stl_file volumes = length(vols)
    finally
        gmsh.finalize()
    end

    return Dict(
        "success"            => true,
        "mesh_file"          => output_file,
        "stl_file"           => stl_file,
        "mesh_url"           => "/design/lacing/mesh",
        "stl_url"            => "/design/lacing/stl",
        "length_m"           => L,
        "channel_spacing_mm" => s * 1000.0,
        "num_panels"         => n,
        "end_plate_mm"       => END_PLATE_MM,
    )
end

end  # module LacingMesh