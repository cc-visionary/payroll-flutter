import { assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { decryptLarkEvent, keywordToIntent, eventKeyToIntent } from './lark_events.ts';

// AES-CBC + SHA-256(key) round trip (encrypt here exactly as Lark does, then decrypt).
async function larkEncrypt(plain: string, key: string): Promise<string> {
  const enc = new TextEncoder();
  const keyBytes = new Uint8Array(await crypto.subtle.digest('SHA-256', enc.encode(key)));
  const iv = crypto.getRandomValues(new Uint8Array(16));
  const ck = await crypto.subtle.importKey('raw', keyBytes, { name: 'AES-CBC' }, false, ['encrypt']);
  const ct = new Uint8Array(await crypto.subtle.encrypt({ name: 'AES-CBC', iv }, ck, enc.encode(plain)));
  const packed = new Uint8Array(iv.length + ct.length);
  packed.set(iv, 0); packed.set(ct, iv.length);
  return btoa(String.fromCharCode(...packed));
}

Deno.test('decryptLarkEvent round-trips a Lark-encrypted payload', async () => {
  const payload = JSON.stringify({ type: 'url_verification', challenge: 'abc123', token: 'vt' });
  const encrypted = await larkEncrypt(payload, 'my-encrypt-key');
  const out = await decryptLarkEvent(encrypted, 'my-encrypt-key');
  assertEquals(out.challenge, 'abc123');
  assertEquals(out.token, 'vt');
});

Deno.test('keywordToIntent maps known keywords, else help', () => {
  assertEquals(keywordToIntent('  Payslip '), 'my_payslip');
  assertEquals(keywordToIntent('leave'), 'my_leave');
  assertEquals(keywordToIntent('my tasks'), 'my_tasks');
  assertEquals(keywordToIntent('responsibilities'), 'my_tasks');
  assertEquals(keywordToIntent('reviews'), 'my_reviews');
  assertEquals(keywordToIntent('info'), 'my_info');
  assertEquals(keywordToIntent('hello?'), 'help');
});

Deno.test('eventKeyToIntent maps menu keys, else help', () => {
  assertEquals(eventKeyToIntent('my_payslip'), 'my_payslip');
  assertEquals(eventKeyToIntent('nonsense'), 'help');
});
