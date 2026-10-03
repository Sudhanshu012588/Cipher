## Standalone test for the LLM report step.
## Does NOT need the CSV files or the real calculation.
##
## Run from the Backend folder:
##   julia Report/test_report.jl          # PASS case
##   julia Report/test_report.jl fail     # FAIL case (capacity below load)
##
## Needs LLM_API_KEY (and optionally LLM_BASE_URL, LLM_MODEL) to be set.

using HTTP
using JSON3


## Stand-in for the real Design_Column.
## SAMPLE NUMBERS ONLY - this is not a real design.
function Design_Column(Length, Fac_Axial_Load, Boundary_Condition, Sections)

    capacity = "fail" in ARGS ? 410.0 : 612.4

    return Dict{String,Any}(
        "Length_m"=>Length,
        "Axial_Load_kN"=>Fac_Axial_Load,
        "Boundary_Condition"=>Boundary_Condition,
        "Effective_Length_m"=>Length,
        "fy_MPa"=>250.0,
        "E_MPa"=>200000.0,
        "gamma_m0"=>1.10,
        "Assumed_fcd_MPa"=>135.0,
        "Required_Area_mm2"=>3703.7,
        "Designation"=>"SAMPLE-SECTION",
        "Section_Type"=>Sections,
        "Section_Area_mm2"=>3233.0,
        "Plate_Thickness_mm"=>10.0,
        "Plate_Width_mm"=>23.535,
        "Composite_Area_mm2"=>3703.7,
        "r_zz_mm"=>82.0,
        "r_yy_mm"=>31.5,
        "r_min_mm"=>31.5,
        "Slenderness"=>95.2,
        "Buckling_Class"=>"c",
        "f_cd_MPa"=>165.4,
        "Design_Capacity_kN"=>capacity,
        "Status"=>capacity >= Fac_Axial_Load ? "SAFE" : "UNSAFE"
    )
end


include(joinpath(@__DIR__, "Report_LLM.jl"))


println("\n=== Data the LLM is given ===")
JSON3.pretty(column_report_data(Design_Column(3.0, 500.0, 0, "I")))


println("\n=== Calling LLM ===")
out = Generate_Column_Report(3.0, 500.0, 0, "I")

if haskey(out, "report")
    println("\nMODEL: ", out["model"], "\n")
    println(out["report"])
else
    println("\nFAILED:")
    for (k, v) in out
        println("  ", k, ": ", v)
    end
end
