import type { SvgBBox } from '../types';

/**
 * Computes axis-aligned bounds from SVG path `d` strings using M/L/H/V/Z commands.
 * Matches the command subset used throughout plan.svg.
 */
export function parsePathBounds(d: string): SvgBBox | null {
  const tokens = d.match(/[a-zA-Z]|-?\d*\.?\d+(?:e[-+]?\d+)?/g);
  if (!tokens?.length) return null;

  let i = 0;
  let cmd = '';
  let x = 0;
  let y = 0;
  let startX = 0;
  let startY = 0;
  let minX = Infinity;
  let minY = Infinity;
  let maxX = -Infinity;
  let maxY = -Infinity;

  const addPoint = (px: number, py: number) => {
    if (!Number.isFinite(px) || !Number.isFinite(py)) return;
    minX = Math.min(minX, px);
    minY = Math.min(minY, py);
    maxX = Math.max(maxX, px);
    maxY = Math.max(maxY, py);
    x = px;
    y = py;
  };

  while (i < tokens.length) {
    const token = tokens[i];
    if (/^[a-zA-Z]$/.test(token)) {
      cmd = token;
      i += 1;
      continue;
    }

    switch (cmd) {
      case 'M': {
        const px = parseFloat(tokens[i++]);
        const py = parseFloat(tokens[i++]);
        startX = px;
        startY = py;
        addPoint(px, py);
        cmd = 'L';
        break;
      }
      case 'L': {
        addPoint(parseFloat(tokens[i++]), parseFloat(tokens[i++]));
        break;
      }
      case 'H': {
        addPoint(parseFloat(tokens[i++]), y);
        break;
      }
      case 'V': {
        addPoint(x, parseFloat(tokens[i++]));
        break;
      }
      case 'Z':
      case 'z': {
        addPoint(startX, startY);
        i += 1;
        break;
      }
      default:
        i += 1;
    }
  }

  if (!Number.isFinite(minX)) return null;

  return {
    x: minX,
    y: minY,
    width: maxX - minX,
    height: maxY - minY,
  };
}

export function mergeBboxes(boxes: SvgBBox[]): SvgBBox | null {
  if (!boxes.length) return null;
  let minX = Infinity;
  let minY = Infinity;
  let maxX = -Infinity;
  let maxY = -Infinity;

  for (const box of boxes) {
    minX = Math.min(minX, box.x);
    minY = Math.min(minY, box.y);
    maxX = Math.max(maxX, box.x + box.width);
    maxY = Math.max(maxY, box.y + box.height);
  }

  return { x: minX, y: minY, width: maxX - minX, height: maxY - minY };
}
