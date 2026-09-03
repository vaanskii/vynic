import type { ReactNode } from "react";
import { Button } from "./Button";

export function Table({ children }: { children: ReactNode }) {
  return <div className="platform-table-wrap"><table className="platform-table">{children}</table></div>;
}

export function Pagination({
  total,
  offset,
  limit,
  onChange,
}: {
  total: number;
  offset: number;
  limit: number;
  onChange(offset: number): void;
}) {
  const first = total === 0 ? 0 : offset + 1;
  const last = Math.min(offset + limit, total);
  return (
    <div className="platform-pagination">
      <span>{first}–{last} of {total}</span>
      <div>
        <Button tone="quiet" disabled={offset === 0} onClick={() => onChange(Math.max(0, offset - limit))}>Previous</Button>
        <Button tone="quiet" disabled={offset + limit >= total} onClick={() => onChange(offset + limit)}>Next</Button>
      </div>
    </div>
  );
}
