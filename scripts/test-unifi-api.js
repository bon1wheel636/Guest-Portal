const http = require('http');
const assert = require('assert');
const { authorizeUnifiGuest, unauthorizeUnifiGuest, describeUnifiGuest, normalizeMac, normalizeConsoleUrl } = require('../unifi-api');

function listen(handler) {
  const server = http.createServer(handler);
  return new Promise(resolve => {
    server.listen(0, '127.0.0.1', () => resolve(server));
  });
}

async function main() {
  assert.strictEqual(normalizeMac('1C:71:25:63:E4:24'), '1c:71:25:63:e4:24');
  assert.strictEqual(normalizeMac('1c712563e424'), '1c:71:25:63:e4:24');
  assert.strictEqual(normalizeMac('1C-71-25-63-E4-24'), '1c:71:25:63:e4:24');
  assert.strictEqual(normalizeMac('not-a-mac'), null);
  assert.strictEqual(normalizeConsoleUrl('https://gw.example:8443/ignore'), 'https://gw.example:8443');
  assert.throws(() => normalizeConsoleUrl('http://gw.example'), /https/);

  const seen = [];
  const server = await listen((req, res) => {
    let body = '';
    req.on('data', chunk => { body += chunk; });
    req.on('end', () => {
      seen.push({ method: req.method, url: req.url, body, apiKey: req.headers['x-api-key'] });
      if (req.url.startsWith('/proxy/network/integration/v1/sites?')) {
        res.end(JSON.stringify({ data: [{ id: 'site-1', name: 'Home' }] }));
        return;
      }
      if (req.url.includes('/clients?')) {
        const upper = decodeURIComponent(req.url).includes("macAddress.eq('1C:71:25:63:E4:24')");
        res.end(JSON.stringify({
          data: upper
            ? []
            : [{ id: 'client-9', macAddress: '1c:71:25:63:e4:24', access: { type: 'GUEST', authorized: false } }]
        }));
        return;
      }
      if (req.url.endsWith('/clients/client-9')) {
        res.end(JSON.stringify({
          id: 'client-9',
          macAddress: '1c:71:25:63:e4:24',
          access: { type: 'GUEST', authorized: true }
        }));
        return;
      }
      if (req.method === 'POST' && req.url.endsWith('/actions')) {
        res.end(JSON.stringify({ grantedAuthorization: true }));
        return;
      }
      res.statusCode = 404;
      res.end(JSON.stringify({ message: 'missing' }));
    });
  });

  const base = `http://127.0.0.1:${server.address().port}`;
  const original = normalizeConsoleUrl;
  // The client requires https origins. Point fetch at the mock by rewriting the origin in fetchImpl.
  const result = await authorizeUnifiGuest({
    consoleUrl: 'https://gw.example',
    apiKey: 'test-key-value',
    siteId: '',
    mac: '1C:71:25:63:E4:24',
    checkoutDate: new Date(Date.now() + 2 * 60 * 60 * 1000).toISOString(),
    fetchImpl: (url, options) => {
      const rewritten = url.replace('https://gw.example', base);
      return fetch(rewritten, options);
    }
  });

  assert.strictEqual(result.ok, true);
  assert.strictEqual(result.siteId, 'site-1');
  assert.strictEqual(result.clientId, 'client-9');
  assert.ok(result.timeLimitMinutes >= 119 && result.timeLimitMinutes <= 121);
  assert.strictEqual(seen[0].apiKey, 'test-key-value');
  assert.ok(seen[0].url.includes('/v1/sites?'));
  assert.ok(seen[1].url.includes("macAddress.eq('1c:71:25:63:e4:24'") || seen[1].url.includes('macAddress.eq(%271c'));
  const action = seen.find(entry => entry.method === 'POST');
  const payload = JSON.parse(action.body);
  assert.strictEqual(payload.action, 'AUTHORIZE_GUEST_ACCESS');
  assert.strictEqual(payload.timeLimitMinutes, result.timeLimitMinutes);
  assert.strictEqual(action.url, '/proxy/network/integration/v1/sites/site-1/clients/client-9/actions');

  const revoked = await unauthorizeUnifiGuest({
    consoleUrl: 'https://gw.example',
    apiKey: 'test-key-value',
    siteId: 'site-1',
    mac: '1c:71:25:63:e4:24',
    fetchImpl: (url, options) => fetch(url.replace('https://gw.example', base), options)
  });
  assert.strictEqual(revoked.state, 'unauthorized');
  const revokeCall = seen.filter(entry => entry.method === 'POST').pop();
  assert.strictEqual(JSON.parse(revokeCall.body).action, 'UNAUTHORIZE_GUEST_ACCESS');

  const missing = listen((req, res) => {
    res.end(JSON.stringify({ data: [] }));
  });
  const missingServer = await missing;
  const missingBase = `http://127.0.0.1:${missingServer.address().port}`;
  await assert.rejects(() => unauthorizeUnifiGuest({
    consoleUrl: 'https://gw.example',
    apiKey: 'test-key-value',
    siteId: 'site-1',
    mac: '1c:71:25:63:e4:24',
    fetchImpl: (url, options) => fetch(url.replace('https://gw.example', missingBase), options)
  }), /not in the UniFi guest list/);
  await new Promise(resolve => missingServer.close(resolve));

  const byIdSeen = [];
  const byIdServer = await listen((req, res) => {
    byIdSeen.push({ method: req.method, url: req.url });
    if (req.method === 'GET' && req.url.endsWith('/clients/client-9')) {
      res.statusCode = 404;
      res.end(JSON.stringify({ message: 'not connected' }));
      return;
    }
    if (req.method === 'POST' && req.url.endsWith('/clients/client-9/actions')) {
      res.end(JSON.stringify({ grantedAuthorization: true }));
      return;
    }
    if (req.url.includes('/clients?')) {
      res.end(JSON.stringify({ data: [] }));
      return;
    }
    res.statusCode = 404;
    res.end(JSON.stringify({ message: 'missing' }));
  });
  const byIdBase = `http://127.0.0.1:${byIdServer.address().port}`;
  const byId = await unauthorizeUnifiGuest({
    consoleUrl: 'https://gw.example',
    apiKey: 'test-key-value',
    siteId: 'site-1',
    clientId: 'client-9',
    mac: '1c:71:25:63:e4:24',
    fetchImpl: (url, options) => fetch(url.replace('https://gw.example', byIdBase), options)
  });
  assert.strictEqual(byId.state, 'unauthorized');
  assert.ok(byIdSeen.some(entry => entry.method === 'POST' && entry.url.endsWith('/clients/client-9/actions')));
  await new Promise(resolve => byIdServer.close(resolve));

  const described = await describeUnifiGuest({
    consoleUrl: 'https://gw.example',
    apiKey: 'test-key-value',
    siteId: 'site-1',
    mac: '1c:71:25:63:e4:24',
    fetchImpl: (url, options) => fetch(url.replace('https://gw.example', base), options)
  });
  assert.strictEqual(described.state, 'unauthorized');

  await new Promise(resolve => server.close(resolve));
  assert.strictEqual(original('https://gw.example'), 'https://gw.example');
  console.log('unifi api client ok');
}

main().catch(err => {
  console.error(err);
  process.exit(1);
});
