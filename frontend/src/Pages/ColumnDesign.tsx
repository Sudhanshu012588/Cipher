import React, { useState } from "react";
import axios from "axios";
import * as THREE from "three";
import { STLLoader } from "three/addons/loaders/STLLoader.js";

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

// Components
import Navbar from "../Components/Navbar";
import ColumnViewer from "../Components/ColumnViewer";

// Config, Types, Utilities, and Styles
import { DESIGN_URL, STL_URL } from "../constants";
import type { DesignForm, DesignResult } from "../types";
import { formatKey, formatValue } from "../utils";
import { inputStyle, unitStyle, tabStyle } from "../styles";

export default function ColumnDesign() {
  /* ----------------------------------------------------------
     Form
     ---------------------------------------------------------- */
  const [form, setForm] = useState<DesignForm>({
    Length: 3,
    Fac_Axial_Load: 500,
    Boundary_Condition: 0,
    Sections: "I",
  });

  /* ----------------------------------------------------------
     State
     ---------------------------------------------------------- */
  const [result, setResult] = useState<DesignResult | null>(null);
  const [geometry, setGeometry] = useState<THREE.BufferGeometry | null>(null);
  const [loading, setLoading] = useState(false);
  const [meshLoading, setMeshLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [activeTab, setActiveTab] = useState<"model" | "report">("model");

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
    const { name, value } = event.target;
    setForm(previous => ({
      ...previous,
      [name]: name === "Sections" ? value : Number(value),
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

  const handleDesign = async () => {
    setLoading(true);
    setError(null);
    clearReport();

    try {
      const response = await axios.post<DesignResult>(DESIGN_URL, form, {
        headers: { "Content-Type": "application/json" },
        timeout: 120000,
      });

      setResult(response.data);
      await loadSTL();
      setActiveTab("model");
    } catch (e: any) {
      console.error("Column design error:", e);
      if (e.response?.data?.message) {
        setError(e.response.data.message);
      } else if (e.response?.data?.error) {
        setError(e.response.data.error);
      } else if (e.code === "ECONNABORTED") {
        setError("The backend took too long to respond.");
      } else {
        setError("Unable to connect to the backend. Make sure Julia is running on 127.0.0.1:8080.");
      }
    } finally {
      setLoading(false);
    }
  };

  const handleReset = () => {
    setForm({
      Length: 3,
      Fac_Axial_Load: 500,
      Boundary_Condition: 0,
      Sections: "I",
    });
    setResult(null);
    setGeometry(null);
    setError(null);
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
    <div style={{ minHeight: "100vh", background: "#eef1f5" }}>
      <Navbar />

      {/* HEADER */}
      <div style={{ background: "#162434", color: "white", padding: "28px 5%" }}>
        <div style={{ color: "#9dafc4", marginBottom: "18px" }}>
          Design <span style={{ margin: "0 12px" }}>›</span>
          <span style={{ color: "white" }}>Column</span>
        </div>
        <h1 style={{ margin: 0, fontSize: "30px" }}>Column Design</h1>
        <p style={{ marginTop: "6px", color: "#9dafc4", fontSize: "16px" }}>
          Design, verify and visualize structural columns
        </p>
      </div>

      {/* MAIN */}
      <div style={{ display: "grid", gridTemplateColumns: "410px minmax(0, 1fr)", gap: "28px", padding: "36px 5%" }}>
        
        {/* LEFT PANEL */}
        <div style={{ background: "white", border: "1px solid #dce3eb", borderRadius: "10px", overflow: "hidden", height: "fit-content" }}>
          <div style={{ padding: "24px", borderBottom: "1px solid #e2e7ed" }}>
            <h2 style={{ margin: 0, color: "#203047", fontSize: "18px" }}>Design Parameters</h2>
            <p style={{ color: "#647894", marginBottom: 0 }}>Enter the parameters required for column design.</p>
          </div>

          <div style={{ padding: "24px" }}>
            {/* Length */}
            <label style={{ display: "block", fontWeight: 600, color: "#34455d", marginBottom: "8px" }}>Column Length</label>
            <div style={{ position: "relative", marginBottom: "28px" }}>
              <input type="number" name="Length" value={form.Length} min={0.1} step={0.1} onChange={handleChange} style={inputStyle} />
              <span style={unitStyle}>m</span>
            </div>

            {/* Axial load */}
            <label style={{ display: "block", fontWeight: 600, color: "#34455d", marginBottom: "8px" }}>Factored Axial Load</label>
            <div style={{ position: "relative", marginBottom: "28px" }}>
              <input type="number" name="Fac_Axial_Load" value={form.Fac_Axial_Load} min={0} step={10} onChange={handleChange} style={inputStyle} />
              <span style={unitStyle}>kN</span>
            </div>

          </aside>


          {/* ================= REPORT ================= */}

          <section className="space-y-6">

            {!result && !error && (
              <EmptyReport />
            )}


            {/* Error */}
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
            )}
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
          </div>

          {activeTab === "model" && (
            <div style={{ padding: "24px" }}>
              <div style={{ position: "relative", height: "650px", background: "#f5f7f9", border: "1px solid #e1e6ec", borderRadius: "8px", overflow: "hidden" }}>
                {geometry ? (
                  <ColumnViewer geometry={geometry} loading={meshLoading} />
                ) : (
                  <div style={{ height: "100%", display: "flex", flexDirection: "column", alignItems: "center", justifyContent: "center", color: "#61758e" }}>
                    <div style={{ fontSize: "42px", marginBottom: "14px", opacity: 0.45 }}>◇</div>
                    <strong style={{ fontSize: "17px", color: "#44556c" }}>Mesh not available</strong>
                    <div style={{ marginTop: "7px" }}>Run the column design to generate the 3D model.</div>
                  </div>
                )}
              </div>
            </div>
          )}

          {activeTab === "report" && (
            <div style={{ padding: "28px" }}>
              {!result ? (
                <div style={{ textAlign: "center", padding: "80px 20px", color: "#687b92" }}>Run the column design to generate the report.</div>
              ) : (
                <>
                  <h2 style={{ marginTop: 0, color: "#203047" }}>Column Design Report</h2>
                  <div style={{ display: "grid", gridTemplateColumns: "repeat(2, minmax(0, 1fr))", gap: "12px" }}>
                    {Object.entries(result)
                      .filter(([key]) => key !== "mesh_url" && key !== "mesh_file" && key !== "stl_url" && key !== "stl_file")
                      .map(([key, value]) => (
                        <div key={key} style={{ border: "1px solid #e1e6ec", borderRadius: "7px", padding: "14px" }}>
                          <div style={{ fontSize: "12px", color: "#71839a", marginBottom: "5px" }}>{formatKey(key)}</div>
                          <div style={{ fontWeight: 600, color: "#203047" }}>{formatValue(value)}</div>
                        </div>
                      ))}
                  </div>
                </>
              )}
            </div>
          )}
        </div>
      </div>
    </div>
  );
}