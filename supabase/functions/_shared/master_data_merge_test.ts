import { assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { mergeField, mergeRecord } from './master_data_merge.ts';

Deno.test('fills an empty app field from Lark', () => {
  const m = mergeField(null, null, '0912');
  assertEquals(m.value, '0912');
  assertEquals(m.snapshot, '0912');
  assertEquals(m.changed, true);
});

Deno.test('applies a Lark correction when the app still tracks Lark', () => {
  const m = mergeField('old', 'old', 'new'); // app == snapshot
  assertEquals(m.value, 'new');
  assertEquals(m.snapshot, 'new');
  assertEquals(m.changed, true);
});

Deno.test('skips (app owns it) when the app diverged from the last Lark value', () => {
  const m = mergeField('hr-edit', 'lark-old', 'lark-new'); // app != snapshot
  assertEquals(m.value, 'hr-edit');
  assertEquals(m.snapshot, 'lark-old'); // frozen
  assertEquals(m.changed, false);
});

Deno.test('a blank incoming never wipes an app value nor advances the snapshot', () => {
  const m = mergeField('has', 'has', '');
  assertEquals(m.value, 'has');
  assertEquals(m.snapshot, 'has');
  assertEquals(m.changed, false);
});

Deno.test('no-op when Lark repeats the value the app already has', () => {
  const m = mergeField('same', 'same', 'same');
  assertEquals(m.changed, false);
});

Deno.test('mergeRecord returns only changed fields + the advanced snapshot', () => {
  const r = mergeRecord(
    { phone: '111', tin: 'hr-fixed', addr: null },
    { phone: '111', tin: 'lark-old', addr: null },
    { phone: '222', tin: 'lark-new', addr: 'Main St' },
  );
  assertEquals(r.updates, { phone: '222', addr: 'Main St' }); // tin skipped (app owns it)
  assertEquals(r.snapshot.phone, '222');
  assertEquals(r.snapshot.tin, 'lark-old'); // frozen — app owns it
  assertEquals(r.snapshot.addr, 'Main St');
});
