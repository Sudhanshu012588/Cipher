import { useRef, useState } from "react";
import ReactMarkdown from "react-markdown";
import html2pdf from "html2pdf.js";

interface EngineeringReportProps {
  report: string;
}

export default function EngineeringReport({
  report,
}: EngineeringReportProps) {
  const reportRef = useRef<HTMLDivElement>(null);
  const [downloading, setDownloading] = useState(false);

  if (!report) {
    return null;
  }

  const downloadPDF = async () => {
    if (!reportRef.current) {
      return;
    }

    try {
      setDownloading(true);

      const element = reportRef.current;

      const options = {
  margin: [12, 12, 12, 12] as [
    number,
    number,
    number,
    number
  ],

  filename: "Column_Engineering_Report.pdf",

  image: {
    type: "jpeg" as const,
    quality: 0.98,
  },

  html2canvas: {
    scale: 2,
    useCORS: true,
    logging: false,
    backgroundColor: "#ffffff",
  },

  jsPDF: {
    unit: "mm" as const,
    format: "a4" as const,
    orientation: "portrait" as const,
  },

  pagebreak: {
    mode: ["avoid-all", "css", "legacy"] as const,
  },
};

      await html2pdf()
        .set(options)
        .from(element)
        .save();

    } catch (error) {

      console.error(
        "PDF generation failed:",
        error
      );

    } finally {

      setDownloading(false);

    }
  };


  return (
    <div
      ref={reportRef}
      style={{
        background: "#ffffff",
        border: "1px solid #dce3eb",
        borderRadius: "10px",
        padding: "28px 32px",
        color: "#34455d",
        lineHeight: 1.7,
        fontSize: "15px",
      }}
    >
      <div
        style={{
          display: "flex",
          justifyContent: "space-between",
          alignItems: "center",
          marginBottom: "20px",
          paddingBottom: "14px",
          borderBottom:
            "1px solid #e2e7ed",
        }}
      >

        <div>

          <h2
            style={{
              margin: 0,
              color: "#203047",
              fontSize: "22px",
            }}
          >
            Engineering Report
          </h2>

          <div
            style={{
              marginTop: "4px",
              color: "#71839a",
              fontSize: "13px",
            }}
          >
            Project Cipher — Column Design
          </div>

        </div>
        <button
          data-html2canvas-ignore="true"
          onClick={downloadPDF}
          disabled={downloading}
          style={{
            padding: "10px 16px",
            background: downloading
              ? "#8b9aad"
              : "#1d5fa7",
            color: "white",
            border: "none",
            borderRadius: "7px",
            fontSize: "14px",
            fontWeight: 600,
            cursor: downloading
              ? "not-allowed"
              : "pointer",
          }}
        >
          {downloading
            ? "Generating PDF..."
            : "↓ Download PDF"}
        </button>

      </div>
      <ReactMarkdown
        components={{

          h2: ({ children }) => (
            <h2
              style={{
                marginTop: "26px",
                marginBottom: "14px",
                paddingBottom: "8px",
                borderBottom:
                  "1px solid #e2e7ed",
                color: "#203047",
                fontSize: "20px",
                fontWeight: 700,
                breakAfter: "avoid",
              }}
            >
              {children}
            </h2>
          ),

          h3: ({ children }) => (
            <h3
              style={{
                color: "#203047",
                marginTop: "20px",
                marginBottom: "10px",
                fontSize: "17px",
              }}
            >
              {children}
            </h3>
          ),

          p: ({ children }) => (
            <p
              style={{
                margin: "8px 0",
              }}
            >
              {children}
            </p>
          ),

          ul: ({ children }) => (
            <ul
              style={{
                margin: "8px 0 18px 0",
                paddingLeft: "24px",
              }}
            >
              {children}
            </ul>
          ),

          li: ({ children }) => (
            <li
              style={{
                marginBottom: "8px",
                paddingLeft: "4px",
              }}
            >
              {children}
            </li>
          ),

          strong: ({ children }) => (
            <strong
              style={{
                color: "#203047",
                fontWeight: 700,
              }}
            >
              {children}
            </strong>
          ),

          code: ({ children }) => (
            <code
              style={{
                background: "#f1f4f7",
                padding: "2px 6px",
                borderRadius: "4px",
                fontSize: "13px",
              }}
            >
              {children}
            </code>
          ),
        }}
      >
        {report}
      </ReactMarkdown>

    </div>
  );
}