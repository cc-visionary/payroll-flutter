// Building the row that `sync-lark-leaves` inserts when Lark reports a leave
// type nobody has seen before.
//
// This lives here, apart from the sync, for one reason: it used to be an inline
// object literal inside a retry loop, and it silently omitted `is_paid`. The
// column defaulted to true, so every leave type Lark had ever sent became paid
// — Personal leave included — and payroll emitted a full-day earnings line for
// each. Nothing could test an object literal buried in a loop. This can be
// tested, and is.

export interface LeaveTypeRow {
  company_id: string;
  code: string;
  name: string;
  lark_leave_type_id: string;
  accrual_type: 'NONE';
  is_active: boolean;
  is_paid: boolean;
}

/// Display name for a Lark leave type, preferring the caller's locale and
/// falling back through en_us and zh_cn to the raw id.
export function larkLeaveTypeName(
  i18nNames: Record<string, string> | undefined,
  defaultLocale: string | undefined,
  fallbackId: string,
): string {
  const names = i18nNames ?? {};
  const locale = defaultLocale ?? 'en_us';
  return (names[locale] ?? names['en_us'] ?? names['zh_cn'] ?? fallbackId)
    .toString()
    .slice(0, 100);
}

/// A readable code from the display name. Two different Lark ids can collapse
/// to the same 18-char slice, so the caller retries with `attempt` 1, 2, … and
/// gets `-2`, `-3`, … suffixes on a unique violation.
export function larkLeaveTypeCode(
  displayName: string,
  fallbackId: string,
  attempt: number,
): string {
  const baseSource = (displayName || fallbackId.toString())
    .toUpperCase()
    .replace(/[^A-Z0-9]+/g, '_')
    .replace(/^_+|_+$/g, '');
  const baseCode = (baseSource || 'LARK').slice(0, 18);
  const code = attempt === 0 ? baseCode : `${baseCode.slice(0, 18)}-${attempt + 1}`;
  return code.slice(0, 20);
}

/// The row itself.
///
/// `is_paid` is ALWAYS false and is not a parameter. That is deliberate, and it
/// is the whole point of this module: Lark tells us a leave type's name, never
/// whether the company pays for it. An importer that cannot know the answer
/// must not guess the expensive one — an underpayment is visible to the
/// employee and correctable, an overpayment ships silently. Whether a type is
/// paid is decided in Settings > Leave Types, by a person, after the fact.
///
/// If you are here to add an `isPaid` parameter so some caller can pass true:
/// don't. Make the caller write to Settings instead.
export function buildLarkLeaveTypeRow(args: {
  companyId: string;
  displayName: string;
  larkLeaveTypeId: string;
  attempt: number;
}): LeaveTypeRow {
  const code = larkLeaveTypeCode(
    args.displayName,
    args.larkLeaveTypeId,
    args.attempt,
  );
  return {
    company_id: args.companyId,
    code,
    name: args.displayName || code,
    lark_leave_type_id: args.larkLeaveTypeId.toString().slice(0, 100),
    accrual_type: 'NONE',
    is_active: true,
    is_paid: false,
  };
}
