#!/usr/bin/env python3
"""Create a new local environment with independent secrets; never overwrite."""
from pathlib import Path
import os
import secrets

root = Path(__file__).resolve().parent.parent
text = (root / '.env.docker.example').read_text()
secret_keys = {'POSTGRES_PASSWORD', 'JWT_SECRET', 'JWT_REFRESH_SECRET',
               'COOKIE_ENCRYPTION_KEY', 'PLATFORM_JWT_SECRET', 'PAYMENT_INTEGRATION_MASTER_KEY'}
text = '\n'.join(
    line.split('=', 1)[0] + '=' + secrets.token_hex(32)
    if line.split('=', 1)[0] in secret_keys else line
    for line in text.splitlines()
) + '\n'
path = root / '.env.docker'
fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
with os.fdopen(fd, 'w') as stream:
    stream.write(text)
print('Created .env.docker (mode 0600). Existing app environments were not read.')
