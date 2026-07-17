// Dispatch queued performance self-review requests through Lark messaging.
// Input: { "review_cycle_id": "uuid", "retry_failed": false }

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { authFromEnv, larkRequest } from '../_shared/lark.ts';

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}

function formLink(
  templateId: string,
  baseUrl: string | undefined,
  values: Record<string, string>,
): string {
  let raw: string;
  if (/^https?:\/\//i.test(templateId)) {
    raw = templateId;
  } else {
    if (!baseUrl) {
      throw new Error(
        'LARK_SELF_REVIEW_FORM_BASE_URL is required when the template ID is not a URL',
      );
    }
    const joiner = baseUrl.includes('?') ? '&' : '?';
    raw = `${baseUrl}${joiner}template_id=${encodeURIComponent(templateId)}`;
  }
  const joiner = raw.includes('?') ? '&' : '?';
  const query = Object.entries(values)
    .map(([key, value]) => `${encodeURIComponent(key)}=${encodeURIComponent(value)}`)
    .join('&');
  return `${raw}${joiner}${query}`;
}

Deno.serve(async (req) => {
  if (req.method !== 'POST') {
    return new Response('Method Not Allowed', { status: 405 });
  }
  const body = await req.json().catch(() => ({}));
  const cycleId = body.review_cycle_id as string | undefined;
  const retryFailed = body.retry_failed === true;
  if (!cycleId) return json({ error: 'review_cycle_id required' }, 400);

  const authorization = req.headers.get('Authorization');
  if (!authorization) return json({ error: 'Unauthorized' }, 401);
  const caller = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_ANON_KEY')!,
    {
      auth: { persistSession: false },
      global: { headers: { Authorization: authorization } },
    },
  );
  // review_cycles RLS grants access only to HR/admin roles in the caller's
  // company (or SUPER_ADMIN). This check happens before service-role access.
  const { data: authorizedCycle, error: authorizationError } = await caller
    .from('review_cycles')
    .select('id')
    .eq('id', cycleId)
    .maybeSingle();
  if (authorizationError || !authorizedCycle) {
    return json({ error: 'Forbidden' }, 403);
  }

  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    { auth: { persistSession: false } },
  );
  const auth = authFromEnv();
  const baseUrl = Deno.env.get('LARK_SELF_REVIEW_FORM_BASE_URL');
  const statuses = retryFailed ? ['PENDING', 'FAILED'] : ['PENDING'];
  const { data, error } = await supabase
    .from('self_review_requests')
    .select('*')
    .eq('review_cycle_id', cycleId)
    .in('status', statuses);
  if (error) return json({ error: error.message }, 500);

  let sent = 0;
  let failed = 0;
  const errors: Array<{ requestId: string; error: string }> = [];

  for (const request of data ?? []) {
    const { data: review, error: reviewError } = await supabase
      .from('employee_reviews')
      .select('*')
      .eq('id', request.review_id)
      .single();
    const { data: employee, error: employeeError } = await supabase
      .from('employees')
      .select('id, lark_user_id')
      .eq('id', request.employee_id)
      .single();
    const { data: card, error: cardError } = review
      ? await supabase
        .from('role_scorecards')
        .select('job_title')
        .eq('id', review.responsibility_card_id)
        .single()
      : { data: null, error: null };

    try {
      if (reviewError) throw reviewError;
      if (employeeError) throw employeeError;
      if (cardError) throw cardError;
      if (!employee?.lark_user_id) {
        throw new Error('Employee has no Lark user ID');
      }

      const link = formLink(request.form_template_id, baseUrl, {
        review_id: review.id,
        review_cycle_id: review.review_cycle_id,
        employee_id: review.employee_id,
        employee_name: review.employee_name_snapshot,
        role_id: review.responsibility_card_id,
        role_name: card?.job_title ?? '',
        manager_id: review.direct_manager_id,
        review_period:
          `${review.review_period_start} to ${review.review_period_end}`,
        form_version: String(request.form_version),
        submission_token: request.submission_token,
      });

      const cardContent = {
        config: { wide_screen_mode: true },
        header: {
          template: 'purple',
          title: { tag: 'plain_text', content: 'Performance self-review' },
        },
        elements: [
          {
            tag: 'markdown',
            content:
              `**${review.employee_name_snapshot}**\n` +
              `Review period: ${review.review_period_start} to ${review.review_period_end}\n` +
              'Please reflect on your accomplishments, challenges, learning, and support needs.',
          },
          {
            tag: 'action',
            actions: [
              {
                tag: 'button',
                text: { tag: 'plain_text', content: 'Open self-review' },
                type: 'primary',
                url: link,
              },
            ],
          },
        ],
      };

      const response = await larkRequest<{ message_id: string }>(
        auth,
        '/im/v1/messages?receive_id_type=user_id',
        {
          method: 'POST',
          body: JSON.stringify({
            receive_id: employee.lark_user_id,
            msg_type: 'interactive',
            content: JSON.stringify(cardContent),
            uuid: request.id,
          }),
        },
      );

      await supabase.from('self_review_requests').update({
        status: 'SENT',
        form_link: link,
        lark_message_id: response.message_id,
        sent_at: new Date().toISOString(),
        last_attempt_at: new Date().toISOString(),
        attempt_count: request.attempt_count + 1,
        error_message: null,
      }).eq('id', request.id);
      sent++;
    } catch (caught) {
      const message = caught instanceof Error ? caught.message : String(caught);
      await supabase.from('self_review_requests').update({
        status: 'FAILED',
        last_attempt_at: new Date().toISOString(),
        attempt_count: request.attempt_count + 1,
        error_message: message,
      }).eq('id', request.id);
      failed++;
      errors.push({ requestId: request.id, error: message });
    }
  }

  return json({ ok: failed === 0, sent, failed, errors });
});
