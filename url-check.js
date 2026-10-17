'use strict';

const URL_CHECK_TIMEOUT_MS = 2500;

function reachabilityFromStatus(status) {
  if (status >= 200 && status < 400) {
    return { checked: true, reachable: true, status, error: null, authRequired: false };
  }
  if (status === 401 || status === 403) {
    return { checked: true, reachable: true, status, error: null, authRequired: true };
  }
  return {
    checked: true,
    reachable: false,
    status,
    error: status === 405 ? 'Method not allowed' : `HTTP ${status}`,
    authRequired: false
  };
}

async function probe(url, signal) {
  const response = await fetch(url, {
    method: 'GET',
    redirect: 'manual',
    signal
  });
  if (response.body && typeof response.body.cancel === 'function') {
    try {
      await response.body.cancel();
    } catch {
      // The body may already be closed.
    }
  }
  return response.status;
}

// Browsers open a dashboard with GET. Home Assistant and some proxies answer
// HEAD with 405 while the same URL still serves the page.
async function checkUrlReachability(rawUrl) {
  if (!rawUrl) {
    return { checked: false, reachable: false, status: null, error: 'No URL configured', authRequired: false };
  }

  let parsed;
  try {
    parsed = new URL(rawUrl);
  } catch {
    return { checked: true, reachable: false, status: null, error: 'Invalid URL', authRequired: false };
  }

  if (!['http:', 'https:'].includes(parsed.protocol)) {
    return { checked: true, reachable: false, status: null, error: 'URL must use http or https', authRequired: false };
  }

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), URL_CHECK_TIMEOUT_MS);

  try {
    const status = await probe(parsed.toString(), controller.signal);
    return reachabilityFromStatus(status);
  } catch (err) {
    return {
      checked: true,
      reachable: false,
      status: null,
      error: err.name === 'AbortError' ? 'Timed out' : err.message,
      authRequired: false
    };
  } finally {
    clearTimeout(timeout);
  }
}

module.exports = {
  checkUrlReachability,
  reachabilityFromStatus
};
