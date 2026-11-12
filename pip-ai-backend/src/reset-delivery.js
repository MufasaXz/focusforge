/** The private cron only wakes a bounded server-side queue; no mail or user data lives here. */
export async function drainResetEmails(env, fetchImpl = fetch, now = Date.now()) {
  if (!env.RESET_DELIVERY_SIGNING_KEY) throw new Error('reset scheduler not configured');
  const bytes = Uint8Array.from(atob(env.RESET_DELIVERY_SIGNING_KEY), char => char.charCodeAt(0));
  const key = await crypto.subtle.importKey('pkcs8', bytes, {name: 'Ed25519'}, false, ['sign']);
  const timestamp = String(now);
  const signature = new Uint8Array(await crypto.subtle.sign('Ed25519', key,
    new TextEncoder().encode('reset-delivery:' + timestamp)));
  const encoded = btoa(String.fromCharCode(...signature)).replaceAll('+', '-').replaceAll('/', '_').replace(/=+$/, '');
  const response = await fetchImpl('https://www.focus-forge.in/api/reset-delivery', {
    method: 'POST', redirect: 'error',
    headers: {authorization: `ResetWorker ${timestamp}.${encoded}`},
    signal: AbortSignal.timeout(55000),
  });
  if (!response.ok) throw new Error('reset scheduler request failed');
  const result = await response.json();
  if (result.retry) console.warn(JSON.stringify({event: 'reset_delivery_retry', count: result.retry}));
}
