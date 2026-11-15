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
import ColumnViewer from "../Components/ColumnViewer";
import { COLUMN_REPORT_URL, DESIGN_URL, STL_URL } from "../constants";
import type { DesignForm, DesignResult } from "../Types/Type";
import ResultCard from "./ResultCard.tsx"
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

  if (typeof value === "number") {
    return Number.isInteger(value)
      ? value.toString()
      : value.toFixed(3);
  }

  return String(value);
}

export default function ColumnDesign() {

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
  const [report, setReport] = useState<string | null>(null);
  const [reportLoading, setReportLoading] = useState(false);
  const [reportError, setReportError] = useState<string | null>(null);

  // CLEAR REPORT

  const clearReport = () => {
    setReport(null);
    setReportError(null);
  };
  // FORM CHANGE
  const handleChange = (event: React.ChangeEvent<HTMLInputElement | HTMLSelectElement>) => {

    const { name, value } = event.target;

    setForm((previous) => ({
      ...previous,

      [name]:
        name === "Sections"
          ? value
          : Number(value),
    }));

    setResult(null);
    setGeometry(null);
    setError(null);

    clearReport();
  };
  // RESET
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
    clearReport();
  };
  // LOAD STL

  const loadSTL = async () => {
    setMeshLoading(true);
    try {
      const loader = new STLLoader();
      const geometry =await loader.loadAsync(STL_URL);
      geometry.computeVertexNormals();
      setGeometry(geometry);
    } catch (err) {
      console.error(
        "STL loading error:",
        err
      );
      setGeometry(null);
      setError("Column design succeeded, but the 3D model could not be loaded.");
    } finally {
      setMeshLoading(false);
    }
  };

  // DESIGN COLUMN

  const handleDesign = async () => {
    setLoading(true);
    setError(null);

    setResult(null);
    setGeometry(null);

    clearReport();

    try {

      const response =
        await axios.post<DesignResult>(
          DESIGN_URL,
          form,
          {
            headers: {
              "Content-Type":
                "application/json",
            },

            timeout: 120000,
          }
        );
      const data = response.data;
      if (data.error) {
        setError(
          data.message ||
          data.error ||
          "Column design failed."
        );
        return;
      }
      setResult(data);
      await loadSTL();
      setActiveTab("model");
    } catch (e: any) {
      console.error("Column design error:",e);
      if (e.response?.data?.message) {
        setError(e.response.data.message);
      } else if (e.response?.data?.error) {
        setError(e.response.data.error);
      } else if (
        e.code === "ECONNABORTED"
      ) {
        setError("The backend took too long to respond.");
      } else {
        setError("Unable to connect to the backend. " +"Make sure Julia is running on 127.0.0.1:8080.");
      }

    } finally {
      setLoading(false);
    }
  };
  // GENERATE REPORT
  const generateReport = async () => {
    setReportLoading(true);
    setReport(null);
    setReportError(null);

    try {

      const response =
        await axios.post(
          COLUMN_REPORT_URL,
          form,
          {
            headers: {
              "Content-Type":
                "application/json",
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

        setReport(
          response.data.report ||
          response.data.message ||
          JSON.stringify(
            response.data,
            null,
            2
          )
        );

      }

    } catch (err) {

      console.error(
        "Report generation error:",
        err
      );

      if (
        axios.isAxiosError(err) &&
        !err.response
      ) {

        setReportError(
          "Unable to connect to the design engine. " +
          "Please make sure the backend is running on 127.0.0.1:8080."
        );

      } else {

        setReportError(
          "The report could not be generated."
        );

      }

    } finally {

      setReportLoading(false);

    }
  };

  // RENDER
  return (
    <div
      style={{
        minHeight: "100vh",
        background: "#eef1f5",
      }}
    >

      <Navbar />
      <div
        style={{
          background: "#162434",
          color: "white",
          padding: "28px 5%",
        }}
      >

        <div
          style={{
            color: "#9dafc4",
            marginBottom: "18px",
          }}
        >
          Design

          <span
            style={{
              margin: "0 12px",
            }}
          >
            ›
          </span>

          <span
            style={{
              color: "white",
            }}
          >
            Column
          </span>
        </div>


        <h1
          style={{
            margin: 0,
            fontSize: "30px",
          }}
        >
          Column Design
        </h1>


        <p
          style={{
            marginTop: "6px",
            color: "#9dafc4",
            fontSize: "16px",
          }}
        >
          Design, verify and visualize
          structural columns
        </p>

      </div>

      <div
        style={{
          display: "grid",
          gridTemplateColumns:
            "410px minmax(0, 1fr)",
          gap: "28px",
          padding: "36px 5%",
        }}
      >

        <div
          style={{
            background: "white",
            border:
              "1px solid #dce3eb",
            borderRadius: "10px",
            overflow: "hidden",
            height: "fit-content",
          }}
        >
          <div
            style={{
              padding: "24px",
              borderBottom:
                "1px solid #e2e7ed",
            }}
          >

            <h2
              style={{
                margin: 0,
                color: "#203047",
                fontSize: "18px",
              }}
            >
              Design Parameters
            </h2>


            <p
              style={{
                color: "#647894",
                marginBottom: 0,
              }}
            >
              Enter the parameters required
              for column design.
            </p>

          </div>
          <div
            style={{
              padding: "24px",
            }}
          >

            <label
              style={{
                display: "block",
                fontWeight: 600,
                color: "#34455d",
                marginBottom: "8px",
              }}
            >
              Column Length
            </label>


            <div
              style={{
                position: "relative",
                marginBottom: "28px",
              }}
            >

              <input
                type="number"
                name="Length"
                value={form.Length}
                min={0.1}
                step={0.1}
                onChange={handleChange}
                style={{
                  width: "100%",
                  boxSizing: "border-box",
                  padding: "12px 60px 12px 14px",
                  border:
                    "1px solid #cfd8e3",
                  borderRadius: "7px",
                  fontSize: "15px",
                }}
              />


              <span
                style={{
                  position: "absolute",
                  right: "14px",
                  top: "50%",
                  transform:
                    "translateY(-50%)",
                  color: "#71839a",
                }}
              >
                m
              </span>

            </div>
            <label
              style={{
                display: "block",
                fontWeight: 600,
                color: "#34455d",
                marginBottom: "8px",
              }}
            >
              Factored Axial Load
            </label>


            <div
              style={{
                position: "relative",
                marginBottom: "28px",
              }}
            >

              <input
                type="number"
                name="Fac_Axial_Load"
                value={
                  form.Fac_Axial_Load
                }
                min={0}
                step={10}
                onChange={handleChange}
                style={{
                  width: "100%",
                  boxSizing: "border-box",
                  padding: "12px 60px 12px 14px",
                  border:
                    "1px solid #cfd8e3",
                  borderRadius: "7px",
                  fontSize: "15px",
                }}
              />


              <span
                style={{
                  position: "absolute",
                  right: "14px",
                  top: "50%",
                  transform:
                    "translateY(-50%)",
                  color: "#71839a",
                }}
              >
                kN
              </span>

            </div>

            <label
              style={{
                display: "block",
                fontWeight: 600,
                color: "#34455d",
                marginBottom: "8px",
              }}
            >
              Boundary Condition
            </label>


            <select
              name="Boundary_Condition"
              value={
                form.Boundary_Condition
              }
              onChange={handleChange}
              style={{
                width: "100%",
                boxSizing: "border-box",
                padding: "12px 14px",
                border:
                  "1px solid #cfd8e3",
                borderRadius: "7px",
                fontSize: "15px",
                background: "white",
                marginBottom: "28px",
              }}
            >

              <option value={0}>
                0 — Both Ends Pinned
              </option>

              <option value={1}>
                1 — Fixed-Fixed
              </option>

              <option value={2}>
                2 — Fixed-Free
              </option>

              <option value={3}>
                3 — Fixed-Pinned
              </option>

            </select>

            <label
              style={{
                display: "block",
                fontWeight: 600,
                color: "#34455d",
                marginBottom: "8px",
              }}
            >
              Section Type
            </label>


            <select
              name="Sections"
              value={form.Sections}
              onChange={handleChange}
              style={{
                width: "100%",
                boxSizing: "border-box",
                padding: "12px 14px",
                border:
                  "1px solid #cfd8e3",
                borderRadius: "7px",
                fontSize: "15px",
                background: "white",
                marginBottom: "28px",
              }}
            >

              <option value="I">
                I-Section
              </option>

              <option value="C">
                C-Section
              </option>

            </select>

            <button
              onClick={handleDesign}
              disabled={loading}
              style={{
                width: "100%",
                padding: "13px",
                border: "none",
                borderRadius: "7px",
                background:
                  loading
                    ? "#8b9aad"
                    : "#1d5fa7",
                color: "white",
                fontWeight: 600,
                fontSize: "15px",
                cursor:
                  loading
                    ? "not-allowed"
                    : "pointer",
                display: "flex",
                alignItems: "center",
                justifyContent: "center",
                gap: "8px",
              }}
            >

              {loading ? (
                <>
                  <Loader2
                    size={18}
                    className="animate-spin"
                  />

                  Designing...
                </>
              ) : (
                <>
                  <CheckCircle2
                    size={18}
                  />

                  Design Column
                </>
              )}

            </button>


            <button
              onClick={handleReset}
              disabled={loading}
              style={{
                width: "100%",
                padding: "12px",
                marginTop: "10px",
                border:
                  "1px solid #cfd8e3",
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

        <div
          style={{
            background: "white",
            border:
              "1px solid #dce3eb",
            borderRadius: "10px",
            overflow: "hidden",
            minHeight: "650px",
          }}
        >

          <div
            style={{
              display: "flex",
              borderBottom:
                "1px solid #e2e7ed",
            }}
          >

            <button
              onClick={() =>
                setActiveTab("model")
              }
              style={{
                flex: 1,
                padding: "16px",
                border: "none",
                borderBottom:
                  activeTab === "model"
                    ? "3px solid #1d5fa7"
                    : "3px solid transparent",
                background: "white",
                color:
                  activeTab === "model"
                    ? "#1d5fa7"
                    : "#647894",
                fontWeight: 600,
                cursor: "pointer",
              }}
            >
              3D Model
            </button>


            <button
              onClick={() =>
                setActiveTab("report")
              }
              style={{
                flex: 1,
                padding: "16px",
                border: "none",
                borderBottom:
                  activeTab === "report"
                    ? "3px solid #1d5fa7"
                    : "3px solid transparent",
                background: "white",
                color:
                  activeTab === "report"
                    ? "#1d5fa7"
                    : "#647894",
                fontWeight: 600,
                cursor: "pointer",
              }}
            >
              Design Report
            </button>

          </div>

          {activeTab === "model" && (

            <div
              style={{
                padding: "24px",
              }}
            >

              {error && (

                <div
                  style={{
                    display: "flex",
                    gap: "10px",
                    alignItems: "flex-start",
                    padding: "14px",
                    marginBottom: "18px",
                    border:
                      "1px solid #f0b8b8",
                    background: "#fff4f4",
                    color: "#9b2c2c",
                    borderRadius: "7px",
                  }}
                >

                  <AlertCircle
                    size={20}
                  />

                  <div>
                    {error}
                  </div>

                </div>

              )}


              {/* VIEWER */}

              <div
                style={{
                  position: "relative",
                  height: "650px",
                  background: "#f5f7f9",
                  border:
                    "1px solid #e1e6ec",
                  borderRadius: "8px",
                  overflow: "hidden",
                }}
              >

                {geometry ? (

                  <ColumnViewer
                    geometry={geometry}
                    loading={meshLoading}
                  />

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
                        <Loader2
                          size={42}
                          className="animate-spin"
                        />

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


                        <div
                          style={{
                            marginTop: "7px",
                          }}
                        >
                          Run the column design
                          to generate the
                          3D model.
                        </div>

                      </>

                    )}

                  </div>

                )}

              </div>


              {/* QUICK RESULT */}

              {result && !result.error && (

                <div
                  style={{
                    marginTop: "20px",
                    display: "grid",
                    gridTemplateColumns:
                      "repeat(3, minmax(0, 1fr))",
                    gap: "12px",
                  }}
                >

                  <ResultCard
                    label="Selected Section"
                    value={
                      result.Designation ||
                      "-"
                    }
                  />

                  <ResultCard
                    label="Design Capacity"
                    value={
                      result.Design_Capacity_kN !==
                      undefined
                        ? `${formatValue(
                            result.Design_Capacity_kN
                          )} kN`
                        : "-"
                    }
                  />

                  <ResultCard
                    label="Section Type"
                    value={
                      result.Section_Type ||
                      "-"
                    }
                  />

                </div>

              )}

            </div>

          )}
          {activeTab === "report" && (

            <div
              style={{
                padding: "28px",
              }}
            >

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
                    style={{
                      marginBottom: "15px",
                      opacity: 0.5,
                    }}
                  />

                  <div>
                    Run the column design
                    to generate the report.
                  </div>

                </div>

              ) : (

                <>

                  {/* REPORT HEADER */}

                  <div
                    style={{
                      display: "flex",
                      justifyContent:
                        "space-between",
                      alignItems: "center",
                      marginBottom: "24px",
                    }}
                  >

                    <div>

                      <h2
                        style={{
                          margin: 0,
                          color: "#203047",
                        }}
                      >
                        Column Design Report
                      </h2>

                      <p
                        style={{
                          color: "#71839a",
                          marginBottom: 0,
                        }}
                      >
                        {result.Designation ||
                          "Designed Column"}
                      </p>

                    </div>


                    <button
                      onClick={
                        generateReport
                      }
                      disabled={
                        reportLoading
                      }
                      style={{
                        padding:
                          "10px 16px",
                        border: "none",
                        borderRadius: "7px",
                        background:
                          reportLoading
                            ? "#8b9aad"
                            : "#1d5fa7",
                        color: "white",
                        fontWeight: 600,
                        cursor:
                          reportLoading
                            ? "not-allowed"
                            : "pointer",
                        display: "flex",
                        alignItems:
                          "center",
                        gap: "8px",
                      }}
                    >

                      {reportLoading ? (
                        <>
                          <Loader2
                            size={16}
                            className="animate-spin"
                          />

                          Generating...
                        </>
                      ) : (
                        <>
                          <FileText
                            size={16}
                          />

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
                        border:
                          "1px solid #f0b8b8",
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
                          ].includes(key)
                      )
                      .map(
                        ([key, value]) => (

                          <div
                            key={key}
                            style={{
                              border:
                                "1px solid #e1e6ec",
                              borderRadius:
                                "7px",
                              padding: "14px",
                            }}
                          >

                            <div
                              style={{
                                fontSize: "12px",
                                color: "#71839a",
                                marginBottom:
                                  "5px",
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

                        )
                      )}

                  </div>


                  {/* LLM REPORT */}

                  {report && (<EngineeringReport report={report} />)}

                </>

              )}

            </div>

          )}

        </div>

      </div>

    </div>
  );
}
