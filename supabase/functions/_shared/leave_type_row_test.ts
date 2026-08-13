// Run with: deno test supabase/functions/_shared/leave_type_row_test.ts
import { assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import {
  buildLarkLeaveTypeRow,
  larkLeaveTypeCode,
  larkLeaveTypeName,
} from './leave_type_row.ts';

Deno.test('an imported leave type is NEVER paid', () => {
  // The bug this whole module exists for. `is_paid` was omitted from an inline
  // insert, the column defaulted to true, and every leave type Lark had ever
  // sent silently paid a full day -- Personal leave included.
  const row = buildLarkLeaveTypeRow({
    companyId: 'c-1',
    displayName: 'Personal leave',
    larkLeaveTypeId: 'lark-personal',
    attempt: 0,
  });
  assertEquals(row.is_paid, false);
});

Deno.test('is_paid is false for every name Lark could send', () => {
  // Including names that sound paid. Nothing about a type's NAME may decide
  // whether the company pays for it -- that is a payroll decision, made in
  // Settings, by a person.
  for (
    const name of [
      'Personal leave',
      'Paid leave',
      'Service Incentive Leave',
      'Vacation Leave (Paid)',
      '',
    ]
  ) {
    const row = buildLarkLeaveTypeRow({
      companyId: 'c-1',
      displayName: name,
      larkLeaveTypeId: 'lark-x',
      attempt: 0,
    });
    assertEquals(row.is_paid, false, `"${name}" must import as unpaid`);
  }
});

Deno.test('the row carries every column the insert needs', () => {
  // A field missing here is a field the database defaults for us, which is
  // exactly how this went wrong the first time.
  const row = buildLarkLeaveTypeRow({
    companyId: 'c-1',
    displayName: 'Sick leave',
    larkLeaveTypeId: 'lark-sick',
    attempt: 0,
  });
  assertEquals(Object.keys(row).sort(), [
    'accrual_type',
    'code',
    'company_id',
    'is_active',
    'is_paid',
    'lark_leave_type_id',
    'name',
  ]);
  assertEquals(row.company_id, 'c-1');
  assertEquals(row.name, 'Sick leave');
  assertEquals(row.lark_leave_type_id, 'lark-sick');
  assertEquals(row.accrual_type, 'NONE');
  assertEquals(row.is_active, true);
});

Deno.test('code is derived from the name and suffixed on retry', () => {
  assertEquals(larkLeaveTypeCode('Personal leave', 'x', 0), 'PERSONAL_LEAVE');
  assertEquals(larkLeaveTypeCode('Personal leave', 'x', 1), 'PERSONAL_LEAVE-2');
  assertEquals(larkLeaveTypeCode('Personal leave', 'x', 2), 'PERSONAL_LEAVE-3');
});

Deno.test('code stays within the column width on every attempt', () => {
  // leave_types.code is varchar(20); overflowing it turns a retry into a hard
  // failure instead of a second attempt.
  const long = 'Extraordinarily Long Leave Type Name From Lark';
  for (let attempt = 0; attempt < 25; attempt++) {
    const code = larkLeaveTypeCode(long, 'x', attempt);
    if (code.length > 20) throw new Error(`attempt ${attempt}: ${code}`);
  }
});

Deno.test('a nameless type still yields a usable code', () => {
  const row = buildLarkLeaveTypeRow({
    companyId: 'c-1',
    displayName: '',
    larkLeaveTypeId: '!!!',
    attempt: 0,
  });
  assertEquals(row.code, 'LARK');
  assertEquals(row.name, 'LARK', 'name falls back to the code, never blank');
});

Deno.test('name prefers the default locale, then en_us, then zh_cn', () => {
  assertEquals(
    larkLeaveTypeName({ ja_jp: '有給休暇', en_us: 'Paid leave' }, 'ja_jp', 'id'),
    '有給休暇',
  );
  assertEquals(
    larkLeaveTypeName({ en_us: 'Personal leave' }, 'ja_jp', 'id'),
    'Personal leave',
  );
  assertEquals(larkLeaveTypeName({ zh_cn: '事假' }, undefined, 'id'), '事假');
  assertEquals(larkLeaveTypeName(undefined, undefined, 'lark-99'), 'lark-99');
});
