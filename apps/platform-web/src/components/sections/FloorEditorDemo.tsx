import {
  AlignBottom,
  AlignCenterHorizontal,
  AlignCenterVertical,
  AlignLeft,
  AlignRight,
  AlignTop,
  ArrowCounterClockwise,
  ArrowClockwise,
  ArrowLeft,
  ArrowsHorizontal,
  ArrowsVertical,
  CaretDown,
  Chair,
  Circle,
  Copy,
  DoorOpen,
  Eye,
  FloppyDisk,
  GridFour,
  Magnet,
  Minus,
  PencilSimple,
  Plus,
  SquaresFour,
  Stairs,
  Storefront,
  Table,
  TextT,
  Trash,
  Wall,
} from "@phosphor-icons/react";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { useLocale, type SiteCopy } from "../../lib/i18n";

type ObjectType = "table" | "wall" | "divider" | "entrance" | "bar" | "stage" | "stairs" | "restroom" | "zone" | "label";
type TableShape = "rectangle" | "square" | "circle" | "long" | "booth" | "barSeat";
type FloorObject = {
  id: string;
  type: ObjectType;
  label: string;
  x: number;
  y: number;
  width: number;
  height: number;
  rotation: number;
  shape?: TableShape;
  capacity?: number;
  color?: string;
};
type Placement = { label: string; type: ObjectType; width: number; height: number; shape?: TableShape; capacity?: number };
type DemoPhase = "idle" | "select" | "place" | "added";

const INITIAL_CANVAS = { width: 1400, height: 875 };
const INITIAL_GRID = 20;

const initialObjects: FloorObject[] = [
  { id: "bar-1", type: "bar", label: "Bar", x: 170, y: 86, width: 300, height: 72, rotation: 0, color: "blue" },
  { id: "stage-1", type: "stage", label: "Stage", x: 980, y: 300, width: 190, height: 270, rotation: 0, color: "pink" },
  { id: "entrance-1", type: "entrance", label: "Entrance", x: 1230, y: 500, width: 150, height: 70, rotation: 0, color: "amber" },
];

const demoTablePlacement: Placement = { label: "Table", type: "table", width: 150, height: 112, shape: "rectangle", capacity: 4 };
const demoTablePosition = { x: 560, y: 420 };

const palettes: Array<{ title: string; items: Array<{ label: string; icon: typeof Table; placement: Placement; variants?: Placement[] }> }> = [
  {
    title: "Tables",
    items: [
      { label: "Table", icon: Table, placement: { label: "Table", type: "table", width: 150, height: 112, shape: "rectangle", capacity: 4 }, variants: [{ label: "Rectangle · 4 seats", type: "table", width: 140, height: 90, shape: "rectangle", capacity: 4 }, { label: "Rectangle · 6 seats", type: "table", width: 190, height: 90, shape: "rectangle", capacity: 6 }, { label: "Square · 4 seats", type: "table", width: 110, height: 110, shape: "square", capacity: 4 }] },
      { label: "Round table", icon: Circle, placement: { label: "Round table", type: "table", width: 120, height: 120, shape: "circle", capacity: 4 }, variants: [{ label: "Round · 2 seats", type: "table", width: 86, height: 86, shape: "circle", capacity: 2 }, { label: "Round · 4 seats", type: "table", width: 120, height: 120, shape: "circle", capacity: 4 }, { label: "Round · 6 seats", type: "table", width: 150, height: 150, shape: "circle", capacity: 6 }] },
      { label: "Booth", icon: Chair, placement: { label: "Booth", type: "table", width: 180, height: 120, shape: "booth", capacity: 4 } },
      { label: "Communal", icon: ArrowsHorizontal, placement: { label: "Communal table", type: "table", width: 300, height: 100, shape: "long", capacity: 8 } },
    ],
  },
  {
    title: "Structure",
    items: [
      { label: "Wall", icon: Wall, placement: { label: "Wall", type: "wall", width: 260, height: 14 } },
      { label: "Divider", icon: ArrowsHorizontal, placement: { label: "Divider", type: "divider", width: 220, height: 10 } },
      { label: "Entrance", icon: DoorOpen, placement: { label: "Entrance", type: "entrance", width: 150, height: 70 } },
    ],
  },
  {
    title: "Objects",
    items: [
      { label: "Bar", icon: Storefront, placement: { label: "Bar", type: "bar", width: 300, height: 72 } },
      { label: "Stage", icon: SquaresFour, placement: { label: "Stage", type: "stage", width: 220, height: 120 } },
      { label: "Stairs", icon: Stairs, placement: { label: "Stairs", type: "stairs", width: 170, height: 100 } },
    ],
  },
  {
    title: "Annotation",
    items: [
      { label: "Zone", icon: SquaresFour, placement: { label: "Service zone", type: "zone", width: 360, height: 220 } },
      { label: "Label", icon: TextT, placement: { label: "Label", type: "label", width: 160, height: 44 } },
    ],
  },
];

function snap(value: number, enabled: boolean, gridSize: number) {
  return enabled ? Math.round(value / gridSize) * gridSize : value;
}

function clampObject(object: FloorObject, canvas: { width: number; height: number }): FloorObject {
  const width = Math.min(object.width, canvas.width);
  const height = Math.min(object.height, canvas.height);
  return { ...object, width, height, x: Math.max(0, Math.min(canvas.width - width, object.x)), y: Math.max(0, Math.min(canvas.height - height, object.y)) };
}

function reflowObjects(objects: FloorObject[], previous: { width: number; height: number }, next: { width: number; height: number }) {
  return objects.map((object) => clampObject({
    ...object,
    x: object.x * next.width / previous.width,
    y: object.y * next.height / previous.height,
  }, next));
}

export function FloorEditorDemo() {
  const { copy } = useLocale();
  const [objects, setObjects] = useState(initialObjects);
  const [selectedIds, setSelectedIds] = useState<string[]>([]);
  const [placement, setPlacement] = useState<Placement | null>(null);
  const [gridVisible, setGridVisible] = useState(true);
  const [snapEnabled, setSnapEnabled] = useState(true);
  const [gridSize, setGridSize] = useState(INITIAL_GRID);
  const [canvasSize, setCanvasSize] = useState(INITIAL_CANVAS);
  const [zoom, setZoom] = useState(1);
  const [dirty, setDirty] = useState(false);
  const [saved, setSaved] = useState(false);
  const [preview, setPreview] = useState(false);
  const [history, setHistory] = useState<FloorObject[][]>([]);
  const [future, setFuture] = useState<FloorObject[][]>([]);
  const [demoPhase, setDemoPhase] = useState<DemoPhase>("idle");
  const demoRef = useRef<HTMLDivElement>(null);
  const demoTimersRef = useRef<number[]>([]);
  const lastScrollYRef = useRef(0);
  const demoHasRunRef = useRef(false);
  const demoWasInterruptedRef = useRef(false);
  const svgRef = useRef<SVGSVGElement>(null);
  const dragRef = useRef<{ mode: "move" | "resize" | "rotate"; id: string; start: { x: number; y: number }; origin: FloorObject } | null>(null);

  const selected = useMemo(() => objects.filter((object) => selectedIds.includes(object.id)), [objects, selectedIds]);
  const single = selected.length === 1 ? selected[0] : null;
  const pushHistory = useCallback(() => {
    setHistory((entries) => [...entries.slice(-39), objects]);
    setFuture([]);
  }, [objects]);

  const addDemoTable = useCallback(() => {
    const id = "demo-table-1";
    const next = clampObject({ id, type: "table", label: copy.editor.table, ...demoTablePosition, width: demoTablePlacement.width, height: demoTablePlacement.height, rotation: 0, shape: demoTablePlacement.shape, capacity: demoTablePlacement.capacity }, canvasSize);
    setObjects((current) => current.some((object) => object.id === id) ? current : [...current, next]);
    setSelectedIds([id]);
    setPlacement(null);
    setDemoPhase("added");
    setDirty(true);
  }, [canvasSize, copy.editor.table]);

  useEffect(() => {
    const node = demoRef.current;
    if (!node) return;
    lastScrollYRef.current = window.scrollY;
    const startDemo = () => {
      if (demoHasRunRef.current || demoWasInterruptedRef.current) return;
      demoHasRunRef.current = true;
      const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
      if (reducedMotion) {
        addDemoTable();
        return;
      }
      setDemoPhase("select");
      demoTimersRef.current = [
        window.setTimeout(() => {
          setPlacement(demoTablePlacement);
          setDemoPhase("place");
        }, 900),
        window.setTimeout(() => addDemoTable(), 2300),
      ];
    };
    const onScroll = () => {
      const nextScrollY = window.scrollY;
      const scrollingDown = nextScrollY > lastScrollYRef.current;
      lastScrollYRef.current = nextScrollY;
      if (!scrollingDown || demoHasRunRef.current || demoWasInterruptedRef.current) return;
      const bounds = node.getBoundingClientRect();
      const inReadingPosition = bounds.top < window.innerHeight * 0.78 && bounds.bottom > window.innerHeight * 0.24;
      if (inReadingPosition) startDemo();
    };
    window.addEventListener("scroll", onScroll, { passive: true });
    return () => {
      window.removeEventListener("scroll", onScroll);
      demoTimersRef.current.forEach((timer) => window.clearTimeout(timer));
    };
  }, [addDemoTable]);

  const interruptDemo = useCallback(() => {
    if (demoPhase === "select" || demoPhase === "place") {
      demoWasInterruptedRef.current = true;
      demoTimersRef.current.forEach((timer) => window.clearTimeout(timer));
      setDemoPhase("idle");
    }
  }, [demoPhase]);

  const pointFromEvent = useCallback((event: React.PointerEvent<SVGSVGElement | SVGGElement>) => {
    const svg = svgRef.current;
    if (!svg) return { x: 0, y: 0 };
    const rect = svg.getBoundingClientRect();
    const viewWidth = canvasSize.width / zoom;
    const viewHeight = canvasSize.height / zoom;
    const viewX = (canvasSize.width - viewWidth) / 2;
    const viewY = (canvasSize.height - viewHeight) / 2;
    return { x: viewX + ((event.clientX - rect.left) / rect.width) * viewWidth, y: viewY + ((event.clientY - rect.top) / rect.height) * viewHeight };
  }, [canvasSize, zoom]);

  const selectObject = (event: React.PointerEvent, id: string) => {
    event.stopPropagation();
    if (preview) return;
    if (event.shiftKey || event.metaKey || event.ctrlKey) {
      setSelectedIds((ids) => ids.includes(id) ? ids.filter((value) => value !== id) : [...ids, id]);
    } else if (!selectedIds.includes(id)) {
      setSelectedIds([id]);
    }
    const object = objects.find((value) => value.id === id);
    if (!object) return;
    pushHistory();
    dragRef.current = { mode: "move", id, start: pointFromEvent(event as React.PointerEvent<SVGGElement>), origin: object };
    (event.currentTarget as SVGGElement).setPointerCapture?.(event.pointerId);
  };

  const onCanvasDown = (event: React.PointerEvent<SVGSVGElement>) => {
    if (preview) return;
    interruptDemo();
    if (placement) {
      const point = pointFromEvent(event);
      const id = `${placement.type}-${Date.now()}`;
      const next = clampObject({ id, type: placement.type, label: localizePlacementLabel(placement, copy), x: snap(point.x - placement.width / 2, snapEnabled, gridSize), y: snap(point.y - placement.height / 2, snapEnabled, gridSize), width: placement.width, height: placement.height, rotation: 0, shape: placement.shape, capacity: placement.capacity }, canvasSize);
      pushHistory();
      setObjects((current) => [...current, next]);
      setSelectedIds([id]);
      setPlacement(null);
      setDirty(true);
      return;
    }
    setSelectedIds([]);
  };

  const onPointerMove = (event: React.PointerEvent<SVGSVGElement>) => {
    const drag = dragRef.current;
    if (!drag || preview) return;
    const point = pointFromEvent(event);
    const dx = point.x - drag.start.x;
    const dy = point.y - drag.start.y;
    setObjects((current) => current.map((object) => {
      if (object.id !== drag.id) return object;
      if (drag.mode === "move") return clampObject({ ...object, x: snap(drag.origin.x + dx, snapEnabled, gridSize), y: snap(drag.origin.y + dy, snapEnabled, gridSize) }, canvasSize);
      if (drag.mode === "resize") return clampObject({ ...object, width: Math.max(50, snap(drag.origin.width + dx, snapEnabled, gridSize)), height: Math.max(42, snap(drag.origin.height + dy, snapEnabled, gridSize)) }, canvasSize);
      const angle = Math.atan2(point.y - (drag.origin.y + drag.origin.height / 2), point.x - (drag.origin.x + drag.origin.width / 2)) * 180 / Math.PI + 90;
      return { ...object, rotation: snap(angle, snapEnabled, 15) };
    }));
    setDirty(true);
  };

  const endDrag = () => { dragRef.current = null; };

  const startHandle = (event: React.PointerEvent<SVGCircleElement>, mode: "resize" | "rotate") => {
    event.stopPropagation();
    const object = single;
    if (!object || preview) return;
    pushHistory();
    dragRef.current = { mode, id: object.id, start: pointFromEvent(event), origin: object };
    event.currentTarget.setPointerCapture?.(event.pointerId);
  };

  const updateObject = (changes: Partial<FloorObject>) => {
    if (!single || preview) return;
    interruptDemo();
    pushHistory();
    setObjects((current) => current.map((object) => object.id === single.id ? clampObject({ ...object, ...changes }, canvasSize) : object));
    setDirty(true);
  };

  const deleteSelected = useCallback(() => {
    if (!selectedIds.length || preview) return;
    pushHistory();
    setObjects((current) => current.filter((object) => !selectedIds.includes(object.id)));
    setSelectedIds([]);
    setDirty(true);
  }, [preview, pushHistory, selectedIds]);

  const duplicateSelected = useCallback(() => {
    if (!selected.length || preview) return;
    pushHistory();
    const copies = selected.map((object, index) => ({ ...object, id: `${object.type}-${Date.now()}-${index}`, label: `${object.label} copy`, x: object.x + gridSize, y: object.y + gridSize }));
    setObjects((current) => [...current, ...copies]);
    setSelectedIds(copies.map((object) => object.id));
    setDirty(true);
  }, [objects, preview, pushHistory, selected]);

  const resizeCanvas = useCallback((next: { width: number; height: number }) => {
    const safeNext = { width: Math.max(400, Math.min(4000, Math.round(next.width))), height: Math.max(400, Math.min(4000, Math.round(next.height))) };
    pushHistory();
    setCanvasSize(safeNext);
    setObjects((current) => reflowObjects(current, canvasSize, safeNext));
    setDirty(true);
  }, [canvasSize, pushHistory]);

  const undo = useCallback(() => {
    const previous = history.at(-1);
    if (!previous || preview) return;
    setFuture((entries) => [...entries, objects]);
    setObjects(previous);
    setHistory((entries) => entries.slice(0, -1));
    setDirty(true);
  }, [history, objects, preview]);

  const redo = useCallback(() => {
    const next = future.at(-1);
    if (!next || preview) return;
    setHistory((entries) => [...entries, objects]);
    setObjects(next);
    setFuture((entries) => entries.slice(0, -1));
    setDirty(true);
  }, [future, objects, preview]);

  const align = (axis: "left" | "centerX" | "right" | "top" | "centerY" | "bottom") => {
    if (selected.length < 2 || preview) return;
    pushHistory();
    const left = Math.min(...selected.map((object) => object.x));
    const top = Math.min(...selected.map((object) => object.y));
    const right = Math.max(...selected.map((object) => object.x + object.width));
    const bottom = Math.max(...selected.map((object) => object.y + object.height));
    setObjects((current) => current.map((object) => {
      if (!selectedIds.includes(object.id)) return object;
      const x = axis === "left" ? left : axis === "right" ? right - object.width : axis === "centerX" ? (left + right - object.width) / 2 : object.x;
      const y = axis === "top" ? top : axis === "bottom" ? bottom - object.height : axis === "centerY" ? (top + bottom - object.height) / 2 : object.y;
      return clampObject({ ...object, x: snap(x, snapEnabled, gridSize), y: snap(y, snapEnabled, gridSize) }, canvasSize);
    }));
    setDirty(true);
  };

  const save = () => { setDirty(false); setSaved(true); window.setTimeout(() => setSaved(false), 2400); };

  useEffect(() => {
    const onKey = (event: KeyboardEvent) => {
      const target = event.target as HTMLElement;
      if (target.matches("input, textarea")) return;
      const command = event.metaKey || event.ctrlKey;
      if (command && event.key.toLowerCase() === "z") { event.preventDefault(); event.shiftKey ? redo() : undo(); }
      else if (command && event.key.toLowerCase() === "y") { event.preventDefault(); redo(); }
      else if (command && event.key.toLowerCase() === "d") { event.preventDefault(); duplicateSelected(); }
      else if (event.key === "Delete" || event.key === "Backspace") deleteSelected();
      else if (event.key === "Escape") { setPlacement(null); setSelectedIds([]); }
      else if (event.key.startsWith("Arrow") && selected.length) {
        event.preventDefault();
        const step = event.shiftKey ? gridSize * 5 : gridSize;
        const delta = { ArrowLeft: [-step, 0], ArrowRight: [step, 0], ArrowUp: [0, -step], ArrowDown: [0, step] }[event.key] ?? [0, 0];
        pushHistory();
        setObjects((current) => current.map((object) => selectedIds.includes(object.id) ? clampObject({ ...object, x: snap(object.x + delta[0], snapEnabled, gridSize), y: snap(object.y + delta[1], snapEnabled, gridSize) }, canvasSize) : object));
        setDirty(true);
      }
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [canvasSize, deleteSelected, duplicateSelected, gridSize, pushHistory, redo, selected.length, selectedIds, snapEnabled, undo]);

  const viewBox = `${(canvasSize.width - canvasSize.width / zoom) / 2} ${(canvasSize.height - canvasSize.height / zoom) / 2} ${canvasSize.width / zoom} ${canvasSize.height / zoom}`;
  const tableCount = objects.filter((object) => object.type === "table").length;
  const seatCount = objects.reduce((sum, object) => sum + (object.type === "table" ? object.capacity ?? 0 : 0), 0);
  const demoTable = objects.find((object) => object.id === "demo-table-1");
  const statusText = demoPhase === "select" ? copy.editor.chooseTable : demoPhase === "place" ? copy.editor.clickFloor : demoPhase === "added" ? `${copy.editor.tableAdded} · ${copy.editor.editName}` : placement ? `${localizePlacementLabel(placement, copy)} · ${copy.editor.click}` : `${tableCount} ${copy.editor.tables.toLowerCase()} · ${seatCount} ${copy.editor.seats.toLowerCase()}`;

  return (
    <div ref={demoRef} className="mt-10 w-full overflow-hidden rounded-[12px] border border-[#d6d0c9] bg-[#f4f2ef] shadow-[0_22px_70px_rgba(41,38,34,0.14)]">
      <div className="flex min-h-[58px] flex-wrap items-center gap-2 border-b border-[#ded8d1] bg-[#fffdfa] px-3 py-2 sm:px-4">
        <button type="button" className="vynic-neu-control rounded-[7px] p-2 text-vynic-charcoal" aria-label={copy.editor.floor}><ArrowLeft size={17} /></button>
        <div className="min-w-[128px] flex-1 sm:flex-none"><p className="text-sm font-bold">{copy.editor.floor} 1</p><p className={`font-vynic-mono text-[9px] font-semibold uppercase tracking-[0.12em] ${dirty ? "text-[#9b7652]" : "text-vynic-green"}`}>{dirty ? copy.editor.unsaved : copy.editor.ready}</p></div>
        <div className="hidden h-7 w-px bg-vynic-border sm:block" />
        <IconButton icon={ArrowCounterClockwise} label={copy.editor.undo} onClick={undo} disabled={!history.length || preview} />
        <IconButton icon={ArrowClockwise} label={copy.editor.redo} onClick={redo} disabled={!future.length || preview} />
        <div className="hidden h-7 w-px bg-vynic-border lg:block" />
        <ToggleButton icon={GridFour} label={copy.editor.grid} active={gridVisible} onClick={() => setGridVisible((value) => !value)} />
        <ToggleButton icon={Magnet} label={copy.editor.snap} active={snapEnabled} onClick={() => setSnapEnabled((value) => !value)} />
        <div className="hidden h-7 w-px bg-vynic-border xl:block" />
        <div className="hidden items-center gap-0.5 xl:flex">
          <IconButton icon={AlignLeft} label="Align left" onClick={() => align("left")} disabled={selected.length < 2 || preview} />
          <IconButton icon={AlignCenterHorizontal} label="Align center" onClick={() => align("centerX")} disabled={selected.length < 2 || preview} />
          <IconButton icon={AlignRight} label="Align right" onClick={() => align("right")} disabled={selected.length < 2 || preview} />
          <IconButton icon={AlignTop} label="Align top" onClick={() => align("top")} disabled={selected.length < 2 || preview} />
          <IconButton icon={AlignCenterVertical} label="Align middle" onClick={() => align("centerY")} disabled={selected.length < 2 || preview} />
          <IconButton icon={AlignBottom} label="Align bottom" onClick={() => align("bottom")} disabled={selected.length < 2 || preview} />
        </div>
        <div className="ml-auto flex items-center gap-2">
          <button type="button" onClick={() => setPreview((value) => !value)} className="hidden items-center gap-2 rounded-[7px] px-3 py-2 text-xs font-bold text-vynic-charcoal hover:bg-vynic-background sm:flex"><Eye size={16} />{preview ? copy.editor.editLayout : copy.editor.preview}</button>
          <button type="button" onClick={save} disabled={!dirty} className={`flex items-center gap-2 rounded-[7px] px-3 py-2 text-xs font-bold text-white transition ${dirty ? "bg-vynic-plum shadow-[0_8px_18px_rgba(118,75,124,0.28)] hover:bg-vynic-plum-dark" : "bg-[#b7b0aa]"}`}><FloppyDisk size={16} />{saved ? copy.editor.saved : copy.editor.save}</button>
        </div>
      </div>

      <div className="flex min-h-[720px] flex-col lg:grid lg:grid-cols-[190px_minmax(0,1fr)_276px]">
        <aside className="order-2 border-t border-[#ded8d1] bg-[#fffdfa] lg:order-1 lg:border-r lg:border-t-0">
          <div className="flex h-full max-h-[400px] gap-4 overflow-x-auto p-3 lg:block lg:max-h-none lg:overflow-y-auto">
            <PaletteGroup title={copy.editor.selection} items={[{ label: copy.editor.selectMove, icon: PencilSimple, placement: null }]} placement={placement} onArm={(next) => { interruptDemo(); setPlacement(next); }} copy={copy} />
            {palettes.map((group) => <PaletteGroup key={group.title} title={localizePaletteGroup(group.title, copy)} items={group.items} placement={placement} onArm={(next) => { interruptDemo(); setPlacement(next); }} highlightLabel={demoPhase === "select" && group.title === "Tables" ? copy.editor.table : undefined} copy={copy} />)}
          </div>
        </aside>

        <section className="order-1 flex min-w-0 flex-col bg-[#edeae6] lg:order-2">
          <div className="flex flex-wrap items-center justify-between gap-3 border-b border-[#d7d1ca] bg-[#f8f7f5] px-4 py-3 text-xs">
            <div className="flex items-center gap-2"><span className="rounded-[6px] border border-vynic-plum bg-[#f1eaf2] px-3 py-1.5 font-bold text-vynic-plum">{copy.editor.floor} 1 <span className="ml-1 rounded-full bg-white px-1.5 py-0.5 text-[10px]">{tableCount}</span></span></div>
            <span aria-live="polite" className={`font-vynic-mono text-[10px] font-semibold uppercase tracking-[0.12em] ${demoPhase !== "idle" || placement ? "text-vynic-plum" : "text-vynic-muted"}`}>{statusText}</span>
          </div>
          <div className="relative flex min-h-[540px] flex-1 items-center justify-center overflow-auto p-4 sm:p-7">
            <svg ref={svgRef} viewBox={viewBox} style={{ aspectRatio: `${canvasSize.width} / ${canvasSize.height}` }} className={`h-auto w-full min-w-[760px] max-w-[1400px] overflow-visible rounded-[5px] border border-[#d8d2cb] bg-white shadow-[0_12px_25px_rgba(41,38,34,0.08)] ${placement ? "cursor-crosshair" : "cursor-default"}`} onPointerDown={onCanvasDown} onPointerMove={onPointerMove} onPointerUp={endDrag} onPointerCancel={endDrag} role="application" aria-label="Interactive floor plan editor">
              <defs>
                <pattern id="fine-grid" width={gridSize} height={gridSize} patternUnits="userSpaceOnUse"><path d={`M ${gridSize} 0 L 0 0 0 ${gridSize}`} fill="none" stroke="#f0eeea" strokeWidth="1" /></pattern>
                <pattern id="major-grid" width={gridSize * 5} height={gridSize * 5} patternUnits="userSpaceOnUse"><rect width={gridSize * 5} height={gridSize * 5} fill="url(#fine-grid)" /><path d={`M ${gridSize * 5} 0 L 0 0 0 ${gridSize * 5}`} fill="none" stroke="#e2ded8" strokeWidth="1.5" /></pattern>
              </defs>
              <rect width={canvasSize.width} height={canvasSize.height} fill="#fff" />
              {gridVisible ? <rect width={canvasSize.width} height={canvasSize.height} fill="url(#major-grid)" /> : null}
              {objects.filter((object) => object.type === "zone").map((object) => <FloorObjectView key={object.id} object={object} selected={selectedIds.includes(object.id)} onPointerDown={selectObject} preview={preview} copy={copy} />)}
              {objects.filter((object) => object.type !== "zone").map((object) => <FloorObjectView key={object.id} object={object} selected={selectedIds.includes(object.id)} onPointerDown={selectObject} preview={preview} copy={copy} />)}
              <DemoGuide phase={demoPhase} object={demoTable} copy={copy} />
              {single && !preview ? <SelectionChrome object={single} onHandle={startHandle} /> : null}
            </svg>
            <div className="absolute bottom-4 left-4 flex items-center gap-1 rounded-[8px] border border-[#d8d2cb] bg-[#fffdfa] p-1.5 shadow-[0_8px_18px_rgba(41,38,34,0.10)]"><button type="button" onClick={() => setZoom((value) => Math.max(0.48, value - 0.08))} className="rounded p-1.5 hover:bg-vynic-background" aria-label="Zoom out"><Minus size={15} /></button><span className="w-12 text-center text-xs font-bold text-vynic-muted">{Math.round(zoom * 100)}%</span><button type="button" onClick={() => setZoom((value) => Math.min(1.15, value + 0.08))} className="rounded p-1.5 hover:bg-vynic-background" aria-label="Zoom in"><Plus size={15} /></button><span className="mx-1 h-4 w-px bg-vynic-border" /><button type="button" onClick={() => setZoom(1)} className="rounded p-1.5 text-vynic-muted hover:bg-vynic-background" aria-label="Fit canvas"><ArrowsOutIcon /></button></div>
          </div>
          <div className="flex flex-wrap items-center gap-x-5 gap-y-2 border-t border-[#d7d1ca] bg-[#f8f7f5] px-4 py-2.5 text-[11px] font-semibold text-vynic-muted"><span><i className="mr-1.5 inline-block h-2 w-2 rounded-full bg-[#d9d3c7]" />{copy.editor.available}</span><span><i className="mr-1.5 inline-block h-2 w-2 rounded-full bg-vynic-plum" />{copy.editor.selected}</span><span className="ml-auto hidden sm:inline">{copy.editor.dragHelp}</span></div>
        </section>

        <aside className="order-3 border-t border-[#ded8d1] bg-[#fffdfa] lg:border-l lg:border-t-0">
          <Inspector object={single} selectedCount={selected.length} tableCount={tableCount} seatCount={seatCount} canvasSize={canvasSize} gridSize={gridSize} copy={copy} onCanvasSizeChange={resizeCanvas} onGridSizeChange={(value) => setGridSize(Math.max(5, Math.min(100, value)))} onAspectChange={(ratio) => resizeCanvas({ width: canvasSize.height * ratio, height: canvasSize.height })} onUpdate={updateObject} onDelete={deleteSelected} onDuplicate={duplicateSelected} onRotate={(degrees) => updateObject({ rotation: ((single?.rotation ?? 0) + degrees + 360) % 360 })} />
        </aside>
      </div>
    </div>
  );
}

function IconButton({ icon: Icon, label, onClick, disabled = false }: { icon: typeof ArrowLeft; label: string; onClick: () => void; disabled?: boolean }) {
  return <button type="button" aria-label={label} title={label} disabled={disabled} onClick={onClick} className="rounded-[7px] p-2 text-vynic-charcoal transition hover:bg-vynic-background disabled:cursor-not-allowed disabled:opacity-30"><Icon size={17} /></button>;
}

function ToggleButton({ icon: Icon, label, active, onClick }: { icon: typeof GridFour; label: string; active: boolean; onClick: () => void }) {
  return <button type="button" title={label} onClick={onClick} className={`flex items-center gap-1.5 rounded-[7px] border px-2.5 py-1.5 text-xs font-bold transition ${active ? "border-vynic-plum bg-[#f1eaf2] text-vynic-plum" : "border-transparent text-vynic-muted hover:bg-vynic-background"}`}><Icon size={15} /> <span className="hidden sm:inline">{label}</span></button>;
}

function localizePaletteGroup(title: string, copy: SiteCopy) {
  return title === "Tables" ? copy.editor.tables : title === "Structure" ? copy.editor.structure : title === "Objects" ? copy.editor.objects : copy.editor.annotation;
}

function localizePlacementLabel(placement: Placement, copy: SiteCopy) {
  if (placement.type === "table") return placement.label.includes("Round") ? copy.editor.roundTable : placement.label.includes("Booth") ? copy.editor.booth : placement.label.includes("Communal") ? copy.editor.communal : copy.editor.table;
  if (placement.type === "wall") return copy.editor.wall;
  if (placement.type === "divider") return copy.editor.divider;
  if (placement.type === "entrance") return copy.editor.entrance;
  if (placement.type === "bar") return copy.editor.bar;
  if (placement.type === "stage") return copy.editor.stage;
  if (placement.type === "stairs") return copy.editor.stairs;
  if (placement.type === "zone") return copy.editor.zone;
  return copy.editor.label;
}

function localizedPaletteItemLabel(label: string, copy: SiteCopy) {
  if (label === "Table") return copy.editor.table;
  if (label === "Round table") return copy.editor.roundTable;
  if (label === "Booth") return copy.editor.booth;
  if (label === "Communal") return copy.editor.communal;
  if (label === "Wall") return copy.editor.wall;
  if (label === "Divider") return copy.editor.divider;
  if (label === "Entrance") return copy.editor.entrance;
  if (label === "Bar") return copy.editor.bar;
  if (label === "Stage") return copy.editor.stage;
  if (label === "Stairs") return copy.editor.stairs;
  if (label === "Zone") return copy.editor.zone;
  return copy.editor.label;
}

function localizedVariantLabel(label: string, copy: SiteCopy) {
  if (copy === undefined) return label;
  if (label.includes("Rectangle") && label.includes("4")) return `${copy.editor.rectangle} · 4 ${copy.editor.seats.toLowerCase()}`;
  if (label.includes("Rectangle") && label.includes("6")) return `${copy.editor.rectangle} · 6 ${copy.editor.seats.toLowerCase()}`;
  if (label.includes("Square")) return `${copy.editor.square} · 4 ${copy.editor.seats.toLowerCase()}`;
  if (label.includes("Round") && label.includes("2")) return `${copy.editor.round} · 2 ${copy.editor.seats.toLowerCase()}`;
  if (label.includes("Round") && label.includes("4")) return `${copy.editor.round} · 4 ${copy.editor.seats.toLowerCase()}`;
  if (label.includes("Round") && label.includes("6")) return `${copy.editor.round} · 6 ${copy.editor.seats.toLowerCase()}`;
  return label;
}

function PaletteGroup({ title, items, placement, onArm, highlightLabel, copy }: { title: string; items: Array<{ label: string; icon: typeof Table; placement: Placement | null; variants?: Placement[] }>; placement: Placement | null; onArm: (placement: Placement | null) => void; highlightLabel?: string; copy: SiteCopy }) {
  return <div className="min-w-[160px] lg:min-w-0"><p className="mb-2 mt-1 px-2 font-vynic-mono text-[9px] font-bold uppercase tracking-[0.14em] text-[#938b84]">{title}</p>{items.map(({ label, icon: Icon, placement: itemPlacement, variants }) => { const highlighted = highlightLabel === (label === "Table" ? copy.editor.table : label); const expanded = Boolean(variants && placement?.label === itemPlacement?.label); return <div key={label} className="relative mb-1"><button type="button" aria-expanded={variants ? expanded : undefined} onClick={() => onArm(itemPlacement)} className={`relative flex w-full items-center gap-2 rounded-[7px] border px-2.5 py-2 text-left text-xs font-bold transition ${highlighted ? "border-vynic-plum bg-[#f1eaf2] text-vynic-plum shadow-[0_0_0_3px_rgba(118,75,124,0.14)]" : placement?.label === itemPlacement?.label ? "border-vynic-plum bg-[#f1eaf2] text-vynic-plum" : "border-transparent text-vynic-charcoal hover:border-vynic-border hover:bg-vynic-background"}`}><Icon size={17} /><span className="flex-1 truncate">{localizedPaletteItemLabel(label, copy)}</span>{variants ? <CaretDown size={13} className="text-vynic-muted" /> : null}{highlighted ? <span className="pointer-events-none absolute -right-1 -top-3 rounded-full bg-vynic-plum px-2 py-1 font-vynic-mono text-[8px] font-bold uppercase tracking-[0.08em] text-white shadow-[0_4px_10px_rgba(118,75,124,0.24)]">1 · {copy.editor.click}</span> : null}</button>{expanded && variants ? <div className="absolute left-6 top-full z-30 mt-1 grid w-[calc(100%-1.5rem)] gap-1 rounded-[7px] border border-vynic-border bg-[#f8f7f5] p-1.5 shadow-[0_10px_24px_rgba(41,38,34,0.14)]">{variants.map((variant) => <button key={variant.label} type="button" onClick={() => onArm(variant)} className="rounded px-2 py-1.5 text-left text-[10px] font-semibold text-vynic-muted hover:bg-white hover:text-vynic-plum">{localizedVariantLabel(variant.label, copy)}</button>)}</div> : null}</div>; })}</div>;
}

function localizeObjectLabel(object: FloorObject, copy: SiteCopy) {
  if (object.type === "table" && object.label === "Table") return copy.editor.table;
  if (object.type === "bar" && object.label === "Bar") return copy.editor.bar;
  if (object.type === "stage" && object.label === "Stage") return copy.editor.stage;
  if (object.type === "entrance" && object.label === "Entrance") return copy.editor.entrance;
  return object.label;
}

function FloorObjectView({ object, selected, onPointerDown, preview, copy }: { object: FloorObject; selected: boolean; onPointerDown: (event: React.PointerEvent, id: string) => void; preview: boolean; copy: SiteCopy }) {
  const isTable = object.type === "table";
  const shape = object.shape === "circle" ? "999" : object.shape === "booth" ? "16" : object.shape === "long" ? "10" : "6";
  const fill = selected ? "#f1e8f3" : object.color === "blue" ? "#efeaf1" : object.color === "pink" ? "#fff0f7" : object.color === "amber" ? "#fff7df" : object.type === "zone" ? "#f5f0f7" : "#fffdfa";
  const stroke = selected ? "#764b7c" : object.color === "blue" ? "#65516e" : object.color === "pink" ? "#df70a9" : object.color === "amber" ? "#c39a35" : object.type === "wall" ? "#3a342c" : object.type === "divider" ? "#8a8175" : "#c8c0b6";
  const radius = object.type === "table" ? shape : object.type === "wall" || object.type === "divider" ? "4" : "8";
  return <g transform={`translate(${object.x + object.width / 2} ${object.y + object.height / 2}) rotate(${object.rotation}) translate(${-object.width / 2} ${-object.height / 2})`} onPointerDown={(event) => onPointerDown(event, object.id)} opacity={preview && !isTable ? 0.82 : 1}>
    {object.type === "entrance" ? <rect width={object.width} height={object.height} rx={radius} fill="#fffdf7" stroke="#ead9a8" strokeWidth="1.5" /> : object.type === "zone" ? <rect width={object.width} height={object.height} rx={radius} fill={fill} stroke={stroke} strokeDasharray="8 7" strokeWidth={selected ? 4 : 2} /> : <rect width={object.width} height={object.height} rx={radius} fill={fill} stroke={stroke} strokeWidth={selected ? 3 : object.type === "wall" ? 8 : 2} />}
    {isTable && <><SeatDots object={object} /><Table size={Math.min(object.width, object.height) > 100 ? 22 : 18} x={object.width / 2 - 11} y={object.height / 2 - 30} weight="duotone" color={selected ? "#764b7c" : "#292622"} /><text x={object.width / 2} y={object.height / 2 + 18} textAnchor="middle" fontSize="17" fontWeight="800" fill={selected ? "#4a2f4e" : "#292622"}>{localizeObjectLabel(object, copy)}</text><text x={object.width / 2} y={object.height / 2 + 38} textAnchor="middle" fontSize="13" fontWeight="700" fill="#817a73">{object.capacity ?? 0}</text></>}
    {object.type === "entrance" ? <EntranceGlyph width={object.width} height={object.height} color={stroke} label={copy.editor.entrance} /> : null}
    {!isTable && object.type !== "entrance" && <text x={object.width / 2} y={object.height / 2 + 5} textAnchor="middle" fontSize="16" fontWeight="800" fill={stroke}>{localizeObjectLabel(object, copy)}</text>}
  </g>;
}

function EntranceGlyph({ width, height, color, label }: { width: number; height: number; color: string; label: string }) {
  const left = width * 0.14;
  const right = width * 0.86;
  const top = height * 0.18;
  const bottom = height * 0.78;
  const hingeX = left + 2;
  const leafX = width * 0.58;
  const leafY = top + 2;
  return <g aria-label={`${label} door`}><path d={`M ${left} ${bottom} V ${top} H ${right} V ${bottom}`} fill="none" stroke="#8a8175" strokeWidth="3.5" strokeLinecap="round" strokeLinejoin="round" /><path d={`M ${hingeX} ${bottom} L ${leafX} ${leafY}`} fill="none" stroke={color} strokeWidth="4.5" strokeLinecap="round" /><path d={`M ${hingeX} ${bottom} A ${width * 0.52} ${width * 0.52} 0 0 1 ${leafX} ${leafY}`} fill="none" stroke="#b5a88e" strokeWidth="2.5" strokeDasharray="5 4" /><circle cx={hingeX} cy={bottom} r="4" fill={color} /><text x={width / 2} y={height * 0.96} textAnchor="middle" fontSize="11" fontWeight="800" fill="#735b25">{label}</text></g>;
}

function DemoGuide({ phase, object, copy }: { phase: DemoPhase; object?: FloorObject; copy: SiteCopy }) {
  if (phase === "place") return <g pointerEvents="none" aria-label="Demo: click to place a table"><circle cx={demoTablePosition.x + 75} cy={demoTablePosition.y + 56} r="78" fill="#764b7c" fillOpacity="0.05" stroke="#764b7c" strokeWidth="3" strokeDasharray="10 8" className="vynic-demo-pulse" /><g transform={`translate(${demoTablePosition.x + 107} ${demoTablePosition.y + 104})`} className="vynic-demo-cursor"><path d="M 0 0 L 0 28 L 8 21 L 14 35 L 20 32 L 14 18 L 27 18 Z" fill="#764b7c" stroke="#fffdfa" strokeWidth="3" strokeLinejoin="round" /><rect x="-62" y="38" width="124" height="28" rx="14" fill="#764b7c" /><text x="0" y="56" textAnchor="middle" fontSize="12" fontWeight="800" fill="#fffdfa">{copy.editor.place}</text></g></g>;
  if (phase === "added") {
    const x = object?.x ?? demoTablePosition.x;
    const y = object?.y ?? demoTablePosition.y;
    const width = object?.width ?? demoTablePlacement.width;
    return <g pointerEvents="none" aria-label={`Demo: ${copy.editor.tableAdded}`}><rect x={x + Math.max(8, (width - 116) / 2)} y={y - 34} width="116" height="25" rx="12.5" fill="#764b7c" /><text x={x + width / 2} y={y - 17} textAnchor="middle" fontSize="11" fontWeight="800" fill="#fffdfa">{copy.editor.tableAdded}</text></g>;
  }
  return null;
}

function SeatDots({ object }: { object: FloorObject }) {
  if (object.shape === "circle") return <><circle cx={object.width / 2} cy="-9" r="6" fill="#d9d3c7" /><circle cx={object.width / 2} cy={object.height + 9} r="6" fill="#d9d3c7" /><circle cx="-9" cy={object.height / 2} r="6" fill="#d9d3c7" /><circle cx={object.width + 9} cy={object.height / 2} r="6" fill="#d9d3c7" /></>;
  return <><rect x={object.width * 0.28} y="-9" width="18" height="10" rx="4" fill="#d9d3c7" /><rect x={object.width * 0.62} y="-9" width="18" height="10" rx="4" fill="#d9d3c7" /><rect x={object.width * 0.28} y={object.height - 1} width="18" height="10" rx="4" fill="#d9d3c7" /><rect x={object.width * 0.62} y={object.height - 1} width="18" height="10" rx="4" fill="#d9d3c7" /></>;
}

function SelectionChrome({ object, onHandle }: { object: FloorObject; onHandle: (event: React.PointerEvent<SVGCircleElement>, mode: "resize" | "rotate") => void }) {
  const cx = object.x + object.width / 2;
  const cy = object.y + object.height / 2;
  return <g transform={`rotate(${object.rotation} ${cx} ${cy})`} pointerEvents="all"><rect x={object.x - 8} y={object.y - 8} width={object.width + 16} height={object.height + 16} rx="8" fill="none" stroke="#764b7c" strokeDasharray="7 5" strokeWidth="2" /><line x1={cx} y1={object.y - 8} x2={cx} y2={object.y - 34} stroke="#764b7c" strokeWidth="2" /><circle cx={cx} cy={object.y - 45} r="9" fill="#fffdfa" stroke="#764b7c" strokeWidth="2" onPointerDown={(event) => onHandle(event, "rotate")} /><ArrowClockwise x={cx - 7} y={object.y - 52} size={14} color="#764b7c" /><circle cx={object.x + object.width + 8} cy={object.y + object.height + 8} r="8" fill="#764b7c" stroke="#fffdfa" strokeWidth="3" onPointerDown={(event) => onHandle(event, "resize")} /></g>;
}

function Inspector({ object, selectedCount, tableCount, seatCount, canvasSize, gridSize, copy, onCanvasSizeChange, onGridSizeChange, onAspectChange, onUpdate, onDelete, onDuplicate, onRotate }: { object: FloorObject | null; selectedCount: number; tableCount: number; seatCount: number; canvasSize: { width: number; height: number }; gridSize: number; copy: SiteCopy; onCanvasSizeChange: (size: { width: number; height: number }) => void; onGridSizeChange: (value: number) => void; onAspectChange: (ratio: number) => void; onUpdate: (changes: Partial<FloorObject>) => void; onDelete: () => void; onDuplicate: () => void; onRotate: (degrees: number) => void }) {
  if (selectedCount > 1) return <div className="p-4 sm:p-5"><InspectorLabel text={`${selectedCount} ${copy.editor.objectsSelected}`} /><p className="mt-2 text-sm leading-6 text-vynic-muted">{copy.editor.alignHelp}</p><div className="mt-5 grid gap-2"><ActionButton icon={Copy} label={copy.editor.duplicate} onClick={onDuplicate} /><ActionButton icon={Trash} label={copy.editor.delete} onClick={onDelete} danger /></div></div>;
  if (!object) return <FloorInspector copy={copy} tableCount={tableCount} seatCount={seatCount} canvasSize={canvasSize} gridSize={gridSize} onCanvasSizeChange={onCanvasSizeChange} onGridSizeChange={onGridSizeChange} onAspectChange={onAspectChange} />;
  const isTable = object.type === "table";
  return <div className="p-4 sm:p-5"><div className="flex items-start justify-between gap-3"><div><InspectorLabel text={isTable ? copy.editor.table : copy.editor.objects} /><h3 className="mt-1 text-lg font-bold text-vynic-charcoal">{object.label}</h3></div><span className="rounded-full bg-[#f1eaf2] px-2 py-1 font-vynic-mono text-[9px] font-bold uppercase tracking-[0.12em] text-vynic-plum">{copy.editor.selected}</span></div><div className="mt-5 grid gap-3"><Field label={copy.form.name} value={object.label} onChange={(value) => onUpdate({ label: value })} /><div className="grid grid-cols-2 gap-2"><NumberField label={copy.editor.width} value={Math.round(object.width)} onChange={(value) => onUpdate({ width: value })} /><NumberField label={copy.editor.height} value={Math.round(object.height)} onChange={(value) => onUpdate({ height: value })} /></div><NumberField label={copy.editor.rotation} value={Math.round(object.rotation)} suffix="°" onChange={(value) => onUpdate({ rotation: value })} /></div>{isTable ? <><InspectorLabel text={copy.editor.shape} className="mt-6" /><div className="mt-2 grid grid-cols-3 gap-1.5">{(["rectangle", "square", "circle", "long", "booth", "barSeat"] as TableShape[]).map((shape) => <button key={shape} type="button" onClick={() => onUpdate({ shape, width: shape === "circle" || shape === "square" ? Math.max(object.width, object.height) : object.width, height: shape === "circle" || shape === "square" ? Math.max(object.width, object.height) : object.height })} className={`rounded-[6px] border px-1 py-2 text-[10px] font-bold capitalize ${object.shape === shape ? "border-vynic-plum bg-[#f1eaf2] text-vynic-plum" : "border-vynic-border text-vynic-muted hover:bg-vynic-background"}`}>{shape === "barSeat" ? copy.editor.barSeat : shape === "rectangle" ? copy.editor.rectangle : shape === "square" ? copy.editor.square : shape === "circle" ? copy.editor.round : shape}</button>)}</div><div className="mt-3"><NumberField label={copy.editor.seats} value={object.capacity ?? 0} onChange={(value) => onUpdate({ capacity: value })} /></div></> : null}<InspectorLabel text={copy.editor.transform} className="mt-6" /><div className="mt-2 grid grid-cols-2 gap-2"><ActionButton icon={ArrowCounterClockwise} label="-90°" onClick={() => onRotate(-90)} /><ActionButton icon={ArrowClockwise} label="+90°" onClick={() => onRotate(90)} /></div><div className="mt-6 grid grid-cols-2 gap-2"><ActionButton icon={Copy} label={copy.editor.duplicate} onClick={onDuplicate} /><ActionButton icon={Trash} label={copy.editor.delete} onClick={onDelete} danger /></div></div>;
}

function FloorInspector({ copy, tableCount, seatCount, canvasSize, gridSize, onCanvasSizeChange, onGridSizeChange, onAspectChange }: { copy: SiteCopy; tableCount: number; seatCount: number; canvasSize: { width: number; height: number }; gridSize: number; onCanvasSizeChange: (size: { width: number; height: number }) => void; onGridSizeChange: (value: number) => void; onAspectChange: (ratio: number) => void }) {
  const ratio = canvasSize.width / canvasSize.height;
  return <div className="p-4 sm:p-5"><InspectorLabel text={copy.editor.floor} /><Field label={copy.editor.floorName} value={`${copy.editor.floor} 1`} onChange={() => undefined} /><InspectorLabel text={copy.editor.canvas} className="mt-6" /><div className="mt-2 grid grid-cols-2 gap-2"><NumberField label={copy.editor.width} value={Math.round(canvasSize.width)} onChange={(value) => onCanvasSizeChange({ width: Math.max(400, value), height: canvasSize.height })} /><NumberField label={copy.editor.height} value={Math.round(canvasSize.height)} onChange={(value) => onCanvasSizeChange({ width: canvasSize.width, height: Math.max(400, value) })} /></div><InspectorLabel text={copy.editor.canvasRatio} className="mt-6" /><div className="mt-2 grid gap-1.5">{[[1.6, "16:10"], [16 / 9, "16:9"], [4 / 3, "4:3"]].map(([value, label]) => <button key={label} type="button" onClick={() => onAspectChange(Number(value))} className={`rounded-[7px] border px-3 py-2 text-left text-xs font-bold transition ${Math.abs(ratio - Number(value)) < 0.02 ? "border-vynic-plum bg-[#f1eaf2] text-vynic-plum" : "border-vynic-border text-vynic-muted hover:bg-vynic-background"}`}>{label}</button>)}</div><NumberField label={copy.editor.gridStep} value={gridSize} onChange={onGridSizeChange} /><div className="mt-5 grid grid-cols-2 gap-2"><Stat label={copy.editor.tables} value={String(tableCount)} /><Stat label={copy.editor.seats} value={String(seatCount)} /></div><div className="mt-6 rounded-[8px] border border-vynic-border bg-[#f8f7f5] p-3 text-xs leading-5 text-vynic-muted"><p className="font-bold text-vynic-charcoal">{copy.editor.editRoom}</p><p className="mt-1">{copy.editor.editRoomBody}</p></div></div>;
}

function InspectorLabel({ text, className = "" }: { text: string; className?: string }) { return <p className={`font-vynic-mono text-[10px] font-bold uppercase tracking-[0.14em] text-[#938b84] ${className}`}>{text}</p>; }
function Field({ label, value, onChange }: { label: string; value: string; onChange: (value: string) => void }) { return <label className="grid gap-1.5 text-xs font-bold text-vynic-muted">{label}<input value={value} onChange={(event) => onChange(event.target.value)} onBlur={(event) => onChange(event.target.value)} className="vynic-neu-inset min-w-0 rounded-[7px] border border-vynic-border px-2.5 py-2 text-sm font-bold text-vynic-charcoal outline-none focus:border-vynic-plum" /></label>; }
function NumberField({ label, value, suffix, onChange }: { label: string; value: number; suffix?: string; onChange: (value: number) => void }) { return <label className="grid gap-1.5 text-xs font-bold text-vynic-muted">{label}<span className="relative"><input type="number" value={value} onChange={(event) => { const next = Number(event.target.value); if (Number.isFinite(next)) onChange(next); }} className="vynic-neu-inset w-full rounded-[7px] border border-vynic-border px-2.5 py-2 text-sm font-bold text-vynic-charcoal outline-none focus:border-vynic-plum" />{suffix ? <span className="absolute right-2.5 top-2.5 text-xs text-vynic-muted">{suffix}</span> : null}</span></label>; }
function Stat({ label, value }: { label: string; value: string }) { return <div className="rounded-[7px] border border-vynic-border bg-[#f8f7f5] p-3"><p className="font-vynic-mono text-[9px] font-bold uppercase tracking-[0.1em] text-vynic-muted">{label}</p><p className="mt-1 text-lg font-bold">{value}</p></div>; }
function ActionButton({ icon: Icon, label, onClick, danger = false }: { icon: typeof Copy; label: string; onClick: () => void; danger?: boolean }) { return <button type="button" onClick={onClick} className={`flex items-center justify-center gap-2 rounded-[7px] border px-2.5 py-2 text-xs font-bold transition ${danger ? "border-[#e3c9c6] text-vynic-red hover:bg-[#fbefed]" : "border-vynic-border text-vynic-charcoal hover:bg-vynic-background"}`}><Icon size={15} />{label}</button>; }
function ArrowsOutIcon() { return <span className="inline-flex h-[15px] w-[15px] items-center justify-center text-[13px] font-bold">↗</span>; }
