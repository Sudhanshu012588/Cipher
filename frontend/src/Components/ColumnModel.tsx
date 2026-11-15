<<<<<<< HEAD
import "@react-three/fiber";
import type { ColumnModelProps } from "../types";

export default function ColumnModel({ geometry }: ColumnModelProps) {
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
=======

import * as THREE from "three";
import "@react-three/fiber"; // Adds the Three.js JSX types
import type { ColumnModelProps } from "../types";

export default function ColumnModel({ geometry }: ColumnModelProps) {
  return (
    <mesh geometry={geometry} castShadow receiveShadow>
      <meshStandardMaterial
        side={THREE.DoubleSide}
        metalness={0.15}
        roughness={0.6}
      />
    </mesh>
  );
>>>>>>> sukirti
}