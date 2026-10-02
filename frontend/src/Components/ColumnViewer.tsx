
import { Canvas } from "@react-three/fiber";
import { OrbitControls, Grid, Bounds } from "@react-three/drei";
import type { ColumnViewerProps } from "../types";
import ColumnModel from "./ColumnModel";

export default function ColumnViewer({ geometry, loading }: ColumnViewerProps) {
  return (
    <div style={{ width: "100%", height: "100%", minHeight: "600px" }}>
      <Canvas shadows camera={{ position: [4, 3, 5], fov: 45 }}>
        <color attach="background" args={["#f6f8fa"]} />
        
        <ambientLight intensity={1.5} />
        <directionalLight position={[5, 8, 5]} intensity={2.5} castShadow />
        <directionalLight position={[-5, 3, -5]} intensity={1} />

        {geometry && (
          <Bounds fit clip observe margin={1.2}>
            <ColumnModel geometry={geometry} />
          </Bounds>
        )}

        <Grid
          args={[10, 20]}
          cellSize={0.5}
          cellThickness={0.5}
          sectionSize={2}
          sectionThickness={1}
          fadeDistance={20}
          fadeStrength={1}
          infiniteGrid
        />

        <OrbitControls makeDefault enableDamping dampingFactor={0.08} />
      </Canvas>

      {loading && (
        <div
          style={{
            position: "absolute",
            inset: 0,
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            pointerEvents: "none",
          }}
        >
          <div>Loading 3D model...</div>
        </div>
      )}
    </div>
  );
}