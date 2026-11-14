import {test} from 'node:test';
import assert from 'node:assert/strict';
import {redactText} from '../src/privacy.js';
import {buildGeminiRequest, parseRequest, readGeminiReply} from '../src/pip.js';

test('common identifiers, hidden separators and identifying links are redacted before capping', () => {
  for (const value of [
    'student@example.com', 'student@exam\u200bple.com', 'com.instagram.android',
    '+91 (98765) 43210', '192.168.1.10', '123456789012345',
    'aabbccdd11223344', '12345678-1234-1234-1234-123456789012',
    'device_id: installation-12345', 'https://school.example/student/name?token=private',
  ]) assert.equal(redactText(value, 900), '[redacted]', value);
  const boundary = redactText('z'.repeat(295) + ' student@example.com', 300);
  assert.equal(boundary.length, 300);
  assert.ok(!boundary.includes('student'));
  assert.equal(redactText('Study 25 minutes, rest 5 minutes.', 900), 'Study 25 minutes, rest 5 minutes.');
  assert.equal(redactText(null, 300), '');
});

test('Gemini explicitly blocks all supported configurable text categories at low threshold', () => {
  const request = buildGeminiRequest(parseRequest({message: 'help me plan revision'}));
  assert.equal(request.safetySettings.length, 4);
  assert.ok(request.safetySettings.every(s => s.threshold === 'BLOCK_LOW_AND_ABOVE'));
  assert.deepEqual(readGeminiReply({candidates: [{finishReason: 'STOP', safetyRatings: [{blocked: true}],
    content: {parts: [{text: 'withheld'}]}}]}), {blocked: true});
});
