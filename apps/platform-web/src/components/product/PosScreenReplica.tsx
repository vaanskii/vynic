import {
  Bell,
  CalendarBlank,
  CheckCircle,
  CreditCard,
  FileText,
  Gear,
  MagnifyingGlass,
  Martini,
  FilmStrip,
  Plus,
  Printer,
  SquaresFour,
  WarningCircle,
  X,
} from "@phosphor-icons/react";
import { useEffect, useLayoutEffect, useRef, useState } from "react";
import { useReducedMotion } from "motion/react";
import type { ScreenshotSpec } from "../../data/siteContent";
import { useLocale } from "../../lib/i18n";

type ReplicaKind = NonNullable<ScreenshotSpec["replica"]>;

const ink = "#292622";
const muted = "#79736c";
const border = "#e7e2dc";
const paper = "#fffdfa";
const purple = "#5b4b86";

export function PosScreenReplica({
  kind,
  live = false,
  onLiveStageChange,
}: {
  kind: ReplicaKind;
  live?: boolean;
  onLiveStageChange?: (stage: number) => void;
}) {
  const frameRef = useRef<HTMLDivElement>(null);
  const [mobileScale, setMobileScale] = useState<number | null>(null);
  const [liveStage, setLiveStage] = useState(0);
  const [liveTransitioning, setLiveTransitioning] = useState(false);
  const reduceMotion = useReducedMotion();
  const baseHeight = kind === "floor" ? 474 : 500;

  useEffect(() => {
    onLiveStageChange?.(liveStage);
  }, [liveStage, onLiveStageChange]);

  useEffect(() => {
    if (!live || kind !== "floor" || reduceMotion) return;

    let transitionTimeout: number | undefined;
    const interval = window.setInterval(() => {
      setLiveStage((stage) => (stage + 1) % 3);
      setLiveTransitioning(true);
      window.clearTimeout(transitionTimeout);
      transitionTimeout = window.setTimeout(() => setLiveTransitioning(false), 1100);
    }, 4200);

    return () => {
      window.clearInterval(interval);
      window.clearTimeout(transitionTimeout);
    };
  }, [kind, live, reduceMotion]);

  useLayoutEffect(() => {
    const frame = frameRef.current;
    if (!frame) return;

    const updateScale = () => {
      if (frame.clientWidth >= 640) {
        setMobileScale(null);
        return;
      }

      setMobileScale(Math.min(frame.clientWidth / 850, frame.clientHeight / baseHeight));
    };

    updateScale();
    const observer = new ResizeObserver(updateScale);
    observer.observe(frame);
    return () => observer.disconnect();
  }, [baseHeight]);

  const screen = (
    <ReplicaScreen
      kind={kind}
      live={live}
      liveStage={liveStage}
      liveTransitioning={liveTransitioning}
    />
  );

  return (
    <div
      ref={frameRef}
      className="relative h-full w-full overflow-hidden bg-[#f7f5f2] font-sans text-[10px] leading-tight text-[#292622]"
      role="img"
      aria-label={`Vynic POS ${kind} screen`}
    >
      {live ? <span className="vynic-live-boot-line pointer-events-none absolute inset-y-0 left-0 z-20 w-[24%]" /> : null}
      {mobileScale === null ? screen : (
        <div className="relative h-full w-full overflow-hidden">
          <div
            className="absolute left-1/2 top-1/2 origin-center"
            style={{
              width: 850,
              height: baseHeight,
              transform: `translate(-50%, -50%) scale(${mobileScale})`,
            }}
          >
            {screen}
          </div>
        </div>
      )}
    </div>
  );
}

function ReplicaScreen({
  kind,
  live,
  liveStage,
  liveTransitioning,
}: {
  kind: ReplicaKind;
  live: boolean;
  liveStage: number;
  liveTransitioning: boolean;
}) {
  return <div className="h-full w-full overflow-hidden bg-[#f7f5f2]">
    {kind === "floor" ? (
      <FloorReplica live={live} liveStage={liveStage} liveTransitioning={liveTransitioning} />
    ) : null}
    {kind === "table-order" ? <TableOrderReplica /> : null}
    {kind === "order-editor" ? <OrderEditorReplica /> : null}
    {kind === "payment" ? <PaymentReplica /> : null}
    {kind === "day-close" ? <DayCloseReplica /> : null}
  </div>;
}

function TopBar({ title = "Vynic POS", back = false, compact = false, time = "22:05", live = false }: { title?: string; back?: boolean; compact?: boolean; time?: string; live?: boolean }) {
  const { copy } = useLocale();
  const s = copy.screen;
  const statusDotClass = `bg-[#5f9b69] ${live ? "vynic-live-dot" : ""}`;

  return (
    <div className={`flex items-center justify-between border-b border-[#e4dfd9] bg-white px-3 text-[9px] font-semibold sm:px-4 ${compact ? "h-[6%] min-h-[24px]" : "h-[8.5%] min-h-[31px]"}`}>
      <div className="flex min-w-0 items-center gap-3">
        <span className="flex h-5 w-5 shrink-0 items-center justify-center rounded-[5px] bg-[#f2edf7] text-[12px] font-black text-[#5b4b86]">V</span>
        {back ? <span className="text-[13px] text-[#4e4944]">←</span> : null}
        <span className="truncate text-[12px]">{title}</span>
        <span className="hidden border-l border-[#e7e2dc] pl-3 text-[#857e77] sm:inline">{s.tables}</span>
      </div>
      <div className="flex items-center gap-2 text-[#766f68]">
        <span className="hidden rounded-[5px] bg-[#edf5ed] px-2 py-1 text-[#52745b] sm:inline"><span className={`mr-1 inline-block h-1.5 w-1.5 rounded-full ${statusDotClass}`} />{s.online}</span>
        <span className="font-mono text-[11px]">{time}</span>
        <span className="rounded-[5px] border border-[#e7e2dc] px-2 py-1">KA</span>
        <Bell size={13} weight="bold" />
        <span className="hidden rounded-[5px] border border-[#e7e2dc] bg-[#faf9f7] px-2 py-1 sm:inline">{s.onDuty}</span>
      </div>
    </div>
  );
}

function NavBar({ active, compact = false }: { active?: string; compact?: boolean }) {
  const { copy } = useLocale();
  const s = copy.screen;
  const activeLabel = active ?? s.tables;
  const items = [{ label: s.tables }, { label: s.count }, { label: s.takeaways, count: "1" }, { label: s.reservation }, { label: "X" }];
  return (
    <div className={`flex items-center gap-2 overflow-hidden border-b border-[#e7e2dc] bg-white px-2 text-[9px] font-semibold text-[#817a73] sm:gap-5 sm:px-4 ${compact ? "h-[6%] min-h-[24px]" : "h-[7.5%] min-h-[28px]"}`}>
      {items.map(({ label, count }) => (
        <div key={label} className={`flex min-w-0 shrink items-center gap-1 whitespace-nowrap rounded-[5px] sm:gap-1.5 ${compact ? "px-2 py-1" : "px-3 py-2"} ${label === activeLabel ? "bg-[#f2edf8] text-[#5b4b86]" : ""}`}>
          {label}{count ? <span className="flex h-4 min-w-4 items-center justify-center rounded-full bg-[#fae9e3] px-1 text-[8px] text-[#9a5c4e]">{count}</span> : null}
        </div>
      ))}
      <span className="ml-auto hidden shrink-0 rounded-[5px] bg-[#5b4b86] px-3 py-1.5 text-white sm:inline">{s.settings}</span>
    </div>
  );
}

function FloorTabs() {
  const { copy } = useLocale();
  const s = copy.screen;
  return (
    <div className="flex min-h-[26px] items-center gap-2 overflow-hidden bg-[#f7f6f4] px-2 py-1 text-[7px] font-semibold text-[#817a73] sm:gap-3 sm:px-3">
      <div className="flex shrink-0 rounded-[6px] border border-[#e7e2dc] bg-white p-0.5 shadow-[0_1px_2px_rgba(41,38,34,0.04)]">
        <span className="whitespace-nowrap rounded-[4px] bg-[#f2edf8] px-2 py-1 text-[#5b4b86]">{s.floorOne} <b className="ml-1 rounded-full bg-white px-1 py-0.5">8</b></span>
        <span className="whitespace-nowrap px-2 py-1">{s.floorTwo} <b className="ml-1 rounded-full bg-[#f7f5f2] px-1 py-0.5">4</b></span>
      </div>
      <div className="hidden min-w-0 items-center gap-3 overflow-hidden sm:flex">
        <span className="whitespace-nowrap"><i className="mr-1 inline-block h-1.5 w-1.5 rounded-full bg-[#dedbd7]" />{s.free}</span>
        <span className="whitespace-nowrap"><i className="mr-1 inline-block h-1.5 w-1.5 rounded-full bg-[#d5a424]" />{s.occupied}</span>
        <span className="whitespace-nowrap"><i className="mr-1 inline-block h-1.5 w-1.5 rounded-full bg-[#cbb6d9]" />{s.reserved}</span>
      </div>
    </div>
  );
}

function SectionTitle({ eyebrow, title, action }: { eyebrow: string; title: string; action?: string }) {
  return (
    <div className="flex items-end justify-between gap-3">
      <div>
        <p className="mb-1 text-[8px] font-semibold uppercase tracking-[0.12em] text-[#817a73]">{eyebrow}</p>
        <h3 className="text-[16px] font-bold tracking-[-0.02em]">{title}</h3>
      </div>
      {action ? <span className="rounded-[5px] bg-[#f0ecf7] px-2 py-1 text-[8px] font-semibold text-[#5b4b86]">{action}</span> : null}
    </div>
  );
}

function TinyCard({ label, value, tone = "white", compact = false }: { label: string; value: string; tone?: "white" | "purple" | "green" | "amber"; compact?: boolean }) {
  const tones = { white: "border-[#e7e2dc] bg-white", purple: "border-[#ddd3ed] bg-[#f2edf8]", green: "border-[#d9e2d7] bg-[#f1f5ef]", amber: "border-[#dfd1b5] bg-[#f7f1e5]" };
  return <div className={`min-w-0 overflow-hidden rounded-[6px] border ${compact ? "px-1.5 py-1.5" : "px-2.5 py-2"} ${tones[tone]}`}><p className={`${compact ? "break-words text-[6px] leading-[1.15] [overflow-wrap:anywhere]" : "text-[8px]"} text-[#79736c]`}>{label}</p><p className={`${compact ? "mt-0.5 text-[11px]" : "mt-1 text-[13px]"} font-bold`}>{value}</p></div>;
}

function FloorReplica({ live, liveStage, liveTransitioning }: { live: boolean; liveStage: number; liveTransitioning: boolean }) {
  const { copy, locale } = useLocale();
  const s = copy.screen;
  const activeNote = locale === "ka" ? "აქტიური" : "Active";
  const tableEight = liveStage === 1
    ? { name: "Table 8", total: "", status: "reserved", note: `${s.reserved} · 20:30`, seats: `6 ${s.seats}` }
    : liveStage === 2
      ? { name: "Table 8", total: "189.50 ₾", status: "occupied", note: `${activeNote} · Walk-in`, seats: `6 ${s.seats}` }
      : { name: "Table 8", total: "", status: "free", note: "", seats: `6 ${s.seats}` };
  const tables = [
    { name: "Table 1", total: "404.80 ₾", status: "occupied", note: `${activeNote} · Walk-in`, seats: `6 ${s.seats}`, position: "left-[24.8%] top-[36.6%]", shape: "square" },
    { name: "Table 2", total: "", status: "free", note: "", seats: `6 ${s.seats}`, position: "left-[24.8%] top-[21.9%]", shape: "round" },
    { name: "Table 3", total: "", status: "free", note: "", seats: `6 ${s.seats}`, position: "left-[40.1%] top-[21.9%]", shape: "round" },
    { name: "Table 4", total: "", status: "free", note: "", seats: `6 ${s.seats}`, position: "left-[56.7%] top-[25.5%]", shape: "long" },
    { name: "Table 5", total: "", status: "free", note: "", seats: `6 ${s.seats}`, position: "left-[16%] top-[65%]", shape: "round" },
    { name: "Table 6", total: "", status: "free", note: "", seats: `6 ${s.seats}`, position: "left-[30%] top-[80%]", shape: "long" },
    { name: "Table 7", total: "", status: "free", note: "", seats: `6 ${s.seats}`, position: "left-[47%] top-[80%]", shape: "round" },
    { ...tableEight, position: "left-[62%] top-[80%]", shape: "long" },
    { name: "Table 9", total: "", status: "free", note: "", seats: `6 ${s.seats}`, position: "left-[77%] top-[80%]", shape: "round" },
  ] as const;
  const counts = liveStage === 2 ? ["6", "2", "0"] : liveStage === 1 ? ["7", "1", "1"] : ["8", "1", "0"];
  const nextReservation = liveStage === 0 ? `8 ${s.guestCount} · Table 1, Table 2` : `4 ${s.guestCount} · Table 8`;

  return <div className="flex h-full min-h-0 flex-col"><TopBar compact time="20:45" live={live} /><NavBar compact /><FloorTabs />
    <div className="grid min-h-0 flex-1 grid-cols-1 gap-2 p-2 sm:grid-cols-[1fr_18%] sm:p-3">
      <div className="min-h-0 rounded-[7px] border border-[#ddd8d1] bg-white p-1.5 shadow-[0_8px_18px_rgba(41,38,34,0.05)]">
        <div className="relative h-full overflow-hidden rounded-[5px] border border-[#e8e4df] bg-[#fff]">
          {live && liveTransitioning ? <span className="vynic-live-activity-sweep pointer-events-none absolute inset-y-0 left-0 z-10 w-[24%]" /> : null}
          <div className="absolute left-[8%] top-[7%] flex h-[11%] w-[28%] items-center justify-center gap-1.5 rounded-[6px] border-2 border-[#2499e5] bg-[#dff2ff] text-[9px] font-bold text-[#1c668f]"><Martini size={11} weight="bold" />{copy.editor.bar}</div>
          <div className="absolute left-[65%] top-[7%] flex h-[13%] w-[21%] items-center justify-center gap-1.5 rounded-[6px] border-2 border-[#f04496] bg-[#fde5f0] text-[8px] font-bold text-[#9b2f61]"><FilmStrip size={11} weight="fill" />{copy.editor.stage}</div>
          <div className="absolute right-[2%] top-[41%] flex h-[25%] w-[7%] items-center justify-center rounded-[5px] border-2 border-[#d5a424] bg-[#fff7df] text-[7px] font-bold text-[#956c17] [writing-mode:vertical-rl]">{copy.editor.entrance} →</div>
          {tables.map(({ name, total, status, note, seats, position, shape }) => {
            const style = status === "occupied"
              ? "border-[#eb5de0] bg-[#fff0fa]"
              : status === "reserved"
                ? "border-[#cbb6d9] bg-[#f5eff9]"
                : "border-[#e8e4e0] bg-[#fff]";
            const shapeClass = shape === "round"
              ? "h-[12.8%] w-[10.5%]"
              : shape === "long"
                ? "h-[10.8%] w-[15.2%]"
                : "h-[12.4%] w-[12.7%]";
            const surfaceClass = shape === "round" ? "rounded-full" : shape === "long" ? "rounded-[9px]" : "rounded-[5px]";
            const isLiveTable = live && name === "Table 8" && liveTransitioning;
            return <div key={name} className={`absolute ${position} ${shapeClass} min-w-[48px]`}>
              <div className="pointer-events-none absolute inset-0">
                <span className="absolute top-0 left-[22%] h-1.5 w-2 rounded-[2px] bg-[#d6d0c8]" />
                <span className="absolute top-0 right-[22%] h-1.5 w-2 rounded-[2px] bg-[#d6d0c8]" />
                <span className="absolute bottom-0 left-[22%] h-1.5 w-2 rounded-[2px] bg-[#d6d0c8]" />
                <span className="absolute bottom-0 right-[22%] h-1.5 w-2 rounded-[2px] bg-[#d6d0c8]" />
                <span className="absolute left-0 top-[42%] h-2 w-1.5 rounded-[2px] bg-[#d6d0c8]" />
                <span className="absolute right-0 top-[42%] h-2 w-1.5 rounded-[2px] bg-[#d6d0c8]" />
              </div>
              <div className={`absolute inset-x-1 inset-y-1 flex flex-col items-center justify-center ${surfaceClass} border transition-[background-color,border-color,box-shadow,transform] duration-700 ease-out ${style} shadow-[0_2px_4px_rgba(41,38,34,0.05)] ${isLiveTable ? "vynic-live-state-change" : ""}`}>
                <span className="flex items-center gap-1 text-[8px] font-bold"><i className={`h-1.5 w-1.5 rounded-full ${status === "occupied" ? "bg-[#e85bda]" : status === "reserved" ? "bg-[#b994c8]" : "bg-[#dedbd7]"}`} />{name}</span>
                {total ? <span className="mt-0.5 text-[9px] font-bold text-[#292622]">{total}</span> : <span className="mt-0.5 text-[7px] font-semibold text-[#79736c]">{seats}</span>}
                {total ? <span className="mt-0.5 max-w-full truncate px-1 text-[6px] text-[#79736c]">{note}</span> : null}
              </div>
            </div>;
          })}
        </div>
      </div>
      <aside className={`hidden min-h-0 min-w-0 overflow-hidden rounded-[7px] border border-[#e1dcd6] bg-white p-2 sm:block ${live && liveTransitioning ? "vynic-live-sidebar-change" : ""}`}><p className="truncate text-[7px] font-semibold uppercase tracking-[0.08em] text-[#817a73]">{s.serviceNow}</p><div className="mt-2 grid grid-cols-2 gap-1"><TinyCard compact label={s.free} value={counts[0]} tone="white" /><TinyCard compact label={s.occupied} value={counts[1]} tone="white" /><TinyCard compact label={s.reserved} value={counts[2]} tone="amber" /><TinyCard compact label={s.forTable} value="0" tone="white" /></div><div className="mt-2 border-t border-[#eee9e3] pt-2"><div className="flex items-center justify-between gap-1"><p className="truncate text-[7px] font-bold uppercase tracking-[0.06em]">{s.needsAttention}</p><span className="shrink-0 text-[7px] text-[#79736c]">0</span></div><p className="mt-1 truncate text-[6px] text-[#79736c]">{s.allGood}</p></div><div className="mt-2 border-t border-[#eee9e3] pt-2"><div className="flex items-center justify-between gap-1"><p className="truncate text-[7px] font-bold uppercase tracking-[0.06em]">{s.nextReservations}</p><span className="shrink-0 text-[7px] font-semibold text-[#5b4b86]">{s.all}</span></div><div className={`mt-1 rounded-[5px] border p-1.5 transition-colors duration-700 ${liveStage === 1 ? "border-[#cbb6d9] bg-[#f5eff9]" : "border-[#e7e2dc]"}`}><div className="flex justify-between gap-1 text-[7px] font-semibold"><span className="truncate">{liveStage === 0 ? (locale === "ka" ? "ტესტი" : "Test") : "Table 8"}</span><span className="shrink-0">{liveStage === 0 ? "19:00" : "20:30"}</span></div><p className="mt-1 truncate text-[6px] text-[#79736c]">{nextReservation}</p><p className="mt-1 truncate text-[6px] font-semibold text-[#5b4b86]">{s.forTable}</p></div></div></aside>
    </div>
  </div>;
}

function TableOrderReplica() {
  const { copy, locale } = useLocale();
  const s = copy.screen;
  const productName = locale === "ka" ? "ბერძნული სალათი" : "Greek salad";
  return <div className="flex h-full min-h-0 flex-col"><TopBar title={`${s.tables} · Table 1`} back /><NavBar />
    <div className="min-h-0 flex-1 overflow-hidden p-3 sm:p-4"><SectionTitle eyebrow={`${s.activeTable} · ${s.floorOne}`} title="Table 1" action={s.occupied} /><p className="mt-1 text-[8px] text-[#79736c]">{s.floorOne} · 6 {s.seats} · {s.walkIn}</p>
      <div className="mt-3 grid grid-cols-4 gap-2"><TinyCard label={s.status} value={s.occupied} tone="amber" /><TinyCard label={s.opened} value="23:56" /><TinyCard label={s.duration} value="00:00:00" /><TinyCard label={s.total} value="368.00 ₾" tone="purple" /></div>
      <div className="mt-3 grid min-h-0 grid-cols-[1fr_29%] gap-3"><div className="min-h-0 overflow-hidden rounded-[6px] border border-[#e7e2dc] bg-white"><div className="flex items-center justify-between border-b border-[#eee9e3] px-3 py-2"><span className="font-bold">{s.order}</span><span className="text-[8px] text-[#79736c]">23 {s.positions}</span></div><div className="p-3"><div className="rounded-[5px] border border-[#e7e2dc] p-3"><div className="flex items-start justify-between"><div><p className="font-bold">{productName}</p><p className="mt-1 text-[8px] text-[#79736c]">23 × 16.00 ₾</p></div><span className="font-bold">368.00 ₾</span></div><div className="mt-3 flex gap-1"><span className="rounded-[4px] bg-[#f2edf8] px-2 py-1 text-[8px] text-[#5b4b86]">{locale === "ka" ? "შეცვლა" : "Edit"}</span><span className="rounded-[4px] bg-[#f7f5f2] px-2 py-1 text-[8px] text-[#79736c]">{locale === "ka" ? "წაშლა" : "Remove"}</span></div></div><div className="mt-3 rounded-[5px] bg-[#f7f5f2] p-3"><p className="text-[8px] font-semibold">{s.reservationContext}</p><div className="mt-2 flex justify-between"><span className="text-[#79736c]">{s.guest}</span><span className="font-semibold">{s.walkIn}</span></div><div className="mt-1 flex justify-between"><span className="text-[#79736c]">{s.status}</span><span className="font-semibold text-[#66816a]">{s.confirmed}</span></div></div></div></div><aside className="rounded-[6px] border border-[#e7e2dc] bg-white p-3"><p className="text-[8px] font-bold">{s.tableActions}</p><div className="mt-2 grid gap-1.5"><button className="rounded-[5px] border border-[#e7e2dc] px-2 py-2 text-left text-[8px]">+ {s.newItem}</button><button className="rounded-[5px] border border-[#e7e2dc] px-2 py-2 text-left text-[8px]">{s.splitMerge}</button><button className="rounded-[5px] border border-[#e7e2dc] px-2 py-2 text-left text-[8px]">{s.print}</button></div><div className="mt-5 border-t border-[#eee9e3] pt-3"><p className="text-[8px] text-[#79736c]">{s.payable}</p><p className="mt-1 text-[18px] font-bold">404.80 ₾</p><p className="mt-1 text-[8px] text-[#956c17]">{s.service} 10% · 36.80 ₾</p><button className="mt-3 w-full rounded-[5px] bg-[#5b4b86] px-2 py-2.5 text-[8px] font-bold text-white">{s.payment}</button></div></aside></div>
    </div>
  </div>;
}

function OrderEditorReplica() {
  const { copy, locale } = useLocale();
  const s = copy.screen;
  const menu = locale === "ka" ? [["ბერძნული სალათი", "16.00 ₾"], ["იმერული ხაჭაპური", "22.00 ₾"], ["ქათმის მწვადი", "18.00 ₾"], ["ცეზარის სალათი", "19.00 ₾"], ["ლიმონათი", "7.00 ₾"], ["ხინკალი", "1.50 ₾"], ["საფირმო სოუსი", "5.00 ₾"], ["შოკოლადის დესერტი", "14.00 ₾"]] : [["Greek salad", "16.00 ₾"], ["Imeruli khachapuri", "22.00 ₾"], ["Chicken mtsvadi", "18.00 ₾"], ["Caesar salad", "19.00 ₾"], ["Lemonade", "7.00 ₾"], ["Khinkali", "1.50 ₾"], ["House sauce", "5.00 ₾"], ["Chocolate dessert", "14.00 ₾"]];
  const categories = [s.coldDishes, s.hotDishes, s.sauces, s.soups, s.bakery, s.dumplings, s.grill, s.seafood, s.dessert];
  return <div className="flex h-full min-h-0 flex-col"><TopBar title={s.orderEditor} back /><div className="flex h-[8%] min-h-[32px] items-center gap-2 border-b border-[#e4dfd9] bg-white px-3"><div className="flex flex-1 items-center gap-2 rounded-[5px] border border-[#e7e2dc] px-2 py-1.5 text-[#918981]"><MagnifyingGlass size={12} /> <span>{s.searchMenu}</span></div><span className="rounded-[5px] bg-[#f2edf8] px-2 py-1.5 font-semibold text-[#5b4b86]">Table 1</span></div><div className="grid min-h-0 flex-1 grid-cols-[1fr_35%] gap-3 p-3 sm:grid-cols-[21%_1fr_28%]"><aside className="hidden min-h-0 overflow-hidden rounded-[6px] border border-[#e7e2dc] bg-white p-2 sm:block"><p className="mb-2 px-1 text-[8px] font-bold">{s.categories}</p>{categories.map((x, i) => <div key={x} className={`mb-1 rounded-[4px] px-2 py-2 text-[8px] ${i === 0 ? "bg-[#f2edf8] font-bold text-[#5b4b86]" : "text-[#79736c]"}`}>{x}</div>)}</aside><main className="min-h-0 overflow-hidden"><div className="mb-2 flex items-center justify-between"><p className="font-bold">{s.coldDishes}</p><span className="text-[8px] text-[#79736c]">24 {s.positions}</span></div><div className="grid grid-cols-2 gap-2 sm:grid-cols-3">{menu.map(([name, price], i) => <div key={name} className="rounded-[6px] border border-[#e7e2dc] bg-white p-2.5"><div className={`mb-3 flex h-7 items-center justify-center rounded-[4px] ${i % 3 === 0 ? "bg-[#f7e8d8]" : i % 3 === 1 ? "bg-[#e5f0e4]" : "bg-[#eee8f5]"}`}><span className="text-[12px]">{i % 3 === 0 ? "◌" : i % 3 === 1 ? "✦" : "◍"}</span></div><p className="truncate text-[8px] font-bold">{name}</p><div className="mt-2 flex items-center justify-between"><span className="text-[8px] text-[#79736c]">{price}</span><span className="flex h-4 w-4 items-center justify-center rounded-full bg-[#5b4b86] text-white"><Plus size={10} weight="bold" /></span></div></div>)}</div></main><aside className="min-h-0 overflow-hidden rounded-[6px] border border-[#e7e2dc] bg-white p-3"><div className="flex items-center justify-between"><p className="font-bold">Table 1 · {s.order}</p><span className="text-[#79736c]">×</span></div><div className="mt-3 rounded-[5px] border border-[#e7e2dc] p-2"><div className="flex justify-between"><span className="font-semibold">{locale === "ka" ? "ბერძნული სალათი" : "Greek salad"}</span><span className="font-bold">368.00 ₾</span></div><div className="mt-1 flex justify-between text-[8px] text-[#79736c]"><span>23 × 16.00 ₾</span><span>− 23 +</span></div></div><div className="mt-3 flex items-center justify-between rounded-[5px] bg-[#f7f5f2] p-2"><span>{s.service} 10%</span><span className="font-semibold">36.80 ₾</span></div><div className="mt-4 border-t border-[#eee9e3] pt-3"><div className="flex justify-between text-[#79736c]"><span>{locale === "ka" ? "ქვეჯამი" : "Subtotal"}</span><span>368.00 ₾</span></div><div className="mt-2 flex justify-between text-[13px] font-bold"><span>{s.total}</span><span>404.80 ₾</span></div><button className="mt-4 w-full rounded-[5px] bg-[#5b4b86] px-2 py-2.5 font-bold text-white">{locale === "ka" ? "შეკვეთის განახლება" : "Update order"}</button></div></aside></div></div>;
}

function PaymentReplica() {
  const { copy, locale } = useLocale();
  const s = copy.screen;
  return <div className="relative h-full min-h-0"><div className="h-full opacity-55"><TableOrderReplica /></div><div className="absolute inset-0 flex items-center justify-center bg-[#292622]/30 p-6"><div className="w-full max-w-[470px] rounded-[8px] border border-[#e1dcd6] bg-[#fffdfa] p-4 shadow-[0_18px_50px_rgba(41,38,34,0.22)] sm:p-5"><div className="flex items-start justify-between"><div><p className="text-[8px] font-semibold uppercase tracking-[0.12em] text-[#817a73]">Table 1 · 404.80 ₾</p><h3 className="mt-1 text-[17px] font-bold">{locale === "ka" ? "აირჩიეთ გადახდის მეთოდი" : "Choose a payment method"}</h3><p className="mt-1 text-[8px] text-[#79736c]">{locale === "ka" ? "აირჩიეთ როგორ გადაიხდის სტუმარი ამ შეკვეთას." : "Choose how the guest will pay this check."}</p></div><span className="flex h-6 w-6 items-center justify-center rounded-full bg-[#f7f5f2] text-[#79736c]"><X size={13} /></span></div><div className="mt-5 grid gap-2 sm:grid-cols-3"><div className="rounded-[6px] border border-[#d7c8e6] bg-[#f2edf8] p-3"><CreditCard size={16} className="text-[#5b4b86]" /><p className="mt-3 font-bold">{locale === "ka" ? "ნაღდი ფული" : "Cash"}</p><p className="mt-1 text-[8px] text-[#79736c]">Cash</p></div><div className="rounded-[6px] border border-[#e7e2dc] bg-white p-3"><CreditCard size={16} className="text-[#5b4b86]" /><p className="mt-3 font-bold">{locale === "ka" ? "ბარათით" : "Card"}</p><p className="mt-1 text-[8px] text-[#79736c]">Bank POS</p></div><div className="rounded-[6px] border border-[#e7e2dc] bg-white p-3"><SquaresFour size={16} className="text-[#5b4b86]" /><p className="mt-3 font-bold">{locale === "ka" ? "გაყოფილი" : "Split"}</p><p className="mt-1 text-[8px] text-[#79736c]">Split payment</p></div></div><div className="mt-5 flex justify-end gap-2 border-t border-[#eee9e3] pt-3"><button className="rounded-[5px] border border-[#e7e2dc] px-4 py-2 font-semibold">{locale === "ka" ? "გაუქმება" : "Cancel"}</button><button className="rounded-[5px] bg-[#5b4b86] px-4 py-2 font-semibold text-white">{locale === "ka" ? "დადასტურება" : "Confirm"}</button></div></div></div></div>;
}

function DayCloseReplica() {
  const { copy, locale } = useLocale();
  const s = copy.screen;
  const sideItems = locale === "ka"
    ? [[SquaresFour, "პერსონალი"], [FileText, "მენიუ"], [CalendarBlank, s.reservation], [CreditCard, s.payment], [WarningCircle, "აუდიტი"], [Gear, s.settings]]
    : [[SquaresFour, "Staff"], [FileText, "Menu"], [CalendarBlank, s.reservation], [CreditCard, s.payment], [WarningCircle, "Audit"], [Gear, s.settings]];
  const tableOne = locale === "ka" ? "მაგიდა 1" : "Table 1";
  return <div className="flex h-full min-h-0 flex-col"><TopBar title="Vynic Manager" /><div className="grid min-h-0 flex-1 grid-cols-[19%_1fr]"><aside className="hidden border-r border-[#e4dfd9] bg-white p-3 sm:block"><div className="mb-4 flex items-center gap-2 border-b border-[#eee9e3] pb-3"><span className="flex h-6 w-6 items-center justify-center rounded-[5px] bg-[#f2edf8] font-black text-[#5b4b86]">V</span><span className="font-bold">{s.managerCenter}</span></div>{sideItems.map(([Icon, label], i) => <div key={label as string} className={`mb-1 flex items-center gap-2 rounded-[5px] px-2 py-2 text-[8px] ${i === 4 ? "bg-[#f2edf8] font-bold text-[#5b4b86]" : "text-[#79736c]"}`}><Icon size={12} />{label as string}</div>)}</aside><main className="min-h-0 overflow-hidden p-3 sm:p-4"><SectionTitle eyebrow={locale === "ka" ? "სამუშაო დღე" : "BUSINESS DAY"} title={s.closeDay} action="22 ივნისი 2026" /><div className="mt-3 grid min-h-0 grid-cols-[1fr_33%] gap-3"><div className="min-h-0 overflow-hidden"><div className="rounded-[6px] border border-[#e7e2dc] bg-white p-3"><div className="flex items-center justify-between"><div><p className="text-[8px] text-[#79736c]">{locale === "ka" ? "მიმდინარე სამუშაო დღე" : "Current business day"}</p><p className="mt-1 text-[13px] font-bold">22 ივნისი 2026</p></div><CheckCircle size={18} className="text-[#66816a]" weight="fill" /></div><div className="mt-3 grid grid-cols-3 gap-2"><TinyCard label={locale === "ka" ? "დახურული შეკვეთები" : "Closed orders"} value="7" /><TinyCard label={locale === "ka" ? "დღის შემოსავალი" : "Day revenue"} value="2743.50 ₾" tone="green" /><TinyCard label={s.openTable} value="1" tone="amber" /></div></div><div className="mt-3 rounded-[6px] border border-[#e7e2dc] bg-white p-3"><p className="font-bold">{s.daySummary}</p><div className="mt-3 grid grid-cols-2 gap-x-6 gap-y-2"><div className="flex justify-between border-b border-[#eee9e3] pb-2"><span className="text-[#79736c]">{s.sales}</span><b>2225.70 ₾</b></div><div className="flex justify-between border-b border-[#eee9e3] pb-2"><span className="text-[#79736c]">{s.service}</span><b>404.80 ₾</b></div><div className="flex justify-between border-b border-[#eee9e3] pb-2"><span className="text-[#79736c]">{s.cash}</span><b>1210.00 ₾</b></div><div className="flex justify-between border-b border-[#eee9e3] pb-2"><span className="text-[#79736c]">{s.bankPos}</span><b>1533.50 ₾</b></div></div></div><div className="mt-3 flex gap-2"><button className="flex-1 rounded-[5px] border border-[#e7e2dc] px-3 py-2 font-semibold"><Printer size={12} className="mr-1 inline" /> {s.zReport}</button><button className="flex-1 rounded-[5px] bg-[#5b4b86] px-3 py-2 font-semibold text-white">{s.closeDay}</button></div></div><aside className="rounded-[6px] border border-[#e7e2dc] bg-white p-3"><p className="font-bold">{s.checkBeforeClose}</p><div className="mt-3 grid gap-2"><div className="rounded-[5px] border border-[#ead9ad] bg-[#fff6e3] p-2"><p className="font-semibold text-[#8c6b27]">{s.openTable}</p><p className="mt-1 text-[8px] text-[#79736c]">{tableOne} · 404.80 ₾</p></div><div className="rounded-[5px] border border-[#ead9ad] bg-[#fff6e3] p-2"><p className="font-semibold text-[#8c6b27]">{s.unfinishedTakeaway}</p><p className="mt-1 text-[8px] text-[#79736c]">{locale === "ka" ? "1 შეკვეთას შემოწმება სჭირდება" : "1 order needs review"}</p></div><div className="rounded-[5px] border border-[#cce1d0] bg-[#eef7ef] p-2"><p className="font-semibold text-[#66816a]">{s.zReportReady}</p><p className="mt-1 text-[8px] text-[#79736c]">{s.noPrinterErrors}</p></div></div></aside></div></main></div></div>;
}

function LegacyDayCloseReplica() {
  return <div className="flex h-full min-h-0 flex-col"><TopBar title="Vynic Manager" /><div className="grid min-h-0 flex-1 grid-cols-[19%_1fr]"><aside className="hidden border-r border-[#e4dfd9] bg-white p-3 sm:block"><div className="mb-4 flex items-center gap-2 border-b border-[#eee9e3] pb-3"><span className="flex h-6 w-6 items-center justify-center rounded-[5px] bg-[#f2edf8] font-black text-[#5b4b86]">V</span><span className="font-bold">Manager center</span></div>{[[SquaresFour, "პერსონალი"], [FileText, "მენიუ"], [CalendarBlank, "რეზერვაციები"], [CreditCard, "გადახდები"], [WarningCircle, "აუდიტი"], [Gear, "პარამეტრები"]].map(([Icon, label], i) => <div key={label as string} className={`mb-1 flex items-center gap-2 rounded-[5px] px-2 py-2 text-[8px] ${i === 4 ? "bg-[#f2edf8] font-bold text-[#5b4b86]" : "text-[#79736c]"}`}><Icon size={12} />{label as string}</div>)}</aside><main className="min-h-0 overflow-hidden p-3 sm:p-4"><SectionTitle eyebrow="BUSINESS DAY" title="დღის დახურვა" action="22 ივნისი 2026" /><div className="mt-3 grid min-h-0 grid-cols-[1fr_33%] gap-3"><div className="min-h-0 overflow-hidden"><div className="rounded-[6px] border border-[#e7e2dc] bg-white p-3"><div className="flex items-center justify-between"><div><p className="text-[8px] text-[#79736c]">მიმდინარე სამუშაო დღე</p><p className="mt-1 text-[13px] font-bold">22 ივნისი 2026</p></div><CheckCircle size={18} className="text-[#66816a]" weight="fill" /></div><div className="mt-3 grid grid-cols-3 gap-2"><TinyCard label="დახურული შეკვეთა" value="7" /><TinyCard label="დღის შემოსავალი" value="2743.50 ₾" tone="green" /><TinyCard label="ღია მაგიდა" value="1" tone="amber" /></div></div><div className="mt-3 rounded-[6px] border border-[#e7e2dc] bg-white p-3"><p className="font-bold">დღის შეჯამება</p><div className="mt-3 grid grid-cols-2 gap-x-6 gap-y-2"><div className="flex justify-between border-b border-[#eee9e3] pb-2"><span className="text-[#79736c]">სულ გაყიდვები</span><b>2225.70 ₾</b></div><div className="flex justify-between border-b border-[#eee9e3] pb-2"><span className="text-[#79736c]">Service</span><b>404.80 ₾</b></div><div className="flex justify-between border-b border-[#eee9e3] pb-2"><span className="text-[#79736c]">Cash</span><b>1210.00 ₾</b></div><div className="flex justify-between border-b border-[#eee9e3] pb-2"><span className="text-[#79736c]">Bank POS</span><b>1533.50 ₾</b></div></div></div><div className="mt-3 flex gap-2"><button className="flex-1 rounded-[5px] border border-[#e7e2dc] px-3 py-2 font-semibold"><Printer size={12} className="mr-1 inline" /> Z რეპორტი</button><button className="flex-1 rounded-[5px] bg-[#5b4b86] px-3 py-2 font-semibold text-white">დღის დახურვა</button></div></div><aside className="rounded-[6px] border border-[#e7e2dc] bg-white p-3"><p className="font-bold">დახურვამდე შეამოწმე</p><div className="mt-3 grid gap-2"><div className="rounded-[5px] border border-[#ead9ad] bg-[#fff6e3] p-2"><p className="font-semibold text-[#8c6b27]">ღია მაგიდა</p><p className="mt-1 text-[8px] text-[#79736c]">Table 1 · 404.80 ₾</p></div><div className="rounded-[5px] border border-[#ead9ad] bg-[#fff6e3] p-2"><p className="font-semibold text-[#8c6b27]">დაუსრულებელი გატანა</p><p className="mt-1 text-[8px] text-[#79736c]">1 order needs review</p></div><div className="rounded-[5px] border border-[#cce1d0] bg-[#eef7ef] p-2"><p className="font-semibold text-[#66816a]">Z report ready</p><p className="mt-1 text-[8px] text-[#79736c]">No printer errors detected</p></div></div></aside></div></main></div></div>;
}
