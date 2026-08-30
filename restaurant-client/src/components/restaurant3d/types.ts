export type TableStatus = 'available' | 'reserved' | 'pending' | 'unknown';

export type SurfaceShape = 'box' | 'cylinder';

export type FloorId = 'floor1' | 'floor2';

export type ZoneKind =
  | 'wall'
  | 'bar'
  | 'stage'
  | 'structure'
  | 'stairs'
  | 'stair-step'
  | 'entrance'
  | 'pole'
  | 'arrow'
  | 'glass-wall'
  | 'photo-zone'
  | 'railing'
  | 'restroom';

export interface SvgBBox {
  x: number;
  y: number;
  width: number;
  height: number;
}

export interface TableSurface {
  shape: SurfaceShape;
  bbox: SvgBBox;
}

export interface SvgTable {
  id: string;
  bbox: SvgBBox;
  surfaces: TableSurface[];
  chairs: SvgBBox[];
}

export interface FloorZone {
  id: string;
  label: string;
  kind: ZoneKind;
  bbox: SvgBBox;
  fill?: string;
  shape?: SurfaceShape;
  /** 1-based index for progressive stair height */
  stepIndex?: number;
}

export interface FloorSlab {
  id: string;
  bbox: SvgBBox;
  /** When set, render the exact SVG path instead of a rectangular bbox */
  pathD?: string;
}

export interface FloorPlanData {
  floorId: FloorId;
  viewBox: { width: number; height: number };
  /** Registration point shared with the other floor (`floor-align-dot` in SVG) */
  alignAnchor?: { x: number; y: number };
  tables: SvgTable[];
  zones: FloorZone[];
  boundary: SvgBBox;
  /** Floor 2 stairwell cutout in SVG coordinates */
  stairOpening?: SvgBBox;
  /** Walkable floor regions from floor-bg (SVG coordinates) */
  floorSlabs?: FloorSlab[];
  /** Railing geometry parsed from floor SVG */
  railingSegments?: RailingSegment[];
  /** Floor 2 restroom units (men / women, 2 stalls each) */
  restrooms?: RestroomUnit[];
}

export type RestroomGender = 'man' | 'woman';

export interface RestroomStall {
  id: string;
  bbox: SvgBBox;
  /** Toilet footprint from `wc-*-bath` rect in the SVG */
  bathBBox?: SvgBBox;
}

export interface RestroomUnit {
  id: string;
  gender: RestroomGender;
  label: string;
  bounds: SvgBBox;
  stalls: RestroomStall[];
}

export type RailingVariant = 'handrail' | 'stair-lip' | 'connector';

export interface RailingSegment {
  points: [number, number][];
  kind: 'rail' | 'post';
  /** Render as a smooth tube (rounded balcony curve) */
  smooth?: boolean;
  variant?: RailingVariant;
  /** `world` = stair lips spanning floor 1 → floor 2 (not elevated with the slab) */
  space?: 'floor2' | 'world';
  /** West end at floor-1 stair lip, east end at handrail (north lip / balcony join) */
  slopeFromStairBottom?: boolean;
  /** Full-span SVG X for sloped rails (posts only have one point) */
  slopeXRange?: { minX: number; maxX: number };
}

export interface BackendTable {
  id: string;
  tableNumber: string;
  capacity: number;
  isActive: boolean;
}

export interface TableAvailability {
  id: string;
  tableNumber: string;
  capacity: number;
  isAvailable: boolean;
  bookedTimeSlots: string[];
}

export interface TableState {
  id: string;
  tableNumber: string;
  status: TableStatus;
  capacity?: number;
}
