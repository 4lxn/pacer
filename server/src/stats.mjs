// Anonymous usage counts: one NDJSON line per (id, day) ping, appended to a file on the volume.
// Pure functions here so the retention math is testable without a disk.

/** Newest ping wins per (id, day); returns Map<id, Map<day, events>>. */
export function fold(lines) {
  const byID = new Map();
  for (const p of lines) {
    if (!p || typeof p.id !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(p.day || "")) continue;
    if (!byID.has(p.id)) byID.set(p.id, new Map());
    byID.get(p.id).set(p.day, p.events || {});
  }
  return byID;
}

function addDays(day, n) {
  const d = new Date(`${day}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() + n);
  return d.toISOString().slice(0, 10);
}

/**
 * The numbers the fail-fast gates ask for (docs/PRODUCT.md): DAU/MAU today, cohort D7 and D30
 * (active on any day in [d+7, d+13] / [d+30, d+36]), and the share of active days with a
 * check-in answered from a notification.
 */
export function stats(byID, today) {
  const mauSince = addDays(today, -29);
  let dau = 0, mau = 0, activeDays = 0, checkInDays = 0, onPaceDays = 0;
  const cohorts = new Map(); // firstDay -> { n, d7, d30 }
  for (const [, days] of byID) {
    const sorted = [...days.keys()].sort();
    const first = sorted[0];
    if (days.has(today)) dau++;
    if (sorted.some((d) => d >= mauSince && d <= today)) mau++;
    for (const [day, e] of days) {
      if (day > today) continue;
      activeDays++;
      if ((e.checkInNotif || 0) > 0) checkInDays++;
      if (e.onPace) onPaceDays++;
    }
    const c = cohorts.get(first) || { n: 0, d7: 0, d30: 0 };
    c.n++;
    if (sorted.some((d) => d >= addDays(first, 7) && d <= addDays(first, 13))) c.d7++;
    if (sorted.some((d) => d >= addDays(first, 30) && d <= addDays(first, 36))) c.d30++;
    cohorts.set(first, c);
  }
  // Only cohorts old enough to have had the window count toward the rate.
  const rate = (key, age) => {
    let n = 0, hit = 0;
    for (const [first, c] of cohorts) if (addDays(first, age) <= today) { n += c.n; hit += c[key]; }
    return n ? hit / n : null;
  };
  return {
    today, users: byID.size, dau, mau, dauOverMau: mau ? dau / mau : null,
    d7: rate("d7", 13), d30: rate("d30", 36),
    checkInShare: activeDays ? checkInDays / activeDays : null,
    onPaceShare: activeDays ? onPaceDays / activeDays : null,
    cohorts: Object.fromEntries([...cohorts].sort()),
  };
}
