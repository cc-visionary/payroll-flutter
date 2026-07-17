// Receives normalized responses from the universal Lark self-review form.
// Configure the form automation to POST the hidden identifiers and answers here.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}

function text(value: unknown): string | null {
  if (typeof value !== 'string') return null;
  const trimmed = value.trim();
  return trimmed.length === 0 ? null : trimmed;
}

Deno.serve(async (req) => {
  if (req.method !== 'POST') return json({ error: 'Method Not Allowed' }, 405);
  const body = await req.json().catch(() => null);
  if (!body || typeof body !== 'object') return json({ error: 'Invalid JSON' }, 400);

  // Lark uses this handshake when registering some webhook endpoints. Gate it on
  // the declared type so a real submission that happens to carry a `challenge`
  // field is not swallowed by the echo.
  if (body.type === 'url_verification' && typeof body.challenge === 'string') {
    return json({ challenge: body.challenge });
  }

  // Deployed with verify_jwt = false (see supabase/config.toml) so Lark can reach
  // it, which makes this shared token the only thing standing in front of a
  // service-role RPC. It must fail closed: an unset secret is a misconfiguration,
  // never a reason to skip the check.
  const webhookToken = Deno.env.get('LARK_PERFORMANCE_FORM_WEBHOOK_TOKEN');
  if (!webhookToken) {
    return json({ error: 'LARK_PERFORMANCE_FORM_WEBHOOK_TOKEN is not configured' }, 500);
  }
  const received = req.headers.get('x-performance-webhook-token') ?? body.webhook_token;
  if (received !== webhookToken) return json({ error: 'Unauthorized' }, 401);

  const reviewId = text(body.review_id);
  const employeeId = text(body.employee_id);
  const submissionToken = text(body.submission_token);
  const formVersion = Number(body.form_version);
  if (!reviewId || !employeeId || !submissionToken || !Number.isInteger(formVersion)) {
    return json({
      error: 'review_id, employee_id, form_version, and submission_token are required',
    }, 400);
  }

  const attachments = Array.isArray(body.attachments) ? body.attachments : [];
  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    { auth: { persistSession: false } },
  );
  const { data, error } = await supabase.rpc('ingest_self_review_submission', {
    p_review_id: reviewId,
    p_employee_id: employeeId,
    p_form_version: formVersion,
    p_submission_token: submissionToken,
    p_external_submission_id: text(body.external_submission_id),
    p_accomplishments: text(body.accomplishments),
    p_challenges: text(body.challenges),
    p_learnings: text(body.learnings),
    p_desired_development_area: text(body.desired_development_area),
    p_support_needed: text(body.support_needed),
    p_additional_comments: text(body.additional_comments),
    p_attachments: attachments,
  });
  if (error) {
    const validationError = /not found|does not match|invalid|cancelled/i.test(error.message);
    return json({ error: error.message }, validationError ? 400 : 500);
  }
  return json({ ok: true, submission_id: data });
});
