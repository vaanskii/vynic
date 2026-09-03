import { Injectable } from '@nestjs/common';

interface Bucket {
  count: number;
  resetAt: number;
}

/**
 * A fixed-window counter for the one unauthenticated write in the system.
 *
 * In memory, on purpose. The alternative is Redis, and adding a second piece of
 * infrastructure to rate-limit an endpoint a restaurant hits once in its life
 * would be a worse trade than the property it buys: with one backend process
 * this is exact, and with several it is per-process, which still bounds the
 * total. The durable ceiling that actually protects a code is
 * `DeviceEnrollment.attemptCount`, which survives a restart and fails that code
 * closed; this only keeps a stranger from grinding through selectors.
 */
@Injectable()
export class EnrollmentRateLimiter {
  private readonly buckets = new Map<string, Bucket>();

  /** True when this key may proceed; false when it has spent its window. */
  consume(key: string, limit: number, windowMs: number, now = Date.now()) {
    this.sweep(now);
    const bucket = this.buckets.get(key);
    if (!bucket || bucket.resetAt <= now) {
      this.buckets.set(key, { count: 1, resetAt: now + windowMs });
      return true;
    }
    if (bucket.count >= limit) return false;
    bucket.count += 1;
    return true;
  }

  private sweep(now: number) {
    // Bounded work: only walk the map when it has grown enough to matter.
    if (this.buckets.size < 512) return;
    for (const [key, bucket] of this.buckets) {
      if (bucket.resetAt <= now) this.buckets.delete(key);
    }
  }
}
