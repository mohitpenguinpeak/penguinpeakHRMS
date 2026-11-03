import { createClient } from 'npm:@supabase/supabase-js@2';
import { GoogleAuth } from 'npm:google-auth-library@9';

// Invoked only by the notifications INSERT webhook with a private shared secret.
Deno.serve(async (request) => {
  const secret = Deno.env.get('PUSH_WEBHOOK_SECRET');
  const suppliedSecret = request.headers.get('x-webhook-secret');
  if (!secret || suppliedSecret !== secret) {
    const code = !secret
      ? 'WEBHOOK_SECRET_NOT_CONFIGURED'
      : !suppliedSecret
      ? 'WEBHOOK_SECRET_HEADER_MISSING'
      : 'WEBHOOK_SECRET_MISMATCH';
    // Report only the failure category, never credentials or request headers.
    console.error('Webhook authentication failed', code);
    return Response.json({ error: code }, { status: 401 });
  }
  if (request.method !== 'POST') return new Response('Method not allowed', { status: 405 });
  let stage = 'payload';
  try {
    const payload = await request.json();
    if (payload.type !== 'INSERT' || payload.table !== 'notifications' || payload.schema !== 'public') {
      return new Response('Invalid event', { status: 400 });
    }
    stage = 'notification_lookup';
    const db = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
    // Re-read trusted content instead of accepting recipient/content from the webhook.
    const { data: notice, error } = await db.from('notifications').select('*').eq('id', payload.record?.id).single();
    if (error) throw error;
    const { data: recipient, error: recipientError } = await db.from('profiles')
      .select('approval_status').eq('id', notice.recipient_id).single();
    if (recipientError) throw recipientError;
    if (recipient.approval_status !== 'approved') {
      return Response.json({ sent: 0, skipped: 'RECIPIENT_NOT_APPROVED' });
    }
    stage = 'device_lookup';
    const { data: devices, error: tokenError } = await db.from('push_tokens').select('token').eq('user_id', notice.recipient_id);
    if (tokenError) throw tokenError;
    if (!devices?.length) {
      console.info('Push dispatch completed', { sent: 0, reason: 'NO_REGISTERED_DEVICES' });
      return Response.json({ sent: 0, skipped: 'NO_REGISTERED_DEVICES' });
    }
    stage = 'firebase_credentials';
    const credentials = JSON.parse(Deno.env.get('FCM_SERVICE_ACCOUNT_JSON')!);
    const auth = new GoogleAuth({ credentials, scopes: ['https://www.googleapis.com/auth/firebase.messaging'] });
    const accessToken = await auth.getAccessToken();
    stage = 'firebase_send';
    let sent = 0;
    let failed = 0;
    for (const device of devices) {
      const response = await fetch(`https://fcm.googleapis.com/v1/projects/${credentials.project_id}/messages:send`, {
        method: 'POST',
        headers: { Authorization: `Bearer ${accessToken}`, 'Content-Type': 'application/json' },
        body: JSON.stringify({ message: {
          token: device.token,
          notification: { title: notice.title, body: notice.body },
          data: { notification_id: notice.id, screen: 'leave' },
          ...(Deno.env.get('HRMS_WEB_URL') ? { webpush: { fcm_options: { link: Deno.env.get('HRMS_WEB_URL') } } } : {}),
          android: { priority: 'high', notification: { tag: notice.id, channel_id: 'leave_requests' } },
          apns: { headers: { 'apns-collapse-id': notice.id }, payload: { aps: { sound: 'default' } } },
        } }),
      });
      if (response.ok) { sent++; continue; }
      const result = await response.json();
      const unregistered = result.error?.details?.some((d: { errorCode?: string }) => d.errorCode === 'UNREGISTERED');
      if (unregistered) {
        await db.from('push_tokens').delete().eq('token', device.token);
      } else {
        failed++;
        const knownCodes = ['UNREGISTERED', 'INVALID_ARGUMENT', 'SENDER_ID_MISMATCH', 'QUOTA_EXCEEDED', 'UNAVAILABLE', 'INTERNAL', 'THIRD_PARTY_AUTH_ERROR'];
        const providerCode = result.error?.details?.map((d: { errorCode?: string }) => d.errorCode)
          .find((code: string) => knownCodes.includes(code)) || 'UNCLASSIFIED';
        console.error('FCM delivery failed', { http_status: response.status, provider_code: providerCode });
      }
    }
    console.info('Push dispatch completed', { sent, failed });
    return Response.json({ sent, failed }, { status: failed ? 502 : 200 });
  } catch (_) {
    console.error('Push dispatch failed', { stage });
    return Response.json({ error: 'PUSH_DISPATCH_FAILED', stage }, { status: 500 });
  }
});
