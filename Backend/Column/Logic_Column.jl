## All Length are in Meter
## All Forces are in KN
## ALl strees are in MPa

Buckling_CSV = "C:\\Users\\taada\\project\\Cipher\\Backend\\CSV_Data\\buckling_curves_IS800.csv"
Steel_Table_CSV = "C:\\Users\\taada\\project\\Cipher\\Backend\\CSV_Data\\steel_sections_I_C_IS808_fixed.csv"

function select_section(sections,required_area;section_type="I")

    candidates = filter(
        row -> row.Type == section_type &&
               row.Area_mm2 >= required_area,
        sections
    )

    if isempty(candidates)
        return nothing
    end

    sort!(
        candidates,
        :Area_mm2
    )

    return candidates[1,:]
end


function PlateCal(section,A_req)

    ## Required additional area
    A_plate = A_req-section.Area_mm2

    ## If steel section itself is sufficient
    if A_plate <= 0
        return Dict(
            "t_plate"=>0.0,
            "b_plate"=>0.0
        )
    end

    ## 10mm plate thickness
    t_plate = 10.0

    ## Two plates are provided
    ## A_req = A_section + 2*b*t

    b_p = A_plate/(2*t_plate)

    if b_p <= 0
        error("Calculated plate width is invalid.")
    end

    return Dict(
        "t_plate"=>t_plate,
        "b_plate"=>b_p
    )
end


function CompositeInertia(section,plate)

    ## Original section inertias
    ## cm4 -> mm4

    I_zz_1 = section.Ix_cm4 * 10^4
    I_yy_1 = section.Iy_cm4 * 10^4

    if !isfinite(I_zz_1) || I_zz_1 <= 0
        error("Invalid major axis inertia in steel section.")
    end

    if !isfinite(I_yy_1) || I_yy_1 <= 0
        error("Invalid minor axis inertia in steel section.")
    end


    ## Overall depth of original section

    D = section.Depth_mm

    if !isfinite(D) || D <= 0
        error("Invalid section depth.")
    end


    ## Plate dimensions

    b_p = plate["b_plate"]
    t_p = plate["t_plate"]

    if b_p < 0 || t_p < 0
        error("Invalid plate dimensions.")
    end


    ## No plate required

    if b_p == 0 || t_p == 0

        return Dict(
            "I_zz"=>I_zz_1,
            "I_yy"=>I_yy_1,
            "d"=>0.0,
            "A_plate"=>0.0
        )

    end


    ## Area of one plate

    A_p = b_p*t_p


    ## Distance from centroid of original section
    ## to centroid of each plate

    d = D/2+t_p/2


    ## About major horizontal axis

    I_plate_zz = b_p*t_p^3/12


    ## About minor vertical axis

    I_plate_yy = t_p*b_p^3/12


    ## Parallel axis theorem
    ## Two identical plates

    I_zz_2 =
        I_zz_1 +
        2*(I_plate_zz+A_p*d^2)


    ## Plates are symmetric about major axis
    ## Therefore no parallel-axis contribution about yy

    I_yy_2 =
        I_yy_1 +
        2*I_plate_yy


    if !isfinite(I_zz_2) || I_zz_2 <= 0
        error("Calculated composite Izz is invalid.")
    end

    if !isfinite(I_yy_2) || I_yy_2 <= 0
        error("Calculated composite Iyy is invalid.")
    end


    return Dict(
        "I_zz"=>I_zz_2,
        "I_yy"=>I_yy_2,
        "d"=>d,
        "A_plate"=>A_p
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


    alpha = curve[1,:].Imperfection_Factor_alpha
    E = curve[1,:].E_MPa
    gamma_m0 = curve[1,:].Gamma_M0


    if !isfinite(alpha) || alpha < 0
        error("Invalid imperfection factor.")
    end

    if !isfinite(E) || E <= 0
        error("Invalid Young's modulus.")
    end

    if !isfinite(gamma_m0) || gamma_m0 <= 0
        error("Invalid gamma_m0.")
    end


    ## Euler elastic critical stress

    f_cc =
        π^2*E/slenderness^2


    if !isfinite(f_cc) || f_cc <= 0
        error("Invalid Euler critical stress.")
    end


    ## Non-dimensional slenderness

    lambda_bar =
        sqrt(fy/f_cc)


    if !isfinite(lambda_bar) || lambda_bar <= 0
        error("Invalid non-dimensional slenderness.")
    end


    ## Phi

    phi =
        0.5*(
            1 +
            alpha*(lambda_bar-0.2) +
            lambda_bar^2
        )


    if !isfinite(phi)
        error("Invalid buckling phi value.")
    end


    ## Reduction factor

    sqrt_term =
        phi^2-lambda_bar^2


    ## Numerical protection

    if sqrt_term < 0

        if sqrt_term > -1e-10
            sqrt_term = 0.0
        else
            error("Invalid buckling reduction calculation.")
        end

    end


    denominator =
        phi+sqrt(sqrt_term)


    if !isfinite(denominator) || denominator <= 0
        error("Invalid buckling reduction factor.")
    end


    chi =
        1/denominator


    if !isfinite(chi) || chi <= 0
        error("Invalid reduction factor.")
    end


    ## Design compressive stress

    f_cd =
        chi*fy/gamma_m0


    if !isfinite(f_cd) || f_cd <= 0
        error("Calculated design compressive stress is invalid.")
    end


    return Dict(
        "buckling_class"=>buckling_class,
        "alpha"=>alpha,
        "f_cc"=>f_cc,
        "lambda_bar"=>lambda_bar,
        "phi"=>phi,
        "chi"=>chi,
        "f_cd"=>f_cd
    )
end


function Design_Column(
    Length,
    Fac_Axial_Load,
    Boundary_Condition,
    Sections
)

    try

        ## Boundary_Condition == 0 => Pinned-Pinned -> k=1
        ## Boundary_Condition == 1 => Fixed-Fixed   -> k=0.5
        ## Boundary_Condition == 2 => Fixed-Free    -> k=2
        ## Boundary_Condition == 3 => Fixed-Pinned  -> k=0.7


        ## Sections == 'I' or Sections == 'C'


        if !isfinite(Length)
            return Dict(
                "error"=>"Length must be a finite number."
            )
        end


        if Length <= 0
            return Dict(
                "error"=>"Length must be greater than zero."
            )
        end


        if !isfinite(Fac_Axial_Load)
            return Dict(
                "error"=>"Axial load must be a finite number."
            )
        end


        if Fac_Axial_Load <= 0
            return Dict(
                "error"=>"Axial load must be greater than zero."
            )
        end


        if Boundary_Condition ∉ [0,1,2,3]
            return Dict(
                "error"=>"Invalid Boundary_Condition. Use 0, 1, 2 or 3."
            )
        end


        if Sections ∉ ["I","C"]
            return Dict(
                "error"=>"Invalid section type. Use I or C."
            )
        end
        Leff = Length


        if Boundary_Condition==0

            Leff *= 1

        elseif Boundary_Condition==1

            Leff *= 0.5

        elseif Boundary_Condition==2

            Leff *= 2

        elseif Boundary_Condition==3

            Leff *= 0.7

        end


        if !isfinite(Leff) || Leff <= 0
            return Dict(
                "error"=>"Effective length is invalid."
            )
        end
        f_cd = 135


        if Fac_Axial_Load > 500
            f_cd = 200
        end


        ## Required area
        ## P = f*A
        ## A(mm2) = P(kN)*1000/f(MPa)

        A_req =
            Fac_Axial_Load/f_cd*1000


        if !isfinite(A_req) || A_req <= 0
            return Dict(
                "error"=>"Required area is invalid."
            )
        end
        if !isfile(Steel_Table_CSV)

            return Dict(
                "error"=>"Steel section CSV file not found.",
                "File"=>Steel_Table_CSV
            )

        end


        sections = CSV.read(
            Steel_Table_CSV,
            DataFrame
        )

        ##println(sections)

        required_columns = [
            :Designation,
            :Type,
            :Mass_kg_m,
            :Area_mm2,
            :Depth_mm,
            :Width_mm,
            :tw_mm,
            :tf_mm,
            :Ix_cm4,
            :Iy_cm4
        ]


        # for column in required_columns

        #     if !(Symbol(column) in propertynames(steel_sections))

        #         return Dict(
        #             "error"=>"Required column missing from steel CSV.",
        #             "Column"=>string(column)
        #         )

        #     end

        # end

        section = select_section(
            sections,
            A_req;
            section_type=Sections
        )


        if section === nothing

            return Dict(
                "error"=>"No suitable section found.",
                "Required_Area_mm2"=>A_req,
                "Section_Type"=>Sections
            )

        end
        if !isfile(Buckling_CSV)

            return Dict(
                "error"=>"Buckling curve CSV file not found.",
                "File"=>Buckling_CSV
            )

        end


        buckling_curves = CSV.read(
            Buckling_CSV,
            DataFrame
        )

        ##println(buckling_curves)

        required_buckling_columns = [
            :Buckling_Class,
            :Imperfection_Factor_alpha,
            :E_MPa,
            :Gamma_M0
        ]


        # for column in required_buckling_columns

        #     if !(column in names(buckling_curves))

        #         return Dict(
        #             "error"=>"Required column missing from buckling CSV.",
        #             "Column"=>string(column)
        #         )

        #     end

        # end


        ## Buckling class c

        curve = filter(
            row -> row.Buckling_Class == "c",
            buckling_curves
        )


        if isempty(curve)

            return Dict(
                "error"=>"Buckling class c not found in buckling CSV."
            )

        end
        itr = 0


        while true

            itr += 1


            if itr > nrow(sections)

                return Dict(
                    "error"=>"No safe section found after checking available sections."
                )

            end

            plate = PlateCal(
                section,
                A_req
            )
            Area_composite =
                section.Area_mm2 +
                2*(
                    plate["t_plate"]*
                    plate["b_plate"]
                )


            if !isfinite(Area_composite) ||
               Area_composite <= 0

                return Dict(
                    "error"=>"Calculated composite area is invalid."
                )

            end

            inertia = CompositeInertia(
                section,
                plate
            )


            I_zz = inertia["I_zz"]
            I_yy = inertia["I_yy"]


            if !isfinite(I_zz) || I_zz <= 0

                return Dict(
                    "error"=>"Composite Izz is invalid."
                )

            end


            if !isfinite(I_yy) || I_yy <= 0

                return Dict(
                    "error"=>"Composite Iyy is invalid."
                )

            end
            r_zz =
                sqrt(I_zz/Area_composite)


            r_yy =
                sqrt(I_yy/Area_composite)


            if !isfinite(r_zz) ||
               !isfinite(r_yy) ||
               r_zz <= 0 ||
               r_yy <= 0

                return Dict(
                    "error"=>"Invalid radius of gyration."
                )

            end


            ## Minimum radius governs buckling

            r_min =min(r_zz,r_yy)

            Leff_mm =Leff*1000
            slenderness =Leff_mm/r_min


            if !isfinite(slenderness) ||
               slenderness <= 0

                return Dict(
                    "error"=>"Invalid column slenderness."
                )

            end
            alpha =curve[1,:].Imperfection_Factor_alpha
            res = calculate_fcd(curve[1,:].Buckling_Class,slenderness,250.0,buckling_curves)
            P_d =Area_composite*res["f_cd"]/1000
            if !isfinite(P_d) || P_d <= 0
                return Dict("error"=>"Calculated design capacity is invalid.")
            end

            if P_d >= Fac_Axial_Load

                return Dict(

                    "Length_m"=>Length,

                    "Axial_Load_kN"=>Fac_Axial_Load,

                    "Boundary_Condition"=>Boundary_Condition,

                    "Effective_Length_m"=>Leff,


                    "fy_MPa"=>250.0,

                    "E_MPa"=>200000.0,

                    "gamma_m0"=>1.10,


                    "Assumed_fcd_MPa"=>f_cd,

                    "Required_Area_mm2"=>A_req,
                    "Designation"=>section.Designation,
                    "Section_Type"=>section.Type,

                    "Section_Area_mm2"=>section.Area_mm2,

                    "Section_Mass_kg_m"=>section.Mass_kg_m,

                    "Depth_mm"=>section.Depth_mm,

                    "Width_mm"=>section.Width_mm,

                    "tw_mm"=>section.tw_mm,

                    "tf_mm"=>section.tf_mm,


                    ## Original section properties

                    "Ix_cm4"=>section.Ix_cm4,

                    "Iy_cm4"=>section.Iy_cm4,

                    "rx_cm"=>section.rx_cm,

                    "ry_cm"=>section.ry_cm,


                    ## Plate properties

                    "Plate_Thickness_mm"=>plate["t_plate"],

                    "Plate_Width_mm"=>plate["b_plate"],

                    "Plate_Area_each_mm2"=>inertia["A_plate"],


                    ## Composite properties

                    "Composite_Area_mm2"=>Area_composite,

                    "I_zz_mm4"=>I_zz,

                    "I_yy_mm4"=>I_yy,

                    "r_zz_mm"=>r_zz,

                    "r_yy_mm"=>r_yy,

                    "r_min_mm"=>r_min,

                    "Slenderness"=>slenderness,


                    ## Buckling

                    "Buckling_Class"=>curve[1,:].Buckling_Class,

                    "Alpha"=>alpha,

                    "f_cc_MPa"=>res["f_cc"],

                    "lambda_bar"=>res["lambda_bar"],

                    "phi"=> res["phi"],

                    "chi"=>res["chi"],

                    "f_cd_MPa"=>res["f_cd"],


                    ## Capacity

                    "Design_Capacity_kN"=>P_d,

                    "Status"=>"SAFE"
                )

            end

            candidates = filter(
                row -> row.Type == Sections &&
                       row.Area_mm2 > section.Area_mm2,
                sections
            )


            if isempty(candidates)

                return Dict(
                    "error"=>"No larger section available.",
                    "Last_Section"=>
                        section.Designation,
                    "Design_Capacity_kN"=>
                        P_d,
                    "Required_Load_kN"=>
                        Fac_Axial_Load
                )

            end


            sort!(candidates,:Area_mm2)
            section=candidates[1,:]
        end
    catch e
        return Dict(
            "error"=>"Column design failed.",
            "message"=>sprint(showerror,e)
        )
    end
end