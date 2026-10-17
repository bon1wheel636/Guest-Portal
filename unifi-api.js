const https = require('https');

const MAC_ADDRESS = /^[0-9a-f]{2}(:[0-9a-f]{2}){5}$/i;

function normalizeMac(value) {
  if (typeof value !== 'string') return null;
  const mac = value.trim().toLowerCase();
  return MAC_ADDRESS.test(mac) ? mac : null;
}

function normalizeConsoleUrl(raw) {
  if (raw == null || String(raw).trim() === '') return null;
  if (typeof raw !== 'string' || raw.length > 500) {
    throw new Error('Invalid UniFi console URL');
  }
  let parsed;
  try {
    parsed = new URL(raw.trim());
  } catch {
    throw new Error('Invalid UniFi console URL');
  }
  if (parsed.protocol !== 'https:') {
    throw new Error('UniFi console URL must use https');
  }
  if (parsed.username || parsed.password) {
    throw new Error('UniFi console URL must not include a password');
  }
  return parsed.origin;
}

function normalizeSiteId(raw) {
  if (raw == null || String(raw).trim() === '') return '';
  const id = String(raw).trim();
  if (!/^[A-Za-z0-9._-]{1,80}$/.test(id)) {
    throw new Error('Invalid UniFi site id');
  }
  return id;
}

function normalizeApiKey(raw) {
  if (raw == null) return undefined;
  const key = String(raw).trim();
  if (!key) return undefined;
  if (key.length < 8 || key.length > 512 || /[\r\n]/.test(key)) {
    throw new Error('Invalid UniFi API key');
  }
  return key;
}

function minutesUntil(isoDate) {
  const ms = new Date(isoDate).getTime() - Date.now();
  if (!Number.isFinite(ms)) return 480;
  return Math.min(1000000, Math.max(1, Math.ceil(ms / 60000)));
}

function listFromBody(body) {
  if (Array.isArray(body)) return body;
  if (body && Array.isArray(body.data)) return body.data;
  return [];
}

function httpsRequest({ origin, path, method, headers, body, tlsInsecure }) {
  const target = new URL(origin + path);
  return new Promise((resolve, reject) => {
    const req = https.request({
      protocol: target.protocol,
      hostname: target.hostname,
      port: target.port || 443,
      path: `${target.pathname}${target.search}`,
      method,
      headers,
      rejectUnauthorized: tlsInsecure === false
    }, (res) => {
      let text = '';
      res.on('data', chunk => { text += chunk; });
      res.on('end', () => resolve({ status: res.statusCode, text }));
    });
    req.on('error', reject);
    if (body) req.write(body);
    req.end();
  });
}

async function unifiRequest({ origin, apiKey, path, method, body, tlsInsecure, fetchImpl }) {
  const headers = {
    'X-API-KEY': apiKey,
    Accept: 'application/json',
    ...(body ? { 'Content-Type': 'application/json' } : {})
  };
  const payload = body ? JSON.stringify(body) : undefined;
  const requestPath = `/proxy/network/integration${path}`;
  let status;
  let text;
  if (fetchImpl) {
    const response = await fetchImpl(`${origin}${requestPath}`, {
      method,
      headers,
      body: payload
    });
    status = response.status;
    text = await response.text();
  } else {
    const response = await httpsRequest({
      origin,
      path: requestPath,
      method,
      headers,
      body: payload,
      tlsInsecure
    });
    status = response.status;
    text = response.text;
  }
  let parsed = null;
  if (text) {
    try {
      parsed = JSON.parse(text);
    } catch {
      parsed = null;
    }
  }
  if (status < 200 || status >= 300) {
    const message = parsed && parsed.message
      ? parsed.message
      : `UniFi request failed (${status})`;
    throw new Error(message);
  }
  return parsed;
}

async function resolveSiteId({ origin, apiKey, siteId, tlsInsecure, fetchImpl }) {
  if (siteId) return siteId;
  const body = await unifiRequest({
    origin,
    apiKey,
    path: '/v1/sites?limit=25',
    method: 'GET',
    tlsInsecure,
    fetchImpl
  });
  const sites = listFromBody(body);
  if (sites.length === 1 && sites[0] && sites[0].id) return String(sites[0].id);
  throw new Error('UniFi returned more than one site. Enter the site id in Admin Settings.');
}

async function authorizeUnifiGuest({ consoleUrl, apiKey, siteId, mac, checkoutDate, tlsInsecure, fetchImpl }) {
  const origin = normalizeConsoleUrl(consoleUrl);
  const clientMac = normalizeMac(mac);
  if (!origin || !apiKey || !clientMac) {
    throw new Error('UniFi console, API key, and client MAC are required');
  }
  const resolvedSiteId = await resolveSiteId({
    origin,
    apiKey,
    siteId: normalizeSiteId(siteId),
    tlsInsecure,
    fetchImpl
  });
  const filter = encodeURIComponent(`macAddress.eq('${clientMac}')`);
  const clientsBody = await unifiRequest({
    origin,
    apiKey,
    path: `/v1/sites/${encodeURIComponent(resolvedSiteId)}/clients?limit=25&filter=${filter}`,
    method: 'GET',
    tlsInsecure,
    fetchImpl
  });
  const client = listFromBody(clientsBody).find(entry => normalizeMac(entry && entry.macAddress) === clientMac);
  if (!client || !client.id) {
    throw new Error('This phone is not in the UniFi guest list yet');
  }
  const timeLimitMinutes = minutesUntil(checkoutDate);
  await unifiRequest({
    origin,
    apiKey,
    path: `/v1/sites/${encodeURIComponent(resolvedSiteId)}/clients/${encodeURIComponent(client.id)}/actions`,
    method: 'POST',
    body: {
      action: 'AUTHORIZE_GUEST_ACCESS',
      timeLimitMinutes
    },
    tlsInsecure,
    fetchImpl
  });
  return { ok: true, timeLimitMinutes, siteId: resolvedSiteId };
}

module.exports = {
  normalizeMac,
  normalizeConsoleUrl,
  normalizeSiteId,
  normalizeApiKey,
  minutesUntil,
  authorizeUnifiGuest
};
