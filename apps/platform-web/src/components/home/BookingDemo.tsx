import { ArrowClockwise, CalendarCheck, Check, Minus, Plus } from "@phosphor-icons/react";
import { AnimatePresence, LayoutGroup, motion, useReducedMotion } from "motion/react";
import { useState } from "react";
import { useLocale } from "../../lib/i18n";
import { curve } from "../../lib/motion";
import { Rise, SectionOpen } from "./primitives";
import { getSiteCopy } from "./siteCopy";

const TIMES = ["19:00", "19:30", "20:00", "20:30", "21:00"];
const TABLES = [1, 2, 3, 4, 5, 6, 7, 8, 9];
const TAKEN = new Set([1, 4]);
const EXISTING = [
  { time: "19:00", name: "Giorgi", guests: 6, table: 2 },
  { time: "21:30", name: "Ana", guests: 2, table: 7 },
];

/**
 * The guest books on a (demo) restaurant website; the booking travels to the
 * POS reservations list and the chosen table turns reserved on its floor.
 * Everything is local to the page — nothing is sent anywhere.
 */
export function BookingDemo() {
  const { locale } = useLocale();
  const copy = getSiteCopy(locale).booking;
  const reduce = useReducedMotion();
  const [guests, setGuests] = useState(4);
  const [time, setTime] = useState("20:30");
  const [table, setTable] = useState(8);
  const [sent, setSent] = useState(false);

  const list = [...EXISTING, ...(sent ? [{ time, name: copy.name, guests, table, fresh: true }] : [])].sort((a, b) => a.time.localeCompare(b.time));

  return (
    <section className="relative px-4 py-24 sm:px-6 lg:px-8 lg:py-32">
      <div className="mx-auto max-w-[1320px]">
        <SectionOpen kicker={copy.kicker} title={copy.title} body={copy.body} />
        <LayoutGroup>
          <div className="relative mt-14 grid grid-cols-[minmax(0,1fr)] items-start gap-10 lg:grid-cols-[minmax(0,1fr)_minmax(0,1fr)] lg:gap-16">
            {/* Guest side: restaurant website */}
            <Rise y={40}>
              <div className="overflow-hidden rounded-[20px] border border-[var(--vh-line-strong)] bg-[#f8f7f4] text-[#1c1a18] shadow-[0_50px_100px_-40px_rgba(0,0,0,0.9)]">
                <div className="flex items-center gap-1.5 border-b border-[#e6e3de] bg-[#ecebe8] px-4 py-2.5">
                  <span className="h-2.5 w-2.5 rounded-full bg-[#d8d1cb]" />
                  <span className="h-2.5 w-2.5 rounded-full bg-[#d8d1cb]" />
                  <span className="h-2.5 w-2.5 rounded-full bg-[#d8d1cb]" />
                  <span className="ml-3 flex-1 rounded-full bg-white px-3 py-1 font-mono text-[10px] text-[#8a827b]">demo-bistro.vynic.ge</span>
                </div>
                <div className="bg-[#22201e] px-5 py-5 text-[#f7f6f4]">
                  <p className="vh-mono text-[10px] text-[#b9a8c4]">{copy.site}</p>
                  <p className="vh-display mt-1 text-3xl">{copy.open}</p>
                </div>
                <div className="grid gap-5 p-5">
                  <div className="flex items-center justify-between">
                    <span className="text-[13px] font-semibold">{copy.guests}</span>
                    <span className="flex items-center gap-3">
                      <button type="button" disabled={sent || guests <= 1} onClick={() => setGuests((g) => g - 1)} className="flex h-8 w-8 items-center justify-center rounded-full border border-[#ded8d1] disabled:opacity-40" aria-label="−">
                        <Minus size={13} weight="bold" />
                      </button>
                      <span className="w-5 text-center text-lg font-semibold tabular-nums">{guests}</span>
                      <button type="button" disabled={sent || guests >= 12} onClick={() => setGuests((g) => g + 1)} className="flex h-8 w-8 items-center justify-center rounded-full border border-[#ded8d1] disabled:opacity-40" aria-label="+">
                        <Plus size={13} weight="bold" />
                      </button>
                    </span>
                  </div>
                  <div>
                    <span className="text-[13px] font-semibold">{copy.time}</span>
                    <div className="mt-2 flex flex-wrap gap-2">
                      {TIMES.map((slot) => (
                        <button
                          key={slot}
                          type="button"
                          disabled={sent}
                          onClick={() => setTime(slot)}
                          aria-pressed={time === slot}
                          className={`relative rounded-full border px-3.5 py-1.5 text-[13px] transition-colors ${time === slot ? "border-[#764b7c] text-white" : "border-[#ded8d1] text-[#4f4941] hover:border-[#764b7c]"}`}
                        >
                          {time === slot ? <motion.span layoutId="vh-time" className="absolute inset-0 rounded-full bg-[#764b7c]" transition={{ duration: 0.4, ease: curve.out }} /> : null}
                          <span className="relative">{slot}</span>
                        </button>
                      ))}
                    </div>
                  </div>
                  <div>
                    <span className="text-[13px] font-semibold">{copy.table}</span>
                    <div className="mt-2 grid grid-cols-5 gap-2 sm:grid-cols-9">
                      {TABLES.map((id) => {
                        const taken = TAKEN.has(id);
                        const on = id === table;
                        return (
                          <button
                            key={id}
                            type="button"
                            disabled={sent || taken}
                            onClick={() => setTable(id)}
                            aria-pressed={on}
                            className={`aspect-square rounded-[10px] border text-[12px] font-semibold transition-all ${
                              on ? "scale-105 border-[#764b7c] bg-[#efe2f2] text-[#4a2f4e]" : taken ? "border-dashed border-[#d6d0c9] text-[#c0b9b1] line-through" : "border-[#ded8d1] hover:border-[#764b7c]"
                            }`}
                          >
                            {id}
                          </button>
                        );
                      })}
                    </div>
                  </div>
                  <div className="relative min-h-[48px]">
                    {!sent ? (
                      <motion.button
                        layoutId="vh-booking"
                        type="button"
                        onClick={() => setSent(true)}
                        className="flex h-12 w-full items-center justify-center gap-2 rounded-[12px] bg-[#764b7c] text-[14px] font-semibold text-white"
                        transition={{ duration: reduce ? 0 : 0.9, ease: curve.inOut }}
                      >
                        <CalendarCheck size={17} weight="bold" />
                        {copy.book} · {time} · {guests}
                      </motion.button>
                    ) : (
                      <div className="flex h-12 items-center justify-between rounded-[12px] border border-[#c7e0d3] bg-[#e7f2ec] px-4 text-[13px] text-[#1f5f44]">
                        <span className="flex items-center gap-2">
                          <Check size={15} weight="bold" />
                          {copy.sent}
                        </span>
                        <button type="button" onClick={() => setSent(false)} className="flex items-center gap-1.5 rounded-full px-2 py-1 hover:bg-white/60" aria-label="Reset">
                          <ArrowClockwise size={14} />
                        </button>
                      </div>
                    )}
                  </div>
                </div>
              </div>
            </Rise>

            {/* Staff side: POS reservations */}
            <Rise y={40} delay={0.1}>
              <div className="overflow-hidden rounded-[20px] border border-[var(--vh-line-strong)] bg-[#f6f5f2] text-[#1c1a18] shadow-[0_50px_100px_-40px_rgba(0,0,0,0.9)]">
                <div className="flex items-center justify-between border-b border-[#e6e3de] bg-white px-4 py-3">
                  <span className="text-[13px] font-bold">{copy.pos}</span>
                  <span className="rounded-full bg-[#fbf2e0] px-2 py-0.5 text-[10px] font-semibold text-[#8a5b14]">{list.length}</span>
                </div>
                <div className="relative grid gap-4 p-4">
                  <AnimatePresence>
                    {sent ? (
                      <motion.div
                        key="toast"
                        className="flex items-center gap-2 rounded-[12px] border border-[#d8c4dc] bg-[#f3edf4] px-3 py-2 text-[12px] font-semibold text-[#4a2f4e]"
                        initial={{ opacity: 0, y: -10, scale: 0.96 }}
                        animate={{ opacity: 1, y: 0, scale: 1 }}
                        exit={{ opacity: 0 }}
                        transition={{ duration: 0.5, ease: curve.out, delay: reduce ? 0 : 0.8 }}
                      >
                        <span className="h-2 w-2 rounded-full bg-[#764b7c]" />
                        {copy.incoming} · {copy.table} {table} · {time}
                      </motion.div>
                    ) : null}
                  </AnimatePresence>
                  <ul className="grid gap-2">
                    {list.map((item) => {
                      const fresh = "fresh" in item;
                      const body = (
                        <>
                          <span className="w-12 font-mono text-[12px] text-[#5c574f]">{item.time}</span>
                          <span className="flex-1 truncate text-[13px] font-semibold">{item.name}</span>
                          <span className="text-[12px] text-[#5c574f]">{item.guests} · T{item.table}</span>
                        </>
                      );
                      return fresh ? (
                        <motion.li
                          key="fresh"
                          layoutId="vh-booking"
                          className="flex items-center gap-3 rounded-[12px] border border-[#b48cbb] bg-white px-3 py-2.5 shadow-[0_10px_30px_-12px_rgba(118,75,124,0.6)]"
                          transition={{ duration: reduce ? 0 : 0.9, ease: curve.inOut }}
                        >
                          {body}
                        </motion.li>
                      ) : (
                        <motion.li layout key={`${item.time}-${item.name}`} className="flex items-center gap-3 rounded-[12px] border border-[#e6e3de] bg-white px-3 py-2.5">
                          {body}
                        </motion.li>
                      );
                    })}
                  </ul>
                  {/* Mini floor: the booked table turns reserved */}
                  <div className="grid grid-cols-9 gap-1.5 rounded-[12px] border border-[#e6e3de] bg-white p-3">
                    {TABLES.map((id) => {
                      const reserved = (sent && id === table) || EXISTING.some((item) => item.table === id);
                      const busy = TAKEN.has(id);
                      return (
                        <motion.span
                          key={id}
                          className="flex aspect-square items-center justify-center rounded-[6px] border text-[10px] font-semibold"
                          animate={{
                            backgroundColor: busy ? "#efe2f2" : reserved ? "#fbf2e0" : "#fcfbf9",
                            borderColor: busy ? "#b48cbb" : reserved ? "#ebdcb5" : "#e6e3de",
                            scale: sent && id === table ? [1, 1.25, 1] : 1,
                          }}
                          transition={{ duration: 0.6, delay: sent && id === table && !reduce ? 1 : 0 }}
                        >
                          {id}
                        </motion.span>
                      );
                    })}
                  </div>
                  {sent ? (
                    <motion.p className="text-[12px] text-[#5c574f]" initial={{ opacity: 0 }} animate={{ opacity: 1 }} transition={{ delay: reduce ? 0 : 1.2 }}>
                      {copy.seat}
                    </motion.p>
                  ) : null}
                </div>
              </div>
            </Rise>
          </div>
        </LayoutGroup>
      </div>
    </section>
  );
}
