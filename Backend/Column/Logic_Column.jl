## All Lengths are in Meter
## All Forces are in kN
## All Stresses are in MPa

Buckling_CSV = joinpath(@__DIR__, "..", "CSV_Data", "buckling_curves_IS800.csv")
Steel_Table_CSV = joinpath(@__DIR__, "..", "CSV_Data", "steel_sections_I_C_IS808_fixed.csv")

function select_section(sections, required_area; section_type="I")
    candidates = filter(
        row -> row.Type == section_type &&
               row.Area_mm2 >= required_area,
        sections
    )

    if isempty(candidates)
        # Fall back to largest available section of that type so cover plates can reinforce it
        all_type = filter(row -> row.Type == section_type, sections)
        if isempty(all_type)
            return nothing
        end
        sort!(all_type, :Area_mm2, rev=true)
        return all_type[1, :]
    end

    sort!(candidates, :Area_mm2)
    return candidates[1, :]
end


function PlateCal(section, A_req)
    ## Required additional area
    A_plate = A_req - section.Area_mm2

    ## If steel section itself is sufficient
    if A_plate <= 0
        return Dict(
            "t_plate" => 0.0,
            "b_plate" => 0.0
        )
    end

    ## 12mm standard cover plate thickness
    t_plate = 12.0

    ## Two cover plates provided: A_plate = 2 * b_p * t_plate
    b_p = ceil((A_plate / (2 * t_plate)) / 5.0) * 5.0

    if b_p <= 0
        error("Calculated plate width is invalid.")
    end

    return Dict(
        "t_plate" => t_plate,
        "b_plate" => b_p
    )
end


function CompositeInertia(section, plate)
    ## Original section inertias (cm4 -> mm4)
    I_zz_1 = section.Ix_cm4 * 10^4
    I_yy_1 = section.Iy_cm4 * 10^4

    if !isfinite(I_zz_1) || I_zz_1 <= 0
        error("Invalid major axis inertia in steel section.")
    end

    if !isfinite(I_yy_1) || I_yy_1 <= 0
        error("Invalid minor axis inertia in steel section.")
    end

    D = section.Depth_mm
    if !isfinite(D) || D <= 0
        error("Invalid section depth.")
    end

    b_p = plate["b_plate"]
    t_p = plate["t_plate"]

    if b_p < 0 || t_p < 0
        error("Invalid plate dimensions.")
    end

    if b_p == 0 || t_p == 0
        return Dict(
            "I_zz" => I_zz_1,
            "I_yy" => I_yy_1,
            "d" => 0.0,
            "A_plate" => 0.0
        )
    end

    A_p = b_p * t_p
    d = D / 2 + t_p / 2

    I_plate_zz = b_p * t_p^3 / 12
    I_plate_yy = t_p * b_p^3 / 12

    I_zz_2 = I_zz_1 + 2 * (I_plate_zz + A_p * d^2)
    I_yy_2 = I_yy_1 + 2 * I_plate_yy

    if !isfinite(I_zz_2) || I_zz_2 <= 0
        error("Calculated composite Izz is invalid.")
    end

    if !isfinite(I_yy_2) || I_yy_2 <= 0
        error("Calculated composite Iyy is invalid.")
    end

    return Dict(
        "I_zz" => I_zz_2,
        "I_yy" => I_yy_2,
        "d" => d,
        "A_plate" => A_p
    )
end


function calculate_fcd(
    buckling_class,
    slenderness,
    fy,
    buckling_curves
)
    if !isfinite(slenderness) || slenderness <= 0
        error("Slenderness must be greater than zero.")
    end

    if !isfinite(fy) || fy <= 0
        error("Yield strength must be greater than zero.")
    end

    curve = filter(
        row -> row.Buckling_Class == buckling_class,
        buckling_curves
    )

    if isempty(curve)
        error("Invalid buckling class: $buckling_class")
    end

    alpha = curve[1, :].Imperfection_Factor_alpha
    E = curve[1, :].E_MPa
    gamma_m0 = curve[1, :].Gamma_M0

    f_cc = π^2 * E / slenderness^2
    lambda_bar = sqrt(fy / f_cc)
    phi = 0.5 * (1 + alpha * (lambda_bar - 0.2) + lambda_bar^2)

    sqrt_term = phi^2 - lambda_bar^2
    if sqrt_term < 0
        if sqrt_term > -1e-10
            sqrt_term = 0.0
        else
            error("Invalid buckling reduction calculation.")
        end
    end

    chi = 1 / (phi + sqrt(sqrt_term))
    f_cd = chi * fy / gamma_m0

    return Dict(
        "buckling_class" => buckling_class,
        "alpha" => alpha,
        "f_cc" => f_cc,
        "lambda_bar" => lambda_bar,
        "phi" => phi,
        "chi" => chi,
        "f_cd" => f_cd
    )
end


function Design_Column(
    Length,
    Fac_Axial_Load,
    Boundary_Condition,
    Sections
)
    try
        if !isfinite(Length) || Length <= 0
            return Dict("error" => "Length must be greater than zero.")
        end

        if !isfinite(Fac_Axial_Load) || Fac_Axial_Load <= 0
            return Dict("error" => "Axial load must be greater than zero.")
        end

        if Boundary_Condition ∉ [0, 1, 2, 3]
            return Dict("error" => "Invalid Boundary_Condition. Use 0, 1, 2 or 3.")
        end

        if Sections ∉ ["I", "C"]
            return Dict("error" => "Invalid section type. Use I or C.")
        end

        Leff = Length
        if Boundary_Condition == 0
            Leff *= 1.0
        elseif Boundary_Condition == 1
            Leff *= 0.5
        elseif Boundary_Condition == 2
            Leff *= 2.0
        elseif Boundary_Condition == 3
            Leff *= 0.7
        end

        f_cd_init = Fac_Axial_Load > 500 ? 180.0 : 120.0
        A_req_init = (Fac_Axial_Load / f_cd_init) * 1000.0

        if !isfile(Steel_Table_CSV)
            return Dict("error" => "Steel section CSV file not found.", "File" => Steel_Table_CSV)
        end

        sections = CSV.read(Steel_Table_CSV, DataFrame)

        section = select_section(sections, A_req_init; section_type=Sections)
        if section === nothing
            return Dict(
                "error" => "No suitable section found.",
                "Required_Area_mm2" => A_req_init,
                "Section_Type" => Sections
            )
        end

        if !isfile(Buckling_CSV)
            return Dict("error" => "Buckling curve CSV file not found.", "File" => Buckling_CSV)
        end

        buckling_curves = CSV.read(Buckling_CSV, DataFrame)
        curve = filter(row -> row.Buckling_Class == "c", buckling_curves)
        if isempty(curve)
            return Dict("error" => "Buckling class c not found in buckling CSV.")
        end

        itr = 0
        while true
            itr += 1
            if itr > nrow(sections) + 5
                return Dict("error" => "No safe section found after checking available sections.")
            end

            # Step A: Evaluate bare rolled section first
            plate = PlateCal(section, A_req_init)
            Area_composite = section.Area_mm2 + 2 * (plate["t_plate"] * plate["b_plate"])
            inertia = CompositeInertia(section, plate)
            I_zz = inertia["I_zz"]
            I_yy = inertia["I_yy"]

            r_zz = sqrt(I_zz / Area_composite)
            r_yy = sqrt(I_yy / Area_composite)
            r_min = min(r_zz, r_yy)

            slenderness = (Leff * 1000.0) / r_min
            res = calculate_fcd(curve[1, :].Buckling_Class, slenderness, 250.0, buckling_curves)
            P_d = Area_composite * res["f_cd"] / 1000.0

            # Step B: Check if there is a larger rolled section available before adding cover plates
            larger_candidates = filter(
                row -> row.Type == Sections &&
                       row.Area_mm2 > section.Area_mm2,
                sections
            )

            # Step C: If bare section fails AND no larger rolled section exists, size flange cover plates iteratively!
            if P_d < Fac_Axial_Load && isempty(larger_candidates)
                for _ in 1:15
                    A_req_actual = (Fac_Axial_Load / res["f_cd"]) * 1000.0 * 1.02
                    plate = PlateCal(section, max(A_req_actual, Area_composite + 480.0))
                    Area_composite = section.Area_mm2 + 2 * (plate["t_plate"] * plate["b_plate"])
                    inertia = CompositeInertia(section, plate)
                    I_zz = inertia["I_zz"]
                    I_yy = inertia["I_yy"]
                    r_zz = sqrt(I_zz / Area_composite)
                    r_yy = sqrt(I_yy / Area_composite)
                    r_min = min(r_zz, r_yy)
                    slenderness = (Leff * 1000.0) / r_min
                    res = calculate_fcd(curve[1, :].Buckling_Class, slenderness, 250.0, buckling_curves)
                    P_d = Area_composite * res["f_cd"] / 1000.0
                    if P_d >= Fac_Axial_Load
                        break
                    end
                end
            end

            if P_d >= Fac_Axial_Load
                alpha = curve[1, :].Imperfection_Factor_alpha
                return Dict(
                    "Length_m" => Length,
                    "Axial_Load_kN" => Fac_Axial_Load,
                    "Boundary_Condition" => Boundary_Condition,
                    "Effective_Length_m" => Leff,
                    "fy_MPa" => 250.0,
                    "E_MPa" => 200000.0,
                    "gamma_m0" => 1.10,
                    "Assumed_fcd_MPa" => f_cd_init,
                    "Required_Area_mm2" => (Fac_Axial_Load / res["f_cd"]) * 1000.0,
                    "Designation" => section.Designation,
                    "Section_Type" => section.Type,
                    "Section_Area_mm2" => section.Area_mm2,
                    "Section_Mass_kg_m" => section.Mass_kg_m,
                    "Depth_mm" => section.Depth_mm,
                    "Width_mm" => section.Width_mm,
                    "tw_mm" => section.tw_mm,
                    "tf_mm" => section.tf_mm,
                    "Ix_cm4" => section.Ix_cm4,
                    "Iy_cm4" => section.Iy_cm4,
                    "rx_cm" => section.rx_cm,
                    "ry_cm" => section.ry_cm,
                    "Plate_Thickness_mm" => plate["t_plate"],
                    "Plate_Width_mm" => plate["b_plate"],
                    "Plate_Area_each_mm2" => inertia["A_plate"],
                    "Composite_Area_mm2" => Area_composite,
                    "I_zz_mm4" => I_zz,
                    "I_yy_mm4" => I_yy,
                    "r_zz_mm" => r_zz,
                    "r_yy_mm" => r_yy,
                    "r_min_mm" => r_min,
                    "Slenderness" => slenderness,
                    "Buckling_Class" => curve[1, :].Buckling_Class,
                    "Alpha" => alpha,
                    "f_cc_MPa" => res["f_cc"],
                    "lambda_bar" => res["lambda_bar"],
                    "phi" => res["phi"],
                    "chi" => res["chi"],
                    "f_cd_MPa" => res["f_cd"],
                    "Design_Capacity_kN" => P_d,
                    "Status" => "SAFE"
                )
            end

            if isempty(larger_candidates)
                return Dict(
                    "error" => "No larger section available.",
                    "Last_Section" => section.Designation,
                    "Design_Capacity_kN" => P_d,
                    "Required_Load_kN" => Fac_Axial_Load
                )
            end

            sort!(larger_candidates, :Area_mm2)
            section = larger_candidates[1, :]
        end
    catch e
        return Dict(
            "error" => "Column design failed.",
            "message" => sprint(showerror, e)
        )
    end
end