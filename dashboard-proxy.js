'use strict';

const http = require('http');
const https = require('https');

const COOKIE_NAME = 'gpDash';
const GUEST_HOME_PATH = '/guest/home';
const EMBED_PATH = '/guest/ha';

const BLOCKED_PREFIXES = [
  '/config',
  '/developer-tools',
  '/developer_tools',
  '/history',
  '/logbook',
  '/activity',
  '/map',
  '/energy',
  '/profile',
  '/media-browser',
  '/hassio',
  '/supervisor',
  '/cloud',
  '/repairs',
  '/backup',
  '/todo',
  '/my'
];

const ASSET_PREFIXES = [
  '/frontend_latest',
  '/frontend_es5',
  '/static',
  '/local',
  '/hacsfiles',
  '/auth',
  '/api',
  '/present',
  '/cast'
];

const ASSET_EXACT = new Set([
  '/manifest.json',
  '/service_worker.js',
  '/robots.txt',
  '/favicon.ico'
]);

const HOP_BY_HOP = new Set([
  'connection',
  'keep-alive',
  'proxy-authenticate',
  'proxy-authorization',
  'te',
  'trailer',
  'transfer-encoding',
  'upgrade'
]);

function parseDashboardTarget(dashboardUrl) {
  if (!dashboardUrl || typeof dashboardUrl !== 'string') return null;
  try {
    const parsed = new URL(dashboardUrl);
    if (!['http:', 'https:'].includes(parsed.protocol)) return null;
    let pathname = parsed.pathname || '/';
    if (pathname.length > 1 && pathname.endsWith('/')) {
      pathname = pathname.slice(0, -1);
    }
    return {
      origin: parsed.origin,
      protocol: parsed.protocol,
      hostname: parsed.hostname,
      port: parsed.port || (parsed.protocol === 'https:' ? '443' : '80'),
      pathname,
      search: parsed.search || ''
    };
  } catch {
    return null;
  }
}

function kioskSearch(storedSearch) {
  const raw = storedSearch && storedSearch.startsWith('?') ? storedSearch.slice(1) : (storedSearch || '');
  const params = new URLSearchParams(raw);
  const hasKiosk = [...params.keys()].some(key => key.toLowerCase() === 'kiosk');
  if (!hasKiosk) params.set('kiosk', '1');
  const parts = [];
  for (const [key, value] of params.entries()) {
    parts.push(value === '' ? encodeURIComponent(key) : `${encodeURIComponent(key)}=${encodeURIComponent(value)}`);
  }
  return parts.length ? `?${parts.join('&')}` : '?kiosk=1';
}

function isBlockedPath(pathname) {
  const p = String(pathname || '').toLowerCase();
  return BLOCKED_PREFIXES.some(prefix => p === prefix || p.startsWith(`${prefix}/`));
}

function isAssetPath(pathname) {
  if (ASSET_EXACT.has(pathname)) return true;
  return ASSET_PREFIXES.some(prefix => pathname === prefix || pathname.startsWith(`${prefix}/`));
}

function isAllowedPagePath(pathname, allowedPath) {
  if (!allowedPath) return false;
  if (pathname === allowedPath) return true;
  if (allowedPath !== '/' && pathname.startsWith(`${allowedPath}/`)) return true;
  return false;
}

function classifyDashboardPath(pathname, allowedPath) {
  if (isBlockedPath(pathname)) return 'blocked';
  if (isAllowedPagePath(pathname, allowedPath)) return 'page';
  if (isAssetPath(pathname)) return 'asset';
  return 'blocked';
}

function looksLikeDashboardTraffic(pathname) {
  if (pathname === GUEST_HOME_PATH || pathname === EMBED_PATH) return true;
  if (ASSET_EXACT.has(pathname)) return true;
  if (isAssetPath(pathname)) return true;
  if (pathname === '/lovelace' || pathname.startsWith('/lovelace/')) return true;
  if (pathname.startsWith('/dashboard')) return true;
  return BLOCKED_PREFIXES.some(prefix => pathname === prefix || pathname.startsWith(`${prefix}/`));
}

function requestPathname(req) {
  try {
    return new URL(req.url, 'http://portal.local').pathname;
  } catch {
    return req.url.split('?')[0];
  }
}

function copyRequestHeaders(req, targetHost) {
  const headers = {};
  for (const [key, value] of Object.entries(req.headers)) {
    if (HOP_BY_HOP.has(key.toLowerCase())) continue;
    if (key.toLowerCase() === 'cookie') {
      headers[key] = String(value)
        .split(';')
        .map(part => part.trim())
        .filter(part => part && !part.startsWith(`${COOKIE_NAME}=`))
        .join('; ');
      if (!headers[key]) delete headers[key];
      continue;
    }
    headers[key] = value;
  }
  headers.host = targetHost;
  return headers;
}

function rewriteSetCookie(value) {
  return String(value)
    .split(';')
    .map(part => part.trim())
    .filter(part => part && !/^domain=/i.test(part))
    .join('; ');
}

function rewriteLocation(location, targetOrigin) {
  if (!location) return GUEST_HOME_PATH;
  try {
    const resolved = new URL(location, targetOrigin);
    if (resolved.origin === targetOrigin) {
      return `${resolved.pathname}${resolved.search}${resolved.hash}`;
    }
  } catch {
    return GUEST_HOME_PATH;
  }
  return GUEST_HOME_PATH;
}

function copyResponseHeaders(proxyRes, targetOrigin) {
  const headers = {};
  for (const [key, value] of Object.entries(proxyRes.headers)) {
    const lower = key.toLowerCase();
    if (HOP_BY_HOP.has(lower)) continue;
    if (lower === 'x-frame-options' || lower === 'content-security-policy' || lower === 'content-security-policy-report-only') {
      continue;
    }
    if (lower === 'set-cookie') {
      const cookies = Array.isArray(value) ? value : [value];
      headers[key] = cookies.map(rewriteSetCookie);
      continue;
    }
    if (lower === 'location') {
      headers[key] = rewriteLocation(value, targetOrigin);
      continue;
    }
    headers[key] = value;
  }
  return headers;
}

function proxyHttp(req, res, target) {
  const lib = target.protocol === 'https:' ? https : http;
  const headers = copyRequestHeaders(req, target.hostname);
  const forwarded = req.socket && req.socket.remoteAddress;
  if (forwarded) {
    headers['x-forwarded-for'] = forwarded;
  }
  headers['x-forwarded-proto'] = req.secure || (req.get && req.get('X-Forwarded-Proto') === 'https') ? 'https' : 'http';
  if (req.get) {
    headers['x-forwarded-host'] = req.get('Host') || headers['x-forwarded-host'];
  }

  const pReq = lib.request({
    protocol: target.protocol,
    hostname: target.hostname,
    port: target.port,
    path: req.url,
    method: req.method,
    headers,
    timeout: 30000
  }, pRes => {
    res.writeHead(pRes.statusCode || 502, copyResponseHeaders(pRes, target.origin));
    pRes.pipe(res);
  });
  pReq.on('timeout', () => pReq.destroy());
  pReq.on('error', () => {
    if (!res.headersSent) {
      res.status(502).send('Smart Home dashboard is unavailable');
    } else {
      res.end();
    }
  });
  req.pipe(pReq);
}

function proxyUpgrade(req, socket, head, target) {
  const lib = target.protocol === 'https:' ? https : http;
  const headers = copyRequestHeaders(req, target.hostname);
  headers.connection = 'Upgrade';
  headers.upgrade = req.headers.upgrade || 'websocket';
  const pReq = lib.request({
    protocol: target.protocol,
    hostname: target.hostname,
    port: target.port,
    path: req.url,
    method: 'GET',
    headers,
    timeout: 30000
  });
  pReq.on('upgrade', (pRes, pSocket, pHead) => {
    const lines = [`HTTP/1.1 ${pRes.statusCode} Switching Protocols`];
    for (const [key, value] of Object.entries(pRes.headers)) {
      const values = Array.isArray(value) ? value : [value];
      values.forEach(item => lines.push(`${key}: ${item}`));
    }
    socket.write(`${lines.join('\r\n')}\r\n\r\n`);
    if (pHead && pHead.length) socket.write(pHead);
    pSocket.pipe(socket);
    socket.pipe(pSocket);
  });
  pReq.on('error', () => socket.destroy());
  pReq.on('timeout', () => {
    pReq.destroy();
    socket.destroy();
  });
  pReq.end(head);
}

function handleDashboardRequest(req, res, guestContext) {
  if (!guestContext || !guestContext.guest) {
    return res.status(guestContext && guestContext.status ? guestContext.status : 401)
      .send((guestContext && guestContext.message) || 'Valid guest session required');
  }
  const target = parseDashboardTarget(guestContext.dashboardUrl);
  if (!target) {
    return res.status(404).send('No dashboard is assigned');
  }
  const pathname = requestPathname(req);
  if (pathname === EMBED_PATH) {
    return res.redirect(302, `${target.pathname}${kioskSearch(target.search)}`);
  }
  const kind = classifyDashboardPath(pathname, target.pathname);
  if (kind === 'blocked') {
    return res.redirect(302, `${target.pathname}${kioskSearch(target.search)}`);
  }
  if (kind === 'page') {
    const desired = kioskSearch(target.search);
    const current = new URL(req.url, 'http://portal.local').search;
    if (current !== desired) {
      return res.redirect(302, `${pathname}${desired}`);
    }
  }
  return proxyHttp(req, res, target);
}

function handleDashboardUpgrade(req, socket, head, guestContext) {
  if (!guestContext || !guestContext.guest) {
    socket.destroy();
    return;
  }
  const target = parseDashboardTarget(guestContext.dashboardUrl);
  const pathname = requestPathname(req);
  if (!target || classifyDashboardPath(pathname, target.pathname) !== 'asset') {
    socket.destroy();
    return;
  }
  proxyUpgrade(req, socket, head, target);
}

module.exports = {
  COOKIE_NAME,
  GUEST_HOME_PATH,
  EMBED_PATH,
  parseDashboardTarget,
  kioskSearch,
  classifyDashboardPath,
  looksLikeDashboardTraffic,
  handleDashboardRequest,
  handleDashboardUpgrade
};
