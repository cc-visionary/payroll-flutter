import { assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { parseAction, validatePayload } from '../functions/manage-user/index.ts';

Deno.test('parseAction recognises every supported action', () => {
  assertEquals(parseAction('create'), 'create');
  assertEquals(parseAction('set_password'), 'set_password');
  assertEquals(parseAction('update_role'), 'update_role');
  assertEquals(parseAction('link_employee'), 'link_employee');
  assertEquals(parseAction('deactivate'), 'deactivate');
  assertEquals(parseAction('reactivate'), 'reactivate');
});

Deno.test('parseAction returns null for unknown', () => {
  assertEquals(parseAction('delete'), null);
  assertEquals(parseAction(''), null);
  assertEquals(parseAction(undefined), null);
});

Deno.test('validatePayload create requires email/password/role_code', () => {
  const ok = validatePayload('create', {
    email: 'a@b.com',
    password: 'longenough',
    role_code: 'PAYROLL_ADMIN',
  });
  assertEquals(ok.ok, true);

  const noEmail = validatePayload('create', {
    password: 'longenough',
    role_code: 'PAYROLL_ADMIN',
  });
  assertEquals(noEmail.ok, false);

  const shortPw = validatePayload('create', {
    email: 'a@b.com',
    password: 'short',
    role_code: 'PAYROLL_ADMIN',
  });
  assertEquals(shortPw.ok, false);
  assertEquals(shortPw.code, 'WEAK_PASSWORD');
});

Deno.test('validatePayload set_password requires user_id + password ≥ 8', () => {
  assertEquals(validatePayload('set_password', { user_id: 'u', password: 'longenough' }).ok, true);
  assertEquals(validatePayload('set_password', { user_id: 'u', password: '1234567' }).code, 'WEAK_PASSWORD');
  assertEquals(validatePayload('set_password', { password: 'longenough' }).ok, false);
});

Deno.test('validatePayload link_employee accepts null employee_id (unlink)', () => {
  assertEquals(validatePayload('link_employee', { user_id: 'u', employee_id: null }).ok, true);
  assertEquals(validatePayload('link_employee', { user_id: 'u', employee_id: 'e' }).ok, true);
  assertEquals(validatePayload('link_employee', { employee_id: 'e' }).ok, false);
});
