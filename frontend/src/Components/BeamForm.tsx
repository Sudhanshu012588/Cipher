import React, { useState, useMemo } from "react";
import axios from "axios";
import * as THREE from "three";
import { STLLoader } from "three/addons/loaders/STLLoader.js";
import {
  AlertCircle,
  CheckCircle2,
  Loader2,
  RotateCcw,
  FileText,
  Activity,
} from "lucide-react";
import Navbar from "../Components/Navbar";
import BeamViewer from "../Components/BeamViewer";
import BeamFEMViewer from "../Components/BeamFEMViewer";
import { BEAM_DESIGN_URL, BEAM_STL_URL, BEAM_FEM_URL } from "../constants";
import type { BeamDesignForm, BeamDesignResult } from "../Types/Type";
import ResultCard from "./ResultCard.tsx";
import EngineeringReport from "../Components/EngineeringReport";

interface BeamFemResult {
  max_deflection_mm: number;
  max_downward_deflection: number;
  max_lateral_deflection: number;
  nominal_flexural_MPa: number;
  min_von_mises_MPa: number;
  max_von_mises_MPa: number;
  avg_von_mises_MPa: number;
  yield_ratio: number;
  boundary_condition_label: string;
  mesh_nodes: number;
  mesh_elements: number;
  positions: number[];
  displacements: number[];
  colors: number[];
  applied_load_udl_kNm: number;
  applied_point_load_kN: number;
}

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
  const [activeTab, setActiveTab] = useState<"model" | "fem" | "report">("model");

  // FEM State
  const [femResult, setFemResult] = useState<BeamFemResult | null>(null);
  const [femLoading, setFemLoading] = useState(false);
  const [femError, setFemError] = useState<string | null>(null);
  const [deformScale, setDeformScale] = useState<number>(200);

  // Report State
  const [report, setReport] = useState<string | null>(null);
  const [reportLoading, setReportLoading] = useState(false);
  const [reportError, setReportError] = useState<string | null>(null);

  // Build scaled & colored deformed FEM BufferGeometry whenever femResult or deformScale changes
  const femGeometry = useMemo(() => {
    if (!femResult?.positions || !femResult?.colors || femResult.positions.length === 0) {
      return null;
    }
    const pos = femResult.positions;
    const disp = femResult.displacements || [];
    const deformed = new Float32Array(pos.length);
    for (let i = 0; i < pos.length; i++) {
      const d = i < disp.length ? disp[i] : 0;
      deformed[i] = pos[i] + deformScale * d;
    }
    const geom = new THREE.BufferGeometry();
    geom.setAttribute("position", new THREE.BufferAttribute(deformed, 3));
    geom.setAttribute("color", new THREE.Float32BufferAttribute(femResult.colors, 3));
    geom.computeVertexNormals();
    geom.center();
    return geom;
  }, [femResult, deformScale]);

  const clearReport = () => {
    setReport(null);
    setReportError(null);
  };

  const clearFem = () => {
    setFemResult(null);
    setFemError(null);
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
    clearFem();
    clearReport();
  };

  const handleReset = () => {
    setForm({ Span: 6, wu: 50, Wu: 0, b1: 100 });
    setResult(null);
    setGeometry(null);
    setError(null);
    clearFem();
    clearReport();
  };

  const loadSTL = async () => {
    setMeshLoading(true);
    try {
      const loader = new STLLoader();
      const loadedGeometry = await loader.loadAsync(`${BEAM_STL_URL}?t=${Date.now()}`);
      loadedGeometry.computeVertexNormals();
      loadedGeometry.center();
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
    clearFem();
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

  const runFemAnalysis = async () => {
    setFemLoading(true);
    setFemError(null);

    try {
      const response = await axios.post<BeamFemResult>(
        BEAM_FEM_URL,
        {
          wu: form.wu,
          Wu: form.Wu,
          b1: form.b1,
        },
        {
          headers: { "Content-Type": "application/json" },
          timeout: 120000,
        }
      );
      setFemResult(response.data);
      setActiveTab("fem");
    } catch (e: any) {
      console.error("FEM analysis error:", e);
      if (e.response?.data?.message) {
        setFemError(e.response.data.message);
      } else if (e.response?.data?.error) {
        setFemError(e.response.data.error);
      } else {
        setFemError("Unable to run 3D FEM analysis. Make sure Beam Design has been run first.");
      }
    } finally {
      setFemLoading(false);
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

            {/* Run 3D FEM Analysis button */}
            <button
              onClick={runFemAnalysis}
              disabled={!result || femLoading}
              style={{
                width: "100%",
                padding: "13px",
                marginTop: "10px",
                border: "none",
                borderRadius: "7px",
                background: !result || femLoading ? "#94a3b8" : "#0f766e",
                color: "white",
                fontWeight: 600,
                fontSize: "15px",
                cursor: !result || femLoading ? "not-allowed" : "pointer",
                display: "flex",
                alignItems: "center",
                justifyContent: "center",
                gap: "8px",
              }}
            >
              {femLoading ? (
                <>
                  <Loader2 size={18} className="animate-spin" />
                  Solving 3D FEM...
                </>
              ) : (
                <>
                  <Activity size={18} />
                  Run 3D FEM Analysis
                </>
              )}
            </button>

            {/* Reset button */}
            <button
              onClick={handleReset}
              disabled={loading || femLoading}
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
              onClick={() => setActiveTab("fem")}
              style={{
                flex: 1,
                padding: "16px",
                border: "none",
                borderBottom:
                  activeTab === "fem"
                    ? "3px solid #0f766e"
                    : "3px solid transparent",
                background: "white",
                color: activeTab === "fem" ? "#0f766e" : "#647894",
                fontWeight: 600,
                cursor: "pointer",
              }}
            >
              3D FEM Analysis
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

          {/* TAB: 3D FEM ANALYSIS */}
          {activeTab === "fem" && (
            <div style={{ padding: "24px" }}>
              {femError && (
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
                  <div>{femError}</div>
                </div>
              )}

              {/* DEFORMATION MAGNIFICATION CONTROLS */}
              {femResult && (
                <div
                  style={{
                    display: "flex",
                    justifyContent: "space-between",
                    alignItems: "center",
                    flexWrap: "wrap",
                    gap: "14px",
                    padding: "12px 18px",
                    marginBottom: "14px",
                    background: "#f8fafc",
                    border: "1px solid #e2e8f0",
                    borderRadius: "8px",
                  }}
                >
                  <div style={{ display: "flex", alignItems: "center", gap: "12px" }}>
                    <span style={{ fontSize: "13px", fontWeight: 700, color: "#1e293b" }}>
                      Deformation Magnification: <span style={{ color: "#0f766e" }}>{deformScale}×</span>
                    </span>
                    <input
                      type="range"
                      min={1}
                      max={500}
                      step={5}
                      value={deformScale}
                      onChange={(e) => setDeformScale(Number(e.target.value))}
                      style={{ width: "160px", cursor: "pointer" }}
                    />
                  </div>

                  <div style={{ display: "flex", gap: "6px" }}>
                    {[1, 50, 200, 500].map((preset) => (
                      <button
                        key={preset}
                        onClick={() => setDeformScale(preset)}
                        style={{
                          padding: "4px 10px",
                          fontSize: "12px",
                          fontWeight: 600,
                          borderRadius: "5px",
                          border: deformScale === preset ? "1px solid #0f766e" : "1px solid #cbd5e1",
                          background: deformScale === preset ? "#ccfbf1" : "white",
                          color: deformScale === preset ? "#0f766e" : "#475569",
                          cursor: "pointer",
                        }}
                      >
                        {preset === 1 ? "1× True" : `${preset}×`}
                      </button>
                    ))}
                  </div>
                </div>
              )}

              {/* FEM 3D VIEWPORT WITH HUD OVERLAYS */}
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
                {femGeometry ? (
                  <>
                    <BeamFEMViewer geometry={femGeometry} loading={femLoading} />

                    {femResult && (
                      <>
                        {/* TOP-LEFT HUD: DEFORMATION & LOAD */}
                        <div
                          style={{
                            position: "absolute",
                            top: "14px",
                            left: "14px",
                            zIndex: 10,
                            background: "rgba(15, 23, 42, 0.88)",
                            backdropFilter: "blur(6px)",
                            color: "white",
                            padding: "12px 14px",
                            borderRadius: "8px",
                            border: "1px solid rgba(148, 163, 184, 0.28)",
                            fontSize: "12px",
                            lineHeight: 1.6,
                            minWidth: "230px",
                            pointerEvents: "none",
                            boxShadow: "0 4px 14px rgba(0,0,0,0.22)",
                          }}
                        >
                          <div
                            style={{
                              fontWeight: 700,
                              fontSize: "11px",
                              letterSpacing: "0.06em",
                              color: "#5eead4",
                              textTransform: "uppercase",
                              marginBottom: "6px",
                            }}
                          >
                            3D FEA Deformation & Load
                          </div>
                          <div style={{ display: "flex", justifyContent: "space-between", gap: "12px" }}>
                            <span style={{ color: "#cbd5e1" }}>UDL Load:</span>
                            <strong>{femResult.applied_load_udl_kNm} kN/m</strong>
                          </div>
                          {femResult.applied_point_load_kN > 0 && (
                            <div style={{ display: "flex", justifyContent: "space-between", gap: "12px" }}>
                              <span style={{ color: "#cbd5e1" }}>Point Load:</span>
                              <strong>{femResult.applied_point_load_kN} kN</strong>
                            </div>
                          )}
                          <div style={{ display: "flex", justifyContent: "space-between", gap: "12px" }}>
                            <span style={{ color: "#cbd5e1" }}>Max Downward δ:</span>
                            <strong style={{ color: "#38bdf8" }}>{femResult.max_downward_deflection} mm</strong>
                          </div>
                          <div style={{ display: "flex", justifyContent: "space-between", gap: "12px" }}>
                            <span style={{ color: "#cbd5e1" }}>Max Lateral:</span>
                            <strong style={{ color: "#38bdf8" }}>{femResult.max_lateral_deflection} mm</strong>
                          </div>
                          <div style={{ display: "flex", justifyContent: "space-between", gap: "12px" }}>
                            <span style={{ color: "#cbd5e1" }}>Resultant Max (|u|):</span>
                            <strong>{femResult.max_deflection_mm} mm</strong>
                          </div>
                          <div
                            style={{
                              marginTop: "6px",
                              paddingTop: "6px",
                              borderTop: "1px solid rgba(148, 163, 184, 0.22)",
                              display: "flex",
                              justifyContent: "space-between",
                              fontSize: "11px",
                              color: "#94a3b8",
                            }}
                          >
                            <span>Scale: {deformScale}×</span>
                            <span>
                              Plotted: {(femResult.max_deflection_mm * deformScale).toFixed(1)} mm
                            </span>
                          </div>
                        </div>

                        {/* TOP-RIGHT HUD: VON MISES STRESS CONTOUR */}
                        <div
                          style={{
                            position: "absolute",
                            top: "14px",
                            right: "14px",
                            zIndex: 10,
                            background: "rgba(15, 23, 42, 0.88)",
                            backdropFilter: "blur(6px)",
                            color: "white",
                            padding: "12px 14px",
                            borderRadius: "8px",
                            border: "1px solid rgba(148, 163, 184, 0.28)",
                            fontSize: "12px",
                            minWidth: "215px",
                            pointerEvents: "none",
                            boxShadow: "0 4px 14px rgba(0,0,0,0.22)",
                          }}
                        >
                          <div
                            style={{
                              fontWeight: 700,
                              fontSize: "11px",
                              letterSpacing: "0.06em",
                              color: "#fda4af",
                              textTransform: "uppercase",
                              marginBottom: "8px",
                            }}
                          >
                            Von Mises Stress (MPa)
                          </div>

                          <div style={{ display: "flex", gap: "12px", alignItems: "stretch" }}>
                            <div
                              style={{
                                width: "14px",
                                height: "130px",
                                borderRadius: "4px",
                                background:
                                  "linear-gradient(180deg, #ff0000 0%, #ffff00 25%, #00ff00 50%, #00ffff 75%, #0000ff 100%)",
                                border: "1px solid rgba(255,255,255,0.45)",
                              }}
                            />

                            <div
                              style={{
                                display: "flex",
                                flexDirection: "column",
                                justifyContent: "space-between",
                                fontSize: "11px",
                                fontWeight: 600,
                                fontFamily: "monospace",
                              }}
                            >
                              <span style={{ color: "#f87171" }}>
                                {femResult.max_von_mises_MPa.toFixed(1)} (Max)
                              </span>
                              <span style={{ color: "#facc15" }}>
                                {(
                                  femResult.min_von_mises_MPa +
                                  0.75 * (femResult.max_von_mises_MPa - femResult.min_von_mises_MPa)
                                ).toFixed(1)}
                              </span>
                              <span style={{ color: "#4ade80" }}>
                                {(
                                  0.5 *
                                  (femResult.min_von_mises_MPa + femResult.max_von_mises_MPa)
                                ).toFixed(1)}{" "}
                                (Mid)
                              </span>
                              <span style={{ color: "#22d3ee" }}>
                                {(
                                  femResult.min_von_mises_MPa +
                                  0.25 * (femResult.max_von_mises_MPa - femResult.min_von_mises_MPa)
                                ).toFixed(1)}
                              </span>
                              <span style={{ color: "#60a5fa" }}>
                                {femResult.min_von_mises_MPa.toFixed(1)} (Min)
                              </span>
                            </div>
                          </div>

                          <div
                            style={{
                              marginTop: "8px",
                              paddingTop: "6px",
                              borderTop: "1px solid rgba(148, 163, 184, 0.22)",
                              fontSize: "11px",
                              color: "#cbd5e1",
                            }}
                          >
                            <div>
                              Flexural:{" "}
                              <strong>
                                {femResult.nominal_flexural_MPa} MPa
                              </strong>
                            </div>
                            <div>
                              Yield Ratio (fy=250):{" "}
                              <strong
                                style={{
                                  color: femResult.yield_ratio > 0.85 ? "#f87171" : "#4ade80",
                                }}
                              >
                                {(femResult.yield_ratio * 100).toFixed(1)}%
                              </strong>
                            </div>
                          </div>
                        </div>
                      </>
                    )}
                  </>
                ) : (
                  <div
                    style={{
                      height: "100%",
                      display: "flex",
                      flexDirection: "column",
                      alignItems: "center",
                      justifyContent: "center",
                      color: "#61758e",
                      padding: "24px",
                      textAlign: "center",
                    }}
                  >
                    {femLoading ? (
                      <>
                        <Loader2 size={42} className="animate-spin" />
                        <strong style={{ marginTop: "14px", fontSize: "17px" }}>
                          Solving 3D beam bending & compression (Ferrite.jl)...
                        </strong>
                      </>
                    ) : (
                      <>
                        <Activity size={42} style={{ marginBottom: "14px", opacity: 0.45 }} />
                        <strong style={{ fontSize: "17px", color: "#44556c" }}>
                          3D FEM Results Not Generated
                        </strong>
                        <div style={{ marginTop: "7px", maxWidth: "420px" }}>
                          {result
                            ? "Click below to solve 3D Von Mises stresses and beam deflection."
                            : "Run Beam Design first to generate the 3D tetrahedral mesh, then run FEM analysis."}
                        </div>
                        {result && (
                          <button
                            onClick={runFemAnalysis}
                            style={{
                              marginTop: "18px",
                              padding: "11px 20px",
                              border: "none",
                              borderRadius: "7px",
                              background: "#0f766e",
                              color: "white",
                              fontWeight: 600,
                              cursor: "pointer",
                              display: "inline-flex",
                              alignItems: "center",
                              gap: "8px",
                            }}
                          >
                            <Activity size={17} />
                            Run 3D FEM Analysis
                          </button>
                        )}
                      </>
                    )}
                  </div>
                )}
              </div>

              {/* DETAILED ENGINEERING & FEA BREAKDOWN CARDS */}
              {femResult && (
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
                      label="Peak Von Mises Stress"
                      value={`${femResult.max_von_mises_MPa} MPa`}
                    />
                    <ResultCard
                      label="Nominal Flexural Stress"
                      value={`${femResult.nominal_flexural_MPa} MPa`}
                    />
                    <ResultCard
                      label="Material Yield Utilization"
                      value={`${(femResult.yield_ratio * 100).toFixed(1)}% (σ / fy)`}
                    />
                    <ResultCard
                      label="Max Deflection"
                      value={`${femResult.max_deflection_mm} mm`}
                    />
                    <ResultCard
                      label="Downward Deflection"
                      value={`${femResult.max_downward_deflection} mm`}
                    />
                    <ResultCard
                      label="3D Mesh & Support"
                      value={`${femResult.mesh_nodes} nodes / ${femResult.mesh_elements} tets`}
                    />
                  </div>

                  <div
                    style={{
                      marginTop: "12px",
                      padding: "12px 16px",
                      background: "#f8fafc",
                      border: "1px solid #e2e8f0",
                      borderRadius: "7px",
                      fontSize: "13px",
                      color: "#475569",
                      display: "flex",
                      justifyContent: "space-between",
                      flexWrap: "wrap",
                      gap: "8px",
                    }}
                  >
                    <span>
                      <strong>Support Condition:</strong> {femResult.boundary_condition_label}
                    </span>
                    <span>
                      <strong>Loading Model:</strong> UDL + Mid-span Point Load
                    </span>
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
