using CSV
using DataFrames

## Logic_Beam.jl — IS 800 Steel Beam Flexural Design Engine
##
## Unit conventions (maintained throughout):
##   Lengths    : mm  (internally); span input in m, converted at entry
##   Forces     : kN
##   Moments    : kN·m
##   Stresses   : MPa  (= N/mm²)
##   Section moduli : mm³
##   Inertia    : mm⁴
##
## Material constants (IS 800, Fe410 / E250):
##   f_y    = 250 MPa
##   γ_m0   = 1.10
##   E      = 200 000 MPa

## ============================================================
## CSV PATH  (relative to this file, one level up)
## ============================================================

const Steel_Table_CSV_Beam = joinpath(
    @__DIR__,
    "..",
    "CSV_Data",
    "steel_sections_I_C_IS808_fixed.csv"
)


## ============================================================
## DESIGN FUNCTION
## ============================================================

function Design_Beam(
    span_m,
    wu_kN_m,
    Wu_kN,
    b1_mm = 100.0
)

    try

        ## ------------------------------------------------
        ## Material & partial-factor constants
        ## ------------------------------------------------

        f_y    = 250.0      # MPa
        γ_m0   = 1.10
        E_MPa  = 200_000.0  # MPa = N/mm²


        ## ------------------------------------------------
        ## Input validation
        ## ------------------------------------------------

        if !isfinite(span_m) || span_m <= 0
            return Dict(
                "error" => "Span must be a finite positive number."
            )
        end

        if !isfinite(wu_kN_m) || wu_kN_m < 0
            return Dict(
                "error" => "Factored UDL (wu_kN_m) must be >= 0."
            )
        end

        if !isfinite(Wu_kN) || Wu_kN < 0
            return Dict(
                "error" => "Factored point load (Wu_kN) must be >= 0."
            )
        end

        if wu_kN_m == 0 && Wu_kN == 0
            return Dict(
                "error" => "At least one of wu_kN_m or Wu_kN must be non-zero."
            )
        end

        if !isfinite(b1_mm) || b1_mm <= 0
            return Dict(
                "error" => "Stiff bearing length (b1_mm) must be a finite positive number."
            )
        end


        ## ------------------------------------------------
        ## STEP 1 — Factored loads and design actions
        ##   M_u  (kN·m) = wu*L²/8 + Wu*L/4
        ##   V_u_s (kN)  = wu*L/2 + Wu/2       (shear at support)
        ##   V_u_m (kN)  = Wu/2                 (shear at midspan from point load)
        ## ------------------------------------------------

        L_m   = span_m
        L_mm  = span_m * 1000.0   # mm

        M_u   = wu_kN_m * L_m^2 / 8.0 + Wu_kN * L_m / 4.0   # kN·m
        V_u_s = wu_kN_m * L_m / 2.0  + Wu_kN / 2.0           # kN
        V_u_m = Wu_kN / 2.0                                    # kN  (from point load only)

        if !isfinite(M_u) || M_u <= 0
            return Dict(
                "error" => "Computed design moment M_u is invalid."
            )
        end

        if !isfinite(V_u_s) || V_u_s <= 0
            return Dict(
                "error" => "Computed support shear V_u_s is invalid."
            )
        end


        ## ------------------------------------------------
        ## STEP 2 — Required plastic section modulus
        ##   M_d = Z_p * f_y / γ_m0   →   Z_p_reqd = M_u * 1e6 * γ_m0 / f_y
        ##   (M_u in kN·m → multiply by 1e6 to get N·mm)
        ## ------------------------------------------------

        Zp_reqd_mm3 = M_u * 1.0e6 * γ_m0 / f_y   # mm³


        ## ------------------------------------------------
        ## STEP 3 — Section selection
        ##   Filter Type == "I", sort by mass (lightest first).
        ##   Choose first section where Zx_cm3 * 1000 >= Zp_reqd_mm3.
        ## ------------------------------------------------

        if !isfile(Steel_Table_CSV_Beam)
            return Dict(
                "error" => "Steel section CSV file not found.",
                "File"  => Steel_Table_CSV_Beam
            )
        end

        all_sections = CSV.read(Steel_Table_CSV_Beam, DataFrame)

        ## Keep only I-sections, sorted lightest first
        i_sections = filter(
            row -> row.Type == "I",
            all_sections
        )

        if isempty(i_sections)
            return Dict(
                "error" => "No I-sections found in the steel CSV."
            )
        end

        sort!(i_sections, :Mass_kg_m)

        ## Find first (lightest) I-section with adequate Z_p
        section_idx = findfirst(
            row -> row.Zx_cm3 * 1000.0 >= Zp_reqd_mm3,
            eachrow(i_sections)
        )

        if section_idx === nothing
            return Dict(
                "error"          => "No I-section found with sufficient plastic section modulus.",
                "Zp_reqd_mm3"    => Zp_reqd_mm3,
                "Max_Zx_cm3"     => maximum(i_sections.Zx_cm3),
                "Max_Zp_avail_mm3" => maximum(i_sections.Zx_cm3) * 1000.0
            )
        end

        section = i_sections[section_idx, :]

        ## Extract section properties
        desig  = section.Designation
        D_mm   = Float64(section.Depth_mm)
        bf_mm  = Float64(section.Width_mm)
        tw_mm  = Float64(section.tw_mm)
        tf_mm  = Float64(section.tf_mm)
        Ix_cm4 = Float64(section.Ix_cm4)
        Iy_cm4 = Float64(section.Iy_cm4)
        Zx_cm3 = Float64(section.Zx_cm3)
        mass   = Float64(section.Mass_kg_m)
        Area_mm2 = Float64(section.Area_mm2)

        Zp_mm3 = Zx_cm3 * 1000.0           # mm³  (plastic section modulus)
        I_mm4  = Ix_cm4 * 1.0e4            # mm⁴  (major-axis inertia)

        ## Elastic section modulus Ze = I / (D/2)
        Ze_mm3 = I_mm4 / (D_mm / 2.0)      # mm³


        ## ------------------------------------------------
        ## STEP 4 — Section classification
        ##   ε = √(250 / f_y)  = 1.0 for Fe250
        ##   Plastic :     flange ≤ 8.4ε   AND  web ≤  84ε
        ##   Compact :     flange ≤ 9.4ε   AND  web ≤ 105ε
        ##   Semi-compact: flange ≤ 13.6ε  AND  web ≤ 126ε
        ##   Else Slender
        ## ------------------------------------------------

        epsilon       = sqrt(250.0 / f_y)
        flange_ratio  = bf_mm / (2.0 * tf_mm)
        web_clear_mm  = D_mm - 2.0 * tf_mm
        web_ratio     = web_clear_mm / tw_mm

        section_class =
            if flange_ratio <= 8.4 * epsilon && web_ratio <= 84.0 * epsilon
                "Plastic"
            elseif flange_ratio <= 9.4 * epsilon && web_ratio <= 105.0 * epsilon
                "Compact"
            elseif flange_ratio <= 13.6 * epsilon && web_ratio <= 126.0 * epsilon
                "Semi-compact"
            else
                "Slender"
            end


        ## ------------------------------------------------
        ## STEP 5a — Shear capacity
        ##   A_v = D * t_w   (shear area of web, IS 800 §8.4.1)
        ##   V_d = (f_y / (√3 · γ_m0)) · A_v   [N] → /1000 → [kN]
        ## ------------------------------------------------

        A_v_mm2 = D_mm * tw_mm                                    # mm²
        V_d_kN  = (f_y / (sqrt(3.0) * γ_m0)) * A_v_mm2 / 1000.0 # kN

        shear_check = V_d_kN >= V_u_s


        ## ------------------------------------------------
        ## STEP 5b — Moment capacity with shear interaction
        ##   High shear : V_u_s > 0.6 · V_d
        ##     β  = (2·V_u_s/V_d − 1)²
        ##     M_dv = [Z_p·f_y/γ_m0 − β·(Z_p − Z_e)·f_y/γ_m0] / 1e6   kN·m
        ##   Low shear:
        ##     M_d = Z_p · f_y / (γ_m0 · 1e6)   kN·m
        ## ------------------------------------------------

        high_shear = V_u_s > 0.6 * V_d_kN

        M_d_kNm = if high_shear
            beta  = (2.0 * V_u_s / V_d_kN - 1.0)^2
            M_dv_Nmm = (Zp_mm3 * f_y / γ_m0) -
                       beta * (Zp_mm3 - Ze_mm3) * f_y / γ_m0
            M_dv_Nmm / 1.0e6   # kN·m
        else
            Zp_mm3 * f_y / (γ_m0 * 1.0e6)   # kN·m
        end

        moment_check = M_d_kNm >= M_u


        ## ------------------------------------------------
        ## STEP 5c — Deflection check (serviceability)
        ##   Unfactored loads = factored / 1.5
        ##   δ_udl = (5/384) · w · L⁴ / (E·I)    w in N/mm
        ##   δ_pl  = W · L³  / (48·E·I)            W in N
        ##   δ_lim = L / 300
        ## ------------------------------------------------

        w_N_mm   = (wu_kN_m / 1.5) * 1000.0 / 1000.0   # N/mm  (kN/m → N/mm: ×1000/1000 = ×1)
        W_N      = (Wu_kN   / 1.5) * 1000.0             # N

        delta_udl = (5.0 / 384.0) * w_N_mm * L_mm^4 / (E_MPa * I_mm4)  # mm
        delta_pl  = W_N * L_mm^3 / (48.0 * E_MPa * I_mm4)              # mm
        delta_tot = delta_udl + delta_pl                                  # mm
        delta_lim = L_mm / 300.0                                         # mm

        deflection_check = delta_tot <= delta_lim


        ## ------------------------------------------------
        ## STEP 5d — Web crippling check (IS 800 §8.7)
        ##   R (root radius) ≈ t_f  (conservative, R not in CSV)
        ##   F_w = (b1 + 2.5·(t_f + R)) · t_w · f_y / γ_m0   [N] → /1000 → [kN]
        ## ------------------------------------------------

        R_mm = tf_mm   # assumed root radius
        F_w_kN = (b1_mm + 2.5 * (tf_mm + R_mm)) * tw_mm * f_y / (γ_m0 * 1000.0)  # kN

        web_crippling_check = F_w_kN >= V_u_s


        ## ------------------------------------------------
        ## Overall status
        ## ------------------------------------------------

        all_pass = shear_check && moment_check && deflection_check && web_crippling_check
        status   = all_pass ? "SAFE" : "UNSAFE"


        ## ------------------------------------------------
        ## Return comprehensive result Dict
        ## ------------------------------------------------

        return Dict(

            ## ── Inputs ──────────────────────────────────
            "Span_m"          => span_m,
            "wu_kN_m"         => wu_kN_m,
            "Wu_kN"           => Wu_kN,
            "b1_mm"           => b1_mm,

            ## ── Material ────────────────────────────────
            "fy_MPa"          => f_y,
            "gamma_m0"        => γ_m0,
            "E_MPa"           => E_MPa,

            ## ── Design actions ──────────────────────────
            "M_u_kNm"         => M_u,
            "V_u_s_kN"        => V_u_s,
            "V_u_m_kN"        => V_u_m,

            ## ── Section selection ────────────────────────
            "Zp_reqd_mm3"     => Zp_reqd_mm3,
            "Designation"     => string(desig),
            "Mass_kg_m"       => mass,
            "Depth_mm"        => D_mm,
            "Width_mm"        => bf_mm,
            "tw_mm"           => tw_mm,
            "tf_mm"           => tf_mm,
            "Ix_cm4"          => Ix_cm4,
            "Iy_cm4"          => Iy_cm4,
            "Zx_cm3"          => Zx_cm3,
            "Area_mm2"        => Area_mm2,
            "Zp_mm3"          => Zp_mm3,
            "Ze_mm3"          => Ze_mm3,
            "I_mm4"           => I_mm4,

            ## ── Section classification ───────────────────
            "epsilon"         => epsilon,
            "flange_ratio"    => flange_ratio,
            "web_ratio"       => web_ratio,
            "Section_Class"   => section_class,

            ## ── Shear capacity ───────────────────────────
            "Av_mm2"          => A_v_mm2,
            "A_v_mm2"         => A_v_mm2,
            "Vd_kN"           => V_d_kN,
            "V_d_kN"          => V_d_kN,
            "shear_check"     => shear_check,
            "Shear_Check"     => shear_check ? "PASS" : "FAIL",

            ## ── Moment capacity ──────────────────────────
            "high_shear"      => high_shear,
            "High_Shear"      => high_shear,
            "Md_kNm"          => M_d_kNm,
            "M_d_kNm"         => M_d_kNm,
            "moment_check"    => moment_check,
            "Moment_Check"    => moment_check ? "PASS" : "FAIL",

            ## ── Deflection ───────────────────────────────
            "w_service_N_mm"  => w_N_mm,
            "W_service_N"     => W_N,
            "delta_udl_mm"    => delta_udl,
            "delta_pl_mm"     => delta_pl,
            "delta_total_mm"  => delta_tot,
            "delta_mm"        => delta_tot,
            "delta_limit_mm"  => delta_lim,
            "deflection_check" => deflection_check,
            "Deflection_Check" => deflection_check ? "PASS" : "FAIL",

            ## ── Web crippling ────────────────────────────
            "R_assumed_mm"       => R_mm,
            "Fw_kN"              => F_w_kN,
            "F_w_kN"             => F_w_kN,
            "web_crippling_check" => web_crippling_check,
            "Web_Crippling_Check" => web_crippling_check ? "PASS" : "FAIL",

            ## ── Overall ──────────────────────────────────
            "Status"          => status
        )

    catch e

        return Dict(
            "error"   => "Beam design failed.",
            "message" => sprint(showerror, e)
        )

    end

end
