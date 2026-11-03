#!/usr/bin/env python3
"""Generate matching Flutter defines and a worker config from Firebase public config.

Usage: python3 scripts/configure_web_push.py firebase-web-config.json
Input: Firebase console's web config JSON plus a `vapidKey` public key.
Never pass a service-account JSON file.
"""
import json
from pathlib import Path
import sys


def generate(source: Path, root: Path) -> None:
    config = json.loads(source.read_text())
    if any(key in config for key in ('private_key', 'private_key_id', 'client_email')):
        raise ValueError('Use public WEB app configuration, never a service-account key.')
    fields = {
        'apiKey': 'FIREBASE_API_KEY',
        'appId': 'FIREBASE_APP_ID',
        'messagingSenderId': 'FIREBASE_MESSAGING_SENDER_ID',
        'projectId': 'FIREBASE_PROJECT_ID',
        'vapidKey': 'FIREBASE_VAPID_KEY',
    }
    for key in fields:
        if not isinstance(config.get(key), str) or not config[key].strip():
            raise ValueError(f'Missing public configuration field: {key}')
    public = {key: config[key] for key in fields if key != 'vapidKey'}
    (root / 'web' / 'firebase-public-config.js').write_text(
        '// Public Firebase web app configuration. Generated; do not edit.\n'
        + 'self.firebasePublicConfig = ' + json.dumps(public) + ';\n'
    )
    defines = {target: config[key] for key, target in fields.items()}
    defines['PUSH_ENABLED'] = 'true'
    (root / 'firebase.web.env.json').write_text(json.dumps(defines, indent=2) + '\n')


if __name__ == '__main__':
    if len(sys.argv) != 2:
        raise SystemExit('Usage: python3 scripts/configure_web_push.py firebase-web-config.json')
    generate(Path(sys.argv[1]), Path(__file__).resolve().parent.parent)
    print('Generated web/firebase-public-config.js and firebase.web.env.json')
