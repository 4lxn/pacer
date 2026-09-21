import test from "node:test";
import assert from "node:assert/strict";
import { fold, stats } from "../src/stats.mjs";

test("retention cohorts, DAU/MAU and check-in share", () => {
  const lines = [
    { id: "a", day: "2026-09-01", events: { opened: 1, checkInNotif: 1, onPace: 1 } },
    { id: "a", day: "2026-09-09", events: { opened: 1 } },            // D7 window (8th–14th)
    { id: "a", day: "2026-10-03", events: { opened: 1 } },            // D30 window (Oct 1–7)
    { id: "b", day: "2026-09-01", events: { opened: 1 } },
    { id: "b", day: "2026-09-02", events: { opened: 2, checkInNotif: 2 } },
    { id: "b", day: "2026-09-02", events: { opened: 3, checkInNotif: 2 } }, // newer ping replaces
    { id: "c", day: "2026-10-03", events: { opened: 1 } },
    { id: "bad", day: "not-a-day", events: {} },
  ];
  const s = stats(fold(lines), "2026-10-03");
  assert.equal(s.users, 3);
  assert.equal(s.dau, 2);
  assert.equal(s.mau, 2, "b's last day is Sep 2, outside the 30-day window");
  assert.equal(s.d7, 0.5, "cohort Sep 1: a came back in the D7 window, b did not");
  assert.equal(s.d30, null, "the Sep 1 cohort's D30 window (Oct 1–7) has not closed on Oct 3");
  assert.equal(stats(fold(lines), "2026-10-08").d30, 0.5);
  assert.equal(s.checkInShare, 2 / 6);
  assert.equal(s.cohorts["2026-09-01"].n, 2);
});

test("cohorts too young for a window do not count", () => {
  const s = stats(fold([{ id: "x", day: "2026-10-01", events: {} }]), "2026-10-03");
  assert.equal(s.d7, null);
  assert.equal(s.d30, null);
});
