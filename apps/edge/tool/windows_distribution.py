"""Validate public Setup trust configuration before a release build; no network I/O."""
import argparse
import base64
from datetime import datetime, timedelta, timezone
import ipaddress
import json
from pathlib import Path
import re
from urllib.parse import urlsplit


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError('Duplicate distribution JSON field: ' + key)
        result[key] = value
    return result


def validate(raw, *, production=False, now=None):
    now = now or datetime.now(timezone.utc)
    config = json.loads(raw, object_pairs_hook=unique_object)
    if not isinstance(config, dict) or set(config) != {'bootstrapURL', 'channel', 'keys'}:
        raise ValueError('Distribution contains only bootstrapURL, channel and public keys')
    endpoint = config['bootstrapURL']
    if not isinstance(endpoint, str) or any(c.isspace() or ord(c) < 32 for c in endpoint):
        raise ValueError('Bootstrap endpoint must be an HTTPS URL')
    url = urlsplit(endpoint)
    if (url.scheme != 'https' or not url.hostname or url.username is not None
            or url.password is not None or url.fragment or url.query or '\\' in endpoint):
        raise ValueError('Bootstrap endpoint requires HTTPS without credentials, query or fragment')
    # Accessing port also rejects malformed ports before invoking the compiler.
    port = url.port
    channel = config['channel']
    if not isinstance(channel, str) or not re.fullmatch(r'[a-z][a-z0-9-]{0,63}', channel):
        raise ValueError('Invalid distribution channel')
    if production:
        if channel not in {'stable', 'beta'}:
            raise ValueError('Production channel must be stable or beta; never ship the LAN lab feed')
        host = url.hostname.lower().rstrip('.')
        try:
            ipaddress.ip_address(host)
        except ValueError:
            pass
        else:
            raise ValueError('Production bootstrap requires a public DNS name, not an IP address')
        if (port not in (None, 443) or '.' not in host or re.fullmatch(r'[0-9.]+', host)
                or any(host == label or host.endswith('.' + label) for label in
                       ('localhost', 'local', 'internal', 'lan', 'home.arpa', 'invalid', 'test', 'example',
                        'example.com', 'example.net', 'example.org'))
                or not all(re.fullmatch(r'[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?', part)
                           for part in host.split('.'))):
            raise ValueError('Production bootstrap requires a public HTTPS DNS endpoint on port 443')
    keys = config['keys']
    if not isinstance(keys, dict) or not keys:
        raise ValueError('Supply existing, approved public Ed25519 trust keys; no keys are generated')
    expiries = []
    for key_id, key in keys.items():
        if (not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._-]{0,127}', key_id)
                or not isinstance(key, dict) or set(key) != {'public', 'expires'}):
            raise ValueError('Trust entries contain only public and expires; never include private keys')
        try:
            public = base64.b64decode(key['public'], validate=True)
        except (ValueError, TypeError):
            raise ValueError('Ed25519 public key must be base64') from None
        if len(public) != 32 or public == bytes(32):
            raise ValueError('Ed25519 public key must be 32 bytes, not a zero placeholder')
        expiry = key['expires']
        if not isinstance(expiry, str) or not re.fullmatch(
                r'\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})', expiry):
            raise ValueError('Trusted key expires must be RFC3339 with a timezone')
        try:
            expires = datetime.fromisoformat(expiry.replace('Z', '+00:00'))
        except ValueError:
            raise ValueError('Invalid trusted key expiry') from None
        if expires <= now:
            raise ValueError('Expired trusted key: ' + key_id)
        expiries.append(expires)
    if production and max(expiries) <= now + timedelta(days=31):
        raise ValueError('At least one production trust key must cover the next 31 days; plan explicit rotation')
    return config


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--distribution', required=True, type=Path)
    parser.add_argument('--production', action='store_true')
    args = parser.parse_args()
    try:
        validate(args.distribution.read_bytes(), production=args.production)
    except (OSError, ValueError) as error:
        parser.error(str(error))
    print('Public distribution configuration valid; endpoint availability, manifest signatures '
          'and Windows publisher trust have not been verified.')


if __name__ == '__main__':
    main()
