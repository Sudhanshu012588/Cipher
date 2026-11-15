import "@react-three/fiber";
import type { BeamFEMModelProps } from "../types";

export default function BeamFEMModel({ geometry }: BeamFEMModelProps) {
  const hasVertexColors = Boolean(geometry?.attributes?.color);

  return (
    <mesh geometry={geometry} castShadow receiveShadow>
      <meshStandardMaterial
        color={hasVertexColors ? "#ffffff" : "#94a3b8"}
        vertexColors={hasVertexColors}
        metalness={hasVertexColors ? 0.1 : 0.6}
        roughness={hasVertexColors ? 0.45 : 0.35}
      />
    </mesh>
  );
}
