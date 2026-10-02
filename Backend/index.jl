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

end
@post "/design/column" function(req)

    try
        body = JSON3.read(String(req.body) )
        Length = Float64(body["Length"])
        Fac_Axial_Load = Float64(body["Fac_Axial_Load"])
        Boundary_Condition = Int(body["Boundary_Condition"])
        Sections = String(body["Sections"])
        result = Design_Column(Length,Fac_Axial_Load,Boundary_Condition,Sections)
        if haskey(result,"error")
            return json_response(400,result)
        end
        mesh_result = create_column_mesh(result;output_file = MESH_FILE,stl_file = STL_FILE)
        if haskey(mesh_result,"error")
            return json_response(500,mesh_result)
        end
        result["mesh_file"] ="Column.msh"
        result["mesh_url"] ="/design/column/mesh"
        result["stl_file"] ="Column.stl"
        result["stl_url"] ="/design/column/stl"
        return json_response(200,result)
    catch e
        return json_response(
            500,
            Dict(
                "error" =>"Column design failed.",
                "message" =>
                    sprint(showerror,e)
                )
        )
    end
end
@get "/design/column/mesh" function(req)
    try
        if !isfile(MESH_FILE)
            return json_response(
                404,
                Dict(
                    "error" =>
                        "Column.msh does not exist.",

                    "path" =>
                        MESH_FILE
                )
            )

        end
        mesh_bytes = read(MESH_FILE)
        return HTTP.Response(
            200,
            [
                "Content-Type" =>
                    "application/octet-stream",

                "Content-Disposition" =>
                    "inline; filename=\"Column.msh\"",

                "Cache-Control" =>
                    "no-store"
            ],
            mesh_bytes
        )

    catch e

        return json_response(
            500,
            Dict(
                "error" =>
                    "Unable to read Column.msh.",

                "message" =>
                    sprint(
                        showerror,
                        e
                    )
            )
        )

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

        end
        stl_bytes = read(STL_FILE)
        return HTTP.Response(
            200,
            [
                "Content-Type" =>
                    "model/stl",

                "Content-Disposition" =>
                    "inline; filename=\"Column.stl\"",

                "Cache-Control" =>
                    "no-store"
            ],
            stl_bytes
        )

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
serve(
    host = "127.0.0.1",
    port = 8080,
    middleware = [CORS]
)