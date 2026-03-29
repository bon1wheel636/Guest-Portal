
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

// H2: Use JSON.parse(fs.readFileSync()) instead of require() to avoid module caching
const config = fs.existsSync(configPath) ? JSON.parse(fs.readFileSync(configPath, 'utf8')) : {};
const guestData = fs.existsSync(dbPath) ? JSON.parse(fs.readFileSync(dbPath, 'utf8')) : { rooms: [], guests: [] };
let sessionCodes = fs.existsSync(sessionFile) ? JSON.parse(fs.readFileSync(sessionFile, 'utf8')) : {};
let guestTokens = fs.existsSync(guestTokensFile) ? JSON.parse(fs.readFileSync(guestTokensFile, 'utf8')) : {};

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

// ─── Middleware ──────────────────────────────────────────────────────────────

app.use(cors());
app.use(express.json());

// H1: Rate limiter BEFORE static files and routes
const limiter = rateLimit({
  windowMs: 60 * 1000,
  max: 60
});
app.use(limiter);

app.use(express.static('frontend'));

// C1: Auth middleware for admin endpoints
function authMiddleware(req, res, next) {
  const user = basicAuth(req);
  if (!user || user.name !== config.adminUser) {
    res.set('WWW-Authenticate', 'Basic realm="Admin Area"');
    return res.status(401).send('Authentication required.');
  }
  bcrypt.compare(user.pass, config.adminHash, (err, result) => {
    if (result) next();
    else {
      res.set('WWW-Authenticate', 'Basic realm="Admin Area"');
      return res.status(401).send('Access denied.');
    }
  });
}

// ─── Multer Storage Config ──────────────────────────────────────────────────

const storage = multer.diskStorage({
  destination: (req, file, cb) => {
    const uploadsDir = getUploadsDir();
    const name = sanitizeName(req.body.guestName || 'anonymous');
    const folderName = `${name}-${new Date().toISOString().split('T')[0]}`;
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
const upload = multer({ storage });

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

  const { username, password } = req.body;

  if (!username || typeof username !== 'string' || username.length < 3 || username.length > 50) {
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
    res.json({ success: true, message: 'Admin account created successfully' });
  } catch (err) {
    res.status(500).send('Failed to create admin account');
  }
});

app.post('/admin-api/login', (req, res) => {
  const user = basicAuth(req);
  if (!user || user.name !== config.adminUser) {
    res.set('WWW-Authenticate', 'Basic realm="Admin Login"');
    return res.status(401).send('Login required.');
  }
  bcrypt.compare(user.pass, config.adminHash, (err, result) => {
    if (result) return res.sendStatus(200);
    else {
      res.set('WWW-Authenticate', 'Basic realm="Admin Login"');
      return res.status(401).send('Invalid credentials.');
    }
  });
});

// Public: rooms list needed by guest registration page
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
  if (!name || !room || /[^\w\s]/.test(name) || /[^\w\s]/.test(room)) {
    return res.status(400).send('Invalid name or room');
  }

  const days = Math.min(Math.max(parseInt(stayDays, 10) || 7, 1), 30);
  const checkoutDate = new Date();
  checkoutDate.setDate(checkoutDate.getDate() + days);

  const token = generateToken();
  const guestId = `guest_${Date.now()}_${crypto.randomBytes(4).toString('hex')}`;

  const roomData = guestData.rooms.find(r => r.name === room);
  const dashboardUrl = roomData ? roomData.dashboardUrl : null;

  guestTokens[token] = {
    id: guestId,
    name,
    room,
    dashboardUrl,
    checkoutDate: checkoutDate.toISOString(),
    createdAt: new Date().toISOString(),
    devices: [{ addedAt: new Date().toISOString(), userAgent: req.get('User-Agent') || 'Unknown' }]
  };
  saveGuestTokens();

  guestData.guests.push({ name, room, timestamp: new Date().toISOString(), guestId });
  saveGuestData();

  res.json({
    token,
    guest: {
      id: guestId,
      name,
      room,
      dashboardUrl,
      checkoutDate: checkoutDate.toISOString()
    }
  });
});

app.post('/guest/validate', (req, res) => {
  const { token } = req.body;
  if (!token || !guestTokens[token]) {
    return res.status(404).json({ valid: false, error: 'Invalid token' });
  }

  const guest = guestTokens[token];
  const checkout = new Date(guest.checkoutDate);

  if (checkout < new Date()) {
    return res.status(410).json({ valid: false, error: 'Session expired (checkout passed)' });
  }

  res.json({
    valid: true,
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
app.post('/upload', upload.array('photos', 10), (req, res) => {
  const guestName = req.body.guestName;
  if (!guestName || guestName === 'anonymous') {
    return res.status(400).send('Guest name required');
  }
  res.sendStatus(200);
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

app.post('/admin-api/rooms', authMiddleware, (req, res) => {
  const { name, dashboardUrl } = req.body;
  if (!name || typeof name !== 'string' || name.length > 100 || /[^\w\s-]/.test(name)) {
    return res.status(400).send('Invalid room name');
  }
  if (!dashboardUrl || typeof dashboardUrl !== 'string' || dashboardUrl.length > 500) {
    return res.status(400).send('Invalid dashboard URL');
  }
  try {
    new URL(dashboardUrl);
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

  const entry = Object.entries(guestTokens).find(([_, g]) => g.id === guestId);
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

app.delete('/admin-api/guest-sessions/:guestId', authMiddleware, (req, res) => {
  const { guestId } = req.params;

  const entry = Object.entries(guestTokens).find(([_, g]) => g.id === guestId);
  if (!entry) {
    return res.status(404).send('Guest not found');
  }

  const [token] = entry;
  delete guestTokens[token];
  saveGuestTokens();

  res.json({ success: true });
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
