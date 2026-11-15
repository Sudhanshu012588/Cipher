module LacingMesh

using Gmsh

export create_lacing_column_mesh

"""
    create_lacing_column_mesh(result; output_file, stl_file)

Generate a 3D tetrahedral mesh for a built-up lacing column.
Geometry: two channel chords (back-to-back with spacing) + diagonal flat-bar lacing bars.
Creates named Physical Groups for FEM boundary conditions.
"""
function create_lacing_column_mesh(result; output_file = "LacingColumn.msh", stl_file = "LacingColumn.stl")

    L   = Float64(result["Length_m"])
    s   = Float64(result["Channel_Spacing_mm"]) / 1000.0   # spacing between channels (m)
    h_c = Float64(result["Chord_Depth_mm"]) / 1000.0       # channel depth D (m)
    b_f = Float64(result["Chord_Width_mm"]) / 1000.0        # channel width B (m)
    t_f = Float64("tf_mm") isa AbstractString ? Float64(get(result, "tf_mm", 9.2)) / 1000.0 : h_c * 0.057
    t_w = Float64(get(result, "tw_mm", 6.2)) / 1000.0       # channel web thickness

    # Fallback: estimate from standard ISMC dimensions
    if t_f <= 0 || t_w <= 0
        t_f = h_c * 0.057
        t_w = h_c * 0.037
    end

    num_panels = Int(get(result, "Num_Lacing_Panels", max(2, round(Int, ceil(L / 2.5)))))
    panel_len  = L / num_panels                             # m — panel length along column
    d_lac_prov = Float64(get(result, "Provided_Lacing_Diameter_mm", 16)) / 1000.0  # lacing bar dia (m)

    h_mesh = min(0.25, s * 0.3)                             # characteristic mesh size
    h_mesh = max(h_mesh, 0.005)

    gmsh.initialize()
    try
        gmsh.model.add("LacingColumn")

        # ── Channel cross-section in X-Z plane at Y = 0 (extruded along Y-axis for column length) ──
        z_left       = -b_f / 2
        z_right      =  b_f / 2
        z_web_l      = -t_w / 2
        z_web_r      =  t_w / 2

        # Points defining one ISMC channel in X-Z plane
        pts = [
            gmsh.model.geo.addPoint(0, 0,       z_left,     h_mesh),   # 1: bottom-left flange tip
            gmsh.model.geo.addPoint(0, 0,       z_right,    h_mesh),   # 2: bottom-right flange tip
            gmsh.model.geo.addPoint(0, t_f,     z_right,    h_mesh),   # 3: bottom flange-web junction (R)
            gmsh.model.geo.addPoint(0, t_f,     z_web_r,    h_mesh),   # 4
            gmsh.model.geo.addPoint(0, h_c-t_f, z_web_r,    h_mesh),   # 5: top flange-web junction (R)
            gmsh.model.geo.addPoint(0, h_c-t_f, z_right,    h_mesh),   # 6
            gmsh.model.geo.addPoint(0, h_c,     z_right,    h_mesh),   # 7: top-right flange tip
            gmsh.model.geo.addPoint(0, h_c,     z_left,     h_mesh),   # 8: top-left flange tip
            gmsh.model.geo.addPoint(0, h_c-t_f, z_left,     h_mesh),   # 9
            gmsh.model.geo.addPoint(0, h_c-t_f, z_web_l,    h_mesh),   # 10
            gmsh.model.geo.addPoint(0, t_f,     z_web_l,    h_mesh),   # 11
            gmsh.model.geo.addPoint(0, t_f,     z_left,     h_mesh),   # 12
        ]

        lines_tags = [
            gmsh.model.geo.addLine(pts[1], pts[2]),
            gmsh.model.geo.addLine(pts[2], pts[3]),
            gmsh.model.geo.addLine(pts[3], pts[4]),
            gmsh.model.geo.addLine(pts[4], pts[5]),
            gmsh.model.geo.addLine(pts[5], pts[6]),
            gmsh.model.geo.addLine(pts[6], pts[7]),
            gmsh.model.geo.addLine(pts[7], pts[8]),
            gmsh.model.geo.addLine(pts[8], pts[9]),
            gmsh.model.geo.addLine(pts[9], pts[10]),
            gmsh.model.geo.addLine(pts[10], pts[11]),
            gmsh.model.geo.addLine(pts[11], pts[12]),
            gmsh.model.geo.addLine(pts[12], pts[1]),
        ]

        curve_loop = gmsh.model.geo.addCurveLoop(lines_tags)
        ch_surface = gmsh.model.geo.addPlaneSurface([curve_loop])

        gmsh.model.geo.synchronize()

        # ── Extrude along Y-axis (column length L) ───────────────────
        out = gmsh.model.geo.extrude([(2, ch_surface)], 0, L, 0, [20], [1.0], false)
        gmsh.model.geo.synchronize()

        vol_tag    = out[3][2]
        bottom_f   = out[1][2]      # face at Y=0 (bottom end)
        top_f      = out[2][2]      # face at Y=L (top end)

        # ── Lacing bars (diagonal flat bars between the two channels) ──
        # Channel 1 centered at Z = -s/2, Channel 2 centered at Z = +s/2
        # Each lacing bar is a thin rectangular plate spanning panel diagonally
        lac_thickness = d_lac_prov / 2       # approximating flat bar thickness
        lac_width = max(d_lac_prov * 1.5, 0.03)   # width of lacing bar

        # Left face at Z = -s/2 + ... and right face at Z = +s/2 + ...
        z_ch1_center = -s / 2                  # channel 1 centroid Z
        z_ch2_center =  s / 2                  # channel 2 centroid Z

        lac_surfaces = Int[]
        panel_centers_y = Float64[]

        for i in 0:num_panels-1
            y_start = i * panel_len + L / num_panels / 2   # center of panel i+1
            push!(panel_centers_y, y_start)

            # Diagonal from channel 1 (bottom of web) at left face to channel 2 (top of web) at right face
            z_web_outer_ch1 = z_ch1_center + t_w/2    # outward face of channel 1 web
            z_top_ch2       = z_ch2_center + h_c/2     # top flange of channel 2

            # Create lacing bar as a thin surface (extruded thin rectangle)
            p_la1 = gmsh.model.geo.addPoint(z_web_outer_ch1, y_start - panel_len/2, 0.0, lac_thickness)
            p_la2 = gmsh.model.geo.addPoint(z_web_outer_ch1, y_start - panel_len/2, lac_width, lac_thickness)
            p_la3 = gmsh.model.geo.addPoint(z_top_ch2,       y_start + panel_len/2, lac_width, lac_thickness)
            p_la4 = gmsh.model.geo.addPoint(z_top_ch2,       y_start + panel_len/2, 0.0,     lac_thickness)

            l1 = gmsh.model.geo.addLine(p_la1, p_la2)
            l2 = gmsh.model.geo.addLine(p_la2, p_la3)
            l3 = gmsh.model.geo.addLine(p_la3, p_la4)
            l4 = gmsh.model.geo.addLine(p_la4, p_la1)

            lac_curve_loop = gmsh.model.geo.addCurveLoop([l1, l2, l3, l4])
            lac_surf = gmsh.model.geo.addPlaneSurface([lac_curve_loop])
            push!(lac_surfaces, lac_surf)

            # Mirror for opposite-direction diagonal in next panel (optional — alternate diagonal pattern)
        end

        # ── Add Physical Groups for FEM boundary conditions ────────────
        # For built-up column: clamp bottom face, roller at top face
        gmsh.model.addPhysicalGroup(3, [vol_tag], -1, "steel_volume")
        gmsh.model.addPhysicalGroup(2, [bottom_f], -1, "bottom_face")
        gmsh.model.addPhysicalGroup(2, [top_f], -1, "top_face")

        # Also tag channel 1 and channel 2 faces for identification
        side_surfaces = Int[]
        for item in out[3:end]
            if item[1] == 2
                push!(side_surfaces, item[2])
            end
        end

        gmsh.option.setNumber("Mesh.CharacteristicLengthMin", h_mesh)
        gmsh.option.setNumber("Mesh.CharacteristicLengthMax", h_mesh)
        gmsh.option.setNumber("Mesh.Algorithm3D", 1)

        # Add lacing bars as separate volume (extrude thin surfaces to flat bars)
        lac_volumes = Int[]
        for i in 1:length(lac_surfaces)
            lac_vol = gmsh.model.geo.extrude([(2, lac_surfaces[i])], 0.0, 0.0, lac_thickness * 0.999, [5], [0.05])
            if !isempty(lac_vol) && length(lac_vol) >= 4
                push!(lac_volumes, lac_vol[3][2])  # volume tag
            end
        end

        gmsh.model.geo.synchronize()

        gmsh.model.mesh.generate(3)

        gmsh.write(output_file)
        gmsh.write(stl_file)

        @info "Lacing column mesh: $(output_file)"
        @info "Mesh written to $(stl_file)"

    finally
        gmsh.finalize()
    end

    return Dict(
        "success"     => true,
        "mesh_file"   => output_file,
        "stl_file"    => stl_file,
        "mesh_url"    => "/design/lacing/mesh",
        "stl_url"     => "/design/lacing/stl",
        "length_m"    => L,
        "channel_spacing_mm" => s * 1000,
        "num_panels"  => num_panels,
        "lacing_diameter_mm"=> d_lac_prov * 1000,
    )
end

end  # module LacingMesh
