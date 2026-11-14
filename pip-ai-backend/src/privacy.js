// Defence in depth for old/modified clients. Free text cannot be guaranteed
// anonymous: unknown names, addresses and obfuscated identifiers can remain.
export function redactText(value, max) {
  if (typeof value !== 'string') return '';
  let text = value.slice(0, 16384).normalize('NFKC')
    .replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F\u200B-\u200F\u202A-\u202E\u2060\uFEFF]/g, '');
  for (const pattern of [
    /(?:https?:\/\/|www\.)[^\s<>]+/gi,
    /[a-z0-9.!#$%&'*+\/=?^_`{|}~-]+@[a-z0-9-]+(?:\.[a-z0-9-]+)+/gi,
    /\b(?:[a-z][a-z0-9_]*\.){2,}[a-z][a-z0-9_]*\b/gi,
    /\b(?:\d{1,3}\.){3}\d{1,3}\b/g,
    /\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b/gi,
    /\b[0-9a-f]{16,}\b/gi,
    /\b(?:imei|imsi|ssaid|android[_ -]?id|aaid|idfa|device[_ -]?id)\s*[:=]?\s*[a-z0-9_-]{6,}\b/gi,
  ]) text = text.replace(pattern, '[redacted]');
  text = text.replace(/\+?\d[\d\s().-]{6,}\d/g, match =>
    (match.match(/\d/g) ?? []).length >= 8 ? '[redacted]' : match);
  return text.replace(/\r\n?/g, '\n').replace(/\n{3,}/g, '\n\n').trim().slice(0, max);
}
