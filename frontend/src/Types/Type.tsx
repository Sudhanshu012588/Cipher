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

export interface BeamDesignForm {
  Span: number;      // m
  wu: number;        // kN/m — factored UDL
  Wu: number;        // kN — factored point load at midspan (0 if none)
  b1: number;        // mm — stiff bearing length
}

export interface BeamDesignResult {
  [key: string]: any;

  Span_m?: number;
  wu_kN_m?: number;
  Wu_kN?: number;
  b1_mm?: number;

  M_u_kNm?: number;
  V_u_s_kN?: number;
  V_u_m_kN?: number;

  fy_MPa?: number;
  gamma_m0?: number;

  Zp_reqd_mm3?: number;

  Designation?: string;
  Section_Type?: string;
  Mass_kg_m?: number;

  Depth_mm?: number;
  Width_mm?: number;
  tw_mm?: number;
  tf_mm?: number;

  Ix_cm4?: number;
  Iy_cm4?: number;
  Zx_cm3?: number;
  rx_cm?: number;
  ry_cm?: number;
  Area_mm2?: number;

  Zp_mm3?: number;
  Ze_mm3?: number;

  Section_Class?: string;

  A_v_mm2?: number;
  V_d_kN?: number;
  High_Shear?: boolean;
  M_d_kNm?: number;

  delta_mm?: number;
  delta_limit_mm?: number;

  F_w_kN?: number;

  Shear_Check?: string;
  Moment_Check?: string;
  Deflection_Check?: string;
  Web_Crippling_Check?: string;

  Status?: string;

  mesh_file?: string;
  stl_file?: string;
  mesh_url?: string;
  stl_url?: string;

  error?: string;
  message?: string;
}