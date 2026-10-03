
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
}