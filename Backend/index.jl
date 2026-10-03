using Oxygen
using HTTP
using JSON3
using CSV
using DataFrames
using Gmsh
include(joinpath(@__DIR__,"Column","Logic_Column.jl"))

include(joinpath(@__DIR__,"Column","Mesh.jl"))
const BACKEND_DIR = @__DIR__
const COLUMN_DIR = joinpath(BACKEND_DIR,"Column")
const MESH_FILE = joinpath(COLUMN_DIR,"Column.msh")
const STL_FILE = joinpath(COLUMN_DIR,"Column.stl")
const CORS = Cors(
    allowed_origins = ["*"],
    allowed_headers = ["*"],
    allowed_methods = [
        "GET",
        "POST",
        "OPTIONS"
    ]
)

function json_response(
    status::Int,
    data
)

    return HTTP.Response(
        status,
        [
            "Content-Type" =>
                "application/json"
        ],
        JSON3.write(data)
    )

include("./Column/Logic_Column.jl")
include("./Column/Logic_Column.jl")
include("./Report/Report_LLM.jl")

const CORS_HEADERS = [
    "Access-Control-Allow-Origin" => "*",
    "Access-Control-Allow-Methods" => "GET, POST, OPTIONS",
    "Access-Control-Allow-Headers" => "Content-Type"
]

function cors_handler(handler)

    return function(req::HTTP.Request)

        try

            # Browser preflight request
            if req.method == "OPTIONS"
                return HTTP.Response(200, CORS_HEADERS)
            end

            # Execute the actual Oxygen route
            response = handler(req)

            # Add CORS headers to the response
            for h in CORS_HEADERS
                HTTP.setheader(response, h)
            end

            return response

        catch e

            # Print the real error instead of a bare 500
            @error "Request failed" path=req.target exception=(e, catch_backtrace())

            return HTTP.Response(
                500,
                CORS_HEADERS,
                JSON3.write(Dict("error" => sprint(showerror, e)))
            )

        end

    end

end
@get "/design/column/stl" function(req)
    try
        if !isfile(STL_FILE)

            return json_response(
                404,
                Dict(
                    "error" =>
                        "Column.stl does not exist.",

                    "path" =>
                        STL_FILE
                )
            )


@get "/health" function (req::HTTP.Request)

    return Dict(
        "Status" => "Good"
    )

end

@post "/design/column" function (req::HTTP.Request)

    body = JSON3.read(String(req.body))

    catch e

        return json_response(
            500,
            Dict(
                "error" =>
                    "Unable to read Column.stl.",

                "message" =>
                    sprint(
                        showerror,
                        e
                    )
            )
        )

    end

end
@get "/health" function(req)

    return json_response(
        200,
        Dict(
            "status" => "ok",
            "service" => "Column Design Engine"
        )
    )

end

## LLM-written report for the same inputs as /design/column.
## Runs the existing Design_Column, then explains its output.
@post "/report/column" function (req::HTTP.Request)

    body = JSON3.read(String(req.body))

    return Generate_Column_Report(
        Float64(body.Length),
        Float64(body.Fac_Axial_Load),
        Int(body.Boundary_Condition),
        String(body.Sections)
    )

end

serve(
    host = "127.0.0.1",
    port = 8080,
    middleware = [CORS]
)