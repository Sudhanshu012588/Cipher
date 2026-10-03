export default function ResultCard({label,value,}: {label: string;value: string;}) {
  return (
    <div style={{
        border:
          "1px solid #e1e6ec",
        borderRadius: "8px",
        padding: "16px",
        background: "white",
      }}
    >

      <div
        style={{
          fontSize: "12px",
          color: "#71839a",
          marginBottom: "6px",
        }}
      >
        {label}
      </div>


      <div
        style={{
          fontSize: "17px",
          fontWeight: 700,
          color: "#203047",
        }}
      >
        {value}
      </div>

    </div>

  );
}