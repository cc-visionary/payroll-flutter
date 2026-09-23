// Every date a Lark holiday event covers.
//
// Background: `sync-lark-calendar` used to read `start_time` and write one
// `calendar_events` row. A holiday spanning several days — the ASEAN Summit
// break, Nov 16-18 2026 — therefore landed in payroll as its first day only,
// and the rest stayed ordinary workdays. This module turns one event into the
// list of dates it actually covers.
//
// The hard part is that Lark's all-day `end_time.date` can be read two ways:
// INCLUSIVE (the last day of the holiday) or EXCLUSIVE (the day after, the
// convention Google Calendar uses). Guessing wrong is damaging either way —
// assume EXCLUSIVE when it is really INCLUSIVE and every single-day holiday
// disappears; assume INCLUSIVE when it is really EXCLUSIVE and Bonifacio Day
// grows a phantom Dec 1 twin. So the caller does not guess: it reads the
// convention off the batch with [detectEndDateConvention] and reports what it
// decided in the sync result.

/// Longest span a single holiday event may cover. A malformed event (or a
/// year-long "holiday" someone parked on the calendar) would otherwise write
/// hundreds of rows, and nothing in the app can delete them by hand.
export const MAX_HOLIDAY_SPAN_DAYS = 31;

export type EndDateConvention = 'INCLUSIVE' | 'EXCLUSIVE';

export interface LarkTimeRef {
  date?: string;
  timestamp?: string;
}

const DAY_MS = 86_400_000;

interface ResolvedDay {
  iso: string;
  /// Which shape the event used. The INCLUSIVE/EXCLUSIVE question only
  /// applies to the all-day `date` form.
  form: 'date' | 'timestamp';
  /// True when a timestamp lands exactly on 00:00 UTC.
  midnight: boolean;
}

function resolveDay(ref: LarkTimeRef | undefined): ResolvedDay | null {
  if (!ref) return null;
  if (ref.date) {
    if (!/^\d{4}-\d{2}-\d{2}$/.test(ref.date)) return null;
    if (Number.isNaN(Date.parse(ref.date))) return null; // e.g. 2026-02-30
    return { iso: ref.date, form: 'date', midnight: false };
  }
  if (ref.timestamp) {
    const secs = Number.parseInt(ref.timestamp, 10);
    if (!Number.isFinite(secs)) return null;
    const ms = secs * 1000;
    const d = new Date(ms);
    if (Number.isNaN(d.getTime())) return null;
    // Same UTC slicing the sync has always used for timestamps; changing it
    // to PH-local here would shift the dates of rows already synced.
    return {
      iso: d.toISOString().slice(0, 10),
      form: 'timestamp',
      midnight: ms % DAY_MS === 0,
    };
  }
  return null;
}

const msOf = (iso: string) => Date.parse(iso);
const isoOf = (ms: number) => new Date(ms).toISOString().slice(0, 10);

/// Every ISO date covered by an event running [start] → [end].
///
/// Falls back to the start date alone whenever [end] is missing, unparseable,
/// or lands before the start — a holiday the calendar plainly shows must not
/// vanish because its end is malformed. Returns `[]` only when there is no
/// usable start. Throws [RangeError] for a span over [MAX_HOLIDAY_SPAN_DAYS].
export function expandHolidayDates(
  start: LarkTimeRef | undefined,
  end: LarkTimeRef | undefined,
  convention: EndDateConvention,
): string[] {
  const s = resolveDay(start);
  if (!s) return [];
  const e = resolveDay(end);
  if (!e) return [s.iso];

  // A timed event ends at a wall-clock moment, so the day it ends on is
  // covered — unless it ends exactly at midnight, which is how an all-day
  // span reads in timestamp form: the event ends as that day begins.
  const endIsExclusive = e.form === 'date'
    ? convention === 'EXCLUSIVE'
    : e.midnight;

  const startMs = msOf(s.iso);
  const lastMs = msOf(e.iso) - (endIsExclusive ? DAY_MS : 0);
  if (!(lastMs >= startMs)) return [s.iso];

  const spanDays = (lastMs - startMs) / DAY_MS + 1;
  if (spanDays > MAX_HOLIDAY_SPAN_DAYS) {
    throw new RangeError(
      `holiday spans ${spanDays} days (${s.iso} → ${e.iso}), over the ` +
        `${MAX_HOLIDAY_SPAN_DAYS}-day limit`,
    );
  }

  const dates: string[] = [];
  for (let ms = startMs; ms <= lastMs; ms += DAY_MS) dates.push(isoOf(ms));
  return dates;
}

/// Which way this batch of events reads its all-day end dates.
///
/// One event ending on its own start date settles it: an EXCLUSIVE API can
/// never emit that, because it would describe a zero-length event. A PH
/// holiday calendar is mostly single-day holidays, so the signal is reliable;
/// no such event across a whole year means the ends are EXCLUSIVE.
export function detectEndDateConvention(
  events: { start_time?: LarkTimeRef; end_time?: LarkTimeRef }[],
): EndDateConvention {
  for (const ev of events) {
    const start = ev.start_time?.date;
    const end = ev.end_time?.date;
    if (start && end && start === end) return 'INCLUSIVE';
  }
  return 'EXCLUSIVE';
}
