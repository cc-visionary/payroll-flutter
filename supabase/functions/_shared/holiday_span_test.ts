// deno test supabase/functions/_shared/holiday_span_test.ts

import { assertEquals, assertThrows } from 'jsr:@std/assert@1';
import {
  detectEndDateConvention,
  expandHolidayDates,
  MAX_HOLIDAY_SPAN_DAYS,
} from './holiday_span.ts';

// --- expandHolidayDates: all-day (`date`) events -------------------------

Deno.test('INCLUSIVE single-day event covers exactly that day', () => {
  assertEquals(
    expandHolidayDates({ date: '2026-11-30' }, { date: '2026-11-30' }, 'INCLUSIVE'),
    ['2026-11-30'],
  );
});

Deno.test('INCLUSIVE multi-day event covers every day through the end date', () => {
  assertEquals(
    expandHolidayDates({ date: '2026-11-16' }, { date: '2026-11-18' }, 'INCLUSIVE'),
    ['2026-11-16', '2026-11-17', '2026-11-18'],
  );
});

Deno.test('EXCLUSIVE single-day event does not leak into the next day', () => {
  assertEquals(
    expandHolidayDates({ date: '2026-11-30' }, { date: '2026-12-01' }, 'EXCLUSIVE'),
    ['2026-11-30'],
  );
});

Deno.test('EXCLUSIVE multi-day event stops before the end date', () => {
  assertEquals(
    expandHolidayDates({ date: '2026-11-16' }, { date: '2026-11-19' }, 'EXCLUSIVE'),
    ['2026-11-16', '2026-11-17', '2026-11-18'],
  );
});

Deno.test('span crossing a year boundary enumerates every date', () => {
  assertEquals(
    expandHolidayDates({ date: '2026-12-30' }, { date: '2027-01-02' }, 'INCLUSIVE'),
    ['2026-12-30', '2026-12-31', '2027-01-01', '2027-01-02'],
  );
});

// --- expandHolidayDates: degenerate input --------------------------------

Deno.test('missing end falls back to the start date alone', () => {
  assertEquals(
    expandHolidayDates({ date: '2026-11-16' }, undefined, 'INCLUSIVE'),
    ['2026-11-16'],
  );
});

Deno.test('unparseable end falls back to the start date alone', () => {
  assertEquals(
    expandHolidayDates({ date: '2026-11-16' }, { date: 'not-a-date' }, 'INCLUSIVE'),
    ['2026-11-16'],
  );
});

Deno.test('end before start falls back to the start date alone', () => {
  assertEquals(
    expandHolidayDates({ date: '2026-11-16' }, { date: '2026-11-10' }, 'INCLUSIVE'),
    ['2026-11-16'],
  );
});

Deno.test('EXCLUSIVE end equal to start falls back to the start date alone', () => {
  // A zero-length event under the exclusive reading. Writing nothing would
  // drop a holiday the calendar clearly shows, so keep the start day.
  assertEquals(
    expandHolidayDates({ date: '2026-11-16' }, { date: '2026-11-16' }, 'EXCLUSIVE'),
    ['2026-11-16'],
  );
});

Deno.test('missing start yields no dates', () => {
  assertEquals(expandHolidayDates(undefined, { date: '2026-11-18' }, 'INCLUSIVE'), []);
});

Deno.test('absurd span throws rather than writing hundreds of rows', () => {
  assertThrows(
    () => expandHolidayDates({ date: '2026-01-01' }, { date: '2026-12-31' }, 'INCLUSIVE'),
    RangeError,
    `${MAX_HOLIDAY_SPAN_DAYS}`,
  );
});

// --- expandHolidayDates: timestamp events --------------------------------

Deno.test('timestamp event covers the day it ends on', () => {
  // 2026-11-16 09:00 UTC → 2026-11-18 18:00 UTC
  assertEquals(
    expandHolidayDates(
      { timestamp: `${Date.UTC(2026, 10, 16, 9) / 1000}` },
      { timestamp: `${Date.UTC(2026, 10, 18, 18) / 1000}` },
      'INCLUSIVE',
    ),
    ['2026-11-16', '2026-11-17', '2026-11-18'],
  );
});

Deno.test('timestamp ending exactly at midnight excludes that day', () => {
  // Midnight is how an all-day span is expressed in timestamp form — the
  // event ends as the day begins, so it does not cover it.
  assertEquals(
    expandHolidayDates(
      { timestamp: `${Date.UTC(2026, 10, 16) / 1000}` },
      { timestamp: `${Date.UTC(2026, 10, 19) / 1000}` },
      'INCLUSIVE',
    ),
    ['2026-11-16', '2026-11-17', '2026-11-18'],
  );
});

// --- detectEndDateConvention ---------------------------------------------

Deno.test('an event ending on its own start date proves the API is inclusive', () => {
  // An exclusive API cannot emit end == start: that is a zero-length event.
  assertEquals(
    detectEndDateConvention([
      { start_time: { date: '2026-11-16' }, end_time: { date: '2026-11-18' } },
      { start_time: { date: '2026-11-30' }, end_time: { date: '2026-11-30' } },
    ]),
    'INCLUSIVE',
  );
});

Deno.test('every event ending a day past its start reads as exclusive', () => {
  assertEquals(
    detectEndDateConvention([
      { start_time: { date: '2026-11-30' }, end_time: { date: '2026-12-01' } },
      { start_time: { date: '2026-12-25' }, end_time: { date: '2026-12-26' } },
    ]),
    'EXCLUSIVE',
  );
});

Deno.test('timestamp-only events carry no signal and leave the default', () => {
  assertEquals(
    detectEndDateConvention([
      { start_time: { timestamp: '1763251200' }, end_time: { timestamp: '1763337600' } },
    ]),
    'EXCLUSIVE',
  );
});

Deno.test('no events reads as exclusive', () => {
  assertEquals(detectEndDateConvention([]), 'EXCLUSIVE');
});
