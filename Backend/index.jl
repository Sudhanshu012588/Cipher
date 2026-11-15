using Oxygen
using HTTP
using JSON3
using CSV
using DataFrames
using Gmsh
using DotEnv

# ============================================================
# INCLUDE PROJECT FILES
# ============================================================
DotEnv.load!()
include(joinpath(@__DIR__, "Column", "Logic_Column.jl"))
include(joinpath(@__DIR__, "Column", "Mesh.jl"))
include(joinpath(@__DIR__, "Report", "Report_LLM.jl"))
include(joinpath(@__DIR__, "Beam", "Logic_Beam.jl"))
include(joinpath(@__DIR__, "Beam", "Mesh.jl"))
include(joinpath(@__DIR__, "Beam", "Report_Beam.jl"))

include(joinpath(@__DIR__, "Column", "FEM_Column.jl"))
include(joinpath(@__DIR__, "Beam", "FEM_Beam.jl"))
include(joinpath(@__DIR__, "LacingColumn", "Logic_Lacing.jl"))
include(joinpath(@__DIR__, "LacingColumn", "Mesh_Lacing.jl"))
include(joinpath(@__DIR__, "LacingColumn", "FEM_Lacing.jl"))
using .FEMColumn
using .FEMBeam
using .LacingColumnDesign
using .LacingMesh
using .FEM_Lacing

# ============================================================
# PATHS
# ============================================================

const BACKEND_DIR = @__DIR__
const COLUMN_DIR = joinpath(BACKEND_DIR, "Column")
const BEAM_DIR = joinpath(BACKEND_DIR, "Beam")

const MESH_FILE = joinpath(COLUMN_DIR, "Column.msh")
const STL_FILE = joinpath(COLUMN_DIR, "Column.stl")

const BEAM_MESH_FILE = joinpath(BEAM_DIR, "Beam.msh")
const BEAM_STL_FILE = joinpath(BEAM_DIR, "Beam.stl")

const LACING_DIR = joinpath(BACKEND_DIR, "LacingColumn")
const LACING_MESH_FILE = joinpath(LACING_DIR, "LacingColumn.msh")
const LACING_STL_FILE = joinpath(LACING_DIR, "LacingColumn.stl")


# ============================================================
# CORS
# ============================================================

const CORS_HEADERS = [
    "Access-Control-Allow-Origin" => "*",
    "Access-Control-Allow-Methods" => "GET, POST, OPTIONS",
    "Access-Control-Allow-Headers" => "Content-Type"
]


# ============================================================
# JSON RESPONSE HELPER
# ============================================================

function json_response(status::Int, data)
    return HTTP.Response(
        status,
        [
            "Content-Type" => "application/json",
            "Access-Control-Allow-Origin" => "*"
        ],
        JSON3.write(data)
    )
end


# ============================================================
# CORS HANDLER
# ============================================================

function cors_handler(handler)
    return function(req::HTTP.Request)
        try
            # Browser preflight request
            if req.method == "OPTIONS"
                return HTTP.Response(
                    200,
                    CORS_HEADERS
                )
            end

            # Execute Oxygen route
            response = handler(req)

            # Add CORS headers
            for header in CORS_HEADERS
                HTTP.setheader(response, header)
            end

            return response

        catch e
            @error "Request failed" path=req.target exception=(e, catch_backtrace())

            return HTTP.Response(
                500,
                CORS_HEADERS,
                JSON3.write(
                    Dict(
                        "error" => sprint(showerror, e)
                    )
                )
            )
        end
    end
end


# ============================================================
# HEALTH CHECK
# ============================================================

@get "/health" function(req::HTTP.Request)
    return json_response(
        200,
        Dict(
            "status" => "ok",
            "service" => "Column Design Engine"
        )
    )
end


# ============================================================
# COLUMN DESIGN
# ============================================================

@post "/design/column" function(req::HTTP.Request)
    try
        # ----------------------------------------------------
        # Read request body
        # ----------------------------------------------------
        body = JSON3.read(String(req.body))

        # ----------------------------------------------------
        # Extract input parameters
        # ----------------------------------------------------
        Length = Float64(body.Length)
        Fac_Axial_Load = Float64(body.Fac_Axial_Load)
        Boundary_Condition = Int(body.Boundary_Condition)
        Sections = String(body.Sections)

        println("==============================================")
        println("COLUMN DESIGN REQUEST")
        println("Length              : ", Length, " m")
        println("Factored Axial Load : ", Fac_Axial_Load, " kN")
        println("Boundary Condition  : ", Boundary_Condition)
        println("Section Type        : ", Sections)
        println("==============================================")

        # ----------------------------------------------------
        # RUN COLUMN DESIGN
        # ----------------------------------------------------
        result = Design_Column(
            Length,
            Fac_Axial_Load,
            Boundary_Condition,
            Sections
        )

        # ----------------------------------------------------
        # Check whether design failed
        # ----------------------------------------------------
        if haskey(result, "error")
            println("Column design failed:")
            println(result)
            return json_response(400, result)
        end

        println("Design successful.")
        println("Selected section: ", result["Designation"])

        # ----------------------------------------------------
        # GENERATE MESH
        # ----------------------------------------------------
        println("Generating Gmsh mesh...")

        mesh_result = create_column_mesh(
            result;
            output_file = MESH_FILE,
            stl_file = STL_FILE
        )

        # ----------------------------------------------------
        # Check mesh generation
        # ----------------------------------------------------
        if haskey(mesh_result, "error")
            println("Mesh generation failed:")
            println(mesh_result["error"])

            return json_response(
                500,
                Dict(
                    "error" => "Column design succeeded but mesh generation failed.",
                    "message" => mesh_result["error"],
                    "design" => result
                )
            )
        end

        println("Mesh generated successfully.")
        println("MSH : ", MESH_FILE)
        println("STL : ", STL_FILE)

        # ----------------------------------------------------
        # Add mesh information to design result
        # ----------------------------------------------------
        result["mesh_file"] = mesh_result["mesh_file"]
        result["stl_file"]  = mesh_result["stl_file"]
        result["mesh_url"]  = mesh_result["mesh_url"]
        result["stl_url"]   = mesh_result["stl_url"]

        # ----------------------------------------------------
        # Return final result
        # ----------------------------------------------------
        return json_response(200, result)

    catch e
        @error "Column design failed" exception=(e, catch_backtrace())

        return json_response(
            500,
            Dict(
                "error" => "Column design failed.",
                "message" => sprint(showerror, e)
            )
        )
    end
end


# ============================================================
# 3D FEM ANALYSIS (ON-DEMAND)
# ============================================================

@post "/fem/column" function(req::HTTP.Request)
    try
        body = JSON3.read(String(req.body))
        Fac_Axial_Load = Float64(body.Fac_Axial_Load)
        Boundary_Condition = Int(body.Boundary_Condition)

        if !isfile(MESH_FILE)
            return json_response(
                400,
                Dict(
                    "error" => "Column.msh not found. Run Column Design first to generate the 3D mesh."
                )
            )
        end

        println("==============================================")
        println("3D FEM ANALYSIS REQUEST")
        println("Mesh File           : ", MESH_FILE)
        println("Factored Axial Load : ", Fac_Axial_Load, " kN")
        println("Boundary Condition  : ", Boundary_Condition)
        println("==============================================")

        fem_result = FEMColumn.run_column_fem(
            MESH_FILE,
            Fac_Axial_Load,
            Boundary_Condition
        )

        println("FEM completed. Max Von Mises: ", fem_result["max_von_mises_MPa"], " MPa")

        return json_response(200, fem_result)

    catch e
        @error "FEM analysis failed" exception=(e, catch_backtrace())

        return json_response(
            500,
            Dict(
                "error" => "3D FEM analysis failed.",
                "message" => sprint(showerror, e)
            )
        )
    end
end


# ============================================================
# 3D FEM ANALYSIS FOR BEAM (ON-DEMAND)
# ============================================================

@post "/fem/beam" function(req::HTTP.Request)
    try
        body = JSON3.read(String(req.body))
        wu_kNm = Float64(body.wu)
        Wu_kN  = haskey(body, :Wu) ? Float64(body.Wu) : 0.0
        b1_mm  = haskey(body, :b1) ? Float64(body.b1) : 100.0

        if !isfile(BEAM_MESH_FILE)
            return json_response(
                400,
                Dict(
                    "error" => "Beam.msh not found. Run Beam Design first to generate the 3D mesh."
                )
            )
        end

        println("==============================================")
        println("3D BEAM FEM ANALYSIS REQUEST")
        println("Mesh File           : ", BEAM_MESH_FILE)
        println("Factored UDL (wu)   : ", wu_kNm, " kN/m")
        println("Factored Point Load : ", Wu_kN, " kN")
        println("Stiff Bearing (b1)  : ", b1_mm, " mm")
        println("==============================================")

        fem_result = FEMBeam.run_beam_fem(
            BEAM_MESH_FILE,
            wu_kNm,
            Wu_kN,
            b1_mm
        )

        println("FEM completed. Max Von Mises: ", fem_result["max_von_mises_MPa"], " MPa")

        return json_response(200, fem_result)

    catch e
        @error "Beam FEM analysis failed" exception=(e, catch_backtrace())

        return json_response(
            500,
            Dict(
                "error" => "3D FEM analysis failed.",
                "message" => sprint(showerror, e)
            )
        )
    end
end


# ============================================================
# GET STL
# ============================================================

@get "/design/column/stl" function(req::HTTP.Request)
    try
        if !isfile(STL_FILE)
            return json_response(
                404,
                Dict(
                    "error" => "Column.stl does not exist.",
                    "path" => STL_FILE
                )
            )
        end

        println("Serving STL: ", STL_FILE)

        return HTTP.Response(
            200,
            [
                "Content-Type" => "model/stl",
                "Access-Control-Allow-Origin" => "*"
            ],
            read(STL_FILE)
        )

    catch e
        @error "Unable to read STL" exception=(e, catch_backtrace())

        return json_response(
            500,
            Dict(
                "error" => "Unable to read Column.stl.",
                "message" => sprint(showerror, e)
            )
        )
    end
end


# ============================================================
# GET MSH
# ============================================================

@get "/design/column/mesh" function(req::HTTP.Request)
    try
        if !isfile(MESH_FILE)
            return json_response(
                404,
                Dict(
                    "error" => "Column.msh does not exist.",
                    "path" => MESH_FILE
                )
            )
        end

        println("Serving MSH: ", MESH_FILE)

        return HTTP.Response(
            200,
            [
                "Content-Type" => "application/octet-stream",
                "Access-Control-Allow-Origin" => "*",
                "Content-Disposition" => "inline; filename=\"Column.msh\""
            ],
            read(MESH_FILE)
        )

    catch e
        @error "Unable to read MSH" exception=(e, catch_backtrace())

        return json_response(
            500,
            Dict(
                "error" => "Unable to read Column.msh.",
                "message" => sprint(showerror, e)
            )
        )
    end

end


# ============================================================
# BEAM DESIGN
# ============================================================

@post "/design/beam" function(req::HTTP.Request)

    try

        body = JSON3.read(
            String(req.body)
        )


        Span  = Float64(body.Span)
        wu    = Float64(body.wu)
        Wu    = Float64(body.Wu)
        b1    = haskey(body, :b1) ? Float64(body.b1) : 100.0


        println("==============================================")
        println("BEAM DESIGN REQUEST")
        println("Span                : ", Span, " m")
        println("Factored UDL (wu)   : ", wu, " kN/m")
        println("Factored Point Load : ", Wu, " kN")
        println("Stiff Bearing (b1)  : ", b1, " mm")
        println("==============================================")


        result = Design_Beam(Span, wu, Wu, b1)


        if haskey(result, "error")

            println("Beam design failed:")
            println(result)

            return json_response(
                400,
                result
            )

        end


        println("Beam design successful.")
        println(
            "Selected section: ",
            result["Designation"]
        )


        # ----------------------------------------------------
        # GENERATE BEAM MESH
        # ----------------------------------------------------

        println("Generating Gmsh mesh for beam...")

        mesh_result = create_beam_mesh(
            result;
            output_file = BEAM_MESH_FILE,
            stl_file = BEAM_STL_FILE
        )

        if haskey(mesh_result, "error")
            println("Beam mesh generation failed:")
            println(mesh_result["error"])

            return json_response(
                500,
                Dict(
                    "error" => "Beam design succeeded but mesh generation failed.",
                    "message" => mesh_result["error"],
                    "design" => result
                )
            )
        end

        println("Beam mesh generated successfully.")
        println("MSH : ", BEAM_MESH_FILE)
        println("STL : ", BEAM_STL_FILE)

        result["mesh_file"] = mesh_result["mesh_file"]
        result["stl_file"]  = mesh_result["stl_file"]
        result["mesh_url"]  = mesh_result["mesh_url"]
        result["stl_url"]   = mesh_result["stl_url"]

        return json_response(
            200,
            result
        )


    catch e

        @error "Beam design failed" exception=(e, catch_backtrace())

        return json_response(
            500,
            Dict(
                "error"   => "Beam design failed.",
                "message" => sprint(showerror, e)
            )
        )

    end

end


# ============================================================
# GET BEAM STL
# ============================================================

@get "/design/beam/stl" function(req::HTTP.Request)

    try

        if !isfile(BEAM_STL_FILE)

            return json_response(
                404,
                Dict(
                    "error" => "Beam.stl does not exist.",
                    "path" => BEAM_STL_FILE
                )
            )

        end

        println("Serving Beam STL: ", BEAM_STL_FILE)

        return HTTP.Response(
            200,
            [
                "Content-Type" => "model/stl",
                "Access-Control-Allow-Origin" => "*"
            ],
            read(BEAM_STL_FILE)
        )

    catch e

        @error "Unable to read Beam STL" exception=(e, catch_backtrace())

        return json_response(
            500,
            Dict(
                "error" => "Unable to read Beam.stl.",
                "message" => sprint(showerror, e)
            )
        )

    end

end


# ============================================================
# GET BEAM MSH
# ============================================================

@get "/design/beam/mesh" function(req::HTTP.Request)

    try

        if !isfile(BEAM_MESH_FILE)

            return json_response(
                404,
                Dict(
                    "error" => "Beam.msh does not exist.",
                    "path" => BEAM_MESH_FILE
                )
            )

        end

        println("Serving Beam MSH: ", BEAM_MESH_FILE)

        return HTTP.Response(
            200,
            [
                "Content-Type" => "application/octet-stream",
                "Access-Control-Allow-Origin" => "*",
                "Content-Disposition" => "inline; filename=\"Beam.msh\""
            ],
            read(BEAM_MESH_FILE)
        )

    catch e

        @error "Unable to read Beam MSH" exception=(e, catch_backtrace())

        return json_response(
            500,
            Dict(
                "error" => "Unable to read Beam.msh.",
                "message" => sprint(showerror, e)
            )
        )

    end

end


# ============================================================
# BEAM LLM REPORT
# ============================================================

@post "/report/beam" function(req::HTTP.Request)

    try

        body = JSON3.read(
            String(req.body)
        )

        Span = Float64(body.Span)
        wu   = Float64(body.wu)
        Wu   = Float64(body.Wu)
        b1   = haskey(body, :b1) ? Float64(body.b1) : 100.0

        return json_response(
            200,
            Generate_Beam_Report(Span, wu, Wu, b1)
        )


    catch e

        @error "Beam report generation failed" exception=(e, catch_backtrace())

        return json_response(
            500,
            Dict(
                "error"   => "Unable to generate beam report.",
                "message" => sprint(showerror, e)
            )
        )

    end

end


# ============================================================
# LLM REPORT
# ============================================================

@post "/report/column" function(req::HTTP.Request)
    try
        body = JSON3.read(String(req.body))

        return Generate_Column_Report(
            Float64(body.Length),
            Float64(body.Fac_Axial_Load),
            Int(body.Boundary_Condition),
            String(body.Sections)
        )

    catch e
        @error "Report generation failed" exception=(e, catch_backtrace())

        return json_response(
            500,
            Dict(
                "error" => "Unable to generate column report.",
                "message" => sprint(showerror, e)
            )
        )
    end
end


# ============================================================
# START SERVER
# ============================================================

println()
println("==============================================")
println("       PROJECT CIPHER - DESIGN ENGINE")
println("==============================================")
println()
println("Server : http://127.0.0.1:8080")
println()
println("Routes:")
println("  GET  /health")
println("  POST /design/column")
println("  POST /fem/column")
println("  GET  /design/column/stl")
println("  GET  /design/column/mesh")
println("  POST /report/column")
println("  POST /design/beam")
println("  GET  /design/beam/stl")
println("  GET  /design/beam/mesh")
println("  POST /report/beam")
println("  POST /design/lacing")
println("  POST /fem/lacing")
println("  GET  /design/lacing/stl")
println("  POST /report/lacing")
println()
println("==============================================")
println()

# ============================================================
# LACING COLUMN DESIGN
# ============================================================

@post "/design/lacing" function(req::HTTP.Request)
    try
        body = JSON3.read(String(req.body))

        Length = Float64(body.Length)
        Fac_Axial_Load = Float64(body.Fac_Axial_Load)
        Boundary_Condition = Int(body.Boundary_Condition)

        println("==============================================")
        println("LACING COLUMN DESIGN REQUEST")
        println("Length              : ", Length, " m")
        println("Factored Axial Load : ", Fac_Axial_Load, " kN")
        println("Boundary Condition  : ", Boundary_Condition)
        println("==============================================")

        result = Design_Lacing_Column(
            Length,
            Fac_Axial_Load,
            Boundary_Condition
        )

        if haskey(result, "error")
            println("Lacing column design failed:")
            println(result)
            return json_response(400, result)
        end

        println("Lacing column design successful.")
        println("Selected section: ", get(result, "Chord_Section", "Unknown"))

        # ----------------------------------------------------
        # GENERATE MESH
        # ----------------------------------------------------
        println("Generating Gmsh mesh for lacing column...")

        mesh_result = create_lacing_column_mesh(
            result;
            output_file = LACING_MESH_FILE,
            stl_file = LACING_STL_FILE
        )

        if haskey(mesh_result, "error")
            println("Lacing column mesh generation failed:")
            println(mesh_result["error"])

            return json_response(
                500,
                Dict(
                    "error" => "Lacing column design succeeded but mesh generation failed.",
                    "message" => mesh_result["error"],
                    "design" => result
                )
            )
        end

        println("Lacing column mesh generated successfully.")
        println("MSH : ", LACING_MESH_FILE)
        println("STL : ", LACING_STL_FILE)

        result["mesh_file"] = mesh_result["mesh_file"]
        result["stl_file"]  = mesh_result["stl_file"]
        result["mesh_url"]  = mesh_result["mesh_url"]
        result["stl_url"]   = mesh_result["stl_url"]

        return json_response(200, result)

    catch e
        @error "Lacing column design failed" exception=(e, catch_backtrace())

        return json_response(
            500,
            Dict(
                "error" => "Lacing column design failed.",
                "message" => sprint(showerror, e)
            )
        )
    end
end


# ============================================================
# 3D FEM ANALYSIS FOR LACING COLUMN (ON-DEMAND)
# ============================================================

@post "/fem/lacing" function(req::HTTP.Request)
    try
        body = JSON3.read(String(req.body))
        Fac_Axial_Load = Float64(body.Fac_Axial_Load)
        Boundary_Condition = Int(body.Boundary_Condition)

        if !isfile(LACING_MESH_FILE)
            return json_response(
                400,
                Dict(
                    "error" => "LacingColumn.msh not found. Run Lacing Column Design first to generate the 3D mesh."
                )
            )
        end

        println("==============================================")
        println("3D LACING COLUMN FEM ANALYSIS REQUEST")
        println("Mesh File           : ", LACING_MESH_FILE)
        println("Factored Axial Load : ", Fac_Axial_Load, " kN")
        println("Boundary Condition  : ", Boundary_Condition)
        println("==============================================")

        fem_result = FEM_Lacing.run_lacing_column_fem(
            LACING_MESH_FILE,
            Fac_Axial_Load,
            Boundary_Condition
        )

        println("FEM completed. Max Von Mises: ", get(fem_result, "max_von_mises_MPa", "N/A"), " MPa")

        return json_response(200, fem_result)

    catch e
        @error "Lacing column FEM analysis failed" exception=(e, catch_backtrace())

        return json_response(
            500,
            Dict(
                "error" => "3D FEM analysis failed.",
                "message" => sprint(showerror, e)
            )
        )
    end
end


# ============================================================
# GET LACING COLUMN STL
# ============================================================

@get "/design/lacing/stl" function(req::HTTP.Request)
    try
        if !isfile(LACING_STL_FILE)
            return json_response(
                404,
                Dict(
                    "error" => "LacingColumn.stl does not exist.",
                    "path" => LACING_STL_FILE
                )
            )
        end

        println("Serving Lacing Column STL: ", LACING_STL_FILE)

        return HTTP.Response(
            200,
            [
                "Content-Type" => "model/stl",
                "Access-Control-Allow-Origin" => "*"
            ],
            read(LACING_STL_FILE)
        )

    catch e
        @error "Unable to read Lacing Column STL" exception=(e, catch_backtrace())

        return json_response(
            500,
            Dict(
                "error" => "Unable to read LacingColumn.stl.",
                "message" => sprint(showerror, e)
            )
        )
    end
end


# ============================================================
# LLM REPORT FOR LACING COLUMN
# ============================================================

@post "/report/lacing" function(req::HTTP.Request)
    try
        body = JSON3.read(String(req.body))

        Length = Float64(body.Length)
        Fac_Axial_Load = Float64(body.Fac_Axial_Load)
        Boundary_Condition = Int(body.Boundary_Condition)

        result = Design_Lacing_Column(
            Length,
            Fac_Axial_Load,
            Boundary_Condition
        )

        if haskey(result, "error")
            return json_response(
                400,
                Dict(
                    "error" => "Design failed.",
                    "message" => get(result, "message", result["error"])
                )
            )
        end

        report = """
# Lacing Column Design Report (IS 800:2007)

## 1. Design Parameters
- Column Length: $(Length) m
- Factored Axial Load: $(Fac_Axial_Load) kN
- Boundary Condition: $Boundary_Condition

## 2. Chord Selection
- Section: $(get(result, "Chord_Section", "N/A"))
- Area: $(get(result, "Chord_Area_mm2", "N/A")) mm²
- Weight: $(get(result, "Chord_Weight_kgm", "N/A")) kg/m

## 3. Built-Up Section Properties
- Channel Spacing: $(get(result, "Channel_Spacing_mm", "N/A")) mm
- Total Area: $(get(result, "Total_Area_mm2", "N/A")) mm²
- Ixx: $(get(result, "Ixx_mm4", "N/A")) mm⁴
- Iyy: $(get(result, "Iyy_mm4", "N/A")) mm⁴
- rx: $(get(result, "rx_mm", "N/A")) mm
- ry: $(get(result, "ry_mm", "N/A")) mm

## 4. Buckling Analysis
- Max Slenderness (λ): $(get(result, "lambda_max", "N/A"))
- Design Compressive Stress (fcd): $(get(result, "fcd_MPa", "N/A")) MPa
- Design Capacity: $(get(result, "Design_Capacity_kN", "N/A")) kN
- Utilization Ratio: $(get(result, "Capacity_Utilization", "N/A"))

## 5. Lacing Design
- Lacing Type: Flat bar
- Number of Channels: 2
- Number of Panels: $(get(result, "Num_Lacing_Panels", "N/A"))
- Lacing Bar Width: $(get(result, "Lacing_Bar_Width_mm", "N/A")) mm
- Lacing Bar Thickness: $(get(result, "Lacing_Bar_Thickness_mm", "N/A")) mm
- Diagonal Length: $(get(result, "Diagonal_Length_mm", "N/A")) mm
- Lacing Angle: $(get(result, "Lacing_Angle_deg", "N/A"))°
- Lacing Slenderness: $(get(result, "Lacing_Slenderness", "N/A"))

## 6. Check Results
$(get(result, "Status", "N/A"))

---
*Report generated automatically per IS 800:2007 specifications.*
"""

        return json_response(200, Dict("report" => report))

    catch e
        @error "Lacing column report generation failed" exception=(e, catch_backtrace())

        return json_response(
            500,
            Dict(
                "error" => "Unable to generate lacing column report.",
                "message" => sprint(showerror, e)
            )
        )
    end
end


# ============================================================
# START SERVER
# ============================================================

println()
println("==============================================")
println("       PROJECT CIPHER - DESIGN ENGINE")
println("==============================================")
println()
println("Server : http://127.0.0.1:8080")
println()
println("Routes:")
println("  GET  /health")
println("  POST /design/column")
println("  POST /fem/column")
println("  GET  /design/column/stl")
println("  GET  /design/column/mesh")
println("  POST /report/column")
println("  POST /design/beam")
println("  GET  /design/beam/stl")
println("  GET  /design/beam/mesh")
println("  POST /report/beam")
println("  POST /design/lacing")
println("  POST /fem/lacing")
println("  GET  /design/lacing/stl")
println("  POST /report/lacing")
println()
println("==============================================")
println()

serve(
    host = "127.0.0.1",
    port = 8080,
    middleware = [cors_handler]
)