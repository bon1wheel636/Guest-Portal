
// server.js - v1.0.2 security patched
const express = require('express');
const multer = require('multer');
const path = require('path');
const fs = require('fs');
const cors = require('cors');
const basicAuth = require('basic-auth');
const bcrypt = require('bcrypt');
const rateLimit = require('express-rate-limit');
const app = express();

// Security: Sanitize filenames and paths to prevent directory traversal
function sanitizeFilename(filename) {
  // Remove path separators and null bytes
  return filename
    .replace(/[/\\]/g, '_')
    .replace(/\.\./g, '_')
    .replace(/\0/g, '')
    .replace(/[<>:"|?*]/g, '_')
    .substring(0, 255);
}

function sanitizeName(name) {
  // Allow only alphanumeric, spaces, hyphens, and underscores
  return name
    .replace(/[^\w\s-]/g, '')
    .replace(/\s+/g, '-')
    .substring(0, 100);
}

// PATCH: Load session timeout from config
function getExpirationMinutes() {
  return config.sessionExpirationMinutes || 10;
}

function getAdminTimeoutMinutes() {
  return config.adminSessionTimeoutMinutes || 15;
}

// PATCH: Save config
function saveConfig() {
  fs.writeFileSync(configPath, JSON.stringify(config, null, 2));
}

// Middleware setup (must be before routes)
app.use(cors());
app.use(express.json());
app.use(express.static('frontend'));

// Check if admin setup is needed (no password configured)
app.get('/admin-api/setup-required', (req, res) => {
  const needsSetup = !config.adminHash || config.adminHash === '<bcrypt_hash_placeholder>';
  res.json({ setupRequired: needsSetup });
});

// First-run admin setup (only works if no password is set)
app.post('/admin-api/setup', async (req, res) => {
  // Only allow setup if no admin password is configured
  if (config.adminHash && config.adminHash !== '<bcrypt_hash_placeholder>') {
    return res.status(403).send('Admin already configured. Use setup-local.sh to reset.');
  }

  const { username, password } = req.body;

  // Validate input
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

// PATCH: Admin login check
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

// PATCH: Save admin session timeout
app.post('/admin-api/admin-timeout', (req, res) => {
  const { minutes } = req.body;
  config.adminSessionTimeoutMinutes = minutes;
  saveConfig();
  res.sendStatus(200);
});

// PATCH: Health check
app.get('/health', (req, res) => {
  res.json({ status: 'ok' });
});

const port = 3000;

const configPath = '/etc/guest-portal/config.json';
const dbPath = '/etc/guest-portal/storage.json';
const sessionFile = '/etc/guest-portal/sessions.json';
const guestTokensFile = '/etc/guest-portal/guest-tokens.json';

const config = fs.existsSync(configPath) ? require(configPath) : {};
const guestData = fs.existsSync(dbPath) ? JSON.parse(fs.readFileSync(dbPath)) : { rooms: [], guests: [] };
let sessionCodes = fs.existsSync(sessionFile) ? JSON.parse(fs.readFileSync(sessionFile)) : {};
let guestTokens = fs.existsSync(guestTokensFile) ? JSON.parse(fs.readFileSync(guestTokensFile)) : {};

// REMOVED: static session expiration, replaced with dynamic config

function saveSessions() {
  fs.writeFileSync(sessionFile, JSON.stringify(sessionCodes, null, 2));
}

function saveGuestTokens() {
  fs.writeFileSync(guestTokensFile, JSON.stringify(guestTokens, null, 2));
}

function generateCode() {
  return Math.random().toString(36).substring(2, 8).toUpperCase();
}

function generateToken() {
  return Math.random().toString(36).substring(2, 15) + Math.random().toString(36).substring(2, 15);
}

const limiter = rateLimit({
  windowMs: 60 * 1000,
  max: 60
});
app.use(limiter);

const storage = multer.diskStorage({
  destination: (req, file, cb) => {
    const name = sanitizeName(req.body.guestName || 'anonymous');
    const folderName = `${name}-${new Date().toISOString().split('T')[0]}`;
    const dir = path.join(__dirname, 'uploads', folderName);
    // Verify the resolved path is within uploads directory
    const uploadsDir = path.join(__dirname, 'uploads');
    if (!dir.startsWith(uploadsDir)) {
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

app.post('/upload', upload.array('photos', 10), (req, res) => res.sendStatus(200));

app.post('/register', (req, res) => {
  const { name, room, stayDays } = req.body;
  if (!name || !room || /[^\w\s]/.test(name) || /[^\w\s]/.test(room)) {
    return res.status(400).send('Invalid name or room');
  }

  // Calculate checkout date (default 7 days)
  const days = Math.min(Math.max(parseInt(stayDays) || 7, 1), 30); // 1-30 days
  const checkoutDate = new Date();
  checkoutDate.setDate(checkoutDate.getDate() + days);

  // Generate persistent guest token
  const token = generateToken();
  const guestId = `guest_${Date.now()}_${Math.random().toString(36).substring(2, 8)}`;

  // Find room dashboard URL
  const roomData = guestData.rooms.find(r => r.name === room);
  const dashboardUrl = roomData ? roomData.dashboardUrl : null;

  // Store guest with token
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

  // Also add to legacy guests list for backward compatibility
  guestData.guests.push({ name, room, timestamp: new Date().toISOString(), guestId });
  fs.writeFileSync(dbPath, JSON.stringify(guestData, null, 2));

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

// Validate and retrieve guest by token (for returning guests)
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

// Generate device link code (allows adding another device to existing session)
app.post('/guest/link-code', (req, res) => {
  const { token } = req.body;
  if (!token || !guestTokens[token]) {
    return res.status(404).send('Invalid token');
  }

  const guest = guestTokens[token];
  const linkCode = generateCode();
  const expires = Date.now() + 30 * 60 * 1000; // 30 minutes for device linking

  sessionCodes[linkCode] = {
    type: 'device-link',
    guestToken: token,
    guestId: guest.id,
    expires
  };
  saveSessions();

  res.json({ code: linkCode, expiresIn: '30 minutes' });
});

// Use device link code to join existing session
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

  // Add device to guest's device list
  guest.devices.push({
    addedAt: new Date().toISOString(),
    userAgent: req.get('User-Agent') || 'Unknown'
  });
  saveGuestTokens();

  // Invalidate the link code (one-time use)
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

// Admin: Get all active guest sessions
app.get('/admin-api/guest-sessions', (req, res) => {
  const now = new Date();
  const sessions = Object.entries(guestTokens)
    .map(([token, guest]) => ({
      token: token.substring(0, 8) + '...', // Truncate for security
      fullToken: token,
      ...guest,
      isExpired: new Date(guest.checkoutDate) < now,
      daysRemaining: Math.ceil((new Date(guest.checkoutDate) - now) / (1000 * 60 * 60 * 24))
    }))
    .sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt));

  res.json(sessions);
});

// Admin: Extend or update guest checkout
app.post('/admin-api/guest-sessions/:guestId/extend', (req, res) => {
  const { guestId } = req.params;
  const { days } = req.body;

  const entry = Object.entries(guestTokens).find(([_, g]) => g.id === guestId);
  if (!entry) {
    return res.status(404).send('Guest not found');
  }

  const [token, guest] = entry;
  const newCheckout = new Date(guest.checkoutDate);
  newCheckout.setDate(newCheckout.getDate() + (parseInt(days) || 1));
  guest.checkoutDate = newCheckout.toISOString();
  saveGuestTokens();

  res.json({ success: true, newCheckoutDate: guest.checkoutDate });
});

// Admin: Remove/checkout a guest
app.delete('/admin-api/guest-sessions/:guestId', (req, res) => {
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

app.get('/api/guests', (req, res) => res.json(guestData));

app.get('/admin-api/rooms', (req, res) => res.json(guestData.rooms || []));

app.post('/admin-api/rooms', (req, res) => {
  const { name, dashboardUrl } = req.body;
  // Validate room name (alphanumeric, spaces, hyphens only)
  if (!name || typeof name !== 'string' || name.length > 100 || /[^\w\s-]/.test(name)) {
    return res.status(400).send('Invalid room name');
  }
  // Validate dashboard URL
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
  fs.writeFileSync(dbPath, JSON.stringify(guestData, null, 2));
  res.sendStatus(200);
});

app.delete('/admin-api/rooms/:name', (req, res) => {
  guestData.rooms = guestData.rooms.filter(r => r.name !== req.params.name);
  fs.writeFileSync(dbPath, JSON.stringify(guestData, null, 2));
  res.sendStatus(200);
});

app.use('/admin/uploads', authMiddleware, express.static(path.join(__dirname, 'uploads')));

app.post('/admin-api/uploadDir', (req, res) => {
  const { path: newPath } = req.body;
  config.uploadDir = newPath;
  fs.writeFileSync(configPath, JSON.stringify(config, null, 2));
  res.sendStatus(200);
});

// Background image upload for landing page
const bgStorage = multer.diskStorage({
  destination: (req, file, cb) => {
    const dir = path.join(__dirname, 'uploads', 'backgrounds');
    fs.mkdirSync(dir, { recursive: true });
    cb(null, dir);
  },
  filename: (req, file, cb) => {
    const ext = path.extname(file.originalname).toLowerCase();
    cb(null, `background${ext}`);
  }
});
const bgUpload = multer({
  storage: bgStorage,
  fileFilter: (req, file, cb) => {
    const allowedTypes = ['image/jpeg', 'image/png', 'image/gif', 'image/webp'];
    if (allowedTypes.includes(file.mimetype)) {
      cb(null, true);
    } else {
      cb(new Error('Only image files are allowed'));
    }
  },
  limits: { fileSize: 5 * 1024 * 1024 } // 5MB limit
});

app.post('/admin-api/background', bgUpload.single('background'), (req, res) => {
  if (!req.file) {
    return res.status(400).send('No image uploaded');
  }
  config.backgroundImage = `/uploads/backgrounds/${req.file.filename}`;
  saveConfig();
  res.json({ success: true, path: config.backgroundImage });
});

app.get('/admin-api/background', (req, res) => {
  res.json({ backgroundImage: config.backgroundImage || null });
});

app.delete('/admin-api/background', (req, res) => {
  if (config.backgroundImage) {
    const bgPath = path.join(__dirname, config.backgroundImage);
    if (fs.existsSync(bgPath)) {
      fs.unlinkSync(bgPath);
    }
    delete config.backgroundImage;
    saveConfig();
  }
  res.json({ success: true });
});

// Serve background images publicly
app.use('/uploads/backgrounds', express.static(path.join(__dirname, 'uploads', 'backgrounds')));

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
    // One-time use: invalidate session code after retrieval
    delete sessionCodes[code];
    saveSessions();
    res.json(guest);
  } else {
    res.status(404).send('Invalid or expired code');
  }
});

app.post('/admin-api/session-expiration', (req, res) => {
  res.sendStatus(200); // Placeholder; expiration is static in this version
});

app.get('/admin-api/sessions', (req, res) => {
  const now = Date.now();
  const result = Object.entries(sessionCodes).map(([code, { guest, expires }]) => ({
    code,
    guest,
    minutesLeft: (expires - now) / 60000
  })).filter(s => s.minutesLeft > 0);
  res.json(result);
});

app.delete('/admin-api/sessions/:code', (req, res) => {
  delete sessionCodes[req.params.code];
  saveSessions();
  res.sendStatus(200);
});

app.listen(port, () => {
  console.log(`Guest Portal backend is running at http://localhost:${port}`);
});
