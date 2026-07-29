import { assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { larkMsToISO, mapSelfEvalRecord } from './self_eval_map.ts';

const SUBMIT_MS = Date.UTC(2026, 0, 15, 3, 30, 0); // a real instant

Deno.test('separates meta fields from the variable Q&A', () => {
  const m = mapSelfEvalRecord({
    'Respondents': [{ id: 'u-77', name: 'Ana' }],
    'Submitted on': SUBMIT_MS,
    'What challenges have you faced?': 'Onboarding tools',
    'Do you feel you have done a good job in your first month?': 4,
  });
  assertEquals(m.respondentLarkUserId, 'u-77');
  assertEquals(m.submittedAt, '2026-01-15T03:30:00.000Z');
  // meta fields never leak into answers
  assertEquals(m.answers['Respondents'], undefined);
  assertEquals(m.answers['Submitted on'], undefined);
  assertEquals(m.answers['What challenges have you faced?'], 'Onboarding tools');
});

Deno.test('numeric questions land in ratings and (stringified) in answers', () => {
  const m = mapSelfEvalRecord({
    'How would you rate the support?': 5,
    'Comfort level': 3,
    'Free text': 'ok',
  });
  assertEquals(m.ratings, { 'How would you rate the support?': 5, 'Comfort level': 3 });
  assertEquals(m.answers['How would you rate the support?'], '5');
  assertEquals(m.answers['Free text'], 'ok');
});

Deno.test('a missing/empty respondent yields a null match key', () => {
  assertEquals(mapSelfEvalRecord({ 'Submitted on': SUBMIT_MS }).respondentLarkUserId, null);
  assertEquals(mapSelfEvalRecord({ 'Respondents': [] }).respondentLarkUserId, null);
});

Deno.test('blank text answers are omitted', () => {
  const m = mapSelfEvalRecord({
    'Respondents': { id: 'u-1' },
    'Q1': '',
    'Q2': [{ text: '   ' }],
    'Q3': 'real',
  });
  assertEquals(m.answers['Q1'], undefined);
  assertEquals(m.answers['Q2'], undefined);
  assertEquals(m.answers['Q3'], 'real');
});

Deno.test('larkMsToISO handles ms, ms-as-string, and junk', () => {
  assertEquals(larkMsToISO(SUBMIT_MS), '2026-01-15T03:30:00.000Z');
  assertEquals(larkMsToISO(String(SUBMIT_MS)), '2026-01-15T03:30:00.000Z');
  assertEquals(larkMsToISO(0), null);
  assertEquals(larkMsToISO(''), null);
  assertEquals(larkMsToISO(null), null);
});

Deno.test('rich-text array answers are flattened to text', () => {
  const m = mapSelfEvalRecord({
    'Respondents': { id: 'u-2' },
    'Comment': [{ text: 'Great ', type: 'text' }, { text: 'experience', type: 'text' }],
  });
  assertEquals(m.answers['Comment'], 'Great experience');
});
