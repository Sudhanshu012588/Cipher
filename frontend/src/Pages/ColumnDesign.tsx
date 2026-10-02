import { useState } from "react";
import axios from "axios";

import {
  AlertCircle,
  CheckCircle2,
  ChevronRight,
  FileText,
  Loader2,
  RotateCcw,
  Ruler,
  TriangleAlert,
} from "lucide-react";

import Navbar from "../Components/Navbar";


type ColumnForm = {
  Length: number;
  Fac_Axial_Load: number;
  Boundary_Condition: number;
  Sections: string;
};


const Column = () => {

  const [form, setForm] = useState<ColumnForm>({
    Length: 3.0,
    Fac_Axial_Load: 500.0,
    Boundary_Condition: 0,
    Sections: "I",
  });

  const [loading, setLoading] = useState(false);

  const [result, setResult] = useState<any>(null);

  const [error, setError] = useState<string | null>(null);

  const [report, setReport] = useState<string | null>(null);

  const [reportLoading, setReportLoading] = useState(false);

  const [reportError, setReportError] = useState<string | null>(null);


  const clearReport = () => {
    setReport(null);
    setReportError(null);
  };


  const updateField = <K extends keyof ColumnForm>(
    field: K,
    value: ColumnForm[K]
  ) => {

    setForm((prev) => ({
      ...prev,
      [field]: value,
    }));

    // Remove previous result when inputs change
    setResult(null);
    setError(null);
    clearReport();
  };


  const resetForm = () => {

    setForm({
      Length: 3.0,
      Fac_Axial_Load: 500.0,
      Boundary_Condition: 0,
      Sections: "I",
    });

    setResult(null);
    setError(null);
    clearReport();
  };


  const designColumn = async () => {

    setLoading(true);
    setResult(null);
    setError(null);
    clearReport();

    try {

      const response = await axios.post(
        "http://127.0.0.1:8080/design/column",
        form,
        {
          headers: {
            "Content-Type": "application/json",
          },
        }
      );

      setResult(response.data);

    } catch (err: any) {

      /*
       * Axios error handling
       */

      if (axios.isAxiosError(err)) {

        if (err.response) {

          const backendError =
            err.response.data?.detail ||
            err.response.data?.message ||
            err.response.data?.error ||
            "The column design could not be completed.";

          setError(backendError);

        } else if (err.request) {

          setError(
            "Unable to connect to the design engine. " +
            "Please make sure the backend is running on 127.0.0.1:8080."
          );

        } else {

          setError(err.message);
        }

      } else {

        setError(
          "An unexpected error occurred while designing the column."
        );
      }

    } finally {

      setLoading(false);
    }
  };


  const generateReport = async () => {

    setReportLoading(true);
    clearReport();

    try {

      const response = await axios.post(
        "http://127.0.0.1:8080/report/column",
        form,
        {
          headers: {
            "Content-Type": "application/json",
          },
        }
      );

      if (response.data?.error) {
        setReportError(
          response.data.message
            ? `${response.data.error} ${response.data.message}`
            : response.data.error
        );
      } else {
        setReport(response.data.report);
      }

    } catch (err) {

      setReportError(
        axios.isAxiosError(err) && !err.response
          ? "Unable to connect to the design engine. " +
            "Please make sure the backend is running on 127.0.0.1:8080."
          : "The report could not be generated."
      );

    } finally {

      setReportLoading(false);
    }
  };


  return (
    <div className="min-h-screen bg-[#eef1f4] text-slate-800">

      <Navbar />


      {/* ================= HEADER ================= */}

      <div className="bg-[#172331] text-white border-b border-slate-700">

        <div className="max-w-[1400px] mx-auto px-8 py-6">

          <div className="flex items-center gap-2 text-xs text-slate-400">

            <span>Design</span>

            <ChevronRight size={13} />

            <span className="text-white">
              Column
            </span>

          </div>


          <h1 className="mt-4 text-2xl font-semibold">
            Column Design
          </h1>

          <p className="mt-1 text-sm text-slate-400">
            Design and verify structural columns
          </p>

        </div>

      </div>


      {/* ================= MAIN ================= */}

      <main className="max-w-[1400px] mx-auto px-8 py-8">

        <div className="grid lg:grid-cols-[360px_1fr] gap-6">


          {/* ================= INPUT PANEL ================= */}

          <aside className="bg-white border border-slate-200 rounded-lg">

            <div className="px-5 py-4 border-b border-slate-200">

              <h2 className="text-sm font-semibold">
                Design Parameters
              </h2>

              <p className="text-xs text-slate-500 mt-1">
                Enter the parameters required for column design.
              </p>

            </div>


            <div className="p-5 space-y-5">


              {/* Column Length */}

              <InputField
                label="Column Length"
                unit="m"
                value={form.Length}
                onChange={(value) =>
                  updateField("Length", value)
                }
              />


              {/* Axial Load */}

              <InputField
                label="Factored Axial Load"
                unit="kN"
                value={form.Fac_Axial_Load}
                onChange={(value) =>
                  updateField(
                    "Fac_Axial_Load",
                    value
                  )
                }
              />


              {/* Boundary Condition */}

              <div>

                <label className="text-xs font-medium text-slate-700">
                  Boundary Condition
                </label>

                <select
                  value={form.Boundary_Condition}
                  onChange={(e) =>
                    updateField(
                      "Boundary_Condition",
                      Number(e.target.value)
                    )
                  }
                  className="mt-2 w-full h-10 px-3 rounded-md border border-slate-300 bg-white text-sm outline-none focus:border-orange-500 focus:ring-1 focus:ring-orange-500"
                >

                  <option value={0}>
                    Fixed - Fixed
                  </option>

                  <option value={1}>
                    Fixed - Pinned
                  </option>

                  <option value={2}>
                    Pinned - Pinned
                  </option>

                  <option value={3}>
                    Fixed - Free
                  </option>

                </select>

              </div>


              {/* Section */}

              <div>

                <label className="text-xs font-medium text-slate-700">
                  Section Type
                </label>

                <select
                  value={form.Sections}
                  onChange={(e) =>
                    updateField(
                      "Sections",
                      e.target.value
                    )
                  }
                  className="mt-2 w-full h-10 px-3 rounded-md border border-slate-300 bg-white text-sm outline-none focus:border-orange-500 focus:ring-1 focus:ring-orange-500"
                >

                  <option value="I">
                    I Section
                  </option>

                  <option value="BOX">
                    Box Section
                  </option>

                  <option value="CHS">
                    Circular Hollow Section
                  </option>

                </select>

              </div>


              {/* Units */}

              <div className="pt-3 border-t border-slate-200">

                <div className="flex items-center gap-2 text-xs text-slate-500">

                  <Ruler size={14} />

                  Units: kN, m

                </div>

              </div>


              {/* Buttons */}

              <div className="flex gap-2">

                <button
                  onClick={designColumn}
                  disabled={loading}
                  className="flex-1 h-10 rounded-md bg-orange-600 hover:bg-orange-500 disabled:bg-orange-300 text-white text-sm font-semibold flex items-center justify-center gap-2 transition"
                >

                  {loading ? (
                    <>
                      <Loader2
                        size={16}
                        className="animate-spin"
                      />

                      Designing...
                    </>
                  ) : (
                    "Design Column"
                  )}

                </button>


                <button
                  onClick={resetForm}
                  disabled={loading}
                  className="h-10 w-10 border border-slate-300 rounded-md flex items-center justify-center text-slate-500 hover:bg-slate-50"
                  title="Reset"
                >

                  <RotateCcw size={16} />

                </button>

              </div>

            </div>

          </aside>


          {/* ================= REPORT ================= */}

          <section className="space-y-6">

            {!result && !error && (
              <EmptyReport />
            )}


            {error && (
              <ErrorReport
                error={error}
                form={form}
              />
            )}


            {result && (
              <SuccessReport result={result} />
            )}


            {result && !result.error && (
              <ReportPanel
                report={report}
                loading={reportLoading}
                error={reportError}
                onGenerate={generateReport}
              />
            )}

          </section>

        </div>

      </main>

    </div>
  );
};


/* =========================================================
   INPUT FIELD
========================================================= */

type InputFieldProps = {
  label: string;
  unit: string;
  value: number;
  onChange: (value: number) => void;
};


const InputField = ({
  label,
  unit,
  value,
  onChange,
}: InputFieldProps) => {

  return (
    <div>

      <label className="text-xs font-medium text-slate-700">
        {label}
      </label>

      <div className="relative mt-2">

        <input
          type="number"
          step="0.01"
          value={value}
          onChange={(e) =>
            onChange(Number(e.target.value))
          }
          className="w-full h-10 px-3 pr-12 rounded-md border border-slate-300 text-sm outline-none focus:border-orange-500 focus:ring-1 focus:ring-orange-500"
        />

        <span className="absolute right-3 top-1/2 -translate-y-1/2 text-[10px] text-slate-400">
          {unit}
        </span>

      </div>

    </div>
  );
};


/* =========================================================
   EMPTY REPORT
========================================================= */

const EmptyReport = () => {

  return (
    <div className="bg-white border border-slate-200 rounded-lg min-h-[420px] flex flex-col items-center justify-center text-center">

      <div className="h-14 w-14 rounded-full bg-slate-100 flex items-center justify-center text-slate-400">

        <Ruler size={24} />

      </div>


      <h2 className="mt-5 text-base font-semibold text-slate-700">
        Column Design Report
      </h2>


      <p className="mt-2 max-w-md text-xs leading-5 text-slate-400">
        Enter the column parameters and run the design.
        The analysis results returned by the design engine
        will appear here.
      </p>

    </div>
  );
};


/* =========================================================
   ERROR REPORT
========================================================= */

type ErrorReportProps = {
  error: string;
  form: ColumnForm;
};


const ErrorReport = ({
  error,
  form,
}: ErrorReportProps) => {

  return (
    <div className="bg-white border border-red-200 rounded-lg overflow-hidden">


      {/* Header */}

      <div className="px-6 py-5 bg-red-50 border-b border-red-200">

        <div className="flex items-start gap-3">

          <div className="h-10 w-10 rounded-full bg-red-100 text-red-600 flex items-center justify-center shrink-0">

            <TriangleAlert size={20} />

          </div>


          <div>

            <h2 className="text-sm font-semibold text-red-800">
              Column Design Failed
            </h2>

            <p className="mt-1 text-xs leading-5 text-red-700">
              {error}
            </p>

          </div>

        </div>

      </div>


      {/* Parameters */}

      <div className="p-6">

        <h3 className="text-xs font-semibold text-slate-800">
          Parameters Used
        </h3>


        <div className="grid sm:grid-cols-2 gap-3 mt-4">

          <Parameter
            label="Column Length"
            value={`${form.Length} m`}
          />

          <Parameter
            label="Factored Axial Load"
            value={`${form.Fac_Axial_Load} kN`}
          />

          <Parameter
            label="Boundary Condition"
            value={getBoundaryName(
              form.Boundary_Condition
            )}
          />

          <Parameter
            label="Section"
            value={form.Sections}
          />

        </div>


        {/* Suggestions */}

        <div className="mt-6 p-4 rounded-md bg-orange-50 border border-orange-100">

          <div className="flex items-start gap-3">

            <AlertCircle
              size={17}
              className="text-orange-600 mt-0.5 shrink-0"
            />

            <div>

              <h3 className="text-xs font-semibold text-orange-800">
                Suggested Actions
              </h3>

              <ul className="mt-2 space-y-1.5 text-xs text-orange-700">

                <li>
                  • Try increasing the column length only if appropriate for your structural model.
                </li>

                <li>
                  • Check whether the applied axial load is correct.
                </li>

                <li>
                  • Verify the selected boundary condition.
                </li>

                <li>
                  • Try another section type if the current section is inadequate.
                </li>

              </ul>

            </div>

          </div>

        </div>

      </div>

    </div>
  );
};


/* =========================================================
   SUCCESS REPORT
========================================================= */

const SuccessReport = ({
  result,
}: {
  result: any;
}) => {

  return (
    <div className="bg-white border border-slate-200 rounded-lg overflow-hidden">


      {/* Header */}

      <div className="px-6 py-5 border-b border-slate-200">

        <div className="flex items-start gap-3">

          <div className="h-10 w-10 rounded-full bg-emerald-100 text-emerald-600 flex items-center justify-center">

            <CheckCircle2 size={20} />

          </div>


          <div>

            <h2 className="text-sm font-semibold text-slate-900">
              Column Design Completed
            </h2>

            <p className="mt-1 text-xs text-slate-500">
              Design engine returned a successful response.
            </p>

          </div>

        </div>

      </div>


      {/* Actual Backend Response */}

      <div className="p-6">

        <h3 className="text-xs font-semibold text-slate-800 mb-4">
          Design Results
        </h3>


        <ReportObject
          data={result}
        />

      </div>

    </div>
  );
};


/* =========================================================
   LLM REPORT
   Explanation layer only: the numbers come from the design
   engine, the LLM just writes them up.
========================================================= */

type ReportPanelProps = {
  report: string | null;
  loading: boolean;
  error: string | null;
  onGenerate: () => void;
};


const ReportPanel = ({
  report,
  loading,
  error,
  onGenerate,
}: ReportPanelProps) => {

  // Split "## Heading" blocks; fall back to one block if none found
  const blocks = report
    ? report.includes("## ")
      ? report
          .split(/^##\s+/m)
          .map((b) => b.trim())
          .filter(Boolean)
          .map((b) => {
            const [title, ...rest] = b.split("\n");
            return { title: title.trim(), body: rest.join("\n").trim() };
          })
      : [{ title: "", body: report }]
    : [];

  return (
    <div className="bg-white border border-slate-200 rounded-lg overflow-hidden">

      <div className="px-6 py-5 border-b border-slate-200 flex items-center justify-between gap-4">

        <div>

          <h2 className="text-sm font-semibold text-slate-900">
            Engineering Report
          </h2>

          <p className="mt-1 text-xs text-slate-500">
            Written summary of the results above.
          </p>

        </div>

        <button
          onClick={onGenerate}
          disabled={loading}
          className="h-10 px-4 rounded-md bg-[#172331] hover:bg-slate-700 disabled:bg-slate-400 text-white text-sm font-semibold flex items-center gap-2 transition shrink-0"
        >

          {loading ? (
            <>
              <Loader2 size={16} className="animate-spin" />
              Generating...
            </>
          ) : (
            <>
              <FileText size={16} />
              Generate Report
            </>
          )}

        </button>

      </div>


      {error && (
        <div className="m-6 p-4 rounded-md bg-red-50 border border-red-200 text-xs leading-5 text-red-700">
          {error}
        </div>
      )}


      {blocks.length > 0 && (

        <div className="p-6 space-y-5">

          {blocks.map((b, i) => (

            <div key={i}>

              {b.title && (
                <h3 className="text-xs font-semibold text-slate-800 mb-2">
                  {b.title}
                </h3>
              )}

              <p className="text-xs leading-5 text-slate-700 whitespace-pre-wrap">
                {b.body}
              </p>

            </div>

          ))}

          <p className="pt-4 border-t border-slate-100 text-[10px] text-slate-400">
            AI-written summary of the calculated values. The design results table above is the source of truth.
          </p>

        </div>

      )}

    </div>
  );
};


/* =========================================================
   RECURSIVE BACKEND REPORT
========================================================= */

const ReportObject = ({
  data,
  level = 0,
}: {
  data: any;
  level?: number;
}) => {

  if (
    data === null ||
    data === undefined
  ) {
    return (
      <span className="text-xs text-slate-400">
        —
      </span>
    );
  }


  if (
    typeof data === "string" ||
    typeof data === "number" ||
    typeof data === "boolean"
  ) {
    return (
      <span className="text-xs font-medium text-slate-800">
        {String(data)}
      </span>
    );
  }


  if (Array.isArray(data)) {

    return (
      <div className="space-y-2">

        {data.map((item, index) => (

          <div
            key={index}
            className="p-3 bg-slate-50 rounded-md"
          >

            <ReportObject
              data={item}
              level={level + 1}
            />

          </div>

        ))}

      </div>
    );
  }


  return (
    <div
      className={
        level === 0
          ? "border border-slate-200 rounded-md overflow-hidden"
          : "space-y-2"
      }
    >

      {Object.entries(data).map(
        ([key, value]) => (

          <div
            key={key}
            className="flex items-start gap-5 px-4 py-3 border-b last:border-b-0 border-slate-100"
          >

            <div className="w-1/2 text-xs text-slate-500 break-words">
              {formatKey(key)}
            </div>

            <div className="flex-1">
              <ReportObject
                data={value}
                level={level + 1}
              />
            </div>

          </div>

        )
      )}

    </div>
  );
};


/* =========================================================
   PARAMETER
========================================================= */

const Parameter = ({
  label,
  value,
}: {
  label: string;
  value: string;
}) => {

  return (
    <div className="bg-slate-50 rounded-md px-3 py-3">

      <p className="text-[10px] text-slate-400">
        {label}
      </p>

      <p className="mt-1 text-xs font-semibold text-slate-700">
        {value}
      </p>

    </div>
  );
};


/* =========================================================
   HELPERS
========================================================= */

const getBoundaryName = (
  value: number
) => {

  switch (value) {

    case 0:
      return "Fixed - Fixed";

    case 1:
      return "Fixed - Pinned";

    case 2:
      return "Pinned - Pinned";

    case 3:
      return "Fixed - Free";

    default:
      return `Condition ${value}`;
  }
};


const formatKey = (key: string) => {

  return key
    .replace(/_/g, " ")
    .replace(/([a-z])([A-Z])/g, "$1 $2")
    .replace(/\b\w/g, (char) =>
      char.toUpperCase()
    );
};


export default Column;