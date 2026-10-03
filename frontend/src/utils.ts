export function formatKey(key: string) {
  return key
    .replace(/_/g, " ")
    .replace(/\b\w/g, c => c.toUpperCase());
}

export function formatValue(value: any) {
  if (typeof value === "number") {
    return Number.isInteger(value) ? value : value.toFixed(3);
  }
  if (typeof value === "boolean") {
    return value ? "Yes" : "No";
  }
  return String(value);
}

