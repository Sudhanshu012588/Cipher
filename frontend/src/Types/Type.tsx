export  interface DesignForm {
  Length: number;
  Fac_Axial_Load: number;
  Boundary_Condition: number;
  Sections: string;
}

export  interface DesignResult {
  [key: string]: any;

  Designation?: string;
  Section_Type?: string;

  Length_m?: number;
  Axial_Load_kN?: number;
  Effective_Length_m?: number;

  Depth_mm?: number;
  Width_mm?: number;
  tw_mm?: number;
  tf_mm?: number;

  Section_Area_mm2?: number;
  Section_Mass_kg_m?: number;

  Plate_Thickness_mm?: number;
  Plate_Width_mm?: number;

  Composite_Area_mm2?: number;

  Design_Capacity_kN?: number;
  f_cd_MPa?: number;

  Status?: string;

  mesh_file?: string;
  stl_file?: string;
  mesh_url?: string;
  stl_url?: string;

  error?: string;
  message?: string;
}