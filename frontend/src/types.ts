import * as THREE from "three";

export interface DesignForm {
  Length: number;
  Fac_Axial_Load: number;
  Boundary_Condition: number;
  Sections: string;
}

export interface DesignResult {
  [key: string]: any;
}

export interface ColumnModelProps {
  geometry: THREE.BufferGeometry;
}

export interface ColumnViewerProps {
  geometry: THREE.BufferGeometry | null;
  loading: boolean;
}

