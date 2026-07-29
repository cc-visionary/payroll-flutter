import { assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import {
  larkMsToPHDate,
  larkPersonId,
  mapEmployeeInfoRecord,
  routeKey,
} from './master_data_map.ts';

// 2001-05-15 00:00 PH == 2001-05-14 16:00 UTC. Naive UTC slicing would give the
// 14th; the +8h shift must recover the 15th.
const BDAY_MS_PH_MIDNIGHT = Date.UTC(2001, 4, 14, 16, 0, 0);

Deno.test('maps a full record into employee/statutory/bank + match key', () => {
  const m = mapEmployeeInfoRecord({
    'First Name': 'Juan',
    'Middle Name': [{ text: 'Santos', type: 'text' }],
    'Last Name': 'Dela Cruz',
    'Lark Profile': [{ id: 'u-123', name: 'Juan' }],
    'Birthday': BDAY_MS_PH_MIDNIGHT,
    'Email Address': 'juan@example.com',
    'Present Address': '123 Main St',
    'Civil Status': 'Married',
    'Contact #': 9171234567,
    'TIN': '123-456-789',
    'SSS': 3411223344,
    'PhilHealth': 112233445566,
    'PAG-IBIG': 998877665544,
    'Emergency Contact': 'Maria Dela Cruz',
    'Emergency #': 9998887777,
    'Relationship': 'Spouse',
    'Metrobank Acct. No.': '0012345678',
    'GCASH No.': 9171234567,
  });

  assertEquals(m.larkUserId, 'u-123');
  assertEquals(m.fullName, 'Juan Dela Cruz');
  assertEquals(m.incoming.first_name, 'Juan');
  assertEquals(m.incoming.middle_name, 'Santos');
  assertEquals(m.incoming.birth_date, '2001-05-15');
  assertEquals(m.incoming.civil_status, 'MARRIED'); // uppercased to app enum
  assertEquals(m.incoming.phone_number, '09171234567'); // leading 0 restored
  assertEquals(m.incoming.emergency_contact_number, '09998887777');
  assertEquals(m.incoming.stat_TIN, '123-456-789');
  assertEquals(m.incoming.stat_SSS, '3411223344'); // statutory left as-is
  assertEquals(m.incoming.bank_MBTC, '0012345678'); // text field keeps leading zeros
  assertEquals(m.incoming.bank_GCASH, '09171234567'); // GCash mobile, leading 0 restored
});

Deno.test('blank optional fields normalise to null', () => {
  const m = mapEmployeeInfoRecord({
    'First Name': 'Ana',
    'Last Name': 'Reyes',
    'Lark Profile': [{ id: 'u-9' }],
    'Middle Name': '',
    'TIN': '   ',
    'SSS': null,
    'GCASH No.': '',
  });
  assertEquals(m.incoming.middle_name, null);
  assertEquals(m.incoming.stat_TIN, null);
  assertEquals(m.incoming.stat_SSS, null);
  assertEquals(m.incoming.bank_GCASH, null);
  assertEquals(m.incoming.personal_email, null);
});

Deno.test('an unlinked row (no Lark Profile) yields a null match key', () => {
  const m = mapEmployeeInfoRecord({ 'First Name': 'X', 'Last Name': 'Y', 'Lark Profile': [] });
  assertEquals(m.larkUserId, null);
});

Deno.test('numeric normalisation strips a trailing .0 and commas', () => {
  const m = mapEmployeeInfoRecord({ 'Contact #': 9171234567.0, 'SSS': '34,112,233' });
  assertEquals(m.incoming.phone_number, '09171234567'); // mobile: leading 0 restored
  assertEquals(m.incoming.stat_SSS, '34112233'); // statutory: not a mobile, left as-is
});

Deno.test('a landline-style contact number is not mangled by the mobile rule', () => {
  const m = mapEmployeeInfoRecord({ 'Contact #': '8123-4567', 'GCASH No.': 639171234567 });
  assertEquals(m.incoming.phone_number, '8123-4567'); // not 10-digit-9xxx -> untouched
  assertEquals(m.incoming.bank_GCASH, '639171234567'); // +63 form -> untouched (not 9xxxxxxxxx)
});

Deno.test('larkMsToPHDate keeps the intended PH calendar date', () => {
  assertEquals(larkMsToPHDate(BDAY_MS_PH_MIDNIGHT), '2001-05-15');
});

Deno.test('larkPersonId handles array, object, and empty forms', () => {
  assertEquals(larkPersonId([{ id: 'u-1' }]), 'u-1');
  assertEquals(larkPersonId({ id: 'u-2' }), 'u-2');
  assertEquals(larkPersonId([]), null);
  assertEquals(larkPersonId(null), null);
});

Deno.test('routeKey directs keys to the right app destination', () => {
  assertEquals(routeKey('first_name'), { kind: 'employee', column: 'first_name' });
  assertEquals(routeKey('stat_PHILHEALTH'), { kind: 'statutory', idType: 'PHILHEALTH' });
  assertEquals(routeKey('bank_MBTC'), {
    kind: 'bank',
    bankCode: 'MBTC',
    bankName: 'Metrobank',
    isPrimary: true,
  });
  assertEquals(routeKey('bank_GCASH'), {
    kind: 'bank',
    bankCode: 'GCASH',
    bankName: 'GCash',
    isPrimary: false,
  });
});
