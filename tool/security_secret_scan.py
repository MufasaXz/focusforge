#!/usr/bin/env python3
"""Scan tracked/unignored files and reachable/reflog Git blobs/messages.

Reports locations and SHA-256 fingerprints, never credential values. This is a
pattern scan, not proof that no unknown credential format can be present.
Ignored local signing/config files are inventoried by filename/mode only.
"""
import argparse
import hashlib
import json
import re
import stat
import subprocess
from pathlib import Path

PATTERNS = {
    'private_key': re.compile(rb'-----BEGIN (?:RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----'),
    'provider_token': re.compile(rb'\b(?:gsk_[A-Za-z0-9]{30,}|gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{40,}|sk-(?:proj-)?[A-Za-z0-9_-]{32,}|AKIA[A-Z0-9]{16})\b'),
    'google_api_key': re.compile(rb'AIza[A-Za-z0-9_-]{35}'),
    'credential_literal': re.compile(rb'''(?i)(?:gemini_api_key|groq_api_key|smtp_pass|storePassword|keyPassword|client_secret|access_token|refresh_token)\s*["']?\s*[:=]\s*["']([^"'\r\n]{8,})["']'''),
    'service_account': re.compile(rb'"type"\s*:\s*"service_account"'),
}
KEY_FILE = re.compile(r'(?i)(?:\.(?:jks|keystore|p12|pfx|pem)$|(?:^|/)key\.properties$)')


def git(repo, *args):
    return subprocess.check_output(['git', '-C', str(repo), *args])


def scan(repo):
    candidates = []
    public = 0
    blobs = 0
    seen = set()

    def inspect(data, location, revision):
        nonlocal public
        for kind, pattern in PATTERNS.items():
            for match in pattern.finditer(data):
                value = match[1] if match.lastindex else match[0]
                fingerprint = hashlib.sha256(value).hexdigest()[:16]
                marker = (location, kind, fingerprint)
                if marker in seen:
                    continue
                seen.add(marker)
                if kind == 'google_api_key' and ('firebase' in location.lower() or b'firebaseapp.com' in data or b'google_app_id' in data or b'project_info' in data):
                    public += 1  # Firebase client config is public, not an Admin/provider secret.
                    continue
                fixture = ('test' in location.lower() and (
                    value.startswith((b'test-', b'fixture', b'not-a-real')) or
                    value in (b'gemini-secret', b'groq-secret')
                ))
                candidates.append({'path': location, 'revision': revision,
                    'line': data.count(b'\n', 0, match.start()) + 1,
                    'kind': kind, 'fingerprint': fingerprint,
                    'review': 'non-production fixture' if fixture else 'REVIEW REQUIRED'})

    objects = git(repo, 'rev-list', '--objects', '--all', '--reflog').splitlines()
    process = subprocess.Popen(['git', '-C', str(repo), 'cat-file', '--batch'], stdin=subprocess.PIPE, stdout=subprocess.PIPE)
    names = []
    for row in objects:
        sha, _, name = row.partition(b' ')
        location = name.decode('utf8', errors='replace')
        if KEY_FILE.search(location):
            names.append(location)
        process.stdin.write(sha + b'\n')
        process.stdin.flush()
        header = process.stdout.readline().split()
        if len(header) != 3:
            continue
        size = int(header[2])
        data = process.stdout.read(size)
        process.stdout.read(1)
        if header[1] in (b'blob', b'commit'):
            blobs += header[1] == b'blob'
            if b'\x00' not in data:
                inspect(data, location or '(commit message)', sha.decode())
    process.stdin.close()
    process.wait()
    for raw in git(repo, 'ls-files', '-z', '--cached', '--others', '--exclude-standard').split(b'\0'):
        if not raw:
            continue
        location = raw.decode('utf8')
        p = repo / location
        if p.is_file():
            data = p.read_bytes()
            if b'\x00' not in data:
                inspect(data, location, 'working tree')
    ignored = []
    for location in ('android/key.properties', 'android/app/google-services.json', '.env', '.dev.vars', 'pip-ai-backend/.dev.vars'):
        p = repo / location
        if p.is_file():
            result = subprocess.run(['git', '-C', str(repo), 'check-ignore', '-q', location], check=False)
            ignored.append({'path': location, 'ignored': result.returncode == 0,
                'mode': oct(stat.S_IMODE(p.stat().st_mode))})
    return {'repo': str(repo), 'gitBlobs': blobs, 'publicFirebaseConfigKeys': public,
        'historicalKeyFilePaths': sorted(set(names)), 'candidates': candidates,
        'localConfigMetadata': ignored}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('repos', nargs='+', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    results = [scan(p.resolve()) for p in args.repos]
    args.output.write_text(json.dumps(results, indent=2) + '\n')
    print(json.dumps([{'repo': r['repo'], 'gitBlobs': r['gitBlobs'],
        'reviewRequired': sum(c['review'] == 'REVIEW REQUIRED' for c in r['candidates']),
        'historicalKeyFilePaths': r['historicalKeyFilePaths']} for r in results]))
