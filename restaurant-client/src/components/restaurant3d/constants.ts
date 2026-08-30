import type { TableStatus, ZoneKind } from './types';

export const DEFAULT_VIEWBOX = { width: 1573, height: 1103 } as const;

export const SVG_SCALE = 0.01;

export const TABLE_TOP_HEIGHT = 0.18;

/** Minimum Y for feature meshes — sits clearly above floor texture */
export const FEATURE_BASE_Y = 0.04;

/** Opacity for floor 1 geometry visible below floor 2 */
export const FLOOR1_GHOST_OPACITY = 0.18;
export const FLOOR1_GHOST_TABLE_OPACITY = 0.14;
export const FLOOR1_STAIRS_OPACITY = 0.92;

/** Opacity for floor 2 preview above floor 1 */
export const FLOOR2_GHOST_OPACITY = 0.11;
export const FLOOR2_GHOST_TABLE_OPACITY = 0.09;

export const BAR_COUNTER_DEPTH_SVG = 52;
export const BAR_COUNTER_HEIGHT = 0.48;
export const STAGE_PLATFORM_HEIGHT = 0.44;
export const STAIR_TREAD_HEIGHT = 0.16;
export const STAIR_TREAD_RISE = 0.082;

/** Full rise of the 15-step stair run (floor 1 → floor 2) */
export const STAIR_STEP_COUNT = 15;
export const STAIR_TOTAL_RISE =
  (STAIR_STEP_COUNT - 1) * STAIR_TREAD_RISE + STAIR_TREAD_HEIGHT;

/** World Y of the floor 1 walking surface */
export const FLOOR1_Y = FEATURE_BASE_Y;

/** Vertical offset of the floor 2 slab — aligns with the top stair landing */
export const FLOOR2_ELEVATION = FEATURE_BASE_Y + STAIR_TOTAL_RISE - 0.01;

/** World Y of the floor 2 walking surface (top of stair run) */
export const FLOOR2_Y = FLOOR2_ELEVATION + FEATURE_BASE_Y;

export const ENTRANCE_DOOR_HEIGHT = 0.72;
export const ENTRANCE_FRAME_THICKNESS = 0.07;
export const POLE_HEIGHT = 1.08;

/**
 * Floor 2 pole zone id → floor 1 pole zone id.
 * Used when markers sit at different plan Y but share the same structural column (east/west).
 */
export const FLOOR2_FLOOR1_POLE_PAIRS: Record<string, string> = {
  'pole-pole1': 'pole-Pole-4',
  'pole-pole2': 'pole-Pole-3',
};

export const GLASS_WALL_HEIGHT = 0.52;
export const PHOTO_ZONE_HEIGHT = 0.06;
export const RAILING_HEIGHT = 0.42;
export const RESTROOM_WALL_HEIGHT = 0.34;

export const ZONE_HEIGHTS: Record<ZoneKind, number> = {
  wall: 0.32,
  structure: 0.34,
  bar: BAR_COUNTER_HEIGHT,
  stage: STAGE_PLATFORM_HEIGHT,
  stairs: 0.08,
  'stair-step': STAIR_TREAD_HEIGHT,
  entrance: ENTRANCE_DOOR_HEIGHT,
  pole: POLE_HEIGHT,
  arrow: 0.1,
  'glass-wall': GLASS_WALL_HEIGHT,
  'photo-zone': PHOTO_ZONE_HEIGHT,
  railing: RAILING_HEIGHT,
  restroom: RESTROOM_WALL_HEIGHT,
};

export const ZONE_COLORS: Record<ZoneKind, string> = {
  wall: '#ebe6dc',
  structure: '#7a7570',
  bar: '#ffffff',
  stage: '#14110e',
  stairs: '#9a9288',
  'stair-step': '#b8aea0',
  entrance: '#c9a060',
  pole: '#2e2e2e',
  arrow: '#d4bc82',
  'glass-wall': '#e2c9d7',
  'photo-zone': '#1a1816',
  railing: '#b8b0a6',
  restroom: '#7a7570',
};

export const ZONE_EMISSIVE: Record<ZoneKind, string> = {
  wall: '#000000',
  structure: '#000000',
  bar: '#6b4428',
  stage: '#5c3d20',
  stairs: '#000000',
  'stair-step': '#8a7a68',
  entrance: '#e8c878',
  pole: '#000000',
  arrow: '#e0c878',
  'glass-wall': '#c8a8b8',
  'photo-zone': '#5c3d20',
  railing: '#000000',
  restroom: '#000000',
};

export const FLOOR_Y = 0;

/** Single backdrop color — canvas, page chrome, both floors */
export const SCENE_BACKGROUND = '#121410';

/** @deprecated Use SCENE_BACKGROUND — kept for imports */
export const SCENE_BACKGROUND_FLOOR2 = SCENE_BACKGROUND;

/** Floor island — warm gray slab, fades into the backdrop at the edges */
export const FLOOR_SURFACE = '#d8d2c8';

/** Floor 2 slab — cooler medium gray */
export const FLOOR_SURFACE_FLOOR2 = '#b0aaa2';

/** Fill colors for sit-floor paths drawn inside zone-sit */
export const SIT_FLOOR_FILL_COLORS = ['#d4c4a8', '#c8e6c9', '#e8dcc8', '#b8d4a8'] as const;

export const STATUS_COLORS: Record<TableStatus, string> = {
  available: '#4ade80',
  reserved: '#f87171',
  pending: '#facc15',
  unknown: '#c0ad7b',
};

export const STATUS_EMISSIVE: Record<TableStatus, string> = {
  available: '#22c55e',
  reserved: '#ef4444',
  pending: '#eab308',
  unknown: '#a89763',
};

export const HOVER_SCALE = 1;
export const SELECTED_SCALE = 1;
export const ANIMATION_SPEED = 8;

/** Orange highlight for selected tables */
export const SELECTED_COLOR = '#f97316';
export const SELECTED_EMISSIVE = '#ea580c';
export const SELECTED_RING_COLOR = '#fb923c';
export const HOVER_RING_COLOR = '#fdba74';

export const CIRCLE_ASPECT_MIN = 0.72;
export const CIRCLE_ASPECT_MAX = 1.38;
export const CIRCLE_MAX_DIMENSION = 42;
