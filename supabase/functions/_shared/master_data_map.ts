// Maps a Lark "Employee Information" Base record → app-shaped master data.
//
// Only the fields the EMPLOYEE enters in the onboarding form are synced (these
// are Lark-owned). Department, Position, Status, Start Date and Contract Link
// are HR-managed in the Base and are NEVER synced — the app owns role /
// employment / comp. The match key is the "Lark Profile" person field, resolved
// to a Lark user_id that lines up with employees.lark_user_id (records must be
// read with user_id_type=user_id). A row with an empty Lark Profile is skipped
// upstream — HR linking the profile is what admits a new hire into payroll.
//
// Pure + field-agnostic: emits a flat `incoming` record keyed by stable snapshot
// keys, which feeds the three-way merge (master_data_merge.ts). `routeKey` maps
// each key back to its app destination (employee column / statutory row / bank
// row). See docs/superpowers/specs/2026-07-25-employee-master-data-sync-design.md.

import { baseCellText } from './lark.ts';

export const LARK_TABLE_EMPLOYEE_INFO = 'Employee Information';

// Exact Lark field names (from the live Base schema, 2026-07).
const F = {
  first: 'First Name',
  middle: 'Middle Name',
  last: 'Last Name',
  profile: 'Lark Profile',
  birthday: 'Birthday',
  email: 'Email Address',
  address: 'Present Address',
  civil: 'Civil Status',
  contact: 'Contact #',
  tin: 'TIN',
  sss: 'SSS',
  philhealth: 'PhilHealth',
  pagibig: 'PAG-IBIG',
  emgName: 'Emergency Contact',
  emgNumber: 'Emergency #',
  emgRel: 'Relationship',
  metrobank: 'Metrobank Acct. No.',
  gcash: 'GCASH No.',
} as const;

// Display names + primary preference for the two disbursement rails the form
// captures. bank_code matches the app's PaymentSource matching (MBTC / GCASH).
export const BANK_META: Record<string, { bankName: string }> = {
  MBTC: { bankName: 'Metrobank' },
  GCASH: { bankName: 'GCash' },
};

export interface MappedMasterData {
  /** Lark user_id from the "Lark Profile" person field; null => unlinked row. */
  larkUserId: string | null;
  /** Synced values keyed by stable snapshot key (feeds mergeRecord). */
  incoming: Record<string, string | null>;
  /** "First Last" — used as the default bank account_name (NOT NULL column). */
  fullName: string;
}

export type Route =
  | { kind: 'employee'; column: string }
  | { kind: 'statutory'; idType: string }
  | { kind: 'bank'; bankCode: string; bankName: string; isPrimary: boolean };

/** Map a snapshot key back to its app destination. `stat_*` -> statutory id_type,
 *  `bank_*` -> bank_code, everything else -> an employees column. */
export function routeKey(key: string): Route {
  if (key.startsWith('stat_')) return { kind: 'statutory', idType: key.slice(5) };
  if (key.startsWith('bank_')) {
    const code = key.slice(5);
    return {
      kind: 'bank',
      bankCode: code,
      bankName: BANK_META[code]?.bankName ?? code,
      // Metrobank is the default primary; the edge fn promotes GCash to primary
      // if it is the only account.
      isPrimary: code === 'MBTC',
    };
  }
  return { kind: 'employee', column: key };
}

/** Lark stores number fields as JS numbers — stringify without a trailing
 *  ".0"/thousands separators. NOTE: leading zeros are already lost in Lark for
 *  Number-type fields (phone/GCash/statutory) and cannot be recovered here. */
function numText(v: unknown): string | null {
  const s = baseCellText(v);
  if (s == null) return null;
  const cleaned = s.replace(/,/g, '').replace(/\.0+$/, '').trim();
  return cleaned === '' ? null : cleaned;
}

/** PH mobile numbers are 11 digits starting "09". Lark Number-type fields drop
 *  the leading 0, leaving 10 digits starting "9" — restore it so phone/GCash
 *  values are valid for disbursement. (Statutory IDs are left as-is; their
 *  leading-zero loss isn't safely reconstructable — switch those to Text.) */
function phMobile(v: unknown): string | null {
  const s = numText(v);
  if (s == null) return null;
  return /^9\d{9}$/.test(s) ? '0' + s : s;
}

function upperOrNull(s: string | null): string | null {
  return s == null ? null : s.toUpperCase();
}

/** Convert a Lark date/datetime cell (epoch ms, or a number-as-string, or an
 *  already-formatted date) to 'YYYY-MM-DD'. Lark date fields sit at local
 *  midnight; shift by +8h (PH) before taking the UTC calendar date so we don't
 *  land on the previous day. */
export function larkMsToPHDate(ms: number): string {
  return new Date(ms + 8 * 3600 * 1000).toISOString().slice(0, 10);
}

function larkDateCell(v: unknown): string | null {
  if (v == null || v === '') return null;
  const ms = typeof v === 'number'
    ? v
    : typeof v === 'string' && /^\d+$/.test(v)
    ? Number(v)
    : NaN;
  if (Number.isFinite(ms)) return larkMsToPHDate(ms);
  const s = baseCellText(v);
  return s && /^\d{4}-\d{2}-\d{2}/.test(s) ? s.slice(0, 10) : null;
}

/** Extract the id from a Lark person-field cell. With user_id_type=user_id on
 *  the records read, `.id` is the tenant user_id that matches
 *  employees.lark_user_id. */
export function larkPersonId(v: unknown): string | null {
  if (Array.isArray(v) && v.length > 0) {
    const first = v[0] as { id?: unknown };
    return typeof first?.id === 'string' && first.id !== '' ? first.id : null;
  }
  if (v && typeof v === 'object' && 'id' in v) {
    const id = (v as { id?: unknown }).id;
    return typeof id === 'string' && id !== '' ? id : null;
  }
  return null;
}

export function mapEmployeeInfoRecord(fields: Record<string, unknown>): MappedMasterData {
  const t = (name: string) => baseCellText(fields[name]);
  const n = (name: string) => numText(fields[name]);

  const incoming: Record<string, string | null> = {
    first_name: t(F.first),
    middle_name: t(F.middle),
    last_name: t(F.last),
    birth_date: larkDateCell(fields[F.birthday]),
    personal_email: t(F.email),
    present_address_line1: t(F.address),
    civil_status: upperOrNull(t(F.civil)),
    phone_number: phMobile(fields[F.contact]),
    emergency_contact_name: t(F.emgName),
    emergency_contact_number: phMobile(fields[F.emgNumber]),
    emergency_contact_relationship: t(F.emgRel),
    stat_TIN: t(F.tin),
    stat_SSS: n(F.sss),
    stat_PHILHEALTH: n(F.philhealth),
    stat_PAGIBIG: n(F.pagibig),
    bank_MBTC: t(F.metrobank),
    bank_GCASH: phMobile(fields[F.gcash]),
  };

  const fullName = `${incoming.first_name ?? ''} ${incoming.last_name ?? ''}`.trim();
  return { larkUserId: larkPersonId(fields[F.profile]), incoming, fullName };
}
