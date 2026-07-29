import { assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { maskLast4, payslipCard, infoCard, helpCard, linkPromptCard, reviewsCard } from './bot_cards.ts';

Deno.test('maskLast4 keeps only the last four digits', () => {
  assertEquals(maskLast4('123456789'), '••••6789');
  assertEquals(maskLast4('12'), '••••12');
  assertEquals(maskLast4(null), '—');
  assertEquals(maskLast4(''), '—');
});

Deno.test('payslipCard renders an empty state when there is no released payslip', () => {
  const card = payslipCard(null);
  const json = JSON.stringify(card);
  assertEquals(json.includes('No released payslip'), true);
  assertEquals((card as { config?: unknown }).config !== undefined || 'elements' in card, true);
});

Deno.test('payslipCard shows net pay and the period', () => {
  const json = JSON.stringify(payslipCard({
    periodLabel: 'Jun 1–15, 2026', netPay: '₱12,345.00', grossPay: '₱15,000.00',
    totalDeductions: '₱2,655.00', sssEe: '₱675.00', philhealthEe: '₱375.00',
    pagibigEe: '₱100.00', withholdingTax: '₱1,505.00', ytdGross: '₱90,000', ytdTax: '₱9,000',
  }));
  assertEquals(json.includes('₱12,345.00'), true);
  assertEquals(json.includes('Jun 1–15, 2026'), true);
});

Deno.test('infoCard masks statutory + bank numbers', () => {
  const json = JSON.stringify(infoCard({
    fullName: 'Juan Dela Cruz', statutory: [{ label: 'SSS', masked: maskLast4('3411223344') }],
    banks: [{ label: 'GCash', masked: maskLast4('09171234567') }],
  }));
  assertEquals(json.includes('••••3344'), true);
  assertEquals(json.includes('3411223344'), false); // full number never present
});

Deno.test('helpCard and linkPromptCard are valid cards', () => {
  for (const c of [helpCard(), linkPromptCard()]) {
    assertEquals('elements' in c || 'config' in c, true);
  }
});

Deno.test('reviewsCard renders the latest review + self-eval count when present', () => {
  const json = JSON.stringify(reviewsCard({
    latest: { type: 'Annual Review', status: 'Completed', outcome: 'Meets Expectations', rating: '4' },
    selfEvalCount: '3',
    latestSelfEvalDate: 'Jun 30, 2026',
  }));
  assertEquals(json.includes('Annual Review'), true);
  assertEquals(json.includes('Completed'), true);
  assertEquals(json.includes('Meets Expectations'), true);
  assertEquals(json.includes('3 self-evaluation'), true);
  assertEquals(json.includes('Jun 30, 2026'), true);
});

Deno.test('reviewsCard renders gracefully with no review and zero self-evals', () => {
  const card = reviewsCard({ selfEvalCount: '0' });
  const json = JSON.stringify(card);
  assertEquals(json.includes('Nothing here yet.'), true);
  assertEquals('elements' in card || 'config' in card, true);
});
