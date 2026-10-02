## LLM reporting layer for column design.
##
## Design_Column (Logic_Column.jl) is NOT modified. This file only takes its
## output and asks an OpenAI-compatible chat-completions API to DESCRIBE it.
## All numbers and all PASS/FAIL verdicts are produced here in plain Julia;
## the LLM only turns them into prose.
##
## Environment variables
##   LLM_API_KEY   required   (falls back to OPENAI_API_KEY)
##   LLM_BASE_URL  optional   default: https://api.openai.com/v1
##   LLM_MODEL     optional   default: gpt-4o-mini
##
## The HTTPS request is sent through the system `curl` (present on Windows 10/11,
## macOS and Linux) because Julia's own TLS client fails on some networks.

using JSON3


const REPORT_SYSTEM_PROMPT = """
You are a technical writer for a structural steel column design tool.
You receive one JSON object with: inputs, results (computed by a verified
calculation engine), checks (PASS/FAIL already decided) and derived values
(already computed). Write a short professional engineering report from it.

STRICT RULES
- Use ONLY values present in the JSON. Copy numbers exactly as given and
  always state their units.
- Never recalculate, convert, round differently, estimate or add any number.
- Never change, soften or second-guess a PASS/FAIL result.
- Do not cite standard clause numbers or add formulas that are not in the data.
- Describe the end conditions only through effective_length_factor_K. Do not
  name a support type.
- If a value is not in the JSON, do not mention it.
- This is a structural STEEL column. f_cd_MPa is the design compressive stress
  of the steel and Assumed_fcd_MPa is the stress assumed for initial sizing.
  Never mention concrete.
- Give utilization_ratio exactly as provided (for example 0.8165). Do not turn
  it into a percentage.
- Give the slenderness value as provided. Do not classify it (high, low,
  stocky, slender) or compare it with any limit.
- Do not add judgements that are not in the data (for example "efficient",
  "conservative", "economical").

FORMAT
- Plain text only. No markdown tables, no bold, no code blocks.
- Use exactly these five headings, each on its own line, in this order:
## Design / Input Summary
## Calculated Results
## Design Checks
## Important Observations
## Final Conclusion
- Under each heading use short lines starting with "- ".
- Calculated Results: list only the section designation, required area,
  section area, composite area, plate size (if plates were added), r_min_mm,
  Slenderness, f_cd_MPa and Design_Capacity_kN.
- Design Checks: one line per check, formatted "- <check>: PASS" or "- <check>: FAIL",
  with the supporting values.
- Important Observations: 3 to 5 points that follow directly from the data
  (utilization_ratio, governing_axis, whether plates were added, the slenderness
  value, the buckling class, and that initial sizing used Assumed_fcd_MPa while
  the final capacity uses f_cd_MPa).
- Final Conclusion: 2 to 3 sentences. State the selected section and whether
  the design is adequate, based only on the checks.
- Keep the whole report under 350 words.
"""


## Round floats so the LLM copies short numbers; leave everything else as is.
report_round(x::AbstractFloat) = isfinite(x) ? round(x; digits=4) : x
report_round(x::AbstractString) = String(x)
report_round(x::AbstractVector) = [report_round(v) for v in x]
report_round(x::AbstractDict) =
    Dict{String,Any}(String(k) => report_round(v) for (k, v) in x)
report_round(x) = x


## Build the exact data the LLM is allowed to talk about.
function column_report_data(results)

    P      = results["Axial_Load_kN"]
    Pd     = results["Design_Capacity_kN"]
    L      = results["Length_m"]
    Leff   = results["Effective_Length_m"]
    A_req  = results["Required_Area_mm2"]
    A_prov = results["Composite_Area_mm2"]
    r_zz   = results["r_zz_mm"]
    r_yy   = results["r_yy_mm"]
    status = string(get(results, "Status", "UNKNOWN"))

    inputs = Dict(
        "Length_m"               => L,
        "Factored_Axial_Load_kN" => P,
        "Section_Type"           => results["Section_Type"]
    )

    ## Verdicts are decided here, not by the LLM.
    ## 1e-6 mm2 tolerance: composite area is built from A_req, so the two can
    ## differ by floating-point noise only.
    checks = [
        Dict(
            "check"       => "Design capacity >= factored axial load",
            "demand_kN"   => P,
            "capacity_kN" => Pd,
            "result"      => Pd >= P ? "PASS" : "FAIL"
        ),
        Dict(
            "check"        => "Provided area >= required area",
            "required_mm2" => A_req,
            "provided_mm2" => A_prov,
            "result"       => A_prov >= A_req - 1e-6 ? "PASS" : "FAIL"
        ),
        Dict(
            "check"  => "Design engine status",
            "value"  => status,
            "result" => status == "SAFE" ? "PASS" : "FAIL"
        )
    ]

    derived = Dict(
        "utilization_ratio"         => P / Pd,
        "effective_length_factor_K" => Leff / L,
        "governing_axis"            => r_yy <= r_zz ? "minor axis (yy)" : "major axis (zz)",
        "plates_added"              => results["Plate_Thickness_mm"] > 0
    )

    ## The numeric boundary-condition code is left out on purpose: the LLM
    ## gets the effective length factor K instead and must not guess a label.
    res = report_round(results)
    delete!(res, "Boundary_Condition")

    return Dict(
        "inputs"  => report_round(inputs),
        "results" => res,
        "checks"  => report_round(checks),
        "derived" => report_round(derived)
    )
end


## POST JSON through curl. Returns (http_status, body).
## status 0 means curl itself failed; body then holds curl's error text.
## The API key goes through a temp config file, not the command line.
function llm_post(url, api_key, payload)

    dir = mktempdir()

    try

        body_f = joinpath(dir, "body.json")
        cfg_f  = joinpath(dir, "curl.cfg")
        out_f  = joinpath(dir, "out.json")
        err_f  = joinpath(dir, "err.txt")
        code_f = joinpath(dir, "code.txt")

        write(body_f, payload)
        write(cfg_f, "header = \"Authorization: Bearer $(api_key)\"\n")

        cmd = Cmd([
            "curl", "-sS", "--max-time", "90",
            "-X", "POST", url,
            "-H", "Content-Type: application/json",
            "-K", cfg_f,
            "--data-binary", "@" * body_f,
            "-o", out_f,
            "-w", "%{http_code}"
        ])

        ok = success(pipeline(cmd; stdout=code_f, stderr=err_f))

        if !ok
            return (0, strip(read(err_f, String)))
        end

        return (parse(Int, strip(read(code_f, String))), read(out_f, String))

    finally

        rm(dir; recursive=true, force=true)

    end
end


## Same 4 inputs as /design/column. Runs the existing Design_Column, then
## asks the LLM to write the report. Returns Dict("report"=>...) or
## Dict("error"=>...).
function Generate_Column_Report(
    Length,
    Fac_Axial_Load,
    Boundary_Condition,
    Sections
)

    try

        api_key = get(ENV, "LLM_API_KEY", get(ENV, "OPENAI_API_KEY", ""))

        if isempty(api_key)
            return Dict(
                "error"=>"LLM_API_KEY is not set on the backend."
            )
        end


        ## Existing calculation, unchanged.
        results = Design_Column(
            Length,
            Fac_Axial_Load,
            Boundary_Condition,
            Sections
        )

        if haskey(results, "error")
            return results
        end


        data = column_report_data(results)

        base  = rstrip(get(ENV, "LLM_BASE_URL", "https://api.openai.com/v1"), '/')
        model = get(ENV, "LLM_MODEL", "gpt-4o-mini")

        payload = JSON3.write(Dict(
            "model"       => model,
            "temperature" => 0.2,
            "messages"    => [
                Dict("role"=>"system", "content"=>REPORT_SYSTEM_PROMPT),
                Dict("role"=>"user",   "content"=>"Design data (JSON):\n" * JSON3.write(data))
            ]
        ))

        status, body = llm_post(
            base * "/chat/completions",
            api_key,
            payload
        )

        if status == 0
            return Dict(
                "error"=>"Could not reach the LLM API.",
                "message"=>first(body, 300)
            )
        end

        if status != 200
            return Dict(
                "error"=>"LLM request failed (HTTP $(status)).",
                "message"=>first(body, 300)
            )
        end

        text = JSON3.read(body).choices[1].message.content

        return Dict(
            "report"=>String(text),
            "model"=>model
        )

    catch e

        return Dict(
            "error"=>"Report generation failed.",
            "message"=>sprint(showerror, e)
        )

    end
end