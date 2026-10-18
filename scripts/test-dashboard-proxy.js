'use strict';

const assert = require('assert');
const {
  parseDashboardTarget,
  kioskSearch,
  classifyDashboardPath,
  looksLikeDashboardTraffic,
  GUEST_HOME_PATH,
  EMBED_PATH
} = require('../dashboard-proxy');

const target = parseDashboardTarget('https://hass.example.invalid/lovelace/guest-room?kiosk');
assert.strictEqual(target.pathname, '/lovelace/guest-room');
assert.strictEqual(target.search, '?kiosk');
assert.strictEqual(kioskSearch(''), '?kiosk=1');
assert.strictEqual(kioskSearch('?kiosk'), '?kiosk');
assert.ok(kioskSearch('?foo=1').includes('kiosk=1'));

assert.strictEqual(classifyDashboardPath('/lovelace/guest-room', target.pathname), 'page');
assert.strictEqual(classifyDashboardPath('/api/websocket', target.pathname), 'asset');
assert.strictEqual(classifyDashboardPath('/frontend_latest/app.js', target.pathname), 'asset');
assert.strictEqual(classifyDashboardPath('/history', target.pathname), 'blocked');
assert.strictEqual(classifyDashboardPath('/map', target.pathname), 'blocked');
assert.strictEqual(classifyDashboardPath('/lovelace/other-room', target.pathname), 'blocked');
assert.strictEqual(classifyDashboardPath('/config', target.pathname), 'blocked');
assert.strictEqual(classifyDashboardPath('/energy', target.pathname), 'blocked');

assert.strictEqual(looksLikeDashboardTraffic(GUEST_HOME_PATH), true);
assert.strictEqual(looksLikeDashboardTraffic(EMBED_PATH), true);
assert.strictEqual(looksLikeDashboardTraffic('/welcome.html'), false);

console.log('dashboard-proxy path rules ok');
