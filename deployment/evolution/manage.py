#!/usr/bin/env python3
"""Manage Evolution inboxes through Chatwoot's account-scoped integration API."""

import argparse
import base64
import getpass
import json
import os
from pathlib import Path
import sys
from urllib.error import HTTPError, URLError
from urllib.parse import urlparse
from urllib.request import HTTPRedirectHandler, Request, build_opener


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def http_url(value):
    parsed = urlparse(value)
    if parsed.scheme not in ('http', 'https') or not parsed.hostname or parsed.username or parsed.password:
        raise argparse.ArgumentTypeError('Use an HTTP(S) URL without embedded credentials')
    return value.rstrip('/')


def positive_id(value):
    number = int(value)
    if number < 1:
        raise argparse.ArgumentTypeError('ID must be positive')
    return number


def request(args, token, method, path, body=None):
    payload = json.dumps(body).encode() if body is not None else None
    req = Request(
        f'{args.chatwoot_url}/api/v1/accounts/{args.account_id}/evolution{path}',
        data=payload,
        method=method,
        headers={'api_access_token': token, 'Content-Type': 'application/json'},
    )
    try:
        with build_opener(NoRedirect()).open(req, timeout=90) as response:
            return json.load(response)
    except HTTPError as error:
        raise RuntimeError(f'Chatwoot request failed: HTTP {error.code}. Check the account, token and Evolution configuration.') from None
    except URLError:
        raise RuntimeError('Cannot reach Chatwoot; check the URL and connection') from None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--chatwoot-url', type=http_url, required=True)
    parser.add_argument('--account-id', type=positive_id, required=True)
    commands = parser.add_subparsers(dest='action', required=True)
    create = commands.add_parser('create', help='Create a managed Evolution inbox')
    create.add_argument('--inbox-name', required=True)
    create.add_argument('--dry-run', action='store_true')
    for action in ('status', 'qr'):
        command = commands.add_parser(action)
        command.add_argument('inbox_id', type=positive_id)
        if action == 'qr':
            command.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if args.action == 'create':
        if not args.inbox_name.strip() or len(args.inbox_name) > 100:
            parser.error('Inbox name must contain between 1 and 100 characters')
        if args.dry_run:
            print(json.dumps({'method': 'POST', 'url': f'{args.chatwoot_url}/api/v1/accounts/{args.account_id}/evolution',
                              'body': {'name': args.inbox_name.strip()}}, indent=2))
            return

    token = os.environ.get('CHATWOOT_API_TOKEN') or getpass.getpass('Chatwoot administrator access token: ')
    if not token:
        parser.error('Chatwoot access token is required')
    if args.action == 'create':
        inbox = request(args, token, 'POST', '', {'name': args.inbox_name.strip()})
        print(f'Created managed Evolution inbox {inbox["id"]}. Assign its agents, then run qr with this inbox ID.')
    elif args.action == 'status':
        result = request(args, token, 'GET', f'/{args.inbox_id}/status')
        print(json.dumps({'state': result['state'], 'reauthorization_required': result['reauthorization_required']}, indent=2))
    else:
        result = request(args, token, 'POST', f'/{args.inbox_id}/qr')
        if result['state'] == 'open':
            print('WhatsApp is connected; Chatwoot authorization has been renewed.')
            return
        qr = result['qr']
        if not qr:
            raise RuntimeError('QR is not ready. Wait a moment, then run qr again.')
        if not qr.startswith('data:image/png;base64,'):
            raise RuntimeError('Provider returned an invalid pairing QR')
        image = base64.b64decode(qr.split(',', 1)[1], validate=True)
        descriptor = os.open(args.output, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(descriptor, 'wb') as output:
            output.write(image)
        print(f'QR saved to {args.output}. Pair from WhatsApp → Linked devices, then remove the QR file.')


if __name__ == '__main__':
    try:
        main()
    except (RuntimeError, ValueError, OSError, KeyError) as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
