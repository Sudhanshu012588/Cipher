
// Imported Config, Types, Utilities, and Styles


import React, { useEffect, useState } from "react";
import axios from "axios";
import * as THREE from "three";
import { STLLoader } from "three/addons/loaders/STLLoader.js";

// Imported Components
import Navbar from "../Components/Navbar";
import ColumnViewer from "../Components/ColumnViewer";

// Imported Config, Types, Utilities, and Styles
import { DESIGN_URL, STL_URL } from "../constants";
import type { DesignForm, DesignResult } from "../types";
import { formatKey, formatValue } from "../utils";
import { inputStyle, unitStyle, tabStyle } from "../styles";

export default function Column() {
  const [form, setForm] = useState<DesignForm>({
    Length: 3,
    Fac_Axial_Load: 500,
    Boundary_Condition: 0,
    Sections: "I",
  });

  const [result, setResult] = useState<DesignResult | null>(null);
  const [geometry, setGeometry] = useState<THREE.BufferGeometry | null>(null);
  const [loading, setLoading] = useState(false);
  const [meshLoading, setMeshLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [activeTab, setActiveTab] = useState<"model" | "report">("model");

  const handleChange = (
    event: React.ChangeEvent<HTMLInputElement | HTMLSelectElement>
  ) => {
    const { name, value } = event.target;
    setForm(previous => ({
      ...previous,
      [name]: name === "Sections" ? value : Number(value),
    }));
  };

  const loadSTL = async () => {
    setMeshLoading(true);
    try {
      const loader = new STLLoader();
      const url = `${STL_URL}?t=${Date.now()}`;
      const loadedGeometry = await loader.loadAsync(url);
      
      loadedGeometry.computeVertexNormals();
      loadedGeometry.center();
      setGeometry(loadedGeometry);
    } catch (e) {
      console.error("Failed to load Column.stl:", e);
      setError("Column design succeeded, but the 3D model could not be loaded.");
    } finally {
      setMeshLoading(false);
    }
  };

  const handleDesign = async () => {
    setLoading(true);
    setError(null);
    setGeometry(null);

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

  return (
    <div style={{ minHeight: "100vh", background: "#eef1f5" }}>
      <Navbar />

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

            {/* Boundary condition */}
            <label style={{ display: "block", fontWeight: 600, color: "#34455d", marginBottom: "8px" }}>Boundary Condition</label>
            <select name="Boundary_Condition" value={form.Boundary_Condition} onChange={handleChange} style={{ ...inputStyle, marginBottom: "28px" }}>
              <option value={0}>Pinned - Pinned</option>
              <option value={1}>Fixed - Fixed</option>
              <option value={2}>Fixed - Free</option>
              <option value={3}>Fixed - Pinned</option>
            </select>

            {/* Section */}
            <label style={{ display: "block", fontWeight: 600, color: "#34455d", marginBottom: "8px" }}>Section Type</label>
            <select name="Sections" value={form.Sections} onChange={handleChange} style={{ ...inputStyle, marginBottom: "28px" }}>
              <option value="I">I Section</option>
              <option value="C">C / Channel Section</option>
            </select>

            {/* Buttons */}
            <div style={{ display: "flex", gap: "14px" }}>
              <button
                onClick={handleDesign}
                disabled={loading || meshLoading}
                style={{
                  flex: 1, border: "none", borderRadius: "7px", background: "#ff4b0b", color: "white", fontSize: "16px", fontWeight: 700, padding: "13px", cursor: loading ? "wait" : "pointer"
                }}
              >
                {loading ? "Designing..." : "Design Column"}
              </button>
              <button onClick={handleReset} style={{ width: "48px", border: "1px solid #ccd7e3", background: "white", borderRadius: "7px", fontSize: "20px", cursor: "pointer" }}>
                ↻
              </button>
            </div>

            {/* Error */}
            {error && (
              <div style={{ marginTop: "22px", padding: "16px", borderRadius: "7px", border: "1px solid #ffb8b8", background: "#fff4f4", color: "#d91c1c" }}>
                <strong>Error</strong>
                <div style={{ marginTop: "8px", lineHeight: 1.4 }}>{error}</div>
              </div>
            )}
          </div>
        </div>

        {/* RIGHT PANEL */}
        <div style={{ background: "white", border: "1px solid #dce3eb", borderRadius: "10px", overflow: "hidden", minWidth: 0 }}>
          <div style={{ display: "flex", borderBottom: "1px solid #e1e6ec" }}>
            <button onClick={() => setActiveTab("model")} style={tabStyle(activeTab === "model")}>◈&nbsp;&nbsp;3D Model</button>
            <button onClick={() => setActiveTab("report")} style={tabStyle(activeTab === "report")}>▤&nbsp;&nbsp;Report</button>
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