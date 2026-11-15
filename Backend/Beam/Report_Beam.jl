## Report_Beam.jl — LLM reporting layer for beam design.
##
## Design_Beam (Logic_Beam.jl) is NOT modified here.  This file only takes
## its output and asks an OpenAI-compatible chat-completions API to describe
## it in prose.  All numbers and all PASS/FAIL verdicts are produced here in
## plain Julia; the LLM only turns them into professional text.
##
## Environment variables (same as the column report):
##   LLM_API_KEY   required   (falls back to OPENAI_API_KEY)
##   LLM_BASE_URL  optional   default: https://api.openai.com/v1
##   LLM_MODEL     optional   default: gpt-4o-mini
##
## llm_post() is defined in Report_LLM.jl and is already available because
## index.jl includes Report_LLM.jl before this file.

using JSON3


## ============================================================
## BEAM REPORT SYSTEM PROMPT
## ============================================================

const BEAM_REPORT_SYSTEM_PROMPT = """
You are a technical writer for a structural steel beam design tool.
You receive one JSON object with: inputs, results (computed by a verified
calculation engine), checks (PASS/FAIL already decided) and derived values
(already computed). Write a short professional engineering report from it.

STRICT RULES
- Use ONLY values present in the JSON. Copy numbers exactly as given and
  always state their units.
- Never recalculate, convert, round differently, estimate or add any number.
- Never change, soften or second-guess a PASS/FAIL result.
- Do not cite standard clause numbers or add formulas that are not in the data.
- If a value is not in the JSON, do not mention it.
- This is a structural STEEL beam designed for flexure per IS 800.
- Never mention concrete.
- Do not add judgements that are not in the data (for example \"efficient\",
  \"conservative\", \"economical\").

FORMAT
- Plain text only. No markdown tables, no bold, no code blocks.
- Use exactly these five headings, each on its own line, in this order:
## Design / Input Summary
## Calculated Results
## Design Checks
## Important Observations
## Final Conclusion
- Under each heading use short lines starting with \"- \".
- Calculated Results: list section designation, mass, section class,
  Zp_reqd_mm3, Zp_mm3, Md_kNm, Vd_kN, delta_total_mm, delta_limit_mm, Fw_kN.
- Design Checks: one line per check, formatted \"- <check>: PASS\" or \"- <check>: FAIL\",
  with the supporting values on the same line.
- Important Observations: 3 to 5 points that follow directly from the data
  (section class, whether high_shear governs, utilization in bending,
  governing deflection vs limit, web crippling margin).
- Final Conclusion: 2 to 3 sentences. State the selected section and whether
  the overall design status is SAFE or UNSAFE, based only on the checks.
- Keep the whole report under 400 words.
"""


## ============================================================
## ROUND HELPER (re-used from column report pattern)
## ============================================================

beam_round(x::AbstractFloat)  = isfinite(x) ? round(x; digits=4) : x
beam_round(x::AbstractString) = String(x)
beam_round(x::Bool)           = x
beam_round(x::AbstractVector) = [beam_round(v) for v in x]
beam_round(x::AbstractDict)   =
    Dict{String,Any}(String(k) => beam_round(v) for (k, v) in x)
beam_round(x) = x


## ============================================================
## BUILD STRUCTURED REPORT DATA
## ============================================================

function beam_report_data(results)

    M_u    = results["M_u_kNm"]
    M_d    = results["Md_kNm"]
    V_u_s  = results["V_u_s_kN"]
    V_d    = results["Vd_kN"]
    dtot   = results["delta_total_mm"]
    dlim   = results["delta_limit_mm"]
    F_w    = results["Fw_kN"]
    status = string(get(results, "Status", "UNKNOWN"))

    inputs = Dict(
        "Span_m"  => results["Span_m"],
        "wu_kN_m" => results["wu_kN_m"],
        "Wu_kN"   => results["Wu_kN"],
        "b1_mm"   => results["b1_mm"]
    )

    ## All verdicts computed here, not by the LLM.
    checks = [
        Dict(
            "check"        => "Shear capacity >= factored shear at support",
            "demand_kN"    => V_u_s,
            "capacity_kN"  => V_d,
            "result"       => results["shear_check"] ? "PASS" : "FAIL"
        ),
        Dict(
            "check"        => "Moment capacity >= factored design moment",
            "demand_kNm"   => M_u,
            "capacity_kNm" => M_d,
            "result"       => results["moment_check"] ? "PASS" : "FAIL"
        ),
        Dict(
            "check"       => "Deflection <= L/300",
            "delta_mm"    => dtot,
            "limit_mm"    => dlim,
            "result"      => results["deflection_check"] ? "PASS" : "FAIL"
        ),
        Dict(
            "check"       => "Web crippling resistance >= factored shear at support",
            "demand_kN"   => V_u_s,
            "capacity_kN" => F_w,
            "result"      => results["web_crippling_check"] ? "PASS" : "FAIL"
        ),
        Dict(
            "check"  => "Overall design status",
            "value"  => status,
            "result" => status == "SAFE" ? "PASS" : "FAIL"
        )
    ]

    derived = Dict(
        "bending_utilization_ratio" => M_u / M_d,
        "shear_utilization_ratio"   => V_u_s / V_d,
        "high_shear_governs"        => results["high_shear"],
        "section_class"             => results["Section_Class"],
        "deflection_utilization"    => dtot / dlim
    )

    res = beam_round(results)

    return Dict(
        "inputs"  => beam_round(inputs),
        "results" => res,
        "checks"  => beam_round(checks),
        "derived" => beam_round(derived)
    )
end


## ============================================================
## GENERATE BEAM REPORT
## ============================================================

function Generate_Beam_Report(
    span_m,
    wu_kN_m,
    Wu_kN,
    b1_mm = 100.0
)

    try

        api_key = get(ENV, "LLM_API_KEY", get(ENV, "OPENAI_API_KEY", ""))

        if isempty(api_key)
            return Dict(
                "error" => "LLM_API_KEY is not set on the backend."
            )
        end


        ## Run beam design engine
        results = Design_Beam(span_m, wu_kN_m, Wu_kN, b1_mm)

        if haskey(results, "error")
            return results
        end


        ## Build structured LLM-safe data package
        data = beam_report_data(results)

        base  = rstrip(get(ENV, "LLM_BASE_URL", "https://api.openai.com/v1"), '/')
        model = get(ENV, "LLM_MODEL", "gpt-4o-mini")

        payload = JSON3.write(Dict(
            "model"       => model,
            "temperature" => 0.2,
            "messages"    => [
                Dict("role" => "system", "content" => BEAM_REPORT_SYSTEM_PROMPT),
                Dict("role" => "user",   "content" => "Design data (JSON):\n" * JSON3.write(data))
            ]
        ))

        ## llm_post is defined in Report_LLM.jl (included first by index.jl)
        status, body = llm_post(
            base * "/chat/completions",
            api_key,
            payload
        )

        if status == 0
            return Dict(
                "error"   => "Could not reach the LLM API.",
                "message" => first(body, 300)
            )
        end

        if status != 200
            return Dict(
                "error"   => "LLM request failed (HTTP $(status)).",
                "message" => first(body, 300)
            )
        end

        text = JSON3.read(body).choices[1].message.content

        return Dict(
            "report" => String(text),
            "model"  => model
        )

    catch e

        return Dict(
            "error"   => "Beam report generation failed.",
            "message" => sprint(showerror, e)
        )

    end

end
