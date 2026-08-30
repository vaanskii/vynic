import { useState, useEffect, useRef } from 'react';
import floor1SvgUrl from '../assets/floor1.svg';
import floor2SvgUrl from '../assets/floor2.svg';
import styles from '../css/SelectTable.module.css';
import { tableService } from '../services/api';

interface TablePickerMiniProps {
  selectedTables: Set<string>;
  onTablesChange: (tables: Set<string>) => void;
  selectedDate: string;
  language: string;
}

const TablePickerMini = ({ selectedTables, onTablesChange, selectedDate, language }: TablePickerMiniProps) => {
  const [currentFloor, setCurrentFloor] = useState<'floor1' | 'floor2'>('floor1');
  const [svgContent, setSvgContent] = useState('');
  const [svgIds, setSvgIds] = useState<string[]>([]);
  const [takenTables, setTakenTables] = useState<Set<string>>(new Set());
  const [isLoading, setIsLoading] = useState(true);
  const svgRef = useRef<HTMLDivElement>(null);

  // Load the floor SVG
  const loadFloorSvg = async (floor: 'floor1' | 'floor2') => {
    setIsLoading(true);
    const url = floor === 'floor1' ? floor1SvgUrl : floor2SvgUrl;
    try {
      const resp = await fetch(url);
      const text = await resp.text();
      setSvgContent(text);
      const matches = text.match(/id="([^"]+)"/g) || [];
      const ids = matches.map(m => m.replace(/id="([^"]+)"/, '$1'));
      const selectable = floor === 'floor1'
        ? ids.filter(id => /^table\d{1,2}$/i.test(id))
        : ids.filter(id => /^vip-zone-\d+$/i.test(id));
      setSvgIds(selectable);
    } catch (e) {
      console.error('Error loading SVG:', e);
    } finally {
      setIsLoading(false);
    }
  };

  // Fetch table availability
  const fetchAvailability = async (date: string) => {
    if (!date) return;
    try {
      const data = await tableService.getTableAvailability(date);
      const taken = new Set<string>(
        data
          .filter((t: { tableNumber: string; isAvailable: boolean }) => !t.isAvailable)
          .map((t: { tableNumber: string; isAvailable: boolean }) => t.tableNumber)
      );
      setTakenTables(taken);
    } catch {
      setTakenTables(new Set());
    }
  };

  useEffect(() => { loadFloorSvg(currentFloor); }, [currentFloor]);
  useEffect(() => { if (selectedDate) fetchAvailability(selectedDate); }, [selectedDate]);

  // Re-apply visual styles after SVG loads or selection changes
  useEffect(() => {
    if (!svgContent || !svgRef.current || svgIds.length === 0) return;
    const timer = setTimeout(() => {
      const container = svgRef.current;
      if (!container) return;
      svgIds.forEach(id => {
        const el = container.querySelector(`#${id}`);
        if (el) el.classList.remove('table-selected', 'table-taken');
      });
      takenTables.forEach(id => {
        const el = container.querySelector(`#${id}`);
        if (el) el.classList.add('table-taken');
      });
      selectedTables.forEach(id => {
        const el = container.querySelector(`#${id}`);
        if (el && !takenTables.has(id)) el.classList.add('table-selected');
      });
    }, 100);
    return () => clearTimeout(timer);
  }, [svgContent, svgIds, selectedTables, takenTables]);

  const handleClick = (e: React.MouseEvent<HTMLDivElement>) => {
    let el = e.target as SVGElement | null;
    for (let i = 0; i < 5 && el; i++) {
      const id = el.getAttribute('id');
      if (id) {
        const isTable = /^table\d{1,2}$/i.test(id);
        const isVip = /^vip-zone-\d+$/i.test(id);
        if ((currentFloor === 'floor1' && isTable) || (currentFloor === 'floor2' && isVip)) {
          if (!takenTables.has(id)) {
            const next = new Set(selectedTables);
            if (next.has(id)) next.delete(id); else next.add(id);
            onTablesChange(next);
          }
          return;
        }
      }
      el = el.parentElement as SVGElement | null;
    }
  };

  const formatTableName = (id: string) => {
    const tm = id.match(/^table(\d{1,2})$/i);
    if (tm) return `Table ${tm[1]}`;
    const vm = id.match(/^vip-zone-(\d+)$/i);
    if (vm) return `VIP Zone ${vm[1]}`;
    return id;
  };

  const switchFloor = (floor: 'floor1' | 'floor2') => {
    if (floor !== currentFloor) setCurrentFloor(floor);
  };

  return (
    <div className="flex-grow flex flex-col animate-fade-up-init">
      {/* Legend */}
      <div className="flex gap-4 text-[10px] tracking-wider text-white/40 uppercase mb-4 justify-end">
        <span className="flex items-center gap-2"><div className="w-2 h-2 rounded-full bg-[#ae895e]" /> {language === 'ka' ? 'არჩეული' : 'Selected'}</span>
        <span className="flex items-center gap-2"><div className="w-2 h-2 rounded-full border border-red-500" /> {language === 'ka' ? 'დაჯავშნული' : 'Booked'}</span>
        <span className="flex items-center gap-2"><div className="w-2 h-2 rounded-full border border-white/30" /> {language === 'ka' ? 'თავისუფალი' : 'Free'}</span>
      </div>

      {/* Floor toggle */}
      <div className="flex gap-3 mb-4 justify-center">
        <button
          onClick={() => switchFloor('floor1')}
          className={`px-4 py-2 text-[10px] font-bold uppercase tracking-wider border transition-all ${currentFloor === 'floor1' ? 'bg-[#ae895e] text-black border-[#ae895e]' : 'bg-transparent text-[#ae895e] border-[#ae895e]/40 hover:border-[#ae895e]'}`}
        >
          {language === 'ka' ? 'I სართული' : 'Floor 1'}
        </button>
        <button
          onClick={() => switchFloor('floor2')}
          className={`px-4 py-2 text-[10px] font-bold uppercase tracking-wider border transition-all ${currentFloor === 'floor2' ? 'bg-[#ae895e] text-black border-[#ae895e]' : 'bg-transparent text-[#ae895e] border-[#ae895e]/40 hover:border-[#ae895e]'}`}
        >
          {language === 'ka' ? 'II სართული (VIP)' : 'Floor 2 (VIP)'}
        </button>
      </div>

      {/* SVG container */}
      <div className="relative flex-grow border border-white/5 bg-[#050505] overflow-hidden">
        {isLoading && (
          <div className="absolute inset-0 flex items-center justify-center">
            <div className="w-8 h-8 border-2 border-white/10 border-t-[#ae895e] rounded-full animate-spin" />
          </div>
        )}
        {svgContent && (
          <div
            ref={svgRef}
            dangerouslySetInnerHTML={{ __html: svgContent }}
            onClick={handleClick}
            className={`cursor-pointer ${styles.svgContainer}`}
          />
        )}
      </div>

      {/* Selected tables summary */}
      {selectedTables.size > 0 && (
        <div className="mt-4 p-4 border border-[#ae895e]/30 bg-[#ae895e]/5 flex justify-between items-center text-sm font-light">
          <span className="text-white/70">
            {language === 'ka' ? 'არჩეული:' : 'Selected:'}{' '}
            <strong className="text-[#ae895e]">
              {Array.from(selectedTables).map(formatTableName).join(', ')}
            </strong>
          </span>
          <svg className="w-4 h-4 text-[#ae895e]" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M5 13l4 4L19 7" />
          </svg>
        </div>
      )}
    </div>
  );
};

export default TablePickerMini;
