module LacingColumnDesign

export Design_Lacing_Column

"""
    Design_Lacing_Column(Length, Pu_kN, bc_code; fy, E)

Design a built-up lacing column as per IS 800:2007.
Two channel chords (back-to-back) connected by diagonal lacing bars.
Returns Dict with section properties, design capacity, and lacing design details.
"""
function Design_Lacing_Column(
    Length::Float64,
    Pu_kN::Float64,
    bc_code::Int;
    fy::Float64=250.0,
    E::Float64=200e3
)

    # Effective length factor per IS 800 Cl. 7.2.2
    k_eff = bc_code == 1 ? 0.65 : (bc_code == 2 ? 2.0 : (bc_code == 3 ? 0.80 : 1.0))
    Le = k_eff * Length

    # Standard ISMC channel sections for chord members
    chord_sections = [
        Dict("name" => "ISMC 150", "Area" => 1899.0, "h" => 150.0, "b" => 65.0,
             "Ixx" => 732.4e4, "Iyy" => 130.5e4, "rx" => 19.6, "ry" => 13.0,
             "Cyy" => 22.4),
        Dict("name" => "ISMC 180", "Area" => 2517.0, "h" => 180.0, "b" => 75.0,
             "Ixx" => 1364.0e4, "Iyy" => 239.0e4, "rx" => 23.3, "ry" => 15.5,
             "Cyy" => 24.8),
        Dict("name" => "ISMC 200", "Area" => 3097.0, "h" => 200.0, "b" => 76.0,
             "Ixx" => 1838.4e4, "Iyy" => 315.0e4, "rx" => 24.4, "ry" => 17.9,
             "Cyy" => 25.2),
        Dict("name" => "ISMC 250", "Area" => 4186.0, "h" => 250.0, "b" => 83.0,
             "Ixx" => 4037.0e4, "Iyy" => 619.0e4, "rx" => 31.0, "ry" => 21.4,
             "Cyy" => 25.6),
        Dict("name" => "ISMC 300", "Area" => 5279.0, "h" => 300.0, "b" => 85.0,
             "Ixx" => 7337.0e4, "Iyy" => 1073.0e4, "rx" => 37.4, "ry" => 25.3,
             "Cyy" => 26.8),
    ]

    # Select first chord section with adequate capacity
    selected_chord = nothing
    for cs in chord_sections
        A_total_test = 2 * cs["Area"]
        f_cd_est = _compute_fcd(A_total_test, Le, fy, E)
        Pu_cap = f_cd_est * A_total_test / 1000.0
        if Pu_cap >= Pu_kN * 1.05
            selected_chord = cs
            break
        end
    end

    if isnothing(selected_chord)
        return Dict(
            "error" => "No suitable channel section found for given loads.",
            "message" => "Increase column length or reduce axial load, or specify higher grade steel."
        )
    end

    # ── Built-up column properties ────────────────────────────────
    A_chord = selected_chord["Area"]
    A_total = 2 * A_chord                          # mm² (both chords)
    I_xx_total = 2 * selected_chord["Ixx"]         # mm⁴ about strong axis

    # Spacing between channels — equal radius of gyration for both axes
    Cyy_val = selected_chord["Cyy"]   # mm from centroid to back
    d_needed = sqrt(max((I_xx_total - 2 * selected_chord["Iyy"]) / (2 * A_chord), 0))
    s = max(2 * d_needed, selected_chord["h"] * 0.5)   # channel spacing

    I_yy_total = 2 * selected_chord["Iyy"] + 2 * A_chord * (s / 2 + Cyy_val)^2
    r_xx = sqrt(I_xx_total / A_total)
    r_yy = sqrt(I_yy_total / A_total)

    # Slenderness ratios (IS 800 Cl. 7.2.4)
    lambda_x = Le * 1000.0 / r_xx
    lambda_y = Le * 1000.0 / r_yy
    lambda_max = max(lambda_x, lambda_y)

    # Modified slenderness for built-up column (lacing effect)
    V_m = lambda_max * 1.05

    # Design compressive stress per IS 800 Cl. 7.1.2 (buckling curve b)
    gamma_m1 = 1.1
    P_E = π^2 * E / (lambda_max^2 + 1e-6)         # MPa
    f_ec = 0.004 * fy
    beta_p = 1.2 + 0.3 * (lambda_max / 200.0)^2

    f_cc = ((1 + (f_ec / P_E)^beta_p) ^ (1/beta_p)) * fy
    f_cd = f_cc / gamma_m1

    # Buckling capacity
    Pu_design = f_cd * A_total / 1000.0            # kN

    # ── Lacing Design per IS 800 Cl. 7.6 ──────────────────────────
    num_panels = max(2, round(Int, ceil(Length / 2.5)))
    panel_length = Length / num_panels               # m

    angle_deg = clamp(round(degrees(atan(selected_chord["h"] / (panel_length * 1000)))), 40, 70)
    theta = deg2rad(angle_deg)

    V_t = 0.025 * Pu_kN                             # transverse shear kN
    V_per_face = V_t / 2.0                          # per lacing face

    P_lacing = V_per_face / sin(theta)              # bar force in lacing (kN)

    f_td = fy / gamma_m1                            # MPa
    A_lac_req = P_lacing * 1000.0 / f_td           # mm²
    d_lac_req = sqrt(4 * A_lac_req / π)            # mm
    d_lac_prov = max(16, ceil(d_lac_req))          # minimum 16mm

    w_lac = max(45, 3 * d_lac_prov)                # width per IS 800 Cl. 7.6.2

    lambda_lac = panel_length * 1000.0 / (d_lac_prov / 4)
    lacing_ok = lambda_lac < 140 ? "PASS" : "FAIL"

    return Dict(
        # Inputs
        "Length_m"         => Length,
        "Axial_Load_kN"    => Pu_kN,
        "Effective_Length_m" => Le,
        "Boundary_Condition" => bc_code == 0 ? "Pinned-Pinned" : (bc_code == 1 ? "Fixed-Fixed" : (bc_code == 2 ? "Fixed-Free" : "Fixed-Pinned")),

        # Chord
        "Chord_Section"    => selected_chord["name"],
        "Chord_Area_mm2"   => selected_chord["Area"],
        "Chord_Depth_mm"   => selected_chord["h"],
        "Chord_Width_mm"   => selected_chord["b"],

        # Built-up section
        "Total_Area_mm2"   => round(A_total, digits=1),
        "Channel_Spacing_mm"=> round(s, digits=1),
        "I_xx_cm4"         => round(I_xx_total / 1e4, digits=1),
        "I_yy_cm4"         => round(I_yy_total / 1e4, digits=1),
        "r_xx_mm"          => round(r_xx, digits=1),
        "r_yy_mm"          => round(r_yy, digits=1),

        # Slenderness & buckling
        "lambda_x"         => round(lambda_x, digits=1),
        "lambda_y"         => round(lambda_y, digits=1),
        "lambda_max"       => round(max(lambda_x, lambda_y), digits=1),
        "modified_slenderness" => round(V_m, digits=1),
        "f_cd_MPa"         => round(f_cd, digits=2),

        # Capacity
        "Design_Capacity_kN" => round(Pu_design, digits=1),
        "Capacity_Utilization"=> round(min(Pu_kN / Pu_design, 9.99), digits=3),
        "Status"           => Pu_design >= Pu_kN ? "SAFE" : "UNSAFE",

        # Lacing
        "Num_Lacing_Panels" => num_panels,
        "Panel_Length_mm"   => round(panel_length * 1000, digits=1),
        "Lacing_Angle_deg"  => angle_deg,
        "Shear_Vt_kN"       => round(V_t, digits=1),
        "Lacing_Bar_Force_kN"=> round(P_lacing, digits=1),
        "Min_Lacing_Diameter_mm" => round(d_lac_req, digits=1),
        "Provided_Lacing_Diameter_mm" => d_lac_prov,
        "Lacing_Bar_Width_mm"    => w_lac,
        "Lacing_Slenderness_Check" => lacing_ok,

        # Mesh / STL URLs
        "mesh_url"   => "/design/lacing/mesh",
        "stl_url"    => "/design/lacing/stl",
    )
end

function _compute_fcd(A_mm2::Float64, Le_m::Float64, fy::Float64, E::Float64)
    lambda = (Le_m * 1000.0) / sqrt(12 * A_mm2 / (2 * 3097.0))
    P_E = π^2 * E / (lambda^2 + 1e-6)
    f_ec = 0.004 * fy
    beta_p = 1.2 + 0.3 * (lambda / 200.0)^2
    denom = (f_ec / P_E) ^ beta_p
    f_cc = ((1 + denom) ^ (1/beta_p)) * fy
    return f_cc / 1.1
end

end  # module LacingColumnDesign
