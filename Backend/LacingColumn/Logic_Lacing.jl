module LacingColumnDesign

export Design_Lacing_Column

# ── IS 800:2007 constants ────────────────────────────────────────────────
const GAMMA_M0 = 1.10      # Table 5: yielding / buckling
const GAMMA_M1 = 1.25      # Table 5: net-section rupture, bolts
const ALPHA_C  = 0.49      # Table 7: imperfection factor, buckling class c
                           # (Table 10: built-up laced/battened members, any axis -> curve c)

# ISMC channels (SP 6(1)): A mm², h, b, tf, tw mm, Ixx, Iyy mm⁴, Cyy mm
# NOTE: verify every row against your copy of SP 6(1) before issuing results.
const ISMC = [
    (name = "ISMC 150", A = 2088.0, h = 150.0, b = 75.0,  tf = 9.0,  tw = 5.4, Ixx = 779.4e4,   Iyy = 102.3e4, Cyy = 22.2),
    (name = "ISMC 175", A = 2438.0, h = 175.0, b = 75.0,  tf = 10.2, tw = 5.7, Ixx = 1223.3e4,  Iyy = 121.0e4, Cyy = 22.0),
    (name = "ISMC 200", A = 2821.0, h = 200.0, b = 75.0,  tf = 11.4, tw = 6.1, Ixx = 1819.3e4,  Iyy = 140.4e4, Cyy = 21.7),
    (name = "ISMC 250", A = 3867.0, h = 250.0, b = 80.0,  tf = 14.1, tw = 7.1, Ixx = 3816.8e4,  Iyy = 219.1e4, Cyy = 23.0),
    (name = "ISMC 300", A = 4564.0, h = 300.0, b = 90.0,  tf = 13.6, tw = 7.6, Ixx = 6362.6e4,  Iyy = 310.8e4, Cyy = 23.6),
    (name = "ISMC 350", A = 5366.0, h = 350.0, b = 100.0, tf = 13.5, tw = 8.1, Ixx = 10008.0e4, Iyy = 430.6e4, Cyy = 24.4),
    (name = "ISMC 400", A = 6293.0, h = 400.0, b = 100.0, tf = 15.3, tw = 8.6, Ixx = 15082.8e4, Iyy = 504.8e4, Cyy = 24.2),
]

"""
    Design_Lacing_Column(Length, Pu_kN, bc_code; fy, fu, E)

Two ISMC chords, back-to-back (webs facing, clear gap `s`, flanges outward), joined by
single (zig-zag) flat-bar lacing bolted to the flange faces on both sides, with end tie plates.
Returns the lightest ISMC section that satisfies every check, or a Dict with "error".

Axes: X = across the two chords, Z = depth of the channels, Y = column axis.
"""
function Design_Lacing_Column(
    Length::Float64,
    Pu_kN::Float64,
    bc_code::Int;
    fy::Float64 = 250.0,
    fu::Float64 = 410.0,
    E::Float64 = 200e3,
)
    if Length <= 0 || Pu_kN <= 0 || !(0 <= bc_code <= 3)
        return Dict("error" => "Invalid input.",
                    "message" => "Length and load must be positive and Boundary_Condition must be 0-3.")
    end

    # IS 800 Table 11 effective length factors
    k_eff = (1.0, 0.65, 2.0, 0.80)[bc_code + 1]
    Le = k_eff * Length

    last_reason = "no section tried"
    for cs in ISMC
        res = _check_section(cs, Length, Le, k_eff, bc_code, Pu_kN, fy, fu, E)
        res isa Dict && return res
        last_reason = res
    end

    return Dict("error" => "No suitable ISMC chord found.",
                "message" => "Heaviest section tried (ISMC 400) failed: $last_reason")
end

# Returns a result Dict if the section passes everything, otherwise a String (reason).
function _check_section(cs, Length, Le, k_eff, bc_code, Pu_kN, fy, fu, E)
    A_chord = cs.A
    A_total = 2 * A_chord
    Ixx_tot = 2 * cs.Ixx                     # about the material axis (parallel to X)

    # Clear gap s so that I_yy >= I_xx (equal slenderness both ways), rounded up to 10 mm
    d = sqrt(max((Ixx_tot - 2 * cs.Iyy) / (2 * A_chord), 0.0))
    s = max(ceil(2 * (d - cs.Cyy) / 10.0) * 10.0, 20.0)

    Iyy_tot = 2 * cs.Iyy + 2 * A_chord * (s / 2 + cs.Cyy)^2   # about the free axis (parallel to Z)
    r_xx = sqrt(Ixx_tot / A_total)
    r_yy = sqrt(Iyy_tot / A_total)

    lam_x   = Le * 1000.0 / r_xx
    lam_y   = Le * 1000.0 / r_yy
    lam_max = max(lam_x, lam_y)
    lam_eff = 1.05 * lam_max                 # Cl. 7.6.1.5: shear-deformation allowance

    lam_eff <= 180.0 || return "$(cs.name): effective slenderness $(round(lam_eff, digits=1)) > 180 (Table 3)"

    f_cd      = _fcd(lam_eff, fy, E)         # Cl. 7.1.2.1
    Pu_design = f_cd * A_total / 1000.0
    Pu_design >= Pu_kN || return "$(cs.name): capacity $(round(Pu_design, digits=1)) kN < $(Pu_kN) kN"

    # ── Lacing geometry ───────────────────────────────────────────────────
    g        = s + cs.b                      # gauge: bolt line to bolt line (bolts at mid-flange)
    ry_chord = sqrt(cs.Iyy / A_chord)        # least r of one channel
    tie_len  = ceil(g / 10.0) * 10.0         # end tie plate length along axis >= g
    tie_t    = max(6.0, ceil(g / 50.0))      # tie plate thickness >= g/50
    edge     = ceil(0.75 * cs.b)             # clearance so bar ends do not run into the tie plate
    y_start  = tie_len + edge                # axial position of first lacing bolt
    L_reg    = Length * 1000.0 - 2 * y_start
    L_reg > 0 || return "$(cs.name): column too short for lacing (use battens)"

    # Cl. 7.6.5: bar inclination to member axis between 40° and 70°
    # Cl. 7.6.1.4: chord slenderness between lacing connections <= min(50, 0.7 λ_max)
    # Single lacing: consecutive bolts on one chord are 2a apart.
    a_max   = g / tand(40.0)
    n       = max(2, 2 * ceil(Int, L_reg / a_max / 2))      # even number of panels (symmetric)
    lam_lim = min(50.0, 0.7 * lam_max)
    found   = false
    a = 0.0; theta = 0.0; lam_c = 0.0
    while true
        a = L_reg / n
        theta = atand(g / a)
        theta > 70.0 && break
        lam_c = 2a / ry_chord
        if lam_c <= lam_lim
            found = true
            break
        end
        n += 2
    end
    found || return "$(cs.name): no lacing layout satisfies 40°-70° and chord slenderness <= $(round(lam_lim, digits=1))"

    # ── Lacing bar (Cl. 7.6.6) ───────────────────────────────────────────
    V_t   = 0.025 * Pu_kN                    # 2.5 % of axial force
    V_pl  = V_t / 2.0                        # two parallel lacing planes
    P_lac = V_pl / sind(theta)               # force in one diagonal
    L_lac = g / sind(theta)                  # length between end bolts

    bar = _design_flat_bar(P_lac, L_lac, cs.b, cs.tf, fy, fu, E)
    bar === nothing && return "$(cs.name): no flat bar/bolt combination resists $(round(P_lac, digits=1)) kN"

    return Dict(
        # Inputs
        "Length_m"                 => Length,
        "Axial_Load_kN"            => Pu_kN,
        "Effective_Length_m"       => round(Le, digits = 3),
        "Effective_Length_Factor"  => k_eff,
        "Boundary_Condition"       => ("Pinned-Pinned", "Fixed-Fixed", "Fixed-Free", "Fixed-Pinned")[bc_code + 1],

        # Chord
        "Chord_Section"            => cs.name,
        "Chord_Area_mm2"           => cs.A,
        "Chord_Depth_mm"           => cs.h,
        "Chord_Width_mm"           => cs.b,
        "tf_mm"                    => cs.tf,
        "tw_mm"                    => cs.tw,

        # Built-up section
        "Total_Area_mm2"           => round(A_total, digits = 1),
        "Channel_Spacing_mm"       => s,
        "I_xx_cm4"                 => round(Ixx_tot / 1e4, digits = 1),
        "I_yy_cm4"                 => round(Iyy_tot / 1e4, digits = 1),
        "r_xx_mm"                  => round(r_xx, digits = 1),
        "r_yy_mm"                  => round(r_yy, digits = 1),

        # Slenderness & capacity
        "lambda_x"                 => round(lam_x, digits = 1),
        "lambda_y"                 => round(lam_y, digits = 1),
        "lambda_max"               => round(lam_max, digits = 1),
        "modified_slenderness"     => round(lam_eff, digits = 1),
        "f_cd_MPa"                 => round(f_cd, digits = 2),
        "Design_Capacity_kN"       => round(Pu_design, digits = 1),
        "Capacity_Utilization"     => round(Pu_kN / Pu_design, digits = 3),
        "Status"                   => "SAFE",

        # Lacing layout
        "Num_Lacing_Panels"        => n,
        "Panel_Length_mm"          => round(a, digits = 1),
        "Lacing_Gauge_mm"          => g,
        "Lacing_Start_mm"          => y_start,
        "Lacing_Angle_deg"         => round(theta, digits = 1),
        "Chord_Slenderness"        => round(lam_c, digits = 1),
        "Chord_Slenderness_Limit"  => round(lam_lim, digits = 1),

        # Lacing bar
        "Shear_Vt_kN"              => round(V_t, digits = 2),
        "Lacing_Bar_Force_kN"      => round(P_lac, digits = 2),
        "Lacing_Bar_Length_mm"     => round(L_lac, digits = 1),
        "Lacing_Bar_Thickness_mm"  => bar.t,
        "Lacing_Bar_Width_mm"      => bar.w,
        "Lacing_Bar_Slenderness"   => round(bar.lam, digits = 1),
        "Lacing_Bar_Capacity_kN"   => round(bar.cap, digits = 2),
        "Lacing_Bolt_Diameter_mm"  => bar.d_b,
        "Lacing_Bolts_Per_End"     => bar.n_b,
        "Lacing_Bolt_Capacity_kN"  => round(bar.V_db, digits = 2),

        # Tie plates
        "Tie_Plate_Length_mm"      => tie_len,
        "Tie_Plate_Thickness_mm"   => tie_t,

        # Checks
        "Slenderness_Limit_Check"      => "PASS",
        "Chord_Slenderness_Check"      => "PASS",
        "Lacing_Angle_Check"           => "PASS",
        "Lacing_Slenderness_Check"     => "PASS",
        "Lacing_Bar_Capacity_Check"    => "PASS",

        "mesh_url" => "/design/lacing/mesh",
        "stl_url"  => "/design/lacing/stl",
    )
end

# Cl. 7.1.2.1 design compressive stress (MPa) for effective slenderness `lam`.
function _fcd(lam::Float64, fy::Float64, E::Float64; alpha::Float64 = ALPHA_C)
    lam = max(lam, 1e-3)
    f_cc = π^2 * E / lam^2
    lb   = sqrt(fy / f_cc)
    phi  = 0.5 * (1.0 + alpha * (lb - 0.2) + lb^2)
    chi  = min(1.0, 1.0 / (phi + sqrt(max(phi^2 - lb^2, 0.0))))
    return chi * fy / GAMMA_M0
end

# Smallest flat bar + bolt that works (single lacing, bar designed as a compression member).
#  - width >= 3 × bolt diameter            (Cl. 7.6.3)
#  - thickness >= L_lac / 40               (Cl. 7.6.4, single lacing)
#  - slenderness (L_lac / r) <= 145        (Cl. 7.6.6)
#  - capacity: buckling (curve c), gross yield, net-section rupture
#  - bolts: grade 4.6, single shear (threads in shear plane), bearing with e = 1.5 d0
function _design_flat_bar(P_kN, L_lac, b_flange, tf, fy, fu, E)
    best = nothing
    for d_b in (16.0, 20.0, 24.0)
        d0    = d_b + 2.0
        w_min = ceil(3 * d_b / 5.0) * 5.0
        w_max = max(w_min, floor(b_flange / 5.0) * 5.0)
        A_nb  = 0.78 * π * d_b^2 / 4
        V_dsb = (400.0 / sqrt(3.0)) * A_nb / GAMMA_M1 / 1000.0
        for t in (6.0, 8.0, 10.0, 12.0, 16.0, 20.0)
            t < L_lac / 40.0 && continue
            lam = L_lac / (t / sqrt(12.0))
            lam > 145.0 && continue
            fcd   = _fcd(lam, fy, E)
            V_dpb = 2.5 * 0.5 * d_b * min(t, tf) * fu / GAMMA_M1 / 1000.0
            V_db  = min(V_dsb, V_dpb)
            n_b   = ceil(Int, P_kN / V_db)
            n_b > 2 && continue
            for w in w_min:5.0:w_max
                Ag  = w * t
                cap = min(fcd * Ag / 1000.0,
                          fy * Ag / GAMMA_M0 / 1000.0,
                          0.9 * fu * (w - d0) * t / GAMMA_M1 / 1000.0)
                if cap >= P_kN && (best === nothing || Ag < best.Ag)
                    best = (d_b = d_b, n_b = n_b, t = t, w = w, Ag = Ag, lam = lam, cap = cap, V_db = V_db)
                end
            end
        end
        best !== nothing && return best
    end
    return best
end

end  # module LacingColumnDesign