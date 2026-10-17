const http = require('http');
const assert = require('assert');
const { checkUrlReachability, reachabilityFromStatus } = require('../url-check');

function listen(handler) {
  const server = http.createServer(handler);
  return new Promise(resolve => {
    server.listen(0, '127.0.0.1', () => resolve(server));
  });
}

async function main() {
  assert.strictEqual(reachabilityFromStatus(405).reachable, false);
  assert.strictEqual(reachabilityFromStatus(404).reachable, false);
  assert.strictEqual(reachabilityFromStatus(500).reachable, false);
  assert.strictEqual(reachabilityFromStatus(200).reachable, true);
  assert.strictEqual(reachabilityFromStatus(302).reachable, true);
  assert.strictEqual(reachabilityFromStatus(401).authRequired, true);
  assert.strictEqual(reachabilityFromStatus(403).authRequired, true);

  const seen = [];
  const server = await listen((req, res) => {
    seen.push({ method: req.method, url: req.url });
    if (req.url === '/dashboard') {
      if (req.method === 'HEAD') {
        res.writeHead(405, { Allow: 'GET' });
        res.end();
        return;
      }
      res.writeHead(200, { 'Content-Type': 'text/html' });
      res.end('<html>dashboard</html>');
      return;
    }
    if (req.url === '/login') {
      res.writeHead(401);
      res.end('sign in');
      return;
    }
    if (req.url === '/missing') {
      res.writeHead(404);
      res.end('missing');
      return;
    }
    res.writeHead(405, { Allow: 'POST' });
    res.end();
  });

  const base = `http://127.0.0.1:${server.address().port}`;
  const dashboard = await checkUrlReachability(`${base}/dashboard`);
  assert.strictEqual(dashboard.reachable, true);
  assert.strictEqual(dashboard.status, 200);
  assert.strictEqual(dashboard.authRequired, false);
  assert.ok(seen.some(entry => entry.url === '/dashboard' && entry.method === 'GET'));
  assert.ok(!seen.some(entry => entry.method === 'HEAD'));

  const login = await checkUrlReachability(`${base}/login`);
  assert.strictEqual(login.reachable, true);
  assert.strictEqual(login.status, 401);
  assert.strictEqual(login.authRequired, true);

  const missing = await checkUrlReachability(`${base}/missing`);
  assert.strictEqual(missing.reachable, false);
  assert.strictEqual(missing.status, 404);

  const method = await checkUrlReachability(`${base}/post-only`);
  assert.strictEqual(method.reachable, false);
  assert.strictEqual(method.status, 405);
  assert.strictEqual(method.error, 'Method not allowed');

  const empty = await checkUrlReachability('');
  assert.strictEqual(empty.checked, false);

  const badScheme = await checkUrlReachability('ftp://files.example/dash');
  assert.strictEqual(badScheme.reachable, false);
  assert.match(badScheme.error, /http or https/);

  await new Promise(resolve => server.close(resolve));
  console.log('url check ok');
}

main().catch(err => {
  console.error(err);
  process.exit(1);
});
