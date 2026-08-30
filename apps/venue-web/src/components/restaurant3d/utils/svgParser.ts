import {
  BAR_COUNTER_DEPTH_SVG,
  CIRCLE_ASPECT_MAX,
  CIRCLE_ASPECT_MIN,
  CIRCLE_MAX_DIMENSION,
  DEFAULT_VIEWBOX,
} from '../constants';
import type { FloorId, FloorPlanData, FloorSlab, FloorZone, RailingSegment, RestroomStall, RestroomUnit, SurfaceShape, SvgBBox, SvgTable, TableSurface, ZoneKind } from '../types';
import { setViewBox } from './coordinates';
import { mergeBboxes, parsePathBounds } from './pathBounds';
import { chainPolylines, parsePathPolyline, parsePathSubpaths } from './svgPathPoints';

function readAttr(attrs: string, name: string): string | null {
  const match = attrs.match(new RegExp(`\\b${name}="([^"]*)"`));
  return match?.[1] ?? null;
}

function toBBox(raw: { x: number; y: number; width: number; height: number }): SvgBBox {
  return { x: raw.x, y: raw.y, width: raw.width, height: raw.height };
}

function parseViewBox(svg: string): { width: number; height: number } {
  const parts = svg.match(/viewBox="([^"]+)"/)?.[1]?.trim().split(/\s+/).map(Number);
  if (parts && parts.length === 4) {
    return { width: parts[2], height: parts[3] };
  }
  return { ...DEFAULT_VIEWBOX };
}

/** `floor-align-dot` — shared registration point between floor 1 and floor 2 SVGs */
function parseAlignAnchor(
  svg: string,
  floorId: FloorId,
  viewBox: { width: number; height: number },
): { x: number; y: number } | undefined {
  const tagMatch = svg.match(/<circle\b[^>]*\bid="floor-align-dot"[^>]*\/?>/i);
  if (tagMatch) {
    const tag = tagMatch[0];
    const cx = readAttr(tag, 'cx');
    const cy = readAttr(tag, 'cy');
    if (cx && cy) {
      const x = parseFloat(cx);
      const y = parseFloat(cy);
      if (Number.isFinite(x) && Number.isFinite(y)) return { x, y };
    }
  }

  if (floorId === 'floor2') {
    const steps = buildStairsFloor2(svg);
    const runBBox = mergeBboxes(steps.map((s) => s.bbox));
    if (runBBox) return { x: runBBox.x, y: runBBox.y };
  } else {
    const steps = buildStairs(svg, viewBox);
    const runBBox = mergeBboxes(steps.map((s) => s.bbox));
    if (runBBox) return { x: runBBox.x, y: runBBox.y };
  }

  return undefined;
}

function extractGroupChunk(svg: string, id: string): string {
  const idEsc = id.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const openMatch = svg.match(new RegExp(`<g\\s+id="${idEsc}"[^>]*>`, 'i'));
  if (!openMatch || openMatch.index === undefined) return '';
  const start = openMatch.index;

  let depth = 0;
  for (let i = start; i < svg.length; i += 1) {
    if (svg.startsWith('<g', i) && !svg.startsWith('<g/', i)) depth += 1;
    if (svg.startsWith('</g>', i)) {
      depth -= 1;
      if (depth === 0) return svg.slice(start, i + 4);
    }
  }
  return '';
}

function boundsFromChunk(chunk: string, viewBox: { width: number; height: number }): SvgBBox | null {
  const boxes: SvgBBox[] = [];

  for (const match of chunk.matchAll(/<path\b([^>]*)\/?>/g)) {
    const d = readAttr(match[1], 'd');
    if (!d) continue;
    const bbox = parsePathBounds(d);
    if (!bbox) continue;
    if (bbox.width > viewBox.width * 0.8 || bbox.height > viewBox.height * 0.8) continue;
    boxes.push(toBBox(bbox));
  }

  return mergeBboxes(boxes);
}

function classifySurface(bbox: SvgBBox): SurfaceShape {
  const aspect = bbox.width / Math.max(bbox.height, 0.001);
  const maxDim = Math.max(bbox.width, bbox.height);
  if (aspect >= CIRCLE_ASPECT_MIN && aspect <= CIRCLE_ASPECT_MAX && maxDim <= CIRCLE_MAX_DIMENSION) {
    return 'cylinder';
  }
  return 'box';
}

function zoneFromBounds(
  id: string,
  label: string,
  kind: ZoneKind,
  bbox: SvgBBox | null,
  extra?: Partial<FloorZone>,
  minSize = 2,
): FloorZone | null {
  if (!bbox || bbox.width < minSize || bbox.height < minSize) return null;
  return { id, label, kind, bbox, ...extra };
}

function expandThinBBox(bbox: SvgBBox, minW = 2, minH = 2): SvgBBox {
  let { x, y, width, height } = bbox;
  if (width < minW) {
    x -= (minW - width) / 2;
    width = minW;
  }
  if (height < minH) {
    y -= (minH - height) / 2;
    height = minH;
  }
  return { x, y, width, height };
}

function filledPathsInChunk(
  chunk: string,
  viewBox: { width: number; height: number },
  allowedFills: string[],
  wallGroup?: string,
): FloorZone[] {
  const zones: FloorZone[] = [];

  for (const match of chunk.matchAll(/<path\b([^>]*)\/?>/g)) {
    const attrs = match[1];
    const fill = (readAttr(attrs, 'fill') ?? '').toLowerCase();
    const d = readAttr(attrs, 'd') ?? '';
    const pathId = readAttr(attrs, 'id') ?? `path-${zones.length}`;

    if (!allowedFills.includes(fill)) continue;
    if (!/[zZ]\s*$/.test(d.trim())) continue;

    const bbox = parsePathBounds(d);
    if (!bbox) continue;

    const isThinSpan =
      (bbox.width > viewBox.width * 0.8 && bbox.height < viewBox.height * 0.08) ||
      (bbox.height > viewBox.height * 0.8 && bbox.width < viewBox.width * 0.08);
    if (
      !isThinSpan &&
      (bbox.width > viewBox.width * 0.8 || bbox.height > viewBox.height * 0.8)
    ) {
      continue;
    }
    if (bbox.width < 3 && bbox.height < 3) continue;

    zones.push({
      id: wallGroup ? `${wallGroup}-${pathId}` : `wall-${pathId}`,
      label: 'Wall',
      kind: fill === '#6a6a6a' ? 'structure' : 'wall',
      bbox: toBBox(bbox),
      fill,
    });
  }

  return zones;
}

/** Door lintel above the stair opening — kept on the floor texture only, not as a 3D block */
const EXCLUDED_WALL_PATH_SUFFIXES = ['path978'];

function isExcludedWallZone(zone: FloorZone): boolean {
  return EXCLUDED_WALL_PATH_SUFFIXES.some((suffix) => zone.id.endsWith(suffix));
}

function buildWalls(svg: string, viewBox: { width: number; height: number }): FloorZone[] {
  const wallsRoot = extractGroupChunk(svg, 'walls');
  if (!wallsRoot) return [];

  const wallIds = [...wallsRoot.matchAll(/<g id="(wall\d+)">/g)].map((m) => m[1]);
  const zones: FloorZone[] = [];

  for (const wallId of wallIds) {
    const chunk = extractGroupChunk(wallsRoot, wallId);
    zones.push(...filledPathsInChunk(chunk, viewBox, ['white', '#6a6a6a'], wallId));
  }

  return zones.filter((z) => !isExcludedWallZone(z));
}

const ENTRANCE_SKIP_PATH_IDS = new Set([
  'path632',
  'path760',
  'path638',
  'path766',
  'path682',
  'path810',
]);

function buildEntrance(svg: string, viewBox: { width: number; height: number }): FloorZone[] {
  const chunk = extractGroupChunk(svg, 'entrance');
  if (!chunk) return [];

  const boxes: SvgBBox[] = [];
  for (const match of chunk.matchAll(/<path\b([^>]*)\/?>/g)) {
    const attrs = match[1];
    const pathId = readAttr(attrs, 'id') ?? '';
    if (ENTRANCE_SKIP_PATH_IDS.has(pathId)) continue;

    const d = readAttr(attrs, 'd') ?? '';
    if (!d || /[Cc]/.test(d)) continue;

    const bbox = parsePathBounds(d);
    if (!bbox || bbox.width > viewBox.width * 0.05) continue;
    if (bbox.x + bbox.width > 305) continue;
    boxes.push(toBBox(bbox));
  }

  const splitY = 595;
  const upper = boxes.filter((b) => b.y + b.height / 2 < splitY);
  const lower = boxes.filter((b) => b.y + b.height / 2 >= splitY);
  const zones: FloorZone[] = [];

  const upperBBox = mergeBboxes(upper);
  const lowerBBox = mergeBboxes(lower);
  const upperZone = zoneFromBounds('entrance-upper', 'Entrance', 'entrance', upperBBox);
  const lowerZone = zoneFromBounds('entrance-lower', 'Entrance', 'entrance', lowerBBox);
  if (upperZone) zones.push(upperZone);
  if (lowerZone) zones.push(lowerZone);

  return zones;
}

function buildStage(svg: string, viewBox: { width: number; height: number }): FloorZone[] {
  const chunk = extractGroupChunk(svg, 'zone-stage');
  const bbox = boundsFromChunk(chunk, viewBox);
  const platform = zoneFromBounds('zone-stage-platform', 'Stage', 'stage', bbox);
  return platform ? [platform] : [];
}

/** Stroke lines (bar outline, etc.) have zero thickness — expand to a solid footprint */
function expandStrokeToBBox(d: string, thicknessSvg: number): SvgBBox | null {
  const raw = parsePathBounds(d);
  if (!raw) return null;

  if (raw.width < 2) {
    return {
      x: raw.x - thicknessSvg / 2,
      y: raw.y,
      width: thicknessSvg,
      height: Math.max(raw.height, thicknessSvg),
    };
  }
  if (raw.height < 2) {
    return {
      x: raw.x,
      y: raw.y - thicknessSvg / 2,
      width: Math.max(raw.width, thicknessSvg),
      height: thicknessSvg,
    };
  }
  return toBBox(raw);
}

function buildBar(svg: string): FloorZone[] {
  const chunk = extractGroupChunk(svg, 'zone-bar');
  if (!chunk) return [];

  const zones: FloorZone[] = [];
  for (const match of chunk.matchAll(/<path\b([^>]*)\/?>/g)) {
    const attrs = match[1];
    const d = readAttr(attrs, 'd');
    const pathId = readAttr(attrs, 'id') ?? `seg-${zones.length}`;
    if (!d) continue;

    const bbox = expandStrokeToBBox(d, BAR_COUNTER_DEPTH_SVG);
    if (!bbox || bbox.width < 3 || bbox.height < 3) continue;

    zones.push({
      id: `bar-${pathId}`,
      label: 'Bar',
      kind: 'bar',
      bbox,
      shape: 'box',
    });
  }

  return zones;
}

function buildStairsFromChunk(chunk: string, viewBox: { width: number; height: number }): FloorZone[] {
  const zones: FloorZone[] = [];
  const stepIds = [...chunk.matchAll(/<g id="(step\d+)">/g)].map((m) => m[1]);

  for (const stepId of stepIds) {
    const stepChunk = extractGroupChunk(chunk, stepId);
    const bbox = boundsFromChunk(stepChunk, viewBox);
    const stepIndex = parseInt(stepId.replace(/\D/g, ''), 10);
    const zone = zoneFromBounds(`stairs-${stepId}`, `Step ${stepIndex}`, 'stair-step', bbox, {
      stepIndex,
    });
    if (zone) zones.push(zone);
  }

  return zones;
}

function buildStairs(svg: string, viewBox: { width: number; height: number }): FloorZone[] {
  const chunk = extractGroupChunk(svg, 'zone-stairs');
  if (!chunk) return [];
  return buildStairsFromChunk(chunk, viewBox);
}

function buildPoles(svg: string, viewBox: { width: number; height: number }): FloorZone[] {
  const chunk = extractGroupChunk(svg, 'zone-poles');
  if (!chunk) return [];

  const poleIds = [...chunk.matchAll(/<g id="(Pole \d+)">/g)].map((m) => m[1]);
  const zones: FloorZone[] = [];

  for (const poleId of poleIds) {
    const poleChunk = extractGroupChunk(chunk, poleId);
    const bbox = boundsFromChunk(poleChunk, viewBox);
    const zone = zoneFromBounds(`pole-${poleId.replace(/\s/g, '-')}`, poleId, 'pole', bbox, {
      shape: 'cylinder',
    });
    if (zone) zones.push(zone);
  }

  return zones;
}

function isChairMarker(bbox: SvgBBox): boolean {
  const maxDim = Math.max(bbox.width, bbox.height);
  const minDim = Math.min(bbox.width, bbox.height);
  return maxDim < 22 && minDim < 6;
}

function isTableTop(bbox: SvgBBox): boolean {
  const maxDim = Math.max(bbox.width, bbox.height);
  const minDim = Math.min(bbox.width, bbox.height);
  return maxDim >= 15 && minDim >= 8;
}

function resolveTablesScope(svg: string): string {
  for (const layerId of ['tablesLayer_2', 'tablesLayer']) {
    const layer = extractGroupChunk(svg, layerId);
    if (layer) return layer;
  }
  return svg;
}

function buildTables(svg: string, tableIdPrefix = ''): SvgTable[] {
  const scope = resolveTablesScope(svg);
  const tableIds = [...new Set([...scope.matchAll(/<g id="(table\d+)">/g)].map((m) => m[1]))];
  const tables: SvgTable[] = [];

  for (const rawId of tableIds) {
    const id = tableIdPrefix ? `${tableIdPrefix}${rawId}` : rawId;
    const chunk = extractGroupChunk(scope, rawId);
    if (!chunk) continue;

    const surfaces: TableSurface[] = [];
    const chairs: SvgBBox[] = [];

    for (const match of chunk.matchAll(/<path\b([^>]*)\/?>/g)) {
      const attrs = match[1];
      const fill = readAttr(attrs, 'fill');
      const d = readAttr(attrs, 'd') ?? '';
      if (fill?.toLowerCase() !== 'white' || !/[zZ]\s*$/.test(d.trim())) continue;

      const bbox = parsePathBounds(d);
      if (!bbox || bbox.width < 0.8 || bbox.height < 0.8) continue;
      const box = toBBox(bbox);

      if (isChairMarker(box)) {
        chairs.push(box);
        continue;
      }
      if (!isTableTop(box)) continue;

      surfaces.push({ shape: classifySurface(box), bbox: box });
    }

    const bbox = mergeBboxes([
      ...surfaces.map((s) => s.bbox),
      ...chairs,
    ]);
    if (!bbox || !surfaces.length) continue;
    tables.push({ id, bbox, surfaces, chairs });
  }

  return tables.sort(
    (a, b) => parseInt(a.id.replace(/\D/g, ''), 10) - parseInt(b.id.replace(/\D/g, ''), 10),
  );
}

function buildBoundary(svg: string): SvgBBox {
  const boundaryIds = ['path632', 'path36', 'path1048'];
  for (const id of boundaryIds) {
    const match = svg.match(new RegExp(`<path[^>]*\\bid="${id}"[^>]*\\bd="([^"]+)"`));
    if (match) {
      const bbox = parsePathBounds(match[1]);
      if (bbox) return toBBox(bbox);
    }
  }
  return { x: 0, y: 0, width: DEFAULT_VIEWBOX.width, height: DEFAULT_VIEWBOX.height };
}

// ─── Floor 2 (floor2.svg) builders ──────────────────────────────────────────

const FLOOR2_GLASS_FILLS = ['#e2c9d7', '#bfbfbf'];

function buildWallsFloor2(svg: string, viewBox: { width: number; height: number }): FloorZone[] {
  const wallIds = [...new Set([...svg.matchAll(/<g id="(wall\d+)">/g)].map((m) => m[1]))];
  const zones: FloorZone[] = [];

  for (const wallId of wallIds) {
    const chunk = extractGroupChunk(svg, wallId);
    zones.push(...filledPathsInChunk(chunk, viewBox, ['white', '#6a6a6a'], wallId));
  }

  return zones.filter((z) => !isExcludedWallZone(z));
}

function buildRestroomWalls(svg: string, viewBox: { width: number; height: number }): FloorZone[] {
  const zones: FloorZone[] = [];

  for (const wcId of ['wc-man', 'wc-woman']) {
    const wcChunk = extractGroupChunk(svg, wcId);
    if (!wcChunk) continue;

    const wcBoxes: SvgBBox[] = [];
    const wcWallIds = [...wcChunk.matchAll(/<g id="(wc-wall[^"]*)">/g)].map((m) => m[1]);
    for (const wallId of wcWallIds) {
      const chunk = extractGroupChunk(wcChunk, wallId);
      const wallZones = filledPathsInChunk(chunk, viewBox, ['#6a6a6a', 'white']);
      zones.push(...wallZones);
      wcBoxes.push(...wallZones.map((z) => z.bbox));
    }

    const merged = mergeBboxes(wcBoxes);
    const label = wcId === 'wc-man' ? "Men's WC" : "Women's WC";
    const marker = zoneFromBounds(`${wcId}-marker`, label, 'restroom', merged);
    if (marker) zones.push(marker);
  }

  return zones;
}

const WC_UNIT_CONFIG: Record<
  string,
  { gender: RestroomUnit['gender']; label: string; dividerId?: string; splitVertical?: boolean }
> = {
  'wc-man': { gender: 'man', label: "Men's WC", dividerId: 'wc-wall_5' },
  'wc-woman': { gender: 'woman', label: "Women's WC", dividerId: 'wc-wall_10' },
};

function stallsSplitVertically(stalls: RestroomStall[]): boolean {
  if (stalls.length < 2) return true;
  const [a, b] = stalls.map((s) => s.bbox);
  const ax = a.x + a.width / 2;
  const bx = b.x + b.width / 2;
  const ay = a.y + a.height / 2;
  const by = b.y + b.height / 2;
  return Math.abs(ax - bx) > Math.abs(ay - by);
}

function sortBboxesForStalls(bboxes: SvgBBox[], vertical: boolean): SvgBBox[] {
  return [...bboxes].sort((a, b) => (vertical ? a.x - b.x : a.y - b.y));
}

function buildWcBathRects(svg: string): Record<string, SvgBBox[]> {
  const baths: Record<string, SvgBBox[]> = { 'wc-man': [], 'wc-woman': [] };

  for (const match of svg.matchAll(/<rect\b([^>]*)\/?>/gi)) {
    const id = readAttr(match[1], 'id') ?? '';
    if (!/^wc-(man|woman)-bath(?:_\d+)?$/i.test(id)) continue;
    const bbox = readRectBBox(match[0]);
    if (!bbox) continue;
    const wcId = id.startsWith('wc-man') ? 'wc-man' : 'wc-woman';
    baths[wcId].push(bbox);
  }

  return baths;
}

function assignBathsToStalls(stalls: RestroomStall[], baths: SvgBBox[]): RestroomStall[] {
  if (!baths.length) return stalls;
  const vertical = stallsSplitVertically(stalls);
  const sortedBaths = sortBboxesForStalls(baths, vertical);
  const sortedStalls = [...stalls].sort((a, b) => {
    const ka = vertical ? a.bbox.x : a.bbox.y;
    const kb = vertical ? b.bbox.x : b.bbox.y;
    return ka - kb;
  });
  return sortedStalls.map((stall, i) => ({
    ...stall,
    bathBBox: sortedBaths[i] ?? stall.bathBBox,
  }));
}

function splitBboxVertical(parent: SvgBBox): [SvgBBox, SvgBBox] {
  const splitX = parent.x + parent.width / 2;
  return [
    { x: parent.x, y: parent.y, width: splitX - parent.x, height: parent.height },
    { x: splitX, y: parent.y, width: parent.x + parent.width - splitX, height: parent.height },
  ];
}

function splitBboxByDivider(parent: SvgBBox, divider: SvgBBox): [SvgBBox, SvgBBox] {
  if (divider.width > divider.height * 1.2) {
    const splitY = divider.y + divider.height / 2;
    return [
      { x: parent.x, y: parent.y, width: parent.width, height: splitY - parent.y },
      { x: parent.x, y: splitY, width: parent.width, height: parent.y + parent.height - splitY },
    ];
  }
  const splitX = divider.x + divider.width / 2;
  return [
    { x: parent.x, y: parent.y, width: splitX - parent.x, height: parent.height },
    { x: splitX, y: parent.y, width: parent.x + parent.width - splitX, height: parent.height },
  ];
}

function buildRestroomUnits(svg: string, viewBox: { width: number; height: number }): RestroomUnit[] {
  const units: RestroomUnit[] = [];
  const bathRects = buildWcBathRects(svg);

  for (const [wcId, config] of Object.entries(WC_UNIT_CONFIG)) {
    const wcChunk = extractGroupChunk(svg, wcId);
    if (!wcChunk) continue;

    const wcBoxes: SvgBBox[] = [];
    for (const wallId of [...wcChunk.matchAll(/<g id="(wc-wall[^"]*)">/g)].map((m) => m[1])) {
      const chunk = extractGroupChunk(wcChunk, wallId);
      wcBoxes.push(...filledPathsInChunk(chunk, viewBox, ['#6a6a6a', 'white']).map((z) => z.bbox));
    }

    const bounds = mergeBboxes(wcBoxes);
    if (!bounds || bounds.width < 8 || bounds.height < 8) continue;

    let stalls: RestroomStall[] = [];

    if (config.splitVertical) {
      const [stallA, stallB] = splitBboxVertical(bounds);
      stalls = [
        { id: `${wcId}-stall-1`, bbox: stallA },
        { id: `${wcId}-stall-2`, bbox: stallB },
      ];
    } else if (config.dividerId) {
      const dividerChunk = extractGroupChunk(wcChunk, config.dividerId);
      if (dividerChunk) {
        const dividerBox = mergeBboxes(
          filledPathsInChunk(dividerChunk, viewBox, ['#6a6a6a', 'white']).map((z) => z.bbox),
        );
        if (dividerBox) {
          const [stallA, stallB] = splitBboxByDivider(bounds, dividerBox);
          stalls = [
            { id: `${wcId}-stall-1`, bbox: stallA },
            { id: `${wcId}-stall-2`, bbox: stallB },
          ];
        }
      }
    }

    if (stalls.length < 2) {
      const [stallA, stallB] = splitBboxVertical(bounds);
      stalls = [
        { id: `${wcId}-stall-1`, bbox: stallA },
        { id: `${wcId}-stall-2`, bbox: stallB },
      ];
    }

    units.push({
      id: wcId,
      gender: config.gender,
      label: config.label,
      bounds,
      stalls: assignBathsToStalls(stalls, bathRects[wcId] ?? []),
    });
  }

  return units;
}

function buildGlassWalls(svg: string, viewBox: { width: number; height: number }): FloorZone[] {
  const zones: FloorZone[] = [];

  for (const groupId of ['glass-wall', 'glass-wall_2']) {
    const chunk = extractGroupChunk(svg, groupId);
    if (!chunk) continue;

    for (const match of chunk.matchAll(/<path\b([^>]*)\/?>/g)) {
      const attrs = match[1];
      const fill = (readAttr(attrs, 'fill') ?? '').toLowerCase();
      const d = readAttr(attrs, 'd') ?? '';
      const pathId = readAttr(attrs, 'id') ?? `glass-${zones.length}`;

      if (!FLOOR2_GLASS_FILLS.includes(fill)) continue;
      if (!/[zZ]\s*$/.test(d.trim())) continue;

      const raw = parsePathBounds(d);
      if (!raw || raw.width < 0.4 || raw.height < 0.4) continue;
      if (raw.width > viewBox.width * 0.8 || raw.height > viewBox.height * 0.8) continue;

      const bbox = expandThinBBox(toBBox(raw), 4, 4);
      const zone = zoneFromBounds(`glass-${groupId}-${pathId}`, 'Glass Wall', 'glass-wall', bbox, {
        fill,
      }, 1);
      if (zone) zones.push(zone);
    }
  }

  return zones;
}

function buildPhotoZone(svg: string, viewBox: { width: number; height: number }): FloorZone[] {
  const chunk = extractGroupChunk(svg, 'zone-photo');
  if (!chunk) return [];

  const bbox = boundsFromChunk(chunk, viewBox);
  const zone = zoneFromBounds('zone-photo-area', 'Photo Zone', 'photo-zone', bbox);
  return zone ? [zone] : [];
}

function buildPolesFloor2(svg: string, viewBox: { width: number; height: number }): FloorZone[] {
  const poleIds = [...svg.matchAll(/<g id="(pole\d+)">/g)].map((m) => m[1]);
  const zones: FloorZone[] = [];

  for (const poleId of poleIds) {
    const poleChunk = extractGroupChunk(svg, poleId);
    const bbox = boundsFromChunk(poleChunk, viewBox);
    const zone = zoneFromBounds(`pole-${poleId}`, poleId, 'pole', bbox, { shape: 'cylinder' });
    if (zone) zones.push(zone);
  }

  return zones;
}

function buildStairsFloor2(svg: string): FloorZone[] {
  const chunk = extractGroupChunk(svg, 'stairs');
  if (!chunk) return [];

  const horizontals: { y: number; x0: number; x1: number }[] = [];
  const dividerXs: number[] = [];

  for (const match of chunk.matchAll(/<path\b([^>]*)\/?>/g)) {
    const d = readAttr(match[1], 'd') ?? '';
    const bbox = parsePathBounds(d);
    if (!bbox) continue;

    if (bbox.height < 4 && bbox.width > 80) {
      horizontals.push({ y: bbox.y, x0: bbox.x, x1: bbox.x + bbox.width });
      continue;
    }

    if (bbox.height > 40 && bbox.width < 8) {
      dividerXs.push(bbox.x + bbox.width / 2);
    }
  }

  if (!horizontals.length || !dividerXs.length) return [];

  horizontals.sort((a, b) => a.y - b.y);
  const yTop = horizontals[0].y;
  const yBottom = horizontals[horizontals.length - 1].y;
  const runHeight = yBottom - yTop;
  if (runHeight < 20) return [];

  const westX = Math.min(...horizontals.flatMap((h) => [h.x0, h.x1]));
  const eastX = Math.max(...horizontals.flatMap((h) => [h.x0, h.x1]));

  const sorted = [...new Set(dividerXs.map((x) => Math.round(x * 100) / 100))]
    .filter((x) => x >= westX - 2 && x <= eastX + 2)
    .sort((a, b) => a - b);

  const zones: FloorZone[] = [];

  for (let i = 0; i < sorted.length - 1; i += 1) {
    const x0 = sorted[i];
    const x1 = sorted[i + 1];
    const treadWidth = x1 - x0;
    if (treadWidth < 8) continue;

    zones.push({
      id: `stairs-step${zones.length + 1}`,
      label: `Step ${zones.length + 1}`,
      kind: 'stair-step',
      bbox: { x: x0, y: yTop, width: treadWidth, height: runHeight },
      stepIndex: zones.length + 1,
    });
  }

  return zones;
}

function buildStairOpeningFloor2(_svg: string, runBBox: SvgBBox): SvgBBox {
  return runBBox;
}

function buildStairsForFloor2(
  prepared: string,
  viewBox: { width: number; height: number },
): { steps: FloorZone[]; opening: SvgBBox | null } {
  const sharedChunk = extractGroupChunk(prepared, 'zone-stairs');
  const steps = sharedChunk
    ? buildStairsFromChunk(sharedChunk, viewBox)
    : buildStairsFloor2(prepared);
  const runBBox = mergeBboxes(steps.map((s) => s.bbox));
  const opening = runBBox ? buildStairOpeningFloor2(prepared, runBBox) : null;
  return { steps, opening };
}

function readStrokePathDFromChunk(chunk: string, id: string): string | null {
  const idEsc = id.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const tagMatch = chunk.match(new RegExp(`<path\\b[^>]*\\bid="${idEsc}"[^>]*/?>`, 'i'));
  if (!tagMatch) return null;
  const tag = tagMatch[0];
  const d = readAttr(tag, 'd');
  if (!d) return null;
  const stroke = readAttr(tag, 'stroke') ?? '';
  if (stroke.includes('6464FF')) return null;
  if (stroke && !stroke.toLowerCase().includes('black')) return null;
  if (!stroke) return null;
  return d;
}

function readStrokePathFromChunk(
  chunk: string,
  id: string,
  curveSamples = 16,
): [number, number][] {
  const d = readStrokePathDFromChunk(chunk, id);
  if (!d) return [];
  return parsePathPolyline(d, curveSamples);
}

function readStrokeSubpathsFromChunk(
  chunk: string,
  id: string,
  curveSamples = 16,
): [number, number][][] {
  const d = readStrokePathDFromChunk(chunk, id);
  if (!d) return [];
  return parsePathSubpaths(d, curveSamples);
}

const FLOOR2_RAIL_IDS = ['rail1', 'rail2', 'rail3'] as const;
const FLOOR2_RAIL_SLOPE_FROM_STAIR_BOTTOM = new Set<string>(['rail3']);

/** Floor 2 — draw stroke paths by SVG id; split on `M`, chain only where endpoints meet. */
function buildRailingStructureFromPaths(svg: string): RailingSegment[] | null {
  const segments: RailingSegment[] = [];
  let foundAny = false;

  for (const id of FLOOR2_RAIL_IDS) {
    const subpaths = readStrokeSubpathsFromChunk(svg, id, 48).filter((s) => s.length >= 2);
    if (!subpaths.length) continue;
    foundAny = true;

    const railOpts = {
      smooth: true as const,
      ...(FLOOR2_RAIL_SLOPE_FROM_STAIR_BOTTOM.has(id) ? { slopeFromStairBottom: true as const } : {}),
    };

    for (const chain of chainPolylines(subpaths)) {
      if (chain.length < 2) continue;
      const xs = chain.map(([x]) => x);
      const slopeXRange = { minX: Math.min(...xs), maxX: Math.max(...xs) };
      const chainOpts = {
        ...railOpts,
        ...(railOpts.slopeFromStairBottom ? { slopeXRange } : {}),
      };
      pushRailSegment(segments, chain, chainOpts);
      segments.push({ points: [chain[0]], kind: 'post', ...chainOpts });
      segments.push({ points: [chain[chain.length - 1]], kind: 'post', ...chainOpts });
    }
  }

  return foundAny ? segments : null;
}

function chainStrokePaths(
  chunk: string,
  ids: string[],
  curveSamples = 16,
): [number, number][] {
  const points: [number, number][] = [];
  for (const id of ids) {
    const pts = readStrokePathFromChunk(chunk, id, curveSamples);
    if (!pts.length) continue;
    if (!points.length) {
      points.push(...pts);
      continue;
    }
    const last = points[points.length - 1];
    const first = pts[0];
    if (Math.hypot(last[0] - first[0], last[1] - first[1]) < 4) {
      points.push(...pts.slice(1));
    } else {
      points.push(...pts);
    }
  }
  return points;
}

function firstStrokePath(chunk: string, ids: string[], curveSamples = 16): [number, number][] {
  for (const id of ids) {
    const pts = readStrokePathFromChunk(chunk, id, curveSamples);
    if (pts.length >= 2) return pts;
  }
  return [];
}

function pushRailSegment(
  segments: RailingSegment[],
  points: [number, number][],
  opts: {
    smooth?: boolean;
    variant?: RailingSegment['variant'];
    space?: RailingSegment['space'];
    slopeFromStairBottom?: boolean;
    slopeXRange?: { minX: number; maxX: number };
  } = {},
) {
  if (points.length >= 2) {
    segments.push({
      points,
      kind: 'rail',
      variant: opts.variant ?? 'handrail',
      space: opts.space,
      ...opts,
    });
  }
}

function pushPathByIds(
  segments: RailingSegment[],
  chunk: string,
  ids: string[],
  opts: {
    smooth?: boolean;
    variant?: RailingSegment['variant'];
    space?: RailingSegment['space'];
    chain?: boolean;
    curveSamples?: number;
  } = {},
) {
  const samples = opts.curveSamples ?? (opts.smooth ? 48 : 16);
  if (opts.chain) {
    pushRailSegment(segments, chainStrokePaths(chunk, ids, samples), opts);
    return;
  }
  for (const id of ids) {
    pushRailSegment(segments, readStrokePathFromChunk(chunk, id, samples), opts);
  }
}

function buildRailingStructure(svg: string): RailingSegment[] {
  const pathRails = buildRailingStructureFromPaths(svg);
  if (pathRails) return pathRails;

  const segments: RailingSegment[] = [];

  const rail1 = extractGroupChunk(svg, 'rail1') ?? extractGroupChunk(svg, 'rounded-railing');
  const rail2 = extractGroupChunk(svg, 'rail2') ?? extractGroupChunk(svg, 'railing');
  const stairsRail = extractGroupChunk(svg, 'stairs-railing');

  if (rail1) {
    const westRailIds = [
      'Vector_225',
      ...Array.from({ length: 19 }, (_, i) => `Vector_${233 + i}`),
    ];

    let outerCurve = readStrokePathFromChunk(rail1, 'Vector_260', 48);
    if (outerCurve.length < 2) {
      outerCurve = readStrokePathFromChunk(rail1, 'Vector_261', 48);
    }
    if (outerCurve.length >= 2) {
      pushRailSegment(segments, outerCurve, { smooth: true });
      segments.push({ points: [outerCurve[0]], kind: 'post' });
      segments.push({ points: [outerCurve[outerCurve.length - 1]], kind: 'post' });
    } else {
      pushPathByIds(segments, rail1, westRailIds, { smooth: true, chain: true, curveSamples: 12 });
    }

    const innerCurve = readStrokePathFromChunk(rail1, 'Vector_261', 48);
    if (innerCurve.length >= 2 && outerCurve.length >= 2) {
      pushRailSegment(segments, innerCurve, { smooth: true });
    } else {
      pushPathByIds(segments, rail1, westRailIds, { chain: true, curveSamples: 16 });
    }

    pushPathByIds(segments, rail1, ['Vector_272', 'Vector_274', 'Vector_276']);

    const topRail = readStrokePathFromChunk(rail1, 'Vector_272');
    if (topRail.length >= 2) {
      segments.push({ points: [topRail[0]], kind: 'post' });
      segments.push({ points: [topRail[topRail.length - 1]], kind: 'post' });
    }

    for (const cornerId of ['Vector_258', 'Vector_259', 'Vector_279']) {
      const corner = readStrokePathFromChunk(rail1, cornerId, 4);
      if (corner.length >= 1) {
        segments.push({ points: [corner[0]], kind: 'post' });
      }
    }
  }

  if (rail2) {
    pushPathByIds(segments, rail2, ['Vector_218', 'Vector_219', 'Vector_221', 'Vector_222']);

    const eastDrop = firstStrokePath(rail2, ['Vector_218', 'Vector_219']);
    if (eastDrop.length >= 2) {
      segments.push({ points: [eastDrop[0]], kind: 'post' });
      segments.push({ points: [eastDrop[eastDrop.length - 1]], kind: 'post' });
    }
  }

  if (stairsRail) {
    pushPathByIds(
      segments,
      stairsRail,
      ['Vector_202', 'Vector_203', 'Vector_204', 'Vector_205'],
      { variant: 'stair-lip', chain: true, space: 'world' },
    );
    pushPathByIds(
      segments,
      stairsRail,
      ['Vector_212', 'Vector_213', 'Vector_214', 'Vector_215'],
      { variant: 'stair-lip', chain: true, space: 'world' },
    );
  }

  return segments;
}

function readRectBBox(tag: string): SvgBBox | null {
  const x = Number(readAttr(tag, 'x'));
  const y = Number(readAttr(tag, 'y'));
  const width = Number(readAttr(tag, 'width'));
  const height = Number(readAttr(tag, 'height'));
  if (![x, y, width, height].every((v) => Number.isFinite(v)) || width <= 0 || height <= 0) {
    return null;
  }
  return { x, y, width, height };
}

const FLOOR_BG_IDS = [
  'Rectangle 2',
  'Rectangle 3',
  'Rectangle 4',
  'Rectangle 5',
  'Rectangle 6',
] as const;

/** Walkable floor regions from the `floor-bg` group */
function buildFloorBgSlabs(svg: string): FloorSlab[] {
  const chunk = extractGroupChunk(svg, 'floor-bg');
  if (!chunk) return [];

  const slabs: FloorSlab[] = [];
  const claimedIds = new Set<string>();

  for (const id of FLOOR_BG_IDS) {
    const idEsc = id.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    const rectMatch = chunk.match(new RegExp(`<rect[^>]*id="${idEsc}"[^>]*/?>`, 'i'));
    if (rectMatch) {
      const bbox = readRectBBox(rectMatch[0]);
      if (bbox) {
        slabs.push({ id, bbox });
        claimedIds.add(id);
      }
      continue;
    }

    const pathMatch = chunk.match(new RegExp(`<path[^>]*id="${idEsc}"[^>]*d="([^"]+)"`, 'i'));
    if (pathMatch) {
      const bounds = parsePathBounds(pathMatch[1]);
      if (bounds) {
        slabs.push({ id, bbox: toBBox(bounds), pathD: pathMatch[1] });
        claimedIds.add(id);
      }
    }
  }

  let genericIndex = 0;
  for (const match of chunk.matchAll(/<path\b([^>]*)\/?>/gi)) {
    const attrs = match[1];
    const id = readAttr(attrs, 'id');
    if (id && claimedIds.has(id)) continue;

    const d = readAttr(attrs, 'd');
    if (!d) continue;

    const bounds = parsePathBounds(d);
    if (!bounds || bounds.width < 4 || bounds.height < 4) continue;

    const slabId = id ?? `floor-bg-${genericIndex++}`;
    if (claimedIds.has(slabId)) continue;
    claimedIds.add(slabId);
    slabs.push({ id: slabId, bbox: toBBox(bounds), pathD: d });
  }

  for (const match of chunk.matchAll(/<rect\b([^>]*)\/?>/gi)) {
    const tag = match[0];
    const id = readAttr(tag, 'id');
    if (id && claimedIds.has(id)) continue;

    const bbox = readRectBBox(tag);
    if (!bbox) continue;

    const slabId = id ?? `floor-bg-rect-${genericIndex++}`;
    if (claimedIds.has(slabId)) continue;
    claimedIds.add(slabId);
    slabs.push({ id: slabId, bbox });
  }

  return slabs;
}

function buildBoundaryFromFloorSlabs(
  floorSlabs: FloorSlab[],
  viewBox: { width: number; height: number },
): SvgBBox {
  const merged = mergeBboxes(floorSlabs.map((s) => s.bbox));
  if (merged && merged.width > 20 && merged.height > 20) {
    return merged;
  }
  return { x: 0, y: 0, width: viewBox.width, height: viewBox.height };
}

function detectFloorId(svgText: string): FloorId {
  if (svgText.includes('id="floor2"') && !svgText.includes('id="floor1"')) return 'floor2';
  return 'floor1';
}

/** Unwrap floor content from standalone floor1.svg / floor2.svg */
function prepareFloorSvg(svgText: string, floorId: FloorId): string {
  const viewBox = parseViewBox(svgText);
  const shell = (inner: string) =>
    `<svg viewBox="0 0 ${viewBox.width} ${viewBox.height}" xmlns="http://www.w3.org/2000/svg">${inner}</svg>`;

  const floorChunk = extractGroupChunk(svgText, floorId);
  if (floorChunk) return shell(floorChunk);

  return svgText;
}

function parseFloorPlanSvgFloor2(svgText: string): FloorPlanData {
  const prepared = prepareFloorSvg(svgText, 'floor2');
  const viewBox = parseViewBox(prepared);
  setViewBox(viewBox.width, viewBox.height);

  const tables = buildTables(prepared, 'f2-');
  const walls = buildWallsFloor2(prepared, viewBox);
  const restroomWalls = buildRestroomWalls(prepared, viewBox);
  const restrooms = buildRestroomUnits(prepared, viewBox);
  const { steps: stairSteps, opening: stairOpening } = buildStairsForFloor2(prepared, viewBox);
  const railingSegments = buildRailingStructure(prepared);

  const zones = [
    ...walls,
    ...restroomWalls.filter((z) => z.kind !== 'restroom'),
    ...buildGlassWalls(prepared, viewBox),
    ...buildPhotoZone(prepared, viewBox),
    ...buildPolesFloor2(prepared, viewBox),
    ...stairSteps,
    ...restroomWalls.filter((z) => z.kind === 'restroom'),
  ];

  const floorSlabs = buildFloorBgSlabs(prepared);

  return {
    floorId: 'floor2',
    viewBox,
    alignAnchor: parseAlignAnchor(prepared, 'floor2', viewBox),
    tables,
    zones,
    boundary: buildBoundaryFromFloorSlabs(floorSlabs, viewBox),
    stairOpening: stairOpening ?? undefined,
    floorSlabs,
    railingSegments,
    restrooms,
  };
}

function parseFloorPlanSvgFloor1(svgText: string): FloorPlanData {
  const prepared = prepareFloorSvg(svgText, 'floor1');
  const viewBox = parseViewBox(prepared);
  setViewBox(viewBox.width, viewBox.height);

  const floorSlabs = buildFloorBgSlabs(prepared);
  const tables = buildTables(prepared);
  const zones = [
    ...buildWalls(prepared, viewBox),
    ...buildEntrance(prepared, viewBox),
    ...buildStage(prepared, viewBox),
    ...buildBar(prepared),
    ...buildStairs(prepared, viewBox),
    ...buildPoles(prepared, viewBox),
  ];

  return {
    floorId: 'floor1',
    viewBox,
    alignAnchor: parseAlignAnchor(prepared, 'floor1', viewBox),
    tables,
    zones,
    boundary: floorSlabs.length
      ? buildBoundaryFromFloorSlabs(floorSlabs, viewBox)
      : buildBoundary(prepared),
    floorSlabs: floorSlabs.length ? floorSlabs : undefined,
  };
}

export function parseFloorPlanSvg(svgText: string, forcedFloor?: FloorId): FloorPlanData {
  const floorId = forcedFloor ?? detectFloorId(svgText);

  if (floorId === 'floor2') {
    return parseFloorPlanSvgFloor2(svgText);
  }

  return parseFloorPlanSvgFloor1(svgText);
}
