import React from "react";

export const inputStyle: React.CSSProperties = {
  width: "100%",
  boxSizing: "border-box",
  height: "46px",
  padding: "0 52px 0 14px",
  border: "1px solid #cbd7e5",
  borderRadius: "7px",
  background: "white",
  color: "#203047",
  fontSize: "16px",
  outline: "none",
};

export const unitStyle: React.CSSProperties = {
  position: "absolute",
  right: "14px",
  top: "50%",
  transform: "translateY(-50%)",
  color: "#91a1b5",
  pointerEvents: "none",
};

export const tabStyle = (active: boolean): React.CSSProperties => ({
  padding: "17px 28px",
  border: "none",
  borderBottom: active ? "3px solid #ff4b0b" : "3px solid transparent",
  background: "white",
  color: active ? "#ff4b0b" : "#60738c",
  fontWeight: active ? 700 : 500,
  cursor: "pointer",
  fontSize: "15px",
});

