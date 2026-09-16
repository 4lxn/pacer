// ponytail: in-memory per-user daily counter; resets on redeploy. Move to a Railway volume + SQLite
// (or Redis) when there are enough users for a restart to matter.
export class DailyLimiter {
  constructor(limit) {
    this.limit = limit;
    this.counts = new Map(); // key -> { day, n }
  }

  /** Returns { allowed, remaining }. `day` is a yyyy-mm-dd string (UTC). */
  hit(key, day = new Date().toISOString().slice(0, 10)) {
    const entry = this.counts.get(key);
    const n = entry && entry.day === day ? entry.n : 0;
    if (n >= this.limit) return { allowed: false, remaining: 0 };
    this.counts.set(key, { day, n: n + 1 });
    return { allowed: true, remaining: this.limit - n - 1 };
  }
}
