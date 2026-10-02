using Oxygen
using HTTP
using JSON3
using CSV
using DataFrames

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


@get "/health" function (req::HTTP.Request)

    return Dict(
        "Status" => "Good"
    )

end

@post "/design/column" function (req::HTTP.Request)

    body = JSON3.read(String(req.body))

    Length = Float64(body.Length)

    Fac_Axial_Load =
        Float64(body.Fac_Axial_Load)

    Boundary_Condition =
        Int(body.Boundary_Condition)

    Sections =
        String(body.Sections)


    result = Design_Column(
        Length,
        Fac_Axial_Load,
        Boundary_Condition,
        Sections
    )

    return result

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
    middleware=[
        cors_handler
    ]
)