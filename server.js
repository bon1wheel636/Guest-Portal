
// server.js - v1.1.0 security hardened
const express = require('express');
const multer = require('multer');
const path = require('path');
const fs = require('fs');
const crypto = require('crypto');
const cors = require('cors');
const basicAuth = require('basic-auth');
const bcrypt = require('bcrypt');
const rateLimit = require('express-rate-limit');
const archiver = require('archiver');
const app = express();

// ─── Constants & Data Loading ───────────────────────────────────────────────

const port = 3000;
const configPath = '/etc/guest-portal/config.json';
const dbPath = '/etc/guest-portal/storage.json';
const sessionFile = '/etc/guest-portal/sessions.json';
const guestTokensFile = '/etc/guest-portal/guest-tokens.json';
const MAX_GUEST_UPLOAD_SIZE_BYTES = 50 * 1024 * 1024;
const MAX_GUEST_UPLOAD_FILES = 10;
const URL_CHECK_TIMEOUT_MS = 2500;

// H2: Use JSON.parse(fs.readFileSync()) instead of require() to avoid module caching
const config = fs.existsSync(configPath) ? JSON.parse(fs.readFileSync(configPath, 'utf8')) : {};
const guestData = fs.existsSync(dbPath) ? JSON.parse(fs.readFileSync(dbPath, 'utf8')) : { rooms: [], guests: [] };
let sessionCodes = fs.existsSync(sessionFile) ? JSON.parse(fs.readFileSync(sessionFile, 'utf8')) : {};
let guestTokens = fs.existsSync(guestTokensFile) ? JSON.parse(fs.readFileSync(guestTokensFile, 'utf8')) : {};
const packageJsonPath = path.join(__dirname, 'package.json');
const packageInfo = fs.existsSync(packageJsonPath) ? JSON.parse(fs.readFileSync(packageJsonPath, 'utf8')) : {};

// ─── Utility Functions ──────────────────────────────────────────────────────

function getUploadsDir() {
  return config.uploadDir || path.join(__dirname, 'uploads');
}

function sanitizeFilename(filename) {
  return filename
    .replace(/[/\\]/g, '_')
    .replace(/\.\./g, '_')
    .replace(/\0/g, '')
    .replace(/[<>:"|?*]/g, '_')
    .substring(0, 255);
}

function sanitizeName(name) {
  return name
    .replace(/[^\w\s-]/g, '')
    .replace(/\s+/g, '-')
    .substring(0, 100);
}

function getExpirationMinutes() {
  return config.sessionExpirationMinutes || 10;
}

function getAdminTimeoutMinutes() {
  return config.adminSessionTimeoutMinutes || 15;
}

// L5: Async file writes to avoid blocking the event loop
function saveConfig() {
  fs.promises.writeFile(configPath, JSON.stringify(config, null, 2)).catch(err => {
    console.error('Failed to save config:', err);
  });
}

function saveSessions() {
  fs.promises.writeFile(sessionFile, JSON.stringify(sessionCodes, null, 2)).catch(err => {
    console.error('Failed to save sessions:', err);
  });
}

function saveGuestTokens() {
  fs.promises.writeFile(guestTokensFile, JSON.stringify(guestTokens, null, 2)).catch(err => {
    console.error('Failed to save guest tokens:', err);
  });
}

function saveGuestData() {
  fs.promises.writeFile(dbPath, JSON.stringify(guestData, null, 2)).catch(err => {
    console.error('Failed to save guest data:', err);
  });
}

// C2: Use crypto.randomBytes instead of Math.random for secure token generation
function generateCode() {
  return crypto.randomBytes(3).toString('hex').toUpperCase();
}

function generateToken() {
  return crypto.randomBytes(32).toString('hex');
}

function getGuestSession(token) {
  if (!token || !guestTokens[token]) {
    return { status: 401, message: 'Valid guest session required' };
  }

  const guest = guestTokens[token];
  if (new Date(guest.checkoutDate) < new Date()) {
    return { status: 410, message: 'Guest session expired' };
  }

  return { guest };
}

function validateGuestNameAndRoom(name, room) {
  if (!name || !room || typeof name !== 'string' || typeof room !== 'string') {
    return 'Invalid name or room';
  }
  if (/[^\w\s]/.test(name) || /[^\w\s]/.test(room)) {
    return 'Invalid name or room';
  }
  return null;
}

function resolveRoomDashboard(roomName) {
  const roomData = guestData.rooms.find(r => r.name === roomName);
  return roomData ? roomData.dashboardUrl : null;
}

function findGuestTokenEntryByGuestId(guestId) {
  return Object.entries(guestTokens).find(([_, guest]) => guest.id === guestId) || null;
}

function isReturningDevice(guest, userAgent) {
  const ua = userAgent || 'Unknown';
  return (guest.devices || []).some(device => device.userAgent === ua);
}

function getGuestUploadFolders(guestId) {
  const uploadsDir = getUploadsDir();
  if (!fs.existsSync(uploadsDir)) {
    return [];
  }

  const guestMarker = `-${guestId}-`;
  return fs.readdirSync(uploadsDir, { withFileTypes: true })
    .filter(entry => entry.isDirectory() && entry.name !== 'backgrounds' && entry.name.includes(guestMarker))
    .map(entry => path.join(uploadsDir, entry.name));
}

function listGuestUploadFiles(guestId) {
  const files = [];

  getGuestUploadFolders(guestId).forEach(folderPath => {
    fs.readdirSync(folderPath).forEach(name => {
      const filePath = path.join(folderPath, name);
      const stat = fs.statSync(filePath);
      if (!stat.isFile()) {
        return;
      }

      files.push({
        name,
        size: stat.size,
        uploadedAt: stat.mtime.toISOString()
      });
    });
  });

  return files.sort((a, b) => b.uploadedAt.localeCompare(a.uploadedAt));
}

function findGuestUploadFile(guestId, filename) {
  const safeName = path.basename(filename);
  if (safeName !== filename || safeName.includes('..')) {
    return null;
  }

  for (const folderPath of getGuestUploadFolders(guestId)) {
    const filePath = path.resolve(path.join(folderPath, safeName));
    if (!filePath.startsWith(path.resolve(folderPath))) {
      continue;
    }
    if (fs.existsSync(filePath) && fs.statSync(filePath).isFile()) {
      return filePath;
    }
  }

  return null;
}

function countGuestSessionsByExpiry() {
  const now = new Date();
  let active = 0;
  let expired = 0;
  Object.values(guestTokens).forEach(guest => {
    if (new Date(guest.checkoutDate) >= now) {
      active += 1;
    } else {
      expired += 1;
    }
  });
  return { active, expired };
}

function createGuestRegistration(name, room, stayDays, userAgent) {
  const days = Math.min(Math.max(parseInt(stayDays, 10) || 7, 1), 30);
  const checkoutDate = new Date();
  checkoutDate.setDate(checkoutDate.getDate() + days);

  const token = generateToken();
  const guestId = `guest_${Date.now()}_${crypto.randomBytes(4).toString('hex')}`;
  const dashboardUrl = resolveRoomDashboard(room);
  const createdAt = new Date().toISOString();

  guestTokens[token] = {
    id: guestId,
    name,
    room,
    dashboardUrl,
    checkoutDate: checkoutDate.toISOString(),
    createdAt,
    devices: [{ addedAt: createdAt, userAgent: userAgent || 'Unknown' }]
  };
  saveGuestTokens();

  guestData.guests.push({ name, room, timestamp: createdAt, guestId });
  saveGuestData();

  return {
    token,
    guestId,
    guest: {
      id: guestId,
      name,
      room,
      dashboardUrl,
      checkoutDate: checkoutDate.toISOString()
    }
  };
}

function bufferStartsWith(buffer, signature) {
  return signature.every((byte, index) => buffer[index] === byte);
}

function readFileHeader(filePath) {
  const fd = fs.openSync(filePath, 'r');
  try {
    const buffer = Buffer.alloc(4100);
    const bytesRead = fs.readSync(fd, buffer, 0, buffer.length, 0);
    return buffer.subarray(0, bytesRead);
  } finally {
    fs.closeSync(fd);
  }
}

function hasExpectedFileSignature(file) {
  const header = readFileHeader(file.path);
  const ascii = header.toString('ascii');

  switch (file.mimetype) {
    case 'image/jpeg':
      return bufferStartsWith(header, [0xff, 0xd8, 0xff]);
    case 'image/png':
      return bufferStartsWith(header, [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
    case 'image/gif':
      return ascii.startsWith('GIF87a') || ascii.startsWith('GIF89a');
    case 'image/webp':
      return ascii.startsWith('RIFF') && ascii.substring(8, 12) === 'WEBP';
    case 'application/pdf':
      return ascii.startsWith('%PDF-');
    case 'video/webm':
      return bufferStartsWith(header, [0x1a, 0x45, 0xdf, 0xa3]);
    case 'video/mp4':
    case 'video/quicktime':
    case 'image/heic':
    case 'image/heif':
      return ascii.substring(4, 8) === 'ftyp';
    default:
      return false;
  }
}

function removeUploadedFiles(files = []) {
  files.forEach(file => {
    fs.promises.unlink(file.path).catch(err => {
      console.error('Failed to remove rejected upload:', err);
    });
  });
}

function getDirectoryStatus(dirPath) {
  const resolved = path.resolve(dirPath);
  const status = {
    path: resolved,
    exists: false,
    isDirectory: false,
    writable: false,
    error: null
  };

  try {
    status.exists = fs.existsSync(resolved);
    if (!status.exists) return status;

    const stat = fs.statSync(resolved);
    status.isDirectory = stat.isDirectory();
    if (!status.isDirectory) return status;

    fs.accessSync(resolved, fs.constants.W_OK);
    status.writable = true;
  } catch (err) {
    status.error = err.message;
  }

  return status;
}

function getReverseProxyStatus(req) {
  const forwardedProto = req.get('X-Forwarded-Proto') || null;
  const forwardedHost = req.get('X-Forwarded-Host') || null;
  const forwardedFor = req.get('X-Forwarded-For') || null;
  const host = req.get('Host') || null;

  return {
    host,
    forwardedHost,
    forwardedProto,
    forwardedForPresent: Boolean(forwardedFor),
    usingForwardedHeaders: Boolean(forwardedProto || forwardedHost || forwardedFor),
    httpsDetected: req.secure || forwardedProto === 'https'
  };
}

async function checkUrlReachability(rawUrl) {
  if (!rawUrl) return { checked: false, reachable: false, status: null, error: 'No URL configured' };

  let parsed;
  try {
    parsed = new URL(rawUrl);
  } catch {
    return { checked: true, reachable: false, status: null, error: 'Invalid URL' };
  }

  if (!['http:', 'https:'].includes(parsed.protocol)) {
    return { checked: true, reachable: false, status: null, error: 'URL must use http or https' };
  }

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), URL_CHECK_TIMEOUT_MS);

  try {
    const response = await fetch(parsed.toString(), {
      method: 'HEAD',
      redirect: 'manual',
      signal: controller.signal
    });
    return {
      checked: true,
      reachable: response.status < 500,
      status: response.status,
      error: null
    };
  } catch (err) {
    return {
      checked: true,
      reachable: false,
      status: null,
      error: err.name === 'AbortError' ? 'Timed out' : err.message
    };
  } finally {
    clearTimeout(timeout);
  }
}

// ─── Middleware ──────────────────────────────────────────────────────────────

app.use(cors());
app.use(express.json());

// H1: Rate limiter BEFORE static files and routes
const limiter = rateLimit({
  windowMs: 60 * 1000,
  max: 60
});
app.use(limiter);

// C1: Auth middleware for admin endpoints
function authMiddleware(req, res, next) {
  const user = basicAuth(req);
  const expectedUser = (config.adminUser || '').trim();
  if (!user || user.name.trim() !== expectedUser) {
    res.set('WWW-Authenticate', 'Basic realm="Guest Portal Admin"');
    return res.status(401).send('Authentication required.');
  }
  if (!config.adminHash || config.adminHash === '<bcrypt_hash_placeholder>') {
    res.set('WWW-Authenticate', 'Basic realm="Guest Portal Admin"');
    return res.status(401).send('Admin account not configured.');
  }
  bcrypt.compare(user.pass, config.adminHash, (err, result) => {
    if (err) {
      return res.status(500).send('Authentication error.');
    }
    if (result) next();
    else {
      res.set('WWW-Authenticate', 'Basic realm="Guest Portal Admin"');
      return res.status(401).send('Access denied.');
    }
  });
}

function adminSetupRequired() {
  return !config.adminHash || config.adminHash === '<bcrypt_hash_placeholder>';
}

function adminPageAuth(req, res, next) {
  if (adminSetupRequired()) return next();
  return authMiddleware(req, res, next);
}

app.get('/admin.html', adminPageAuth, (req, res) => {
  res.sendFile(path.join(__dirname, 'frontend', 'admin.html'));
});

app.use(express.static('frontend'));

// ─── Multer Storage Config ──────────────────────────────────────────────────

const storage = multer.diskStorage({
  destination: (req, file, cb) => {
    const uploadsDir = getUploadsDir();
    const guest = req.guestSession.guest;
    const name = sanitizeName(guest.name || guest.id);
    const folderName = `${name}-${guest.id}-${new Date().toISOString().split('T')[0]}`;
    const dir = path.join(uploadsDir, folderName);
    if (!path.resolve(dir).startsWith(path.resolve(uploadsDir))) {
      return cb(new Error('Invalid upload path'));
    }
    fs.mkdirSync(dir, { recursive: true });
    cb(null, dir);
  },
  filename: (req, file, cb) => {
    const safeName = sanitizeFilename(file.originalname);
    cb(null, `${Date.now()}-${safeName}`);
  }
});

const GUEST_UPLOAD_TYPES = {
  'image/jpeg': ['.jpg', '.jpeg'],
  'image/png': ['.png'],
  'image/gif': ['.gif'],
  'image/webp': ['.webp'],
  'image/heic': ['.heic'],
  'image/heif': ['.heif'],
  'video/mp4': ['.mp4'],
  'video/quicktime': ['.mov', '.qt'],
  'video/webm': ['.webm'],
  'application/pdf': ['.pdf']
};

const upload = multer({
  storage,
  fileFilter: (req, file, cb) => {
    const allowedExts = GUEST_UPLOAD_TYPES[file.mimetype];
    const ext = path.extname(file.originalname).toLowerCase();
    if (!allowedExts || !allowedExts.includes(ext)) {
      return cb(new Error('Only photos, videos, and PDF files are allowed'));
    }
    cb(null, true);
  },
  limits: {
    fileSize: MAX_GUEST_UPLOAD_SIZE_BYTES,
    files: MAX_GUEST_UPLOAD_FILES
  }
});

function validateGuestUploadToken(req, res, next) {
  const token = req.get('X-Guest-Token') || req.query.token;
  const session = getGuestSession(token);
  if (!session.guest) {
    return res.status(session.status).send(session.message);
  }
  req.guestSession = { token, guest: session.guest };
  next();
}

function handleGuestUpload(req, res, next) {
  upload.array('photos', MAX_GUEST_UPLOAD_FILES)(req, res, err => {
    if (!err) return next();

    if (err instanceof multer.MulterError) {
      if (err.code === 'LIMIT_FILE_SIZE') {
        return res.status(413).send('File too large');
      }
      if (err.code === 'LIMIT_FILE_COUNT') {
        return res.status(400).send(`Upload up to ${MAX_GUEST_UPLOAD_FILES} files at a time`);
      }
      return res.status(400).send(err.message);
    }

    return res.status(400).send(err.message);
  });
}

// L1: Map MIME types to allowed extensions to prevent mismatches
const MIME_TO_EXT = {
  'image/jpeg': '.jpg',
  'image/png': '.png',
  'image/gif': '.gif',
  'image/webp': '.webp'
};

const bgStorage = multer.diskStorage({
  destination: (req, file, cb) => {
    const dir = path.join(getUploadsDir(), 'backgrounds');
    fs.mkdirSync(dir, { recursive: true });
    cb(null, dir);
  },
  filename: (req, file, cb) => {
    const ext = MIME_TO_EXT[file.mimetype] || '.jpg';
    cb(null, `background${ext}`);
  }
});
const bgUpload = multer({
  storage: bgStorage,
  fileFilter: (req, file, cb) => {
    if (MIME_TO_EXT[file.mimetype]) {
      cb(null, true);
    } else {
      cb(new Error('Only image files are allowed (JPG, PNG, GIF, WebP)'));
    }
  },
  limits: { fileSize: 5 * 1024 * 1024 }
});

// ─── Public Routes ──────────────────────────────────────────────────────────

app.get('/health', (req, res) => {
  res.json({ status: 'ok' });
});

// Check if admin setup is needed (no password configured)
app.get('/admin-api/setup-required', (req, res) => {
  const needsSetup = !config.adminHash || config.adminHash === '<bcrypt_hash_placeholder>';
  res.json({ setupRequired: needsSetup });
});

// First-run admin setup (only works if no password is set)
app.post('/admin-api/setup', async (req, res) => {
  if (config.adminHash && config.adminHash !== '<bcrypt_hash_placeholder>') {
    return res.status(403).send('Admin already configured. Use setup-local.sh to reset.');
  }

  const username = typeof req.body.username === 'string' ? req.body.username.trim() : '';
  const { password } = req.body;

  if (!username || username.length < 3 || username.length > 50) {
    return res.status(400).send('Username must be 3-50 characters');
  }
  if (!password || typeof password !== 'string' || password.length < 8) {
    return res.status(400).send('Password must be at least 8 characters');
  }
  if (!/^[a-zA-Z0-9_-]+$/.test(username)) {
    return res.status(400).send('Username can only contain letters, numbers, underscores, and hyphens');
  }

  try {
    const hash = await bcrypt.hash(password, 10);
    config.adminUser = username;
    config.adminHash = hash;
    saveConfig();
    res.json({ success: true, username, message: 'Admin account created successfully' });
  } catch (err) {
    res.status(500).send('Failed to create admin account');
  }
});

// Public guest endpoints (do not place under /admin-api — proxies may require auth there)
app.get('/guest/rooms', (req, res) => res.json(guestData.rooms || []));

app.get('/guest/background', (req, res) => {
  res.json({ backgroundImage: config.backgroundImage || null });
});

// Backward-compatible aliases
app.get('/admin-api/rooms', (req, res) => res.json(guestData.rooms || []));

// Public: background image info needed by guest pages
app.get('/admin-api/background', (req, res) => {
  res.json({ backgroundImage: config.backgroundImage || null });
});

// Serve background images publicly (dynamic path via config)
app.use('/uploads/backgrounds', (req, res, next) => {
  express.static(path.join(getUploadsDir(), 'backgrounds'))(req, res, next);
});

app.post('/register', (req, res) => {
  const { name, room, stayDays } = req.body;
  const validationError = validateGuestNameAndRoom(name, room);
  if (validationError) {
    return res.status(400).send(validationError);
  }

  const registration = createGuestRegistration(name, room, stayDays, req.get('User-Agent') || 'Unknown');
  res.json({
    token: registration.token,
    guest: registration.guest,
    returningDevice: false
  });
});

app.post('/guest/validate', (req, res) => {
  const { token } = req.body;
  const session = getGuestSession(token);
  if (session.status === 410) {
    return res.status(410).json({ valid: false, error: 'Session expired (checkout passed)' });
  }
  if (!session.guest) {
    return res.status(404).json({ valid: false, error: 'Invalid token' });
  }

  const guest = session.guest;
  res.json({
    valid: true,
    returningDevice: isReturningDevice(guest, req.get('User-Agent')),
    guest: {
      id: guest.id,
      name: guest.name,
      room: guest.room,
      dashboardUrl: guest.dashboardUrl,
      checkoutDate: guest.checkoutDate
    }
  });
});

app.post('/guest/link-code', (req, res) => {
  const { token } = req.body;
  if (!token || !guestTokens[token]) {
    return res.status(404).send('Invalid token');
  }

  const guest = guestTokens[token];
  const linkCode = generateCode();
  const expires = Date.now() + 30 * 60 * 1000;

  sessionCodes[linkCode] = {
    type: 'device-link',
    guestToken: token,
    guestId: guest.id,
    expires
  };
  saveSessions();

  res.json({ code: linkCode, expiresIn: '30 minutes' });
});

app.post('/guest/link-device', (req, res) => {
  const { code } = req.body;
  const entry = sessionCodes[code];

  if (!entry || entry.expires < Date.now() || entry.type !== 'device-link') {
    return res.status(404).send('Invalid or expired link code');
  }

  const guest = guestTokens[entry.guestToken];
  if (!guest) {
    return res.status(404).send('Guest session not found');
  }

  guest.devices.push({
    addedAt: new Date().toISOString(),
    userAgent: req.get('User-Agent') || 'Unknown'
  });
  saveGuestTokens();

  delete sessionCodes[code];
  saveSessions();

  res.json({
    token: entry.guestToken,
    returningDevice: false,
    guest: {
      id: guest.id,
      name: guest.name,
      room: guest.room,
      dashboardUrl: guest.dashboardUrl,
      checkoutDate: guest.checkoutDate
    }
  });
});

// H4: Validate guest token on upload
app.post('/upload', validateGuestUploadToken, handleGuestUpload, (req, res) => {
  if (!req.files || req.files.length === 0) {
    return res.status(400).send('At least one file is required');
  }
  const invalidFile = req.files.find(file => !hasExpectedFileSignature(file));
  if (invalidFile) {
    removeUploadedFiles(req.files);
    return res.status(400).send('Uploaded file content does not match an allowed file type');
  }
  res.sendStatus(200);
});

app.get('/guest/uploads', validateGuestUploadToken, (req, res) => {
  const files = listGuestUploadFiles(req.guestSession.guest.id);
  res.json({ files });
});

app.get('/guest/uploads/:filename', validateGuestUploadToken, (req, res) => {
  const filePath = findGuestUploadFile(req.guestSession.guest.id, req.params.filename);
  if (!filePath) {
    return res.status(404).send('File not found');
  }
  res.sendFile(filePath);
});

app.delete('/guest/uploads/:filename', validateGuestUploadToken, (req, res) => {
  const filePath = findGuestUploadFile(req.guestSession.guest.id, req.params.filename);
  if (!filePath) {
    return res.status(404).send('File not found');
  }

  try {
    fs.unlinkSync(filePath);
    res.json({ success: true });
  } catch (err) {
    console.error('Failed to delete guest upload:', err);
    res.status(500).send('Failed to delete file');
  }
});

// Legacy session routes (public)
app.post('/session', (req, res) => {
  const { name, room } = req.body;
  const code = generateCode();
  const guest = { name, room };
  const expires = Date.now() + getExpirationMinutes() * 60 * 1000;
  sessionCodes[code] = { guest, expires };
  saveSessions();
  res.json({ code });
});

app.get('/session/:code', (req, res) => {
  const { code } = req.params;
  const entry = sessionCodes[code];
  if (entry && entry.expires > Date.now()) {
    const guest = entry.guest;
    delete sessionCodes[code];
    saveSessions();
    res.json(guest);
  } else {
    res.status(404).send('Invalid or expired code');
  }
});

// ─── Admin-Protected Routes ─────────────────────────────────────────────────
// C1: All admin endpoints below require authMiddleware

app.post('/admin-api/admin-timeout', authMiddleware, (req, res) => {
  const { minutes } = req.body;
  config.adminSessionTimeoutMinutes = minutes;
  saveConfig();
  res.sendStatus(200);
});

app.get('/admin-api/deployment-status', authMiddleware, async (req, res) => {
  const checkUrls = req.query.checkUrls === 'true';
  const rooms = guestData.rooms || [];

  const dashboardChecks = await Promise.all(rooms.map(async room => ({
    name: room.name,
    dashboardUrl: room.dashboardUrl || null,
    ...(checkUrls
      ? await checkUrlReachability(room.dashboardUrl)
      : { checked: false, reachable: null, status: null, error: null })
  })));

  const now = new Date();
  const sessionCounts = countGuestSessionsByExpiry();

  res.json({
    generatedAt: now.toISOString(),
    app: {
      status: 'ok',
      version: packageInfo.version || 'unknown',
      nodeVersion: process.version,
      environment: process.env.NODE_ENV || 'development',
      uptimeSeconds: Math.round(process.uptime())
    },
    storage: getDirectoryStatus(getUploadsDir()),
    reverseProxy: getReverseProxyStatus(req),
    data: {
      rooms: rooms.length,
      registrationHistory: (guestData.guests || []).length,
      activeGuestSessions: sessionCounts.active,
      expiredGuestSessions: sessionCounts.expired,
      pendingSessionCodes: Object.values(sessionCodes).filter(entry => entry.expires > Date.now()).length
    },
    admin: {
      username: config.adminUser || 'admin'
    },
    dashboards: {
      checked: checkUrls,
      rooms: dashboardChecks
    }
  });
});

app.post('/admin-api/rooms', authMiddleware, (req, res) => {
  const { name, dashboardUrl } = req.body;
  if (!name || typeof name !== 'string' || name.length > 100 || /[^\w\s-]/.test(name)) {
    return res.status(400).send('Invalid room name');
  }
  if (!dashboardUrl || typeof dashboardUrl !== 'string' || dashboardUrl.length > 500) {
    return res.status(400).send('Invalid dashboard URL');
  }
  try {
    const parsedDashboardUrl = new URL(dashboardUrl);
    if (!['http:', 'https:'].includes(parsedDashboardUrl.protocol)) {
      return res.status(400).send('Dashboard URL must use http or https');
    }
  } catch {
    return res.status(400).send('Invalid dashboard URL format');
  }
  const index = guestData.rooms.findIndex(r => r.name === name);
  if (index >= 0) guestData.rooms[index].dashboardUrl = dashboardUrl;
  else guestData.rooms.push({ name, dashboardUrl });
  saveGuestData();
  res.sendStatus(200);
});

app.delete('/admin-api/rooms/:name', authMiddleware, (req, res) => {
  guestData.rooms = guestData.rooms.filter(r => r.name !== req.params.name);
  saveGuestData();
  res.sendStatus(200);
});

app.use('/admin/uploads', authMiddleware, (req, res, next) => {
  express.static(getUploadsDir())(req, res, next);
});

// Upload path configuration
app.get('/admin-api/upload-path', authMiddleware, (req, res) => {
  const uploadsDir = getUploadsDir();
  let writable = false;
  let exists = false;
  try {
    exists = fs.existsSync(uploadsDir);
    if (exists) {
      fs.accessSync(uploadsDir, fs.constants.W_OK);
      writable = true;
    }
  } catch {}
  res.json({ path: uploadsDir, exists, writable });
});

app.post('/admin-api/upload-path', authMiddleware, (req, res) => {
  const { path: newPath } = req.body;

  // Empty path resets to default
  if (!newPath || newPath.trim() === '') {
    delete config.uploadDir;
    saveConfig();
    const defaultDir = path.join(__dirname, 'uploads');
    fs.mkdirSync(path.join(defaultDir, 'backgrounds'), { recursive: true });
    return res.json({ success: true, path: defaultDir });
  }

  if (typeof newPath !== 'string' || newPath.length > 500) {
    return res.status(400).send('Invalid path');
  }

  const resolved = path.resolve(newPath);

  // Validate the directory exists and is writable
  if (!fs.existsSync(resolved)) {
    return res.status(400).send('Directory does not exist. Create it and mount your NFS/SMB share first.');
  }

  try {
    fs.accessSync(resolved, fs.constants.W_OK);
  } catch {
    return res.status(400).send('Directory is not writable. Check permissions.');
  }

  config.uploadDir = resolved;
  saveConfig();

  // Ensure backgrounds subdirectory exists
  const bgDir = path.join(resolved, 'backgrounds');
  fs.mkdirSync(bgDir, { recursive: true });

  res.json({ success: true, path: resolved });
});

// List guest photo folders
app.get('/admin-api/uploads', authMiddleware, (req, res) => {
  const uploadsDir = getUploadsDir();
  if (!fs.existsSync(uploadsDir)) {
    return res.json({ folders: [] });
  }

  try {
    const entries = fs.readdirSync(uploadsDir, { withFileTypes: true });
    const folders = entries
      .filter(e => e.isDirectory() && e.name !== 'backgrounds')
      .map(e => {
        const folderPath = path.join(uploadsDir, e.name);
        const files = fs.readdirSync(folderPath).filter(f => {
          const stat = fs.statSync(path.join(folderPath, f));
          return stat.isFile();
        });
        const totalSize = files.reduce((sum, f) => {
          return sum + fs.statSync(path.join(folderPath, f)).size;
        }, 0);
        return {
          name: e.name,
          fileCount: files.length,
          totalSize,
          files: files.map(f => ({
            name: f,
            size: fs.statSync(path.join(folderPath, f)).size
          }))
        };
      })
      .filter(f => f.fileCount > 0)
      .sort((a, b) => b.name.localeCompare(a.name));

    res.json({ folders });
  } catch (err) {
    console.error('Failed to list uploads:', err);
    res.status(500).send('Failed to list uploads');
  }
});

// Download a single guest folder as zip
app.get('/admin-api/uploads/download/:folder', authMiddleware, (req, res) => {
  const uploadsDir = getUploadsDir();
  const folderName = req.params.folder;
  const folderPath = path.resolve(path.join(uploadsDir, folderName));

  if (!folderPath.startsWith(path.resolve(uploadsDir))) {
    return res.status(400).send('Invalid folder');
  }
  if (!fs.existsSync(folderPath) || !fs.statSync(folderPath).isDirectory()) {
    return res.status(404).send('Folder not found');
  }

  res.setHeader('Content-Type', 'application/zip');
  res.setHeader('Content-Disposition', `attachment; filename="${folderName}.zip"`);

  const archive = archiver('zip', { zlib: { level: 5 } });
  archive.on('error', err => {
    console.error('Archive error:', err);
    if (!res.headersSent) res.status(500).send('Archive failed');
  });
  archive.pipe(res);
  archive.directory(folderPath, folderName);
  archive.finalize();
});

// Download all guest photos as zip
app.get('/admin-api/uploads/download-all', authMiddleware, (req, res) => {
  const uploadsDir = getUploadsDir();
  if (!fs.existsSync(uploadsDir)) {
    return res.status(404).send('No uploads directory');
  }

  const entries = fs.readdirSync(uploadsDir, { withFileTypes: true });
  const folders = entries.filter(e => e.isDirectory() && e.name !== 'backgrounds');

  if (folders.length === 0) {
    return res.status(404).send('No guest photos to download');
  }

  const date = new Date().toISOString().split('T')[0];
  res.setHeader('Content-Type', 'application/zip');
  res.setHeader('Content-Disposition', `attachment; filename="guest-photos-${date}.zip"`);

  const archive = archiver('zip', { zlib: { level: 5 } });
  archive.on('error', err => {
    console.error('Archive error:', err);
    if (!res.headersSent) res.status(500).send('Archive failed');
  });
  archive.pipe(res);

  folders.forEach(e => {
    archive.directory(path.join(uploadsDir, e.name), e.name);
  });
  archive.finalize();
});

// Delete a single guest photo folder
app.delete('/admin-api/uploads/:folder', authMiddleware, (req, res) => {
  const uploadsDir = getUploadsDir();
  const folderName = req.params.folder;
  const folderPath = path.resolve(path.join(uploadsDir, folderName));

  if (!folderPath.startsWith(path.resolve(uploadsDir))) {
    return res.status(400).send('Invalid folder');
  }
  if (folderName === 'backgrounds') {
    return res.status(400).send('Cannot delete backgrounds folder');
  }
  if (!fs.existsSync(folderPath) || !fs.statSync(folderPath).isDirectory()) {
    return res.status(404).send('Folder not found');
  }

  try {
    fs.rmSync(folderPath, { recursive: true, force: true });
    res.json({ success: true });
  } catch (err) {
    console.error('Failed to delete folder:', err);
    res.status(500).send('Failed to delete folder');
  }
});

// Delete all guest photo folders
app.delete('/admin-api/uploads', authMiddleware, (req, res) => {
  const uploadsDir = getUploadsDir();
  if (!fs.existsSync(uploadsDir)) {
    return res.json({ success: true, deleted: 0 });
  }

  try {
    const entries = fs.readdirSync(uploadsDir, { withFileTypes: true });
    const folders = entries.filter(e => e.isDirectory() && e.name !== 'backgrounds');
    let deleted = 0;

    folders.forEach(e => {
      const folderPath = path.join(uploadsDir, e.name);
      fs.rmSync(folderPath, { recursive: true, force: true });
      deleted++;
    });

    res.json({ success: true, deleted });
  } catch (err) {
    console.error('Failed to delete folders:', err);
    res.status(500).send('Failed to delete folders');
  }
});

// M6: GET endpoint to retrieve current admin timeout setting
app.get('/admin-api/admin-timeout', authMiddleware, (req, res) => {
  res.json({ minutes: getAdminTimeoutMinutes() });
});

app.post('/admin-api/background', authMiddleware, bgUpload.single('background'), (req, res) => {
  if (!req.file) {
    return res.status(400).send('No image uploaded');
  }
  config.backgroundImage = `/uploads/backgrounds/${req.file.filename}`;
  saveConfig();
  res.json({ success: true, path: config.backgroundImage });
});

// C6: Validate resolved path stays within uploads directory
app.delete('/admin-api/background', authMiddleware, (req, res) => {
  if (config.backgroundImage) {
    const uploadsDir = path.resolve(getUploadsDir());
    const bgPath = path.resolve(path.join(uploadsDir, 'backgrounds', path.basename(config.backgroundImage)));
    if (bgPath.startsWith(uploadsDir) && fs.existsSync(bgPath)) {
      fs.unlinkSync(bgPath);
    }
    delete config.backgroundImage;
    saveConfig();
  }
  res.json({ success: true });
});

app.post('/admin-api/session-expiration', authMiddleware, (req, res) => {
  const { minutes } = req.body;
  if (minutes && typeof minutes === 'number' && minutes > 0) {
    config.sessionExpirationMinutes = minutes;
    saveConfig();
  }
  res.sendStatus(200);
});

// C4: Remove fullToken from response
app.get('/admin-api/guest-sessions', authMiddleware, (req, res) => {
  const now = new Date();
  const sessions = Object.entries(guestTokens)
    .map(([token, guest]) => ({
      token: token.substring(0, 8) + '...',
      ...guest,
      isExpired: new Date(guest.checkoutDate) < now,
      daysRemaining: Math.ceil((new Date(guest.checkoutDate) - now) / (1000 * 60 * 60 * 24))
    }))
    .sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt));

  res.json(sessions);
});

app.post('/admin-api/guest-sessions/:guestId/extend', authMiddleware, (req, res) => {
  const { guestId } = req.params;
  const { days } = req.body;

  const entry = findGuestTokenEntryByGuestId(guestId);
  if (!entry) {
    return res.status(404).send('Guest not found');
  }

  const [, guest] = entry;
  const newCheckout = new Date(guest.checkoutDate);
  newCheckout.setDate(newCheckout.getDate() + (parseInt(days, 10) || 1));
  guest.checkoutDate = newCheckout.toISOString();
  saveGuestTokens();

  res.json({ success: true, newCheckoutDate: guest.checkoutDate });
});

app.patch('/admin-api/guest-sessions/:guestId', authMiddleware, (req, res) => {
  const { guestId } = req.params;
  const { room } = req.body;

  const validationError = validateGuestNameAndRoom('Guest', room);
  if (validationError) {
    return res.status(400).send('Invalid room');
  }
  if (!guestData.rooms.some(r => r.name === room)) {
    return res.status(400).send('Room not found');
  }

  const entry = findGuestTokenEntryByGuestId(guestId);
  if (!entry) {
    return res.status(404).send('Guest not found');
  }

  const [, guest] = entry;
  guest.room = room;
  guest.dashboardUrl = resolveRoomDashboard(room);
  saveGuestTokens();

  const historyEntry = (guestData.guests || []).find(g => g.guestId === guestId);
  if (historyEntry) {
    historyEntry.room = room;
    saveGuestData();
  }

  res.json({
    success: true,
    guest: {
      id: guest.id,
      name: guest.name,
      room: guest.room,
      dashboardUrl: guest.dashboardUrl,
      checkoutDate: guest.checkoutDate
    }
  });
});

app.delete('/admin-api/guest-sessions/:guestId/devices', authMiddleware, (req, res) => {
  const { guestId } = req.params;
  const entry = findGuestTokenEntryByGuestId(guestId);
  if (!entry) {
    return res.status(404).send('Guest not found');
  }

  const [, guest] = entry;
  guest.devices = [];
  saveGuestTokens();

  res.json({ success: true, devicesCleared: true });
});

app.delete('/admin-api/guest-sessions/:guestId', authMiddleware, (req, res) => {
  const { guestId } = req.params;

  const entry = findGuestTokenEntryByGuestId(guestId);
  if (!entry) {
    return res.status(404).send('Guest not found');
  }

  const [token] = entry;
  delete guestTokens[token];
  saveGuestTokens();

  res.json({ success: true });
});

app.post('/admin-api/guest-sessions/purge-expired', authMiddleware, (req, res) => {
  const now = new Date();
  let removed = 0;
  Object.entries(guestTokens).forEach(([token, guest]) => {
    if (new Date(guest.checkoutDate) < now) {
      delete guestTokens[token];
      removed += 1;
    }
  });
  if (removed > 0) {
    saveGuestTokens();
  }
  res.json({ success: true, removed });
});

app.get('/admin-api/guests', authMiddleware, (req, res) => {
  const now = new Date();
  const activeGuestIds = new Set(
    Object.values(guestTokens)
      .filter(guest => new Date(guest.checkoutDate) >= now)
      .map(guest => guest.id)
  );

  const guests = (guestData.guests || [])
    .map(entry => ({
      ...entry,
      hasActiveSession: activeGuestIds.has(entry.guestId)
    }))
    .sort((a, b) => new Date(b.timestamp) - new Date(a.timestamp));

  res.json(guests);
});

app.post('/admin-api/guests', authMiddleware, (req, res) => {
  const { name, room, stayDays } = req.body;
  const validationError = validateGuestNameAndRoom(name, room);
  if (validationError) {
    return res.status(400).send(validationError);
  }
  if (!guestData.rooms.some(r => r.name === room)) {
    return res.status(400).send('Room not found');
  }

  const registration = createGuestRegistration(name, room, stayDays, 'Admin registration');
  res.json({
    success: true,
    token: registration.token,
    guest: registration.guest
  });
});

app.delete('/admin-api/guests/:guestId', authMiddleware, (req, res) => {
  const { guestId } = req.params;
  const endSession = req.query.endSession === 'true';

  const beforeCount = (guestData.guests || []).length;
  guestData.guests = (guestData.guests || []).filter(g => g.guestId !== guestId);
  if (guestData.guests.length === beforeCount) {
    return res.status(404).send('Registration history entry not found');
  }
  saveGuestData();

  let sessionEnded = false;
  if (endSession) {
    const entry = findGuestTokenEntryByGuestId(guestId);
    if (entry) {
      const [token] = entry;
      delete guestTokens[token];
      saveGuestTokens();
      sessionEnded = true;
    }
  }

  res.json({ success: true, sessionEnded });
});

app.post('/admin-api/guests/purge-history', authMiddleware, (req, res) => {
  const { inactiveOnly } = req.body || {};
  const now = new Date();
  const activeGuestIds = new Set(
    Object.values(guestTokens)
      .filter(guest => new Date(guest.checkoutDate) >= now)
      .map(guest => guest.id)
  );

  const beforeCount = (guestData.guests || []).length;
  if (inactiveOnly) {
    guestData.guests = (guestData.guests || []).filter(entry => activeGuestIds.has(entry.guestId));
  } else {
    guestData.guests = [];
  }
  const removed = beforeCount - guestData.guests.length;
  saveGuestData();

  res.json({ success: true, removed });
});

app.get('/api/guests', authMiddleware, (req, res) => res.json(guestData));

app.get('/admin-api/sessions', authMiddleware, (req, res) => {
  const now = Date.now();
  const result = Object.entries(sessionCodes).map(([code, { guest, expires }]) => ({
    code,
    guest,
    minutesLeft: (expires - now) / 60000
  })).filter(s => s.minutesLeft > 0);
  res.json(result);
});

app.delete('/admin-api/sessions/:code', authMiddleware, (req, res) => {
  delete sessionCodes[req.params.code];
  saveSessions();
  res.sendStatus(200);
});

// ─── Start Server ───────────────────────────────────────────────────────────

const server = app.listen(port, () => {
  console.log(`Guest Portal backend is running at http://localhost:${port}`);
});

// L4: Graceful shutdown — close server and flush pending writes
function shutdown(signal) {
  console.log(`\n${signal} received. Shutting down gracefully...`);
  server.close(() => {
    console.log('Server closed.');
    process.exit(0);
  });
  setTimeout(() => {
    console.error('Forced shutdown after timeout.');
    process.exit(1);
  }, 5000);
}

process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));
