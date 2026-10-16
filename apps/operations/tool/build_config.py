"""Read only public Flutter compile-time settings; legacy secrets stay local/server-only."""
from pathlib import Path
from urllib.parse import urlparse

PUBLIC_KEYS = frozenset({'VYNIC_ENV', 'VYNIC_API_URL'})


def public_build_config(path):
    path = Path(path)
    if not path.exists():
        return {}
    values = {}
    for line in path.read_text().splitlines():
        key, separator, raw = line.strip().removeprefix('export ').partition('=')
        key = key.strip()
        if not separator or key not in PUBLIC_KEYS:
            continue
        value = raw.strip()
        if value[:1] in ('"', "'") and value[-1:] == value[:1]:
            value = value[1:-1]
        else:
            value = value.split(' #', 1)[0].strip()
        if value:
            values[key] = value
    if values.get('VYNIC_ENV', 'development') not in ('development', 'staging', 'production'):
        raise ValueError('VYNIC_ENV must be development, staging or production')
    if values.get('VYNIC_API_URL'):
        validate_public_origin(values['VYNIC_API_URL'])
    return values


def validate_public_origin(value):
    uri = urlparse(value)
    if uri.scheme not in ('http', 'https') or not uri.hostname or uri.username or uri.password or uri.query or uri.fragment or uri.path not in ('', '/'):
        raise ValueError('VYNIC_API_URL must be a plain http(s) origin')
    try:
        port = uri.port
    except ValueError:
        raise ValueError('VYNIC_API_URL has an invalid port') from None
    if port is not None and not 0 < port <= 65535:
        raise ValueError('VYNIC_API_URL has an invalid port')
    return value.rstrip('/')
