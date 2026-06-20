import {
  HttpException,
  HttpStatus,
  Injectable,
  Logger,
} from '@nestjs/common';

/**
 * In-memory brute-force protection for PIN login.
 *
 * PIN login has no username, so attempts are tracked per client IP: after
 * MAX_FAILURES failed PINs an IP is locked for LOCK_MS. State is in-memory
 * (resets on restart) — adequate for the single-server deployment. For a
 * multi-instance deploy this would move to a shared store (Redis/DB).
 */
@Injectable()
export class LoginThrottleService {
  private readonly logger = new Logger(LoginThrottleService.name);
  private readonly attempts = new Map<
    string,
    { failures: number; lockedUntil: number }
  >();

  private readonly maxFailures = 5;
  private readonly lockMs = 15 * 60 * 1000; // 15 minutes

  /** Throw 429 if the key is currently locked; clear an expired lock. */
  assertNotLocked(key: string): void {
    const entry = this.attempts.get(key);
    if (!entry) return;
    const now = Date.now();
    if (entry.lockedUntil > now) {
      const retryInSec = Math.ceil((entry.lockedUntil - now) / 1000);
      throw new HttpException(
        `Too many failed login attempts. Try again in ${retryInSec}s.`,
        HttpStatus.TOO_MANY_REQUESTS,
      );
    }
    // Lock expired — start the next window fresh.
    if (entry.lockedUntil > 0) this.attempts.delete(key);
  }

  recordFailure(key: string): void {
    const failures = (this.attempts.get(key)?.failures ?? 0) + 1;
    const lockedUntil =
      failures >= this.maxFailures ? Date.now() + this.lockMs : 0;
    this.attempts.set(key, { failures, lockedUntil });
    if (lockedUntil) {
      this.logger.warn(
        `Login locked for ${key} for ${this.lockMs / 60000}m after ${failures} failed attempts`,
      );
    }
  }

  recordSuccess(key: string): void {
    this.attempts.delete(key);
  }
}
