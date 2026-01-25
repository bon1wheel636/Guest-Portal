
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

const config = fs.existsSync(configPath) ? require(configPath) : {};
const guestData = fs.existsSync(dbPath) ? JSON.parse(fs.readFileSync(dbPath)) : { rooms: [], guests: [] };
let sessionCodes = fs.existsSync(sessionFile) ? JSON.parse(fs.readFileSync(sessionFile)) : {};

// REMOVED: static session expiration, replaced with dynamic config

function saveSessions() {
  fs.writeFileSync(sessionFile, JSON.stringify(sessionCodes, null, 2));
}

function generateCode() {
  return Math.random().toString(36).substring(2, 8).toUpperCase();
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
  const { name, room } = req.body;
  if (!name || !room || /[^\w\s]/.test(name) || /[^\w\s]/.test(room)) {
    return res.status(400).send('Invalid name or room');
  }
  guestData.guests.push({ name, room, timestamp: new Date().toISOString() });
  fs.writeFileSync(dbPath, JSON.stringify(guestData, null, 2));
  res.sendStatus(200);
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
  if (entry && entry.expires > Date.now()) res.json(entry.guest);
  else res.status(404).send('Invalid or expired code');
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
