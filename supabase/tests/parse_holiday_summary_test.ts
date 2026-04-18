// Run with: deno test supabase/tests/parse_holiday_summary_test.ts
import { assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { parseHolidaySummary } from '../functions/_shared/lark.ts';

Deno.test('parses real PH HR-Calendar formats', () => {
  assertEquals(
    parseHolidaySummary("Maundy Thursday (Regular Holiday)"),
    { dayType: 'REGULAR_HOLIDAY', name: 'Maundy Thursday' },
  );
  assertEquals(
    parseHolidaySummary("Araw ng Kagitingan (Regular Holiday)"),
    { dayType: 'REGULAR_HOLIDAY', name: 'Araw ng Kagitingan' },
  );
  assertEquals(
    parseHolidaySummary("Eidul Adha (Special Non-Working Holiday)"),
    { dayType: 'SPECIAL_HOLIDAY', name: 'Eidul Adha' },
  );
  assertEquals(
    parseHolidaySummary("Ninoy Aquino Day (Special Non Working Holiday)"),
    { dayType: 'SPECIAL_HOLIDAY', name: 'Ninoy Aquino Day' },
  );
  assertEquals(
    parseHolidaySummary("EDSA Revolution Anniversary (Special Working Holiday)"),
    { dayType: 'SPECIAL_WORKING', name: 'EDSA Revolution Anniversary' },
  );
});

Deno.test('parses legacy short suffixes', () => {
  assertEquals(
    parseHolidaySummary("New Year's Day (Regular)"),
    { dayType: 'REGULAR_HOLIDAY', name: "New Year's Day" },
  );
  assertEquals(
    parseHolidaySummary("All Saints' Day (Special)"),
    { dayType: 'SPECIAL_HOLIDAY', name: "All Saints' Day" },
  );
});

Deno.test('parses legacy bracket prefix', () => {
  assertEquals(
    parseHolidaySummary("[REGULAR] Christmas"),
    { dayType: 'REGULAR_HOLIDAY', name: 'Christmas' },
  );
  assertEquals(
    parseHolidaySummary("[SPECIAL] Halloween"),
    { dayType: 'SPECIAL_HOLIDAY', name: 'Halloween' },
  );
  assertEquals(
    parseHolidaySummary("[EXTRA] Bonus Workday"),
    { dayType: 'SPECIAL_WORKING', name: 'Bonus Workday' },
  );
});

Deno.test('skips non-holiday events', () => {
  assertEquals(parseHolidaySummary('Donald Xu Leave'), null);
  assertEquals(parseHolidaySummary('Toycon PH Summer Prelude'), null);
  assertEquals(parseHolidaySummary('Team Lunch (Optional)'), null);
  assertEquals(parseHolidaySummary('Birthday (HR)'), null);
});

Deno.test('skips missing or blank summaries', () => {
  assertEquals(parseHolidaySummary(undefined), null);
  assertEquals(parseHolidaySummary(null), null);
  assertEquals(parseHolidaySummary(''), null);
  assertEquals(parseHolidaySummary('   '), null);
});
