# Cipher

### in the root directory fire up the virtual env
for linux
```bash
source venv/bin/activate
```
To run the backend
run inside the Backend folder
```bash
    julia index.jl
```
then install the Julia and Oxygen.jl 
```bash
    ##fire julia in cmd only inside the venv
    julia
    using Pkg
    Pkg.add("Oxygen")
```
## The csv files for steel table and all IS table shall be in ./Backend/CSV_Data

## Testing column design
Test example
```bash
 curl -X POST http://127.0.0.1:8080/design/column \
   -H "Content-Type: application/json" \
   -d '{
     "Length": 3.0,
     "Fac_Axial_Load": 500.0,
     "Boundary_Condition": 0,
     "Sections": "I"
   }'
```

## LLM report generation (optional)
After a column design succeeds, the UI shows a **Generate Report** button. It calls `POST /report/column`, which re-runs `Design_Column` unchanged and asks an OpenAI-compatible API to write a short report from the results. The LLM only explains; PASS/FAIL checks and all numbers are computed in `Backend/Report/Report_LLM.jl`.

Set these in the shell that runs `julia index.jl` (the key is never sent to the browser):
```bash
export LLM_API_KEY="your-key"                      # required (OPENAI_API_KEY also works)
export LLM_BASE_URL="https://api.openai.com/v1"    # optional, any OpenAI-compatible endpoint
export LLM_MODEL="gpt-4o-mini"                     # optional
```
Test:
```bash
curl -X POST http://127.0.0.1:8080/report/column \
  -H "Content-Type: application/json" \
  -d '{"Length": 3.0, "Fac_Axial_Load": 500.0, "Boundary_Condition": 0, "Sections": "I"}'
```
