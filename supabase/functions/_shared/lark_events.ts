// Pure helpers for the Luxium People bot: decrypt a Lark event, and map a menu
// event_key / message keyword to a bot intent. No Lark/DB dependency.
// See docs/superpowers/specs/2026-07-29-employee-self-service-bot-design.md.

export type BotIntent =
  | 'my_payslip' | 'my_leave' | 'my_tasks' | 'my_reviews' | 'my_info' | 'help';

/** Decrypt a Lark `encrypt` payload. Lark: key = SHA-256(EncryptKey); the
 *  base64 body is IV(16 bytes) || AES-256-CBC ciphertext (PKCS7). */
export async function decryptLarkEvent(
  encrypt: string,
  encryptKey: string,
): Promise<Record<string, unknown>> {
  const keyBytes = new Uint8Array(
    await crypto.subtle.digest('SHA-256', new TextEncoder().encode(encryptKey)),
  );
  const raw = Uint8Array.from(atob(encrypt), (c) => c.charCodeAt(0));
  const iv = raw.slice(0, 16);
  const ct = raw.slice(16);
  const ck = await crypto.subtle.importKey('raw', keyBytes, { name: 'AES-CBC' }, false, ['decrypt']);
  const pt = await crypto.subtle.decrypt({ name: 'AES-CBC', iv }, ck, ct);
  return JSON.parse(new TextDecoder().decode(pt)) as Record<string, unknown>;
}

const _KEYWORDS: Array<[RegExp, BotIntent]> = [
  [/pay ?slip|payroll|salary/i, 'my_payslip'],
  [/leave|attendance|balance/i, 'my_leave'],
  [/task|responsib|workload/i, 'my_tasks'],
  [/review|self.?eval|evaluation/i, 'my_reviews'],
  [/info|profile|personal|bank|statutory/i, 'my_info'],
];

export function keywordToIntent(text: string): BotIntent {
  const t = (text ?? '').trim();
  for (const [re, intent] of _KEYWORDS) if (re.test(t)) return intent;
  return 'help';
}

const _MENU_KEYS = new Set<BotIntent>(['my_payslip', 'my_leave', 'my_tasks', 'my_reviews', 'my_info']);

export function eventKeyToIntent(key: string): BotIntent {
  return _MENU_KEYS.has(key as BotIntent) ? (key as BotIntent) : 'help';
}
