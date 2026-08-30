/** Sample SVG path commands into a polyline (M/L/H/V/C/Z). */
export function parsePathPolyline(d: string, curveSamples = 10): [number, number][] {
  const subpaths = parsePathSubpaths(d, curveSamples);
  return subpaths[0] ?? [];
}

/** Each `M` starts a new subpath — use before chaining contours that should meet. */
export function parsePathSubpaths(d: string, curveSamples = 10): [number, number][][] {
  const tokens = d.match(/[a-zA-Z]|-?\d*\.?\d+(?:e[-+]?\d+)?/g);
  if (!tokens?.length) return [];

  const subpaths: [number, number][][] = [];
  let points: [number, number][] = [];
  let i = 0;
  let cmd = '';
  let x = 0;
  let y = 0;
  let startX = 0;
  let startY = 0;

  const flush = () => {
    if (points.length) {
      subpaths.push(points);
      points = [];
    }
  };

  const push = (px: number, py: number) => {
    if (!Number.isFinite(px) || !Number.isFinite(py)) return;
    const last = points[points.length - 1];
    if (!last || Math.hypot(last[0] - px, last[1] - py) > 0.05) {
      points.push([px, py]);
    }
    x = px;
    y = py;
  };

  const sampleCubic = (
    x0: number,
    y0: number,
    x1: number,
    y1: number,
    x2: number,
    y2: number,
    x3: number,
    y3: number,
  ) => {
    for (let t = 1; t <= curveSamples; t += 1) {
      const u = t / curveSamples;
      const inv = 1 - u;
      const px =
        inv * inv * inv * x0 +
        3 * inv * inv * u * x1 +
        3 * inv * u * u * x2 +
        u * u * u * x3;
      const py =
        inv * inv * inv * y0 +
        3 * inv * inv * u * y1 +
        3 * inv * u * u * y2 +
        u * u * u * y3;
      push(px, py);
    }
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
        flush();
        const px = parseFloat(tokens[i++]);
        const py = parseFloat(tokens[i++]);
        startX = px;
        startY = py;
        push(px, py);
        cmd = 'L';
        break;
      }
      case 'L':
        push(parseFloat(tokens[i++]), parseFloat(tokens[i++]));
        break;
      case 'H':
        push(parseFloat(tokens[i++]), y);
        break;
      case 'V':
        push(x, parseFloat(tokens[i++]));
        break;
      case 'C': {
        const x1 = parseFloat(tokens[i++]);
        const y1 = parseFloat(tokens[i++]);
        const x2 = parseFloat(tokens[i++]);
        const y2 = parseFloat(tokens[i++]);
        const x3 = parseFloat(tokens[i++]);
        const y3 = parseFloat(tokens[i++]);
        sampleCubic(x, y, x1, y1, x2, y2, x3, y3);
        break;
      }
      case 'Z':
      case 'z':
        push(startX, startY);
        i += 1;
        break;
      default:
        i += 1;
    }
  }

  flush();
  return subpaths;
}

const CHAIN_EPS = 2.5;

function dist(a: [number, number], b: [number, number]): number {
  return Math.hypot(a[0] - b[0], a[1] - b[1]);
}

/** Join short path segments whose endpoints meet into continuous polylines. */
export function chainPolylines(segments: [number, number][][]): [number, number][][] {
  const remaining = segments.filter((s) => s.length >= 2);
  const chains: [number, number][][] = [];

  while (remaining.length) {
    let chain = remaining.shift()!;
    let extended = true;

    while (extended) {
      extended = false;
      for (let j = 0; j < remaining.length; j += 1) {
        const seg = remaining[j];
        const chainStart = chain[0];
        const chainEnd = chain[chain.length - 1];
        const segStart = seg[0];
        const segEnd = seg[seg.length - 1];

        if (dist(chainEnd, segStart) < CHAIN_EPS) {
          chain = [...chain, ...seg.slice(1)];
          remaining.splice(j, 1);
          extended = true;
          break;
        }
        if (dist(chainEnd, segEnd) < CHAIN_EPS) {
          chain = [...chain, ...[...seg].reverse().slice(1)];
          remaining.splice(j, 1);
          extended = true;
          break;
        }
        if (dist(chainStart, segEnd) < CHAIN_EPS) {
          chain = [...seg.slice(0, -1), ...chain];
          remaining.splice(j, 1);
          extended = true;
          break;
        }
        if (dist(chainStart, segStart) < CHAIN_EPS) {
          chain = [...[...seg].reverse().slice(0, -1), ...chain];
          remaining.splice(j, 1);
          extended = true;
          break;
        }
      }
    }

    if (chain.length >= 2) chains.push(chain);
  }

  return chains;
}
