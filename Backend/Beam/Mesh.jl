using Gmsh

## Cross-section in the Y-Z plane at X = 0:
## Y is vertical (depth D from 0 to D)
## Z is lateral width (from -B/2 to +B/2, centered)
## X is horizontal span (extruded from 0 to L)
function create_I_section_beam(B, D, tf, tw, h)
    z_left      = -B / 2.0
    z_right     =  B / 2.0
    z_web_left  = -tw / 2.0
    z_web_right =  tw / 2.0

    p1  = gmsh.model.geo.addPoint(0, 0,          z_left,       h)
    p2  = gmsh.model.geo.addPoint(0, 0,          z_right,      h)
    p3  = gmsh.model.geo.addPoint(0, tf,         z_right,      h)
    p4  = gmsh.model.geo.addPoint(0, tf,         z_web_right,  h)
    p5  = gmsh.model.geo.addPoint(0, D - tf,     z_web_right,  h)
    p6  = gmsh.model.geo.addPoint(0, D - tf,     z_right,      h)
    p7  = gmsh.model.geo.addPoint(0, D,          z_right,      h)
    p8  = gmsh.model.geo.addPoint(0, D,          z_left,       h)
    p9  = gmsh.model.geo.addPoint(0, D - tf,     z_left,       h)
    p10 = gmsh.model.geo.addPoint(0, D - tf,     z_web_left,   h)
    p11 = gmsh.model.geo.addPoint(0, tf,         z_web_left,   h)
    p12 = gmsh.model.geo.addPoint(0, tf,         z_left,       h)

    l1  = gmsh.model.geo.addLine(p1,  p2)
    l2  = gmsh.model.geo.addLine(p2,  p3)
    l3  = gmsh.model.geo.addLine(p3,  p4)
    l4  = gmsh.model.geo.addLine(p4,  p5)
    l5  = gmsh.model.geo.addLine(p5,  p6)
    l6  = gmsh.model.geo.addLine(p6,  p7)
    l7  = gmsh.model.geo.addLine(p7,  p8)
    l8  = gmsh.model.geo.addLine(p8,  p9)
    l9  = gmsh.model.geo.addLine(p9,  p10)
    l10 = gmsh.model.geo.addLine(p10, p11)
    l11 = gmsh.model.geo.addLine(p11, p12)
    l12 = gmsh.model.geo.addLine(p12, p1)

    curve_loop = gmsh.model.geo.addCurveLoop([
        l1, l2, l3, l4, l5, l6, l7, l8, l9, l10, l11, l12
    ])
    surface = gmsh.model.geo.addPlaneSurface([curve_loop])
    return surface
end

function create_beam_mesh(result; output_file = "Beam.msh", stl_file = "Beam.stl")
    D  = Float64(result["Depth_mm"]) / 1000.0
    B  = Float64(result["Width_mm"]) / 1000.0
    tf = Float64(result["tf_mm"]) / 1000.0
    tw = Float64(result["tw_mm"]) / 1000.0
    L  = Float64(result["Span_m"])

    if D <= 0
        return Dict("error" => "Section depth must be greater than zero.")
    end
    if B <= 0
        return Dict("error" => "Section width must be greater than zero.")
    end
    if tf <= 0
        return Dict("error" => "Flange thickness must be greater than zero.")
    end
    if tw <= 0
        return Dict("error" => "Web thickness must be greater than zero.")
    end
    if L <= 0
        return Dict("error" => "Beam span must be greater than zero.")
    end

    h = min(0.25, min(B, D) / 3)
    h = max(h, 0.01)

    gmsh.initialize()
    try
        gmsh.model.add("Beam")
        section_surface = create_I_section_beam(B, D, tf, tw, h)
        gmsh.model.geo.synchronize()

        ## Extrude horizontally along the X-axis by span L
        # Use recombine=false so Gmsh generates pure tetrahedra (required for Ferrite.fem)
        outDimTags = gmsh.model.geo.extrude([(2, section_surface)], L, 0, 0, [20], [1.0], false)
        gmsh.model.geo.synchronize()

        # Tag boundary surfaces and 3D volume (same pattern as column mesh)
        bottom_surfaces = Int[]
        top_surfaces    = Int[]
        side_surfaces   = Int[]
        volume_tags     = Int[]

        push!(bottom_surfaces, section_surface)
        push!(top_surfaces, outDimTags[1][2])
        push!(volume_tags, outDimTags[2][2])

        for item in outDimTags[3:end]
            if item[1] == 2
                push!(side_surfaces, item[2])
            end
        end

        gmsh.model.addPhysicalGroup(2, bottom_surfaces, -1, "bottom_face")
        gmsh.model.addPhysicalGroup(2, top_surfaces, -1, "top_face")
        gmsh.model.addPhysicalGroup(2, side_surfaces, -1, "side_faces")
        gmsh.model.addPhysicalGroup(3, volume_tags, -1, "steel_volume")

        gmsh.option.setNumber("Mesh.CharacteristicLengthMin", h)
        gmsh.option.setNumber("Mesh.CharacteristicLengthMax", h)
        gmsh.option.setNumber("Mesh.Algorithm3D", 1)
        gmsh.model.mesh.generate(3)

        gmsh.write(output_file)
        gmsh.write(stl_file)
    finally
        gmsh.finalize()
    end

    return Dict(
        "success"   => true,
        "mesh_file" => output_file,
        "stl_file"  => stl_file,
        "mesh_url"  => "/design/beam/mesh",
        "stl_url"   => "/design/beam/stl",
        "span_m"    => L,
        "depth_m"   => D,
        "width_m"   => B,
        "tf_m"      => tf,
        "tw_m"      => tw
    )
end
