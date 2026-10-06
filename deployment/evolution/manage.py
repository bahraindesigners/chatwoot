#!/usr/bin/env python3
"""Provision internal Baileys inboxes using Evolution's native Chatwoot integration."""

import argparse
import base64
import getpass
import json
import os
from pathlib import Path
import re
import sys
from urllib.error import HTTPError, URLError
from urllib.parse import quote, urlparse
from urllib.request import Request, urlopen


def request(api_url, key, method, path, body=None):
    payload = json.dumps(body).encode() if body is not None else None
    req = Request(
        api_url.rstrip('/') + path,
        data=payload,
        method=method,
        headers={'apikey': key, 'Content-Type': 'application/json'},
    )
    try:
        with urlopen(req, timeout=30) as response:
            return json.load(response)
    except HTTPError as error:
        # Upstream responses can echo the Chatwoot token. Do not print response bodies.
        raise RuntimeError(f'{method} {path} failed: HTTP {error.code}') from None
    except URLError as error:
        raise RuntimeError(f'Cannot reach Evolution: {error.reason}') from None


def http_url(value):
    parsed = urlparse(value)
    if parsed.scheme not in ('http', 'https') or not parsed.hostname or parsed.username or parsed.password:
        raise argparse.ArgumentTypeError('Use an HTTP(S) URL without embedded credentials')
    return value.rstrip('/')


def instance_name(value):
    if not re.fullmatch(r'[a-z0-9][a-z0-9_-]{2,79}', value):
        raise argparse.ArgumentTypeError('Use 3–80 lowercase letters, digits, underscores or hyphens')
    return value


def list_inboxes(chatwoot_url, account_id, token):
    req = Request(
        f'{chatwoot_url}/api/v1/accounts/{account_id}/inboxes',
        headers={'api_access_token': token},
    )
    try:
        with urlopen(req, timeout=30) as response:
            return json.load(response)['payload']
    except (HTTPError, URLError, KeyError, ValueError):
        raise RuntimeError('Cannot list Chatwoot inboxes; check URL, account and token') from None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--api-url', type=http_url, default='http://127.0.0.1:8081')
    commands = parser.add_subparsers(dest='action', required=True)
    create = commands.add_parser('create', help='Create a Baileys instance and a new Chatwoot API inbox')
    create.add_argument('instance', type=instance_name)
    create.add_argument('--chatwoot-url', type=http_url, required=True)
    create.add_argument('--account-id', type=int, required=True)
    create.add_argument('--inbox-name', required=True)
    create.add_argument('--dry-run', action='store_true')
    for action in ('status', 'qr'):
        command = commands.add_parser(action)
        command.add_argument('instance', type=instance_name)
        if action == 'qr':
            command.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    name = quote(args.instance, safe='')

    if args.action == 'create':
        if args.account_id < 1 or not args.inbox_name.strip():
            parser.error('Account ID must be positive and inbox name must not be empty')
        instance = {
            'instanceName': args.instance,
            'integration': 'WHATSAPP-BAILEYS',
            'qrcode': False,
            'groupsIgnore': True,
            'alwaysOnline': False,
            'readMessages': False,
            'readStatus': False,
            'syncFullHistory': False,
        }
        chatwoot = {
            'enabled': True,
            'accountId': str(args.account_id),
            'url': args.chatwoot_url,
            'token': '[REDACTED]',
            'nameInbox': args.inbox_name,
            'signMsg': False,
            'reopenConversation': True,
            'conversationPending': False,
            'importContacts': False,
            'importMessages': False,
            'autoCreate': True,
        }
        if args.dry_run:
            print(json.dumps({'POST /instance/create': instance, f'POST /chatwoot/set/{name}': chatwoot}, indent=2))
            return

    key = os.environ.get('EVOLUTION_API_KEY') or getpass.getpass('Evolution API key: ')
    if not key:
        parser.error('Evolution API key is required')
    if args.action == 'create':
        token = os.environ.get('CHATWOOT_API_TOKEN') or getpass.getpass('Chatwoot access token: ')
        if not token:
            parser.error('Chatwoot access token is required')
        # Refuse an existing inbox name: Evolution otherwise reuses it without checking channel type.
        inboxes = list_inboxes(args.chatwoot_url, args.account_id, token)
        if any(inbox['name'] == args.inbox_name for inbox in inboxes):
            raise RuntimeError('Inbox name already exists. Choose a new name; no changes were made.')
        request(args.api_url, key, 'POST', '/instance/create', instance)
        print(f'Created Evolution instance {args.instance}.')
        chatwoot['token'] = token
        request(args.api_url, key, 'POST', f'/chatwoot/set/{name}', chatwoot)
        # Evolution may return configuration even when its inbox creation failed.
        inboxes = list_inboxes(args.chatwoot_url, args.account_id, token)
        inbox = next((item for item in inboxes if item['name'] == args.inbox_name), None)
        if not inbox or inbox.get('channel_type') != 'Channel::Api' or not (
            inbox.get('webhook_url') or ''
        ).endswith(f'/chatwoot/webhook/{name}'):
            raise RuntimeError('Evolution was configured, but its API inbox/webhook was not verified. Inspect both services before retrying.')
        print(f'Configured Chatwoot API inbox {args.inbox_name}. Assign its agents in Chatwoot, then run qr.')
    elif args.action == 'status':
        result = request(args.api_url, key, 'GET', f'/instance/connectionState/{name}')
        print(json.dumps(result.get('instance', {}), indent=2))
    else:
        result = request(args.api_url, key, 'GET', f'/instance/connect/{name}')
        qr = result.get('base64')
        if not qr:
            raise RuntimeError('No QR returned. Check status; the instance may already be connected. Retry qr if still connecting.')
        image = base64.b64decode(qr.split(',')[-1], validate=True)
        # A pairing QR grants device access. Create a private file and never overwrite existing files.
        descriptor = os.open(args.output, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(descriptor, 'wb') as output:
            output.write(image)
        print(f'QR saved to {args.output}. Pair from WhatsApp → Linked devices, then remove the QR file.')


if __name__ == '__main__':
    try:
        main()
    except (RuntimeError, ValueError, OSError) as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
