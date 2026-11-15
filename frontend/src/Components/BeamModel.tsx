import * as THREE from "three";
import "@react-three/fiber";

interface BeamModelProps {
  geometry: THREE.BufferGeometry;
}

export default function BeamModel({ geometry }: BeamModelProps) {
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

