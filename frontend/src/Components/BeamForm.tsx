import React, { useState } from "react";
import axios from "axios";
import * as THREE from "three";
import { STLLoader } from "three/addons/loaders/STLLoader.js";
import {
  AlertCircle,
  CheckCircle2,
  Loader2,
  RotateCcw,
  FileText,
} from "lucide-react";
import Navbar from "../Components/Navbar";
import BeamViewer from "../Components/BeamViewer";
import { BEAM_DESIGN_URL, BEAM_STL_URL, BEAM_REPORT_URL } from "../constants";
import type { BeamDesignForm, BeamDesignResult } from "../Types/Type";
import ResultCard from "./ResultCard.tsx";
import EngineeringReport from "../Components/EngineeringReport";

function formatKey(key: string): string {
  return key
    .replace(/_/g, " ")
    .replace(/\b\w/g, (char) => char.toUpperCase());
}

function formatValue(value: any): string {
  if (value === null || value === undefined) {
    return "-";
  }
  if (typeof value === "boolean") {
    return value ? "Yes" : "No";
  }
  if (typeof value === "number") {
    return Number.isInteger(value)
      ? value.toString()
      : value.toFixed(3);
  }
  return String(value);
}

const CHECK_KEYS = [
  "Shear_Check",
  "Moment_Check",
  "Deflection_Check",
  "Web_Crippling_Check",
];

const CHECK_LABELS: Record<string, string> = {
  Shear_Check: "Shear",
  Moment_Check: "Moment",
  Deflection_Check: "Deflection",
  Web_Crippling_Check: "Web Crippling",
};

export default function BeamForm() {
  const [form, setForm] = useState<BeamDesignForm>({
    Span: 6,
    wu: 50,
    Wu: 0,
    b1: 100,
  });
  const [result, setResult] = useState<BeamDesignResult | null>(null);
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

  const handleChange = (event: React.ChangeEvent<HTMLInputElement>) => {
    const { name, value } = event.target;
    setForm((previous) => ({
      ...previous,
      [name]: Number(value),
    }));
    setResult(null);
    setGeometry(null);
    setError(null);
    clearReport();
  };

  const handleReset = () => {
    setForm({ Span: 6, wu: 50, Wu: 0, b1: 100 });
    setResult(null);
    setGeometry(null);
    setError(null);
    clearReport();
  };

  const loadSTL = async () => {
    setMeshLoading(true);
    try {
      const loader = new STLLoader();
      const loadedGeometry = await loader.loadAsync(BEAM_STL_URL);
      loadedGeometry.computeVertexNormals();
      setGeometry(loadedGeometry);
    } catch (err) {
      console.error("STL loading error:", err);
      setGeometry(null);
      setError("Beam design succeeded, but the 3D model could not be loaded.");
    } finally {
      setMeshLoading(false);
    }
  };

  const handleDesign = async () => {
    setLoading(true);
    setError(null);
    setResult(null);
    setGeometry(null);
    clearReport();

    try {
      const response = await axios.post<BeamDesignResult>(
        BEAM_DESIGN_URL,
        form,
        {
          headers: { "Content-Type": "application/json" },
          timeout: 120000,
        }
      );
      const data = response.data;
      if (data.error) {
        setError(data.message || data.error || "Beam design failed.");
        return;
      }
      setResult(data);
      await loadSTL();
      setActiveTab("model");
    } catch (e: any) {
      console.error("Beam design error:", e);
      if (e.response?.data?.message) {
        setError(e.response.data.message);
      } else if (e.response?.data?.error) {
        setError(e.response.data.error);
      } else if (e.code === "ECONNABORTED") {
        setError("The backend took too long to respond.");
      } else {
        setError(
          "Unable to connect to the backend. Make sure Julia is running on 127.0.0.1:8080."
        );
      }
    } finally {
      setLoading(false);
    }
  };

  const generateReport = async () => {
    setReportLoading(true);
    setReport(null);
    setReportError(null);

    try {
      const response = await axios.post(BEAM_REPORT_URL, form, {
        headers: { "Content-Type": "application/json" },
        timeout: 120000,
      });

      if (response.data?.error) {
        setReportError(
          response.data.message
            ? `${response.data.error} ${response.data.message}`
            : response.data.error
        );
      } else {
        setReport(
          response.data.report ||
            response.data.message ||
            JSON.stringify(response.data, null, 2)
        );
      }
    } catch (err) {
      console.error("Report generation error:", err);
      if (axios.isAxiosError(err) && !err.response) {
        setReportError(
          "Unable to connect to the design engine. Please make sure the backend is running on 127.0.0.1:8080."
        );
      } else {
        setReportError("The report could not be generated.");
      }
    } finally {
      setReportLoading(false);
    }
  };

  const isSafe = result?.Status === "SAFE";

  return (
    <div style={{ minHeight: "100vh", background: "#eef1f5" }}>
      <Navbar />

      {/* HEADER */}
      <div
        style={{
          background: "#162434",
          color: "white",
          padding: "28px 5%",
        }}
      >
        <div style={{ color: "#9dafc4", marginBottom: "18px" }}>
          Design
          <span style={{ margin: "0 12px" }}>›</span>
          <span style={{ color: "white" }}>Beam</span>
        </div>

        <h1 style={{ margin: 0, fontSize: "30px" }}>Beam Design</h1>

        <p style={{ marginTop: "6px", color: "#9dafc4", fontSize: "16px" }}>
          Design, verify and visualize structural steel beams (IS 800)
        </p>
      </div>

      {/* MAIN LAYOUT */}
      <div
        style={{
          display: "grid",
          gridTemplateColumns: "410px minmax(0, 1fr)",
          gap: "28px",
          padding: "36px 5%",
        }}
      >
        {/* INPUT PANEL */}
        <div
          style={{
            background: "white",
            border: "1px solid #dce3eb",
            borderRadius: "10px",
            overflow: "hidden",
            height: "fit-content",
          }}
        >
          <div
            style={{
              padding: "24px",
              borderBottom: "1px solid #e2e7ed",
            }}
          >
            <h2 style={{ margin: 0, color: "#203047", fontSize: "18px" }}>
              Design Parameters
            </h2>
            <p style={{ color: "#647894", marginBottom: 0 }}>
              Enter the parameters required for beam design.
            </p>
          </div>

          <div style={{ padding: "24px" }}>
            {/* Span */}
            <label
              style={{
                display: "block",
                fontWeight: 600,
                color: "#34455d",
                marginBottom: "8px",
              }}
            >
              Beam Span
            </label>
            <div style={{ position: "relative", marginBottom: "28px" }}>
              <input
                type="number"
                name="Span"
                value={form.Span}
                min={0.1}
                step={0.5}
                onChange={handleChange}
                style={{
                  width: "100%",
                  boxSizing: "border-box",
                  padding: "12px 60px 12px 14px",
                  border: "1px solid #cfd8e3",
                  borderRadius: "7px",
                  fontSize: "15px",
                }}
              />
              <span
                style={{
                  position: "absolute",
                  right: "14px",
                  top: "50%",
                  transform: "translateY(-50%)",
                  color: "#71839a",
                }}
              >
                m
              </span>
            </div>

            {/* wu */}
            <label
              style={{
                display: "block",
                fontWeight: 600,
                color: "#34455d",
                marginBottom: "8px",
              }}
            >
              Factored UDL (w<sub>u</sub>)
            </label>
            <div style={{ position: "relative", marginBottom: "28px" }}>
              <input
                type="number"
                name="wu"
                value={form.wu}
                min={0}
                step={5}
                onChange={handleChange}
                style={{
                  width: "100%",
                  boxSizing: "border-box",
                  padding: "12px 70px 12px 14px",
                  border: "1px solid #cfd8e3",
                  borderRadius: "7px",
                  fontSize: "15px",
                }}
              />
              <span
                style={{
                  position: "absolute",
                  right: "14px",
                  top: "50%",
                  transform: "translateY(-50%)",
                  color: "#71839a",
                }}
              >
                kN/m
              </span>
            </div>

            {/* Wu */}
            <label
              style={{
                display: "block",
                fontWeight: 600,
                color: "#34455d",
                marginBottom: "8px",
              }}
            >
              Factored Point Load (W<sub>u</sub>)
            </label>
            <div style={{ position: "relative", marginBottom: "28px" }}>
              <input
                type="number"
                name="Wu"
                value={form.Wu}
                min={0}
                step={10}
                onChange={handleChange}
                style={{
                  width: "100%",
                  boxSizing: "border-box",
                  padding: "12px 60px 12px 14px",
                  border: "1px solid #cfd8e3",
                  borderRadius: "7px",
                  fontSize: "15px",
                }}
              />
              <span
                style={{
                  position: "absolute",
                  right: "14px",
                  top: "50%",
                  transform: "translateY(-50%)",
                  color: "#71839a",
                }}
              >
                kN
              </span>
            </div>

            {/* b1 */}
            <label
              style={{
                display: "block",
                fontWeight: 600,
                color: "#34455d",
                marginBottom: "8px",
              }}
            >
              Stiff Bearing Length (b<sub>1</sub>)
            </label>
            <div style={{ position: "relative", marginBottom: "28px" }}>
              <input
                type="number"
                name="b1"
                value={form.b1}
                min={0}
                step={10}
                onChange={handleChange}
                style={{
                  width: "100%",
                  boxSizing: "border-box",
                  padding: "12px 60px 12px 14px",
                  border: "1px solid #cfd8e3",
                  borderRadius: "7px",
                  fontSize: "15px",
                }}
              />
              <span
                style={{
                  position: "absolute",
                  right: "14px",
                  top: "50%",
                  transform: "translateY(-50%)",
                  color: "#71839a",
                }}
              >
                mm
              </span>
            </div>

            {/* Design button */}
            <button
              onClick={handleDesign}
              disabled={loading}
              style={{
                width: "100%",
                padding: "13px",
                border: "none",
                borderRadius: "7px",
                background: loading ? "#8b9aad" : "#1d5fa7",
                color: "white",
                fontWeight: 600,
                fontSize: "15px",
                cursor: loading ? "not-allowed" : "pointer",
                display: "flex",
                alignItems: "center",
                justifyContent: "center",
                gap: "8px",
              }}
            >
              {loading ? (
                <>
                  <Loader2 size={18} className="animate-spin" />
                  Designing...
                </>
              ) : (
                <>
                  <CheckCircle2 size={18} />
                  Design Beam
                </>
              )}
            </button>

            {/* Reset button */}
            <button
              onClick={handleReset}
              disabled={loading}
              style={{
                width: "100%",
                padding: "12px",
                marginTop: "10px",
                border: "1px solid #cfd8e3",
                borderRadius: "7px",
                background: "white",
                color: "#40536c",
                fontWeight: 600,
                fontSize: "14px",
                cursor: "pointer",
                display: "flex",
                alignItems: "center",
                justifyContent: "center",
                gap: "8px",
              }}
            >
              <RotateCcw size={16} />
              Reset
            </button>
          </div>
        </div>

        {/* RESULTS & 3D MODEL PANEL */}
        <div
          style={{
            background: "white",
            border: "1px solid #dce3eb",
            borderRadius: "10px",
            overflow: "hidden",
            minHeight: "650px",
          }}
        >
          {/* TABS */}
          <div style={{ display: "flex", borderBottom: "1px solid #e2e7ed" }}>
            <button
              onClick={() => setActiveTab("model")}
              style={{
                flex: 1,
                padding: "16px",
                border: "none",
                borderBottom:
                  activeTab === "model"
                    ? "3px solid #1d5fa7"
                    : "3px solid transparent",
                background: "white",
                color: activeTab === "model" ? "#1d5fa7" : "#647894",
                fontWeight: 600,
                cursor: "pointer",
              }}
            >
              3D Model
            </button>

            <button
              onClick={() => setActiveTab("report")}
              style={{
                flex: 1,
                padding: "16px",
                border: "none",
                borderBottom:
                  activeTab === "report"
                    ? "3px solid #1d5fa7"
                    : "3px solid transparent",
                background: "white",
                color: activeTab === "report" ? "#1d5fa7" : "#647894",
                fontWeight: 600,
                cursor: "pointer",
              }}
            >
              Design Report
            </button>
          </div>

          {/* TAB: 3D MODEL & DESIGN RESULTS */}
          {activeTab === "model" && (
            <div style={{ padding: "24px" }}>
              {/* ERROR ALERT */}
              {error && (
                <div
                  style={{
                    display: "flex",
                    gap: "10px",
                    alignItems: "flex-start",
                    padding: "14px",
                    marginBottom: "18px",
                    border: "1px solid #f0b8b8",
                    background: "#fff4f4",
                    color: "#9b2c2c",
                    borderRadius: "7px",
                  }}
                >
                  <AlertCircle size={20} />
                  <div>{error}</div>
                </div>
              )}

              {/* 3D VIEWER CONTAINER */}
              <div
                style={{
                  position: "relative",
                  height: "650px",
                  background: "#f5f7f9",
                  border: "1px solid #e1e6ec",
                  borderRadius: "8px",
                  overflow: "hidden",
                }}
              >
                {geometry ? (
                  <BeamViewer geometry={geometry} loading={meshLoading} />
                ) : (
                  <div
                    style={{
                      height: "100%",
                      display: "flex",
                      flexDirection: "column",
                      alignItems: "center",
                      justifyContent: "center",
                      color: "#61758e",
                    }}
                  >
                    {meshLoading ? (
                      <>
                        <Loader2 size={42} className="animate-spin" />
                        <strong
                          style={{
                            marginTop: "14px",
                            fontSize: "17px",
                          }}
                        >
                          Loading 3D model...
                        </strong>
                      </>
                    ) : (
                      <>
                        <div
                          style={{
                            fontSize: "42px",
                            marginBottom: "14px",
                            opacity: 0.45,
                          }}
                        >
                          ◇
                        </div>
                        <strong
                          style={{
                            fontSize: "17px",
                            color: "#44556c",
                          }}
                        >
                          Mesh not available
                        </strong>
                        <div style={{ marginTop: "7px" }}>
                          Run the beam design to generate the 3D model.
                        </div>
                      </>
                    )}
                  </div>
                )}
              </div>

              {/* QUICK RESULT CARDS (Same format as Column) */}
              {result && !result.error && (
                <>
                  <div
                    style={{
                      marginTop: "20px",
                      display: "grid",
                      gridTemplateColumns: "repeat(3, minmax(0, 1fr))",
                      gap: "12px",
                    }}
                  >
                    <ResultCard
                      label="Selected Section"
                      value={result.Designation || "-"}
                    />
                    <ResultCard
                      label="Design Moment Mᵤ"
                      value={
                        result.M_u_kNm !== undefined
                          ? `${formatValue(result.M_u_kNm)} kN·m`
                          : "-"
                      }
                    />
                    <ResultCard
                      label="Moment Capacity M_d"
                      value={
                        result.M_d_kNm !== undefined
                          ? `${formatValue(result.M_d_kNm)} kN·m`
                          : "-"
                      }
                    />
                  </div>

                  <div
                    style={{
                      marginTop: "12px",
                      display: "grid",
                      gridTemplateColumns: "repeat(3, minmax(0, 1fr))",
                      gap: "12px",
                    }}
                  >
                    <ResultCard
                      label="Shear at Support Vᵤ,s"
                      value={
                        result.V_u_s_kN !== undefined
                          ? `${formatValue(result.V_u_s_kN)} kN`
                          : "-"
                      }
                    />
                    <ResultCard
                      label="Shear Capacity V_d"
                      value={
                        result.V_d_kN !== undefined
                          ? `${formatValue(result.V_d_kN)} kN`
                          : "-"
                      }
                    />
                    <ResultCard
                      label="Section Classification"
                      value={result.Section_Class || "-"}
                    />
                  </div>

                  {/* STATUS & CHECKS BADGES */}
                  <div
                    style={{
                      marginTop: "20px",
                      display: "flex",
                      alignItems: "center",
                      gap: "12px",
                      flexWrap: "wrap",
                    }}
                  >
                    <span
                      style={{
                        display: "inline-flex",
                        alignItems: "center",
                        gap: "6px",
                        padding: "8px 20px",
                        borderRadius: "999px",
                        fontWeight: 700,
                        fontSize: "15px",
                        background: isSafe ? "#e6f4ea" : "#fff4f4",
                        color: isSafe ? "#1e7e34" : "#9b2c2c",
                        border: isSafe
                          ? "1px solid #b7dfbf"
                          : "1px solid #f0b8b8",
                      }}
                    >
                      {isSafe ? (
                        <CheckCircle2 size={16} />
                      ) : (
                        <AlertCircle size={16} />
                      )}
                      {result.Status || "UNKNOWN"}
                    </span>

                    {CHECK_KEYS.map((key) => {
                      const val = result[key] as string | undefined;
                      const pass = val === "PASS";
                      return (
                        <span
                          key={key}
                          style={{
                            display: "inline-flex",
                            alignItems: "center",
                            gap: "6px",
                            padding: "6px 14px",
                            borderRadius: "999px",
                            fontWeight: 600,
                            fontSize: "13px",
                            background: pass ? "#e6f4ea" : "#fff4f4",
                            color: pass ? "#1e7e34" : "#9b2c2c",
                            border: pass
                              ? "1px solid #b7dfbf"
                              : "1px solid #f0b8b8",
                          }}
                        >
                          {pass ? (
                            <CheckCircle2 size={13} />
                          ) : (
                            <AlertCircle size={13} />
                          )}
                          {CHECK_LABELS[key]}: {val || "N/A"}
                        </span>
                      );
                    })}
                  </div>
                </>
              )}
            </div>
          )}

          {/* TAB: DESIGN REPORT */}
          {activeTab === "report" && (
            <div style={{ padding: "28px" }}>
              {!result ? (
                <div
                  style={{
                    textAlign: "center",
                    padding: "80px 20px",
                    color: "#687b92",
                  }}
                >
                  <FileText
                    size={42}
                    style={{ marginBottom: "15px", opacity: 0.5 }}
                  />
                  <div>Run the beam design to generate the report.</div>
                </div>
              ) : (
                <>
                  {/* REPORT HEADER */}
                  <div
                    style={{
                      display: "flex",
                      justifyContent: "space-between",
                      alignItems: "center",
                      marginBottom: "24px",
                    }}
                  >
                    <div>
                      <h2 style={{ margin: 0, color: "#203047" }}>
                        Beam Design Report
                      </h2>
                      <p style={{ color: "#71839a", marginBottom: 0 }}>
                        {result.Designation || "Designed Beam"}
                      </p>
                    </div>

                    <button
                      onClick={generateReport}
                      disabled={reportLoading}
                      style={{
                        padding: "10px 16px",
                        border: "none",
                        borderRadius: "7px",
                        background: reportLoading ? "#8b9aad" : "#1d5fa7",
                        color: "white",
                        fontWeight: 600,
                        cursor: reportLoading ? "not-allowed" : "pointer",
                        display: "flex",
                        alignItems: "center",
                        gap: "8px",
                      }}
                    >
                      {reportLoading ? (
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

                  {/* REPORT ERROR */}
                  {reportError && (
                    <div
                      style={{
                        padding: "14px",
                        marginBottom: "20px",
                        border: "1px solid #f0b8b8",
                        background: "#fff4f4",
                        color: "#9b2c2c",
                        borderRadius: "7px",
                      }}
                    >
                      {reportError}
                    </div>
                  )}

                  {/* BACKEND DESIGN VALUES */}
                  <h3
                    style={{
                      color: "#203047",
                      marginBottom: "14px",
                    }}
                  >
                    Design Results
                  </h3>

                  <div
                    style={{
                      display: "grid",
                      gridTemplateColumns:
                        "repeat(2, minmax(0, 1fr))",
                      gap: "12px",
                      marginBottom: "24px",
                    }}
                  >
                    {Object.entries(result)
                      .filter(
                        ([key]) =>
                          ![
                            "mesh_url",
                            "mesh_file",
                            "stl_url",
                            "stl_file",
                            "error",
                            "message",
                          ].includes(key)
                      )
                      .map(([key, value]) => (
                        <div
                          key={key}
                          style={{
                            border: "1px solid #e1e6ec",
                            borderRadius: "7px",
                            padding: "14px",
                          }}
                        >
                          <div
                            style={{
                              fontSize: "12px",
                              color: "#71839a",
                              marginBottom: "5px",
                            }}
                          >
                            {formatKey(key)}
                          </div>

                          <div
                            style={{
                              fontWeight: 600,
                              color: "#203047",
                            }}
                          >
                            {formatValue(value)}
                          </div>
                        </div>
                      ))}
                  </div>

                  {/* LLM REPORT */}
                  {report && <EngineeringReport report={report} />}
                </>
              )}
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
