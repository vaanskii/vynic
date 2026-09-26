#!/usr/bin/env python3
"""HTTP acceptance for the explicit local samples; no external DB or credentials."""
import http.client
import json
import re
import uuid


def request(host, path='/', method='GET', data=None, headers=None):
    connection = http.client.HTTPConnection('127.0.0.1', 80, timeout=15)
    h = {'Host': host, **(headers or {})}
    if data is not None:
        h['Content-Type'] = 'application/json'
    connection.request(method, path, json.dumps(data) if data is not None else None, h)
    response = connection.getresponse()
    body = response.read()
    result = response.status, dict(response.getheaders()), body
    cookies = response.headers.get_all('Set-Cookie', [])
    connection.close()
    return (*result, cookies)


def check(value, label):
    assert value, label
    print('PASS', label)


html = {}
for host in ['vynic.localhost', 'admin.vynic.localhost', 'tabla.vynic.localhost', 'vankisi.vynic.localhost']:
    status, headers, body, _ = request(host)
    check(status == 200 and b'text/html' in headers.get('Content-Type', '').encode(), host)
    html[host] = body
    for asset in re.findall(rb'(?:src|href)="(/assets/[^"]+)"', body):
        check(request(host, asset.decode())[0] == 200, host + ' asset ' + asset.decode())
    check(request(host, '/en/menu')[0] == 200, host + ' nested history')
check(html['tabla.vynic.localhost'] != html['vankisi.vynic.localhost'], 'CUSTOM overrides wildcard renderer')
for slug, name, other, hour in [('tabla', 'Tabla', 'Vankisi', '10:00'), ('vankisi', 'Vankisi', 'Tabla', '12:00')]:
    host = slug + '.vynic.localhost'
    status, _, body, _ = request(host, '/api/website/venue', headers={'Origin': 'http://' + host})
    site = json.loads(body)
    check(status == 200 and site['profile']['name'] == name, name + ' Host tenancy / same-origin API')
    check(hour.encode() in body, name + ' shared hours')
    for path in ['/api/menu', '/api/website/venue/menu']:
        status, _, body, _ = request(host, path)
        check(status == 200 and name.encode() in body and other.encode() not in body, name + ' isolated menu ' + path)
    status, _, body, _ = request(host, '/api/website/venue', headers={'X-Forwarded-Host': other.lower() + '.vynic.localhost'})
    check(status == 200 and json.loads(body)['profile']['name'] == name, name + ' forwarded Host spoof refused')
    status, headers, _, _ = request(host, '/api/website/venue', headers={'Origin': 'https://evil.invalid'})
    check(status >= 400 and 'Access-Control-Allow-Origin' not in headers, name + ' cross-origin refusal')
    status, _, body, cookies = request(host, '/api/auth/csrf')
    csrf = json.loads(body)['csrfToken']
    cookie = '; '.join(c.split(';')[0] for c in cookies)
    identity = uuid.uuid4().hex[:12]
    status, _, body, cookies = request(host, '/api/auth/signup', 'POST', {
        'phone': '+995' + str(int(identity, 16)), 'email': identity + '@docker.invalid',
        'password': uuid.uuid4().hex, 'firstName': 'Docker proof',
    }, {'Cookie': cookie, 'X-CSRF-Token': csrf, 'Origin': 'http://' + host})
    check(status == 201, name + ' WebsiteUser signup')
    check(len(cookies) == 2 and all('HttpOnly' in c and 'SameSite=Strict' in c and 'Domain=' not in c and 'Secure' not in c for c in cookies), name + ' local host-only auth cookie attributes')
    auth = '; '.join(c.split(';')[0] for c in cookies)
    status, _, body, _ = request(host, '/api/auth/verify', headers={'Cookie': auth})
    check(status == 200 and json.loads(body)['isAuthenticated'], name + ' WebsiteUser cookie round-trip')
    status, _, _, _ = request(host, '/api/bog/create-order', 'POST', {}, {'Cookie': auth, 'X-CSRF-Token': csrf})
    check(status >= 400, name + ' unconfigured payment fails closed')
check(request('unknown.vynic.localhost', '/api/website/venue')[0] == 404, 'unknown Venue fails closed')
check(request('attacker.invalid')[0] == 404, 'unrouted host fails closed')
check(request('admin.vynic.localhost', '/platform/auth/me')[0] == 401, 'admin API requires Platform identity')
check(request('vynic.localhost', '/platform/auth/login', 'POST', {})[0] != 201, 'admin API not exposed on public host')
print('All HTTP acceptance checks passed. Signup created test-only WebsiteUsers in the isolated Docker DB.')
