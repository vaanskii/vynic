/**
 * Where one POS snapshot request spends its time on the server.
 *
 * The POS reports a sync taking ten to fifteen seconds, and its own summary can
 * only say how long the whole HTTP call took. This is the other half of that
 * number: which ingest steps the request actually spent time in, so a slow
 * category can be told apart from a slow network — or from a POS that had not
 * started sending yet.
 *
 * Monotonic by construction (`process.hrtime.bigint()`), because a duration
 * measured by subtracting two clock readings is not a duration if the clock
 * moves. One request prints one line, and it carries step names and counts
 * only — never payload contents.
 */
export class SyncTimer {
  private readonly startedAt = process.hrtime.bigint();
  private readonly steps: Array<[string, number]> = [];
  private readonly notes: string[] = [];

  /** Runs [body] as a named step and records how long it took. */
  async phase<T>(name: string, body: () => Promise<T>): Promise<T> {
    const from = process.hrtime.bigint();
    try {
      return await body();
    } finally {
      this.steps.push([name, Number(process.hrtime.bigint() - from) / 1e6]);
    }
  }

  /** Times a synchronous step. */
  sync<T>(name: string, body: () => T): T {
    const from = process.hrtime.bigint();
    try {
      return body();
    } finally {
      this.steps.push([name, Number(process.hrtime.bigint() - from) / 1e6]);
    }
  }

  /** Adds a plain counter to the summary line, e.g. `orders=42`. */
  note(text: string): void {
    this.notes.push(text);
  }

  /** Prints the one-line summary for [source]. */
  log(source: string): void {
    const total = Number(process.hrtime.bigint() - this.startedAt) / 1e6;
    const measured = this.steps
      .map(([name, ms]) => `${name}=${Math.round(ms)}ms`)
      .join(' ');
    const counted = this.notes.length > 0 ? ` ${this.notes.join(' ')}` : '';
    console.log(
      `[SyncTiming][${source}] ${measured} total=${Math.round(total)}ms${counted}`,
    );
  }
}
