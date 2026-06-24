
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
const QRCode = require('qrcode');
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
const MAX_GUEST_NOTE_LENGTH = 5000;

// H2: Use JSON.parse(fs.readFileSync()) instead of require() to avoid module caching
const config = fs.existsSync(configPath) ? JSON.parse(fs.readFileSync(configPath, 'utf8')) : {};
const guestData = fs.existsSync(dbPath) ? JSON.parse(fs.readFileSync(dbPath, 'utf8')) : { rooms: [], guests: [], events: [], guestTypes: [], guestNotes: [] };
let sessionCodes = fs.existsSync(sessionFile) ? JSON.parse(fs.readFileSync(sessionFile, 'utf8')) : {};
let guestTokens = fs.existsSync(guestTokensFile) ? JSON.parse(fs.readFileSync(guestTokensFile, 'utf8')) : {};
const packageJsonPath = path.join(__dirname, 'package.json');
const packageInfo = fs.existsSync(packageJsonPath) ? JSON.parse(fs.readFileSync(packageJsonPath, 'utf8')) : {};

const DEFAULT_GUEST_TYPES = [
  {
    id: 'type_overnight',
    name: 'Overnight Guest',
    description: 'Staying one or more nights',
    visitMode: 'overnight',
    defaultStayDays: 7,
    requiresRoom: true,
    enabled: true,
    permissions: {
      uploadPhotos: true,
      deleteOwnPhotos: true,
      viewPhotoGallery: true,
      smartHomeControls: true,
      linkDevice: true,
      extendStay: false,
      selectStayLength: true,
      selectEventAtRegistration: false,
      tagPhotosToEvent: true,
      createEventNames: true,
      viewWelcomeHub: true,
      signOut: true,
      leaveGuestNote: true
    }
  },
  {
    id: 'type_day_personal',
    name: 'Day Visitor — Personal',
    description: 'Friends and family visiting for the day',
    visitMode: 'day',
    defaultDayVisitHours: 8,
    requiresRoom: false,
    enabled: true,
    permissions: {
      uploadPhotos: true,
      deleteOwnPhotos: true,
      viewPhotoGallery: true,
      smartHomeControls: false,
      linkDevice: true,
      extendStay: false,
      selectStayLength: false,
      selectEventAtRegistration: true,
      tagPhotosToEvent: true,
      createEventNames: true,
      viewWelcomeHub: true,
      signOut: true,
      leaveGuestNote: true
    }
  },
  {
    id: 'type_day_business',
    name: 'Day Visitor — Business',
    description: 'Sales, service, or business appointments',
    visitMode: 'day',
    defaultDayVisitHours: 4,
    requiresRoom: false,
    enabled: true,
    permissions: {
      uploadPhotos: false,
      deleteOwnPhotos: false,
      viewPhotoGallery: false,
      smartHomeControls: false,
      linkDevice: false,
      extendStay: false,
      selectStayLength: false,
      selectEventAtRegistration: false,
      tagPhotosToEvent: false,
      createEventNames: false,
      viewWelcomeHub: true,
      signOut: true,
      leaveGuestNote: true
    }
  }
];

const PERMISSION_KEYS = [
  'uploadPhotos',
  'deleteOwnPhotos',
  'viewPhotoGallery',
  'smartHomeControls',
  'linkDevice',
  'extendStay',
  'selectStayLength',
  'selectEventAtRegistration',
  'tagPhotosToEvent',
  'createEventNames',
  'viewWelcomeHub',
  'signOut',
  'leaveGuestNote'
];

const RESTRICTED_FALLBACK_PERMISSIONS = {
  uploadPhotos: false,
  deleteOwnPhotos: false,
  viewPhotoGallery: false,
  smartHomeControls: false,
  linkDevice: false,
  extendStay: false,
  selectStayLength: false,
  selectEventAtRegistration: false,
  tagPhotosToEvent: false,
  createEventNames: false,
  viewWelcomeHub: true,
  signOut: true,
  leaveGuestNote: false
};

function ensureStorageDefaults() {
  let changed = false;
  if (!Array.isArray(guestData.events)) {
    guestData.events = [];
    changed = true;
  }
  if (!Array.isArray(guestData.guestNotes)) {
    guestData.guestNotes = [];
    changed = true;
  }
  if (!Array.isArray(guestData.guestTypes) || guestData.guestTypes.length === 0) {
    guestData.guestTypes = JSON.parse(JSON.stringify(DEFAULT_GUEST_TYPES));
    changed = true;
  } else {
    guestData.guestTypes.forEach(type => {
      if (type.permissions && !Object.prototype.hasOwnProperty.call(type.permissions, 'leaveGuestNote')) {
        type.permissions.leaveGuestNote = true;
        changed = true;
      }
    });
  }
  if (changed) {
    saveGuestData();
  }
}

ensureStorageDefaults();

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

function formatExpirationLabel(minutes) {
  const value = Number(minutes);
  if (!Number.isFinite(value) || value <= 0) return '10 minutes';
  return value === 1 ? '1 minute' : `${value} minutes`;
}

function getLinkCodeExpirationMs() {
  return getExpirationMinutes() * 60 * 1000;
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

function validateGuestName(name) {
  if (!name || typeof name !== 'string') {
    return 'Invalid name';
  }
  if (/[^\w\s]/.test(name)) {
    return 'Invalid name';
  }
  return null;
}

function validateGuestRoom(room) {
  if (!room || typeof room !== 'string') {
    return 'Invalid room';
  }
  if (/[^\w\s]/.test(room)) {
    return 'Invalid room';
  }
  return null;
}

function validateGuestNameAndRoom(name, room) {
  const nameError = validateGuestName(name);
  if (nameError) return nameError;
  const roomError = validateGuestRoom(room);
  if (roomError) return roomError;
  return null;
}

function validateGuestNoteText(text) {
  if (typeof text !== 'string') {
    return { error: 'Note text is required', status: 400 };
  }
  const trimmed = text.trim();
  if (!trimmed) {
    return { error: 'Note text cannot be empty', status: 400 };
  }
  if (trimmed.length > MAX_GUEST_NOTE_LENGTH) {
    return { error: `Note text must be ${MAX_GUEST_NOTE_LENGTH} characters or fewer`, status: 400 };
  }
  return { text: trimmed };
}

function formatGuestNoteForResponse(note) {
  return {
    id: note.id,
    guestId: note.guestId,
    guestName: note.guestName,
    room: note.room || '',
    guestTypeId: note.guestTypeId || '',
    eventName: note.eventName || '',
    text: note.text,
    createdAt: note.createdAt,
    updatedAt: note.updatedAt
  };
}

function getGuestNoteByGuestId(guestId) {
  return (guestData.guestNotes || []).find(note => note.guestId === guestId) || null;
}

function getGuestNoteById(id) {
  return (guestData.guestNotes || []).find(note => note.id === id) || null;
}

function upsertGuestNote(guest, text) {
  if (!Array.isArray(guestData.guestNotes)) {
    guestData.guestNotes = [];
  }
  const now = new Date().toISOString();
  const existing = getGuestNoteByGuestId(guest.id);
  if (existing) {
    existing.text = text;
    existing.updatedAt = now;
    existing.guestName = guest.name || existing.guestName;
    existing.room = guest.room || '';
    existing.guestTypeId = guest.guestTypeId || existing.guestTypeId || '';
    existing.eventName = guest.eventName || '';
    saveGuestData();
    return existing;
  }

  const note = {
    id: `note_${Date.now()}_${crypto.randomBytes(4).toString('hex')}`,
    guestId: guest.id,
    guestName: guest.name || '',
    room: guest.room || '',
    guestTypeId: guest.guestTypeId || '',
    eventName: guest.eventName || '',
    text,
    createdAt: now,
    updatedAt: now
  };
  guestData.guestNotes.push(note);
  saveGuestData();
  return note;
}

function deleteGuestNoteByGuestId(guestId) {
  const notes = guestData.guestNotes || [];
  const index = notes.findIndex(note => note.guestId === guestId);
  if (index < 0) {
    return false;
  }
  notes.splice(index, 1);
  saveGuestData();
  return true;
}

function deleteGuestNoteById(id) {
  const notes = guestData.guestNotes || [];
  const index = notes.findIndex(note => note.id === id);
  if (index < 0) {
    return false;
  }
  notes.splice(index, 1);
  saveGuestData();
  return true;
}

function getGuestTypeById(id) {
  return (guestData.guestTypes || []).find(type => type.id === id) || null;
}

function getLegacyGuestType() {
  return getGuestTypeById('type_overnight') || DEFAULT_GUEST_TYPES[0];
}

function isGuestTypeMissing(guest) {
  if (!guest || !guest.guestTypeId) {
    return false;
  }
  const type = getGuestTypeById(guest.guestTypeId);
  return !type || !type.enabled;
}

function writePermissionsSnapshot(guest, guestType) {
  guest.permissionsSnapshot = normalizeGuestTypePermissions(
    guestType.permissions,
    guestType.visitMode
  );
}

function resolveGuestType(guest) {
  if (!guest) return getLegacyGuestType();
  if (!guest.guestTypeId) return getLegacyGuestType();

  const type = getGuestTypeById(guest.guestTypeId);
  if (type && type.enabled) {
    return type;
  }

  return {
    id: guest.guestTypeId,
    name: 'Unknown (restricted)',
    description: '',
    visitMode: guest.visitMode || 'overnight',
    requiresRoom: false,
    enabled: false,
    permissions: getGuestPermissions(guest)
  };
}

function getGuestPermissions(guest) {
  if (!guest) {
    return { ...RESTRICTED_FALLBACK_PERMISSIONS };
  }
  if (!guest.guestTypeId) {
    return { ...getLegacyGuestType().permissions };
  }

  const type = getGuestTypeById(guest.guestTypeId);
  if (type && type.enabled) {
    return { ...type.permissions };
  }

  if (guest.permissionsSnapshot) {
    return { ...guest.permissionsSnapshot };
  }
  return { ...RESTRICTED_FALLBACK_PERMISSIONS };
}

function getEnabledGuestTypeById(id) {
  const type = getGuestTypeById(id);
  if (!type || !type.enabled) return null;
  return type;
}

function normalizeGuestTypePermissions(permissions = {}, visitMode = 'overnight') {
  const normalized = {};
  PERMISSION_KEYS.forEach(key => {
    normalized[key] = Boolean(permissions[key]);
  });
  if (visitMode === 'day') {
    normalized.selectStayLength = false;
    normalized.extendStay = false;
  }
  return normalized;
}

function sanitizeGuestTypeInput(body, existing = null) {
  const visitMode = body.visitMode === 'day' ? 'day' : 'overnight';
  const type = {
    id: existing ? existing.id : (typeof body.id === 'string' && body.id.trim() ? body.id.trim() : `type_${Date.now()}_${crypto.randomBytes(3).toString('hex')}`),
    name: typeof body.name === 'string' ? body.name.trim().substring(0, 100) : '',
    description: typeof body.description === 'string' ? body.description.trim().substring(0, 500) : '',
    visitMode,
    requiresRoom: Boolean(body.requiresRoom),
    enabled: body.enabled !== false,
    permissions: normalizeGuestTypePermissions(body.permissions || {}, visitMode)
  };

  if (!type.name) {
    return { error: 'Guest type name is required' };
  }

  if (visitMode === 'overnight') {
    type.defaultStayDays = Math.min(Math.max(parseInt(body.defaultStayDays, 10) || 7, 1), 30);
  } else {
    type.defaultDayVisitHours = Math.min(Math.max(parseInt(body.defaultDayVisitHours, 10) || 8, 1), 24);
  }

  return { type };
}

function formatGuestTypeForPublic(type) {
  return {
    id: type.id,
    name: type.name,
    description: type.description || '',
    visitMode: type.visitMode,
    defaultStayDays: type.defaultStayDays,
    defaultDayVisitHours: type.defaultDayVisitHours,
    requiresRoom: Boolean(type.requiresRoom),
    permissions: {
      selectStayLength: Boolean(type.permissions.selectStayLength),
      selectEventAtRegistration: Boolean(type.permissions.selectEventAtRegistration),
      tagPhotosToEvent: Boolean(type.permissions.tagPhotosToEvent),
      createEventNames: Boolean(type.permissions.createEventNames)
    }
  };
}

function formatGuestResponse(guest) {
  const guestType = resolveGuestType(guest);
  const permissions = getGuestPermissions(guest);
  const missingType = isGuestTypeMissing(guest);
  return {
    id: guest.id,
    name: guest.name,
    room: guest.room || '',
    dashboardUrl: permissions.smartHomeControls ? (guest.dashboardUrl || null) : null,
    checkoutDate: guest.checkoutDate,
    guestTypeId: guest.guestTypeId || guestType.id,
    guestTypeName: missingType ? 'Unknown (restricted)' : guestType.name,
    visitMode: guest.visitMode || guestType.visitMode,
    eventName: guest.eventName || null,
    permissions
  };
}

function sanitizeEventSlug(name) {
  const slug = sanitizeName(name || 'General');
  return slug || 'General';
}

function resolveEventNameFromSlug(eventSlug) {
  const slug = sanitizeEventSlug(eventSlug);
  if (slug === 'General') {
    return 'General';
  }
  const match = (guestData.events || []).find(event => sanitizeEventSlug(event.name) === slug);
  return match ? match.name : slug.replace(/-/g, ' ');
}

function findEventByName(name) {
  const trimmed = (name || '').trim();
  if (!trimmed) return null;
  return (guestData.events || []).find(event => event.name.toLowerCase() === trimmed.toLowerCase()) || null;
}

function findEventById(id) {
  return (guestData.events || []).find(event => event.id === id) || null;
}

function createEventRecord(name, createdBy = 'admin') {
  const trimmed = (name || '').trim().substring(0, 100);
  if (!trimmed) {
    return { error: 'Event name is required' };
  }
  if (findEventByName(trimmed)) {
    return { error: 'Event already exists' };
  }

  const event = {
    id: `event_${Date.now()}_${crypto.randomBytes(4).toString('hex')}`,
    name: trimmed,
    createdAt: new Date().toISOString(),
    createdBy: createdBy || 'admin'
  };
  guestData.events.push(event);
  saveGuestData();
  return { event };
}

function forEachStayUploadFolder(callback) {
  const uploadsDir = getUploadsDir();
  if (!fs.existsSync(uploadsDir)) {
    return;
  }

  fs.readdirSync(uploadsDir, { withFileTypes: true })
    .filter(entry => entry.isDirectory() && entry.name !== 'backgrounds')
    .forEach(entry => callback(path.join(uploadsDir, entry.name)));
}

function countEventFilesOnDisk(eventSlug) {
  let count = 0;
  forEachStayUploadFolder(stayPath => {
    const eventDir = path.join(stayPath, eventSlug);
    if (!fs.existsSync(eventDir) || !fs.statSync(eventDir).isDirectory()) {
      return;
    }
    fs.readdirSync(eventDir, { withFileTypes: true }).forEach(entry => {
      if (entry.isFile()) {
        count += 1;
      }
    });
  });
  return count;
}

function renameEventFoldersOnDisk(oldSlug, newSlug) {
  if (!oldSlug || !newSlug || oldSlug === newSlug) {
    return;
  }

  forEachStayUploadFolder(stayPath => {
    const oldPath = path.resolve(path.join(stayPath, oldSlug));
    const newPath = path.resolve(path.join(stayPath, newSlug));
    if (!oldPath.startsWith(path.resolve(stayPath)) || !newPath.startsWith(path.resolve(stayPath))) {
      return;
    }
    if (!fs.existsSync(oldPath) || !fs.statSync(oldPath).isDirectory()) {
      return;
    }
    if (fs.existsSync(newPath)) {
      fs.readdirSync(oldPath, { withFileTypes: true }).forEach(entry => {
        if (!entry.isFile()) {
          return;
        }
        const source = path.join(oldPath, entry.name);
        const target = path.join(newPath, entry.name);
        if (!fs.existsSync(target)) {
          fs.renameSync(source, target);
        }
      });
      fs.rmdirSync(oldPath, { recursive: true });
      return;
    }
    fs.renameSync(oldPath, newPath);
  });
}

function mergeEventFoldersOnDisk(sourceSlug, targetSlug) {
  if (!sourceSlug || !targetSlug || sourceSlug === targetSlug) {
    return;
  }
  renameEventFoldersOnDisk(sourceSlug, targetSlug);
}

function getOrCreateEvent(eventName, createdBy, guestType) {
  const trimmed = (eventName || '').trim().substring(0, 100);
  if (!trimmed) return null;

  const existing = findEventByName(trimmed);
  if (existing) return existing;

  if (!guestType.permissions.createEventNames) {
    return null;
  }

  const event = {
    id: `event_${Date.now()}_${crypto.randomBytes(4).toString('hex')}`,
    name: trimmed,
    createdAt: new Date().toISOString(),
    createdBy: createdBy || 'guest'
  };
  guestData.events.push(event);
  saveGuestData();
  return event;
}

function formatEventForAdmin(event) {
  const eventSlug = sanitizeEventSlug(event.name);
  return {
    id: event.id,
    name: event.name,
    eventSlug,
    createdAt: event.createdAt,
    createdBy: event.createdBy || 'unknown',
    uploadFileCount: countEventFilesOnDisk(eventSlug)
  };
}

function resolveUploadEventName(guest, requestedEventName) {
  const guestType = resolveGuestType(guest);
  if (!guestType.permissions.tagPhotosToEvent) {
    return 'General';
  }

  const candidate = (requestedEventName || guest.eventName || '').trim();
  if (!candidate) {
    return 'General';
  }

  const event = getOrCreateEvent(candidate, guest.id, guestType);
  if (!event) {
    const existing = findEventByName(candidate);
    if (existing) {
      return sanitizeEventSlug(existing.name);
    }
    return 'General';
  }

  return sanitizeEventSlug(event.name);
}

function getGuestStayFolder(guest) {
  const uploadsDir = getUploadsDir();
  const name = sanitizeName(guest.name || guest.id);
  const datePart = guest.createdAt
    ? guest.createdAt.split('T')[0]
    : new Date().toISOString().split('T')[0];
  const folderName = `${name}-${guest.id}-${datePart}`;
  const dir = path.join(uploadsDir, folderName);
  if (!path.resolve(dir).startsWith(path.resolve(uploadsDir))) {
    throw new Error('Invalid upload path');
  }
  return dir;
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
      const entryPath = path.join(folderPath, name);
      const stat = fs.statSync(entryPath);
      if (stat.isFile()) {
        files.push({
          name,
          size: stat.size,
          uploadedAt: stat.mtime.toISOString(),
          event: 'General',
          eventSlug: 'General'
        });
        return;
      }

      if (!stat.isDirectory()) {
        return;
      }

      fs.readdirSync(entryPath).forEach(fileName => {
        const filePath = path.join(entryPath, fileName);
        const fileStat = fs.statSync(filePath);
        if (!fileStat.isFile()) {
          return;
        }
        files.push({
          name: fileName,
          size: fileStat.size,
          uploadedAt: fileStat.mtime.toISOString(),
          event: resolveEventNameFromSlug(name),
          eventSlug: name
        });
      });
    });
  });

  return files.sort((a, b) => b.uploadedAt.localeCompare(a.uploadedAt));
}

function isSafeUploadFilename(filename) {
  const safeName = path.basename(filename);
  return safeName === filename && !safeName.includes('..');
}

function findGuestUploadFile(guestId, filename, eventSlug) {
  if (!isSafeUploadFilename(filename)) {
    return null;
  }

  const safeName = path.basename(filename);
  const normalizedSlug = sanitizeEventSlug(eventSlug);

  for (const folderPath of getGuestUploadFolders(guestId)) {
    const scopedPath = path.resolve(path.join(folderPath, normalizedSlug, safeName));
    if (
      scopedPath.startsWith(path.resolve(folderPath)) &&
      fs.existsSync(scopedPath) &&
      fs.statSync(scopedPath).isFile()
    ) {
      return scopedPath;
    }

    if (normalizedSlug === 'General') {
      const rootPath = path.resolve(path.join(folderPath, safeName));
      if (
        rootPath.startsWith(path.resolve(folderPath)) &&
        fs.existsSync(rootPath) &&
        fs.statSync(rootPath).isFile()
      ) {
        return rootPath;
      }
    }
  }

  return null;
}

function getStayFolderFromUploadPath(filePath, guestId) {
  const resolvedFile = path.resolve(filePath);
  for (const folderPath of getGuestUploadFolders(guestId)) {
    const resolvedFolder = path.resolve(folderPath);
    if (resolvedFile === resolvedFolder || resolvedFile.startsWith(resolvedFolder + path.sep)) {
      return folderPath;
    }
  }
  return null;
}

function resolveRetagTargetEvent(guest, body) {
  const guestType = resolveGuestType(guest);

  if (body?.clearEvent === true) {
    return { event: { name: 'General' } };
  }

  let event = null;

  if (body?.eventId) {
    event = findEventById(body.eventId);
    if (!event) {
      return { error: 'Target event not found', status: 400 };
    }
    return { event };
  }

  const trimmed = typeof body?.eventName === 'string' ? body.eventName.trim() : '';
  if (!trimmed) {
    return { error: 'Target event is required', status: 400 };
  }

  if (trimmed.toLowerCase() === 'general') {
    return { event: { name: 'General' } };
  }

  event = findEventByName(trimmed);
  if (!event) {
    event = getOrCreateEvent(trimmed, guest.id, guestType);
  }
  if (!event) {
    return { error: 'Unknown event name', status: 400 };
  }
  return { event };
}

function moveGuestUploadFile(guestId, sourcePath, targetEventName) {
  const stayFolder = getStayFolderFromUploadPath(sourcePath, guestId);
  if (!stayFolder) {
    return { error: 'Invalid source path', status: 500 };
  }

  const filename = path.basename(sourcePath);
  const targetSlug = sanitizeEventSlug(targetEventName);
  const targetDir = path.join(stayFolder, targetSlug);
  const targetPath = path.resolve(path.join(targetDir, filename));
  const resolvedStayFolder = path.resolve(stayFolder);

  if (!targetPath.startsWith(resolvedStayFolder + path.sep)) {
    return { error: 'Invalid target path', status: 500 };
  }

  if (path.resolve(sourcePath) === targetPath) {
    return { path: targetPath, eventSlug: targetSlug };
  }

  if (fs.existsSync(targetPath)) {
    return { error: 'A file with that name already exists in the target event', status: 409 };
  }

  fs.mkdirSync(targetDir, { recursive: true });
  fs.renameSync(sourcePath, targetPath);

  const sourceDir = path.dirname(sourcePath);
  if (sourceDir !== stayFolder && fs.existsSync(sourceDir)) {
    try {
      if (fs.readdirSync(sourceDir).length === 0) {
        fs.rmdirSync(sourceDir);
      }
    } catch (err) {
      console.error('Failed to remove empty event folder after re-tag:', err);
    }
  }

  return { path: targetPath, eventSlug: targetSlug };
}

function resolveLegacyGuestUploadFile(guestId, filename) {
  if (!isSafeUploadFilename(filename)) {
    return { status: 404 };
  }

  const safeName = path.basename(filename);
  let flatPath = null;
  let nestedMatches = 0;

  for (const folderPath of getGuestUploadFolders(guestId)) {
    const flatCandidates = [
      path.resolve(path.join(folderPath, safeName)),
      path.resolve(path.join(folderPath, 'General', safeName))
    ];

    flatCandidates.forEach(candidate => {
      if (
        candidate.startsWith(path.resolve(folderPath)) &&
        fs.existsSync(candidate) &&
        fs.statSync(candidate).isFile()
      ) {
        if (flatPath && flatPath !== candidate) {
          flatPath = 'ambiguous';
        } else if (flatPath !== 'ambiguous') {
          flatPath = candidate;
        }
      }
    });

    fs.readdirSync(folderPath, { withFileTypes: true })
      .filter(entry => entry.isDirectory() && entry.name !== 'General')
      .forEach(subdir => {
        const nestedPath = path.resolve(path.join(folderPath, subdir.name, safeName));
        if (
          nestedPath.startsWith(path.resolve(folderPath)) &&
          fs.existsSync(nestedPath) &&
          fs.statSync(nestedPath).isFile()
        ) {
          nestedMatches += 1;
        }
      });
  }

  if (flatPath === 'ambiguous' || nestedMatches > 0) {
    return {
      status: 409,
      message: 'Ambiguous file path; use /guest/uploads/:eventSlug/:filename'
    };
  }
  if (!flatPath) {
    return { status: 404 };
  }
  return { status: 200, path: flatPath };
}

function publicBaseUrl(req) {
  if (config.portalPublicUrl) {
    return config.portalPublicUrl;
  }
  const proto = (req.get('X-Forwarded-Proto') || req.protocol || 'http').split(',')[0].trim();
  const host = (req.get('X-Forwarded-Host') || req.get('Host') || '').split(',')[0].trim();
  return `${proto}://${host}`;
}

function normalizePortalPublicUrl(rawUrl) {
  if (!rawUrl || typeof rawUrl !== 'string' || rawUrl.trim() === '') {
    return null;
  }
  if (rawUrl.length > 500) {
    throw new Error('Portal URL is too long');
  }

  let parsed;
  try {
    parsed = new URL(rawUrl.trim());
  } catch {
    throw new Error('Invalid portal URL format');
  }

  if (!['http:', 'https:'].includes(parsed.protocol)) {
    throw new Error('Portal URL must use http or https');
  }

  parsed.pathname = parsed.pathname.replace(/\/+$/, '');
  if (parsed.pathname && parsed.pathname !== '/') {
    throw new Error('Portal URL must be an origin only, such as https://guestportal.example.com');
  }
  parsed.pathname = '';
  parsed.search = '';
  parsed.hash = '';
  return parsed.toString().replace(/\/$/, '');
}

function csvEscape(value) {
  if (value === null || value === undefined) return '';
  const text = String(value);
  if (/[",\r\n]/.test(text)) {
    return `"${text.replace(/"/g, '""')}"`;
  }
  return text;
}

function sendCsv(res, filename, columns, rows) {
  const header = columns.map(column => csvEscape(column.header)).join(',');
  const body = rows.map(row => columns.map(column => csvEscape(row[column.key])).join(',')).join('\n');
  const csv = `${header}\n${body}${body ? '\n' : ''}`;
  res.setHeader('Content-Type', 'text/csv; charset=utf-8');
  res.setHeader('Content-Disposition', `attachment; filename="${filename}"`);
  res.send(csv);
}

function getGuestSessionRows() {
  const now = new Date();
  return Object.entries(guestTokens)
    .map(([token, guest]) => {
      const checkout = new Date(guest.checkoutDate);
      const guestType = resolveGuestType(guest);
      return {
        token: token.substring(0, 8) + '...',
        guestId: guest.id,
        name: guest.name,
        room: guest.room || '',
        guestTypeId: guest.guestTypeId || guestType.id,
        guestTypeName: guestType.name,
        visitMode: guest.visitMode || guestType.visitMode,
        eventName: guest.eventName || '',
        createdAt: guest.createdAt || '',
        checkoutDate: guest.checkoutDate || '',
        active: checkout >= now ? 'yes' : 'no',
        daysRemaining: Math.ceil((checkout - now) / (1000 * 60 * 60 * 24)),
        deviceCount: (guest.devices || []).length
      };
    })
    .sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt));
}

function getRegistrationHistoryRows() {
  const now = new Date();
  const activeGuestIds = new Set(
    Object.values(guestTokens)
      .filter(guest => new Date(guest.checkoutDate) >= now)
      .map(guest => guest.id)
  );

  return (guestData.guests || [])
    .map(entry => {
      const guestType = entry.guestTypeId ? getGuestTypeById(entry.guestTypeId) : getLegacyGuestType();
      return {
        guestId: entry.guestId || '',
        name: entry.name || '',
        room: entry.room || '',
        guestTypeId: entry.guestTypeId || guestType.id,
        guestTypeName: guestType.name,
        visitMode: entry.visitMode || guestType.visitMode,
        timestamp: entry.timestamp || '',
        hasActiveSession: activeGuestIds.has(entry.guestId) ? 'yes' : 'no'
      };
    })
    .sort((a, b) => new Date(b.timestamp) - new Date(a.timestamp));
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

function createGuestRegistration(name, guestTypeId, options = {}, userAgent) {
  const guestType = guestTypeId
    ? getEnabledGuestTypeById(guestTypeId)
    : getEnabledGuestTypeById('type_overnight');

  if (!guestType) {
    return { error: 'Invalid or disabled guest type' };
  }

  const nameError = validateGuestName(name);
  if (nameError) {
    return { error: nameError };
  }

  const room = typeof options.room === 'string' ? options.room.trim() : '';
  if (guestType.requiresRoom) {
    const roomError = validateGuestRoom(room);
    if (roomError) {
      return { error: roomError };
    }
  } else if (room) {
    const roomError = validateGuestRoom(room);
    if (roomError) {
      return { error: roomError };
    }
  }

  const checkoutDate = new Date();
  if (guestType.visitMode === 'day') {
    const hours = guestType.defaultDayVisitHours || 8;
    checkoutDate.setTime(checkoutDate.getTime() + hours * 60 * 60 * 1000);
  } else {
    const defaultDays = guestType.defaultStayDays || 7;
    const days = guestType.permissions.selectStayLength
      ? Math.min(Math.max(parseInt(options.stayDays, 10) || defaultDays, 1), 30)
      : defaultDays;
    checkoutDate.setDate(checkoutDate.getDate() + days);
  }

  let eventName = null;
  if (guestType.permissions.selectEventAtRegistration) {
    const requestedEvent = (options.eventName || '').trim();
    if (!requestedEvent) {
      return { error: 'Event name is required for this guest type' };
    }
    const event = getOrCreateEvent(requestedEvent, 'registration', guestType);
    if (!event) {
      return { error: 'Event not found or creation not permitted' };
    }
    eventName = event.name;
  }

  const token = generateToken();
  const guestId = `guest_${Date.now()}_${crypto.randomBytes(4).toString('hex')}`;
  const dashboardUrl = room ? resolveRoomDashboard(room) : null;
  const createdAt = new Date().toISOString();

  guestTokens[token] = {
    id: guestId,
    name,
    room: room || '',
    dashboardUrl,
    checkoutDate: checkoutDate.toISOString(),
    guestTypeId: guestType.id,
    visitMode: guestType.visitMode,
    eventName,
    createdAt,
    devices: [{ addedAt: createdAt, userAgent: userAgent || 'Unknown' }]
  };
  writePermissionsSnapshot(guestTokens[token], guestType);
  saveGuestTokens();

  guestData.guests.push({
    name,
    room: room || '',
    guestTypeId: guestType.id,
    visitMode: guestType.visitMode,
    eventName,
    timestamp: createdAt,
    guestId
  });
  saveGuestData();

  return {
    token,
    guestId,
    guest: formatGuestResponse(guestTokens[token])
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

function getGuestEntryHealth() {
  const rooms = guestData.rooms || [];
  const frontendDir = path.join(__dirname, 'frontend');
  const checks = [
    { path: '/health', ok: true, detail: 'Health endpoint is registered' },
    { path: '/', ok: fs.existsSync(path.join(frontendDir, 'index.html')), detail: 'Guest registration page is present' },
    { path: '/guest/rooms', ok: Array.isArray(rooms), detail: `${rooms.length} room${rooms.length === 1 ? '' : 's'} available` },
    { path: '/welcome.html', ok: fs.existsSync(path.join(frontendDir, 'welcome.html')), detail: 'Guest welcome hub is present' },
    { path: '/photo.html', ok: fs.existsSync(path.join(frontendDir, 'photo.html')), detail: 'Guest photo gallery is present' }
  ];
  const roomsConfigured = rooms.length > 0;
  const endpointsOk = checks.every(check => check.ok);

  return {
    ok: endpointsOk && roomsConfigured,
    roomsConfigured,
    roomCount: rooms.length,
    summary: endpointsOk && roomsConfigured
      ? 'Guest registration should be usable.'
      : 'Guest registration needs attention.',
    checks
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

function collectStayFolderFiles(stayFolderPath, stayFolderName, uploadsDir) {
  const files = [];
  const entries = fs.readdirSync(stayFolderPath, { withFileTypes: true });

  entries.forEach(entry => {
    const entryPath = path.join(stayFolderPath, entry.name);
    if (entry.isFile()) {
      const stat = fs.statSync(entryPath);
      files.push({
        name: entry.name,
        size: stat.size,
        uploadedAt: stat.mtime.toISOString(),
        event: 'General',
        url: `/admin/uploads/${encodeURIComponent(stayFolderName)}/${encodeURIComponent(entry.name)}`
      });
      return;
    }

    if (!entry.isDirectory()) {
      return;
    }

    fs.readdirSync(entryPath, { withFileTypes: true }).forEach(fileEntry => {
      if (!fileEntry.isFile()) {
        return;
      }
      const filePath = path.join(entryPath, fileEntry.name);
      const stat = fs.statSync(filePath);
      files.push({
        name: fileEntry.name,
        size: stat.size,
        uploadedAt: stat.mtime.toISOString(),
        event: resolveEventNameFromSlug(entry.name),
        eventSlug: entry.name,
        url: `/admin/uploads/${encodeURIComponent(stayFolderName)}/${encodeURIComponent(entry.name)}/${encodeURIComponent(fileEntry.name)}`
      });
    });
  });

  return files;
}

// ─── Middleware ──────────────────────────────────────────────────────────────

app.use(cors());
app.use(express.json());

// H1: Rate limiter BEFORE static files and routes
const limiter = rateLimit({
  windowMs: 60 * 1000,
  max: 200
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
    try {
      const guest = req.guestSession.guest;
      const stayDir = getGuestStayFolder(guest);
      const eventSlug = resolveUploadEventName(guest, req.body?.eventName);
      const dir = path.join(stayDir, eventSlug);
      if (!path.resolve(dir).startsWith(path.resolve(getUploadsDir()))) {
        return cb(new Error('Invalid upload path'));
      }
      fs.mkdirSync(dir, { recursive: true });
      cb(null, dir);
    } catch (err) {
      cb(err);
    }
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

function requireGuestPermission(permissionKey) {
  return (req, res, next) => {
    const permissions = getGuestPermissions(req.guestSession.guest);
    if (!permissions[permissionKey]) {
      return res.status(403).send('Not permitted for your guest type');
    }
    next();
  };
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

app.get('/guest/guest-types', (req, res) => {
  const types = (guestData.guestTypes || [])
    .filter(type => type.enabled)
    .map(formatGuestTypeForPublic);
  res.json(types);
});

app.get('/guest/events', (req, res) => {
  res.json((guestData.events || []).map(event => ({
    id: event.id,
    name: event.name
  })));
});

app.post('/guest/events', (req, res) => {
  const token = req.body?.token || req.get('X-Guest-Token');
  const session = getGuestSession(token);
  if (!session.guest) {
    return res.status(session.status).send(session.message);
  }

  const guestType = resolveGuestType(session.guest);
  if (!guestType.permissions.createEventNames) {
    return res.status(403).send('Not permitted to create event names');
  }

  const event = getOrCreateEvent(req.body?.name, session.guest.id, guestType);
  if (!event) {
    return res.status(400).send('Invalid event name');
  }

  res.json({ id: event.id, name: event.name });
});

app.post('/register', (req, res) => {
  const { name, room, stayDays, guestTypeId, eventName } = req.body;

  if (!guestTypeId) {
    const validationError = validateGuestNameAndRoom(name, room);
    if (validationError) {
      return res.status(400).send(validationError);
    }
  }

  const registration = createGuestRegistration(
    name,
    guestTypeId || 'type_overnight',
    { room, stayDays, eventName },
    req.get('User-Agent') || 'Unknown'
  );

  if (registration.error) {
    return res.status(400).send(registration.error);
  }

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
  const guestPayload = formatGuestResponse(guest);
  if (!guestPayload.permissions.viewWelcomeHub) {
    return res.status(403).json({ valid: false, error: 'Welcome hub not available for your guest type' });
  }

  res.json({
    valid: true,
    returningDevice: isReturningDevice(guest, req.get('User-Agent')),
    guest: guestPayload
  });
});

app.post('/guest/link-code', async (req, res) => {
  const { token } = req.body;
  if (!token || !guestTokens[token]) {
    return res.status(404).send('Invalid token');
  }

  const guest = guestTokens[token];
  if (!getGuestPermissions(guest).linkDevice) {
    return res.status(403).send('Not permitted for your guest type');
  }
  const linkCode = generateCode();
  const expirationMinutes = getExpirationMinutes();
  const expires = Date.now() + getLinkCodeExpirationMs();

  sessionCodes[linkCode] = {
    type: 'device-link',
    guestToken: token,
    guestId: guest.id,
    expires
  };
  saveSessions();

  const linkUrl = `${publicBaseUrl(req)}/?linkCode=${encodeURIComponent(linkCode)}`;
  const expiresIn = formatExpirationLabel(expirationMinutes);
  try {
    const qrSvg = await QRCode.toString(linkUrl, {
      type: 'svg',
      errorCorrectionLevel: 'M',
      margin: 1,
      width: 180
    });
    res.json({ code: linkCode, linkUrl, qrSvg, expiresIn, expiresAt: expires });
  } catch (err) {
    console.error('Failed to generate link QR:', err);
    res.json({ code: linkCode, linkUrl, expiresIn, expiresAt: expires });
  }
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
    guest: formatGuestResponse(guest)
  });
});

// H4: Validate guest token on upload
app.post('/upload', validateGuestUploadToken, requireGuestPermission('uploadPhotos'), handleGuestUpload, (req, res) => {
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

app.get('/guest/uploads', validateGuestUploadToken, requireGuestPermission('viewPhotoGallery'), (req, res) => {
  const files = listGuestUploadFiles(req.guestSession.guest.id);
  res.json({ files });
});

app.get('/guest/uploads/:eventSlug/:filename', validateGuestUploadToken, requireGuestPermission('viewPhotoGallery'), (req, res) => {
  const filePath = findGuestUploadFile(
    req.guestSession.guest.id,
    req.params.filename,
    req.params.eventSlug
  );
  if (!filePath) {
    return res.status(404).send('File not found');
  }
  res.sendFile(filePath);
});

app.delete('/guest/uploads/:eventSlug/:filename', validateGuestUploadToken, requireGuestPermission('deleteOwnPhotos'), (req, res) => {
  const filePath = findGuestUploadFile(
    req.guestSession.guest.id,
    req.params.filename,
    req.params.eventSlug
  );
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

app.patch('/guest/uploads/:eventSlug/:filename', validateGuestUploadToken, requireGuestPermission('tagPhotosToEvent'), (req, res) => {
  const guest = req.guestSession.guest;
  const filePath = findGuestUploadFile(guest.id, req.params.filename, req.params.eventSlug);
  if (!filePath) {
    return res.status(404).send('File not found');
  }

  const targetResult = resolveRetagTargetEvent(guest, req.body);
  if (targetResult.error) {
    return res.status(targetResult.status || 400).send(targetResult.error);
  }

  const targetSlug = sanitizeEventSlug(targetResult.event.name);
  const sourceSlug = sanitizeEventSlug(req.params.eventSlug);
  if (targetSlug === sourceSlug) {
    const stat = fs.statSync(filePath);
    return res.json({
      name: path.basename(filePath),
      eventSlug: targetSlug,
      event: targetResult.event.name,
      size: stat.size,
      uploadedAt: stat.mtime.toISOString()
    });
  }

  try {
    const moveResult = moveGuestUploadFile(guest.id, filePath, targetResult.event.name);
    if (moveResult.error) {
      return res.status(moveResult.status || 500).send(moveResult.error);
    }
    const stat = fs.statSync(moveResult.path);
    res.json({
      name: path.basename(moveResult.path),
      eventSlug: targetSlug,
      event: targetResult.event.name,
      size: stat.size,
      uploadedAt: stat.mtime.toISOString()
    });
  } catch (err) {
    console.error('Failed to re-tag guest upload:', err);
    res.status(500).send('Failed to move file');
  }
});

app.get('/guest/uploads/:filename', validateGuestUploadToken, requireGuestPermission('viewPhotoGallery'), (req, res) => {
  const result = resolveLegacyGuestUploadFile(req.guestSession.guest.id, req.params.filename);
  if (result.status === 409) {
    res.set('Deprecation', 'true');
    return res.status(409).send(result.message);
  }
  if (result.status !== 200) {
    return res.status(404).send('File not found');
  }
  res.set('Deprecation', 'true');
  res.sendFile(result.path);
});

app.delete('/guest/uploads/:filename', validateGuestUploadToken, requireGuestPermission('deleteOwnPhotos'), (req, res) => {
  const result = resolveLegacyGuestUploadFile(req.guestSession.guest.id, req.params.filename);
  if (result.status === 409) {
    res.set('Deprecation', 'true');
    return res.status(409).send(result.message);
  }
  if (result.status !== 200) {
    return res.status(404).send('File not found');
  }

  try {
    res.set('Deprecation', 'true');
    fs.unlinkSync(result.path);
    res.json({ success: true });
  } catch (err) {
    console.error('Failed to delete guest upload:', err);
    res.status(500).send('Failed to delete file');
  }
});

app.get('/guest/note', validateGuestUploadToken, requireGuestPermission('leaveGuestNote'), (req, res) => {
  const note = getGuestNoteByGuestId(req.guestSession.guest.id);
  res.json({ note: note ? formatGuestNoteForResponse(note) : null });
});

app.put('/guest/note', validateGuestUploadToken, requireGuestPermission('leaveGuestNote'), (req, res) => {
  const validation = validateGuestNoteText(req.body?.text);
  if (validation.error) {
    return res.status(validation.status || 400).send(validation.error);
  }
  const note = upsertGuestNote(req.guestSession.guest, validation.text);
  res.json({ note: formatGuestNoteForResponse(note) });
});

app.delete('/guest/note', validateGuestUploadToken, requireGuestPermission('leaveGuestNote'), (req, res) => {
  const deleted = deleteGuestNoteByGuestId(req.guestSession.guest.id);
  if (!deleted) {
    return res.status(404).send('Note not found');
  }
  res.json({ success: true });
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
      guestNotes: (guestData.guestNotes || []).length,
      activeGuestSessions: sessionCounts.active,
      expiredGuestSessions: sessionCounts.expired,
      pendingSessionCodes: Object.values(sessionCodes).filter(entry => entry.expires > Date.now()).length
    },
    guestEntry: getGuestEntryHealth(),
    admin: {
      username: config.adminUser || 'admin'
    },
    portal: {
      publicUrl: config.portalPublicUrl || null
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
        const files = collectStayFolderFiles(folderPath, e.name, uploadsDir);
        const totalSize = files.reduce((sum, file) => sum + file.size, 0);
        return {
          name: e.name,
          fileCount: files.length,
          totalSize,
          files
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

app.get('/admin-api/portal-url', authMiddleware, (req, res) => {
  res.json({ portalPublicUrl: config.portalPublicUrl || '' });
});

app.post('/admin-api/portal-url', authMiddleware, (req, res) => {
  try {
    const normalized = normalizePortalPublicUrl(req.body?.portalPublicUrl);
    if (normalized) {
      config.portalPublicUrl = normalized;
    } else {
      delete config.portalPublicUrl;
    }
    saveConfig();
    res.json({ success: true, portalPublicUrl: config.portalPublicUrl || '' });
  } catch (err) {
    res.status(400).send(err.message);
  }
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

app.get('/admin-api/session-expiration', authMiddleware, (req, res) => {
  res.json({ minutes: getExpirationMinutes() });
});

app.post('/admin-api/session-expiration', authMiddleware, (req, res) => {
  const minutes = parseInt(req.body?.minutes, 10);
  if (!Number.isFinite(minutes) || minutes <= 0) {
    return res.status(400).send('Invalid expiration minutes');
  }
  config.sessionExpirationMinutes = minutes;
  saveConfig();
  res.json({ success: true, minutes });
});

// C4: Remove fullToken from response
app.get('/admin-api/guest-sessions', authMiddleware, (req, res) => {
  const sessions = getGuestSessionRows().map(row => {
    const guestEntry = findGuestTokenEntryByGuestId(row.guestId)?.[1];
    const guestType = resolveGuestType(guestEntry);
    return {
      token: row.token,
      id: row.guestId,
      name: row.name,
      room: row.room,
      guestTypeId: row.guestTypeId,
      guestTypeName: row.guestTypeName,
      visitMode: row.visitMode,
      eventName: row.eventName || null,
      createdAt: row.createdAt,
      checkoutDate: row.checkoutDate,
      devices: guestEntry?.devices || [],
      isExpired: row.active !== 'yes',
      daysRemaining: row.daysRemaining,
      permissions: guestEntry ? getGuestPermissions(guestEntry) : guestType.permissions
    };
  });
  res.json(sessions);
});

app.get('/admin-api/guest-sessions.csv', authMiddleware, (req, res) => {
  sendCsv(res, 'active-guest-sessions.csv', [
    { key: 'guestId', header: 'Guest ID' },
    { key: 'name', header: 'Name' },
    { key: 'room', header: 'Room' },
    { key: 'guestTypeId', header: 'Guest Type ID' },
    { key: 'guestTypeName', header: 'Guest Type' },
    { key: 'visitMode', header: 'Visit Mode' },
    { key: 'createdAt', header: 'Created At' },
    { key: 'checkoutDate', header: 'Checkout Date' },
    { key: 'active', header: 'Active' },
    { key: 'daysRemaining', header: 'Days Remaining' },
    { key: 'deviceCount', header: 'Device Count' },
    { key: 'token', header: 'Token Prefix' }
  ], getGuestSessionRows());
});

app.post('/admin-api/guest-sessions/:guestId/link-code', authMiddleware, async (req, res) => {
  const { guestId } = req.params;
  const entry = findGuestTokenEntryByGuestId(guestId);
  if (!entry) {
    return res.status(404).send('Guest not found');
  }

  const [guestToken, guest] = entry;
  const linkCode = generateCode();
  const expirationMinutes = getExpirationMinutes();
  const expires = Date.now() + getLinkCodeExpirationMs();

  sessionCodes[linkCode] = {
    type: 'device-link',
    guestToken,
    guestId: guest.id,
    expires
  };
  saveSessions();

  const linkUrl = `${publicBaseUrl(req)}/?linkCode=${encodeURIComponent(linkCode)}`;
  const expiresIn = formatExpirationLabel(expirationMinutes);
  try {
    const qrSvg = await QRCode.toString(linkUrl, {
      type: 'svg',
      errorCorrectionLevel: 'M',
      margin: 1,
      width: 180
    });
    res.json({ code: linkCode, linkUrl, qrSvg, expiresIn, expiresAt: expires });
  } catch (err) {
    console.error('Failed to generate admin link QR:', err);
    res.json({ code: linkCode, linkUrl, expiresIn, expiresAt: expires });
  }
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
  const { room, guestTypeId } = req.body;

  const entry = findGuestTokenEntryByGuestId(guestId);
  if (!entry) {
    return res.status(404).send('Guest not found');
  }

  const [, guest] = entry;

  if (guestTypeId !== undefined) {
    if (guestTypeId === null || guestTypeId === '') {
      delete guest.guestTypeId;
      delete guest.permissionsSnapshot;
    } else {
      const guestType = getGuestTypeById(guestTypeId);
      if (!guestType) {
        return res.status(400).send('Guest type not found');
      }
      guest.guestTypeId = guestType.id;
      guest.visitMode = guestType.visitMode;
      writePermissionsSnapshot(guest, guestType);

      if (guestType.visitMode === 'day') {
        const checkoutDate = new Date();
        checkoutDate.setTime(checkoutDate.getTime() + (guestType.defaultDayVisitHours || 8) * 60 * 60 * 1000);
        guest.checkoutDate = checkoutDate.toISOString();
      } else {
        const checkoutDate = new Date(guest.checkoutDate);
        const minCheckout = new Date();
        minCheckout.setDate(minCheckout.getDate() + (guestType.defaultStayDays || 7));
        if (checkoutDate < minCheckout) {
          guest.checkoutDate = minCheckout.toISOString();
        }
      }
    }
  }

  if (room !== undefined) {
    const validationError = validateGuestRoom(room);
    if (validationError) {
      return res.status(400).send('Invalid room');
    }
    if (!guestData.rooms.some(r => r.name === room)) {
      return res.status(400).send('Room not found');
    }
    guest.room = room;
    guest.dashboardUrl = resolveRoomDashboard(room);
  }

  saveGuestTokens();

  const historyEntry = (guestData.guests || []).find(g => g.guestId === guestId);
  if (historyEntry) {
    if (room !== undefined) historyEntry.room = room;
    if (guestTypeId !== undefined) {
      historyEntry.guestTypeId = guest.guestTypeId;
      historyEntry.visitMode = guest.visitMode;
    }
    saveGuestData();
  }

  res.json({
    success: true,
    guest: formatGuestResponse(guest)
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
  const guests = getRegistrationHistoryRows().map(row => ({
    guestId: row.guestId,
    name: row.name,
    room: row.room,
    guestTypeId: row.guestTypeId,
    guestTypeName: row.guestTypeName,
    visitMode: row.visitMode,
    timestamp: row.timestamp,
    hasActiveSession: row.hasActiveSession === 'yes'
  }));

  res.json(guests);
});

app.get('/admin-api/guests.csv', authMiddleware, (req, res) => {
  sendCsv(res, 'registration-history.csv', [
    { key: 'guestId', header: 'Guest ID' },
    { key: 'name', header: 'Name' },
    { key: 'room', header: 'Room' },
    { key: 'guestTypeId', header: 'Guest Type ID' },
    { key: 'guestTypeName', header: 'Guest Type' },
    { key: 'visitMode', header: 'Visit Mode' },
    { key: 'timestamp', header: 'Registered At' },
    { key: 'hasActiveSession', header: 'Has Active Session' }
  ], getRegistrationHistoryRows());
});

app.get('/admin-api/guest-notes', authMiddleware, (req, res) => {
  const notes = (guestData.guestNotes || [])
    .slice()
    .sort((a, b) => new Date(b.updatedAt || b.createdAt) - new Date(a.updatedAt || a.createdAt))
    .map(formatGuestNoteForResponse);
  res.json({ notes });
});

app.delete('/admin-api/guest-notes/:id', authMiddleware, (req, res) => {
  const note = getGuestNoteById(req.params.id);
  if (!note) {
    return res.status(404).send('Note not found');
  }
  deleteGuestNoteById(req.params.id);
  res.json({ success: true });
});

app.get('/admin-api/guest-types', authMiddleware, (req, res) => {
  res.json(guestData.guestTypes || []);
});

app.get('/admin-api/events', authMiddleware, (req, res) => {
  res.json((guestData.events || []).map(formatEventForAdmin));
});

app.post('/admin-api/events', authMiddleware, (req, res) => {
  const result = createEventRecord(req.body?.name, 'admin');
  if (result.error) {
    return res.status(400).send(result.error);
  }
  res.json({ success: true, event: formatEventForAdmin(result.event) });
});

app.patch('/admin-api/events/:id', authMiddleware, (req, res) => {
  const event = findEventById(req.params.id);
  if (!event) {
    return res.status(404).send('Event not found');
  }

  if (req.body?.mergeIntoId) {
    const target = findEventById(req.body.mergeIntoId);
    if (!target) {
      return res.status(400).send('Target event not found');
    }
    if (target.id === event.id) {
      return res.status(400).send('Cannot merge an event into itself');
    }
    mergeEventFoldersOnDisk(sanitizeEventSlug(event.name), sanitizeEventSlug(target.name));
    guestData.events = (guestData.events || []).filter(entry => entry.id !== event.id);
    saveGuestData();
    return res.json({ success: true, mergedInto: target.id, event: formatEventForAdmin(target) });
  }

  const newName = typeof req.body?.name === 'string' ? req.body.name.trim() : '';
  if (!newName) {
    return res.status(400).send('Event name is required');
  }
  const duplicate = findEventByName(newName);
  if (duplicate && duplicate.id !== event.id) {
    return res.status(400).send('Event name already exists');
  }

  const oldSlug = sanitizeEventSlug(event.name);
  event.name = newName.substring(0, 100);
  renameEventFoldersOnDisk(oldSlug, sanitizeEventSlug(event.name));
  saveGuestData();
  res.json({ success: true, event: formatEventForAdmin(event) });
});

app.delete('/admin-api/events/:id', authMiddleware, (req, res) => {
  const event = findEventById(req.params.id);
  if (!event) {
    return res.status(404).send('Event not found');
  }

  const eventSlug = sanitizeEventSlug(event.name);
  if (countEventFilesOnDisk(eventSlug) > 0) {
    return res.status(409).send('Event has uploaded photos. Rename or merge it before deleting.');
  }

  guestData.events = (guestData.events || []).filter(entry => entry.id !== event.id);
  saveGuestData();
  res.json({ success: true });
});

app.post('/admin-api/guest-types', authMiddleware, (req, res) => {
  const parsed = sanitizeGuestTypeInput(req.body);
  if (parsed.error) {
    return res.status(400).send(parsed.error);
  }
  if ((guestData.guestTypes || []).some(type => type.id === parsed.type.id)) {
    return res.status(400).send('Guest type ID already exists');
  }
  guestData.guestTypes.push(parsed.type);
  saveGuestData();
  res.json({ success: true, guestType: parsed.type });
});

app.patch('/admin-api/guest-types/:id', authMiddleware, (req, res) => {
  const index = (guestData.guestTypes || []).findIndex(type => type.id === req.params.id);
  if (index < 0) {
    return res.status(404).send('Guest type not found');
  }
  const parsed = sanitizeGuestTypeInput(req.body, guestData.guestTypes[index]);
  if (parsed.error) {
    return res.status(400).send(parsed.error);
  }
  guestData.guestTypes[index] = parsed.type;
  saveGuestData();
  res.json({ success: true, guestType: parsed.type });
});

app.delete('/admin-api/guest-types/:id', authMiddleware, (req, res) => {
  const index = (guestData.guestTypes || []).findIndex(type => type.id === req.params.id);
  if (index < 0) {
    return res.status(404).send('Guest type not found');
  }
  guestData.guestTypes[index].enabled = false;
  saveGuestData();
  res.json({ success: true });
});

app.post('/admin-api/guest-types/reorder', authMiddleware, (req, res) => {
  const { order } = req.body || {};
  if (!Array.isArray(order)) {
    return res.status(400).send('Order must be an array of guest type IDs');
  }
  const typeMap = new Map((guestData.guestTypes || []).map(type => [type.id, type]));
  const reordered = order.map(id => typeMap.get(id)).filter(Boolean);
  if (reordered.length !== (guestData.guestTypes || []).length) {
    return res.status(400).send('Order must include every guest type ID exactly once');
  }
  guestData.guestTypes = reordered;
  saveGuestData();
  res.json({ success: true, guestTypes: guestData.guestTypes });
});

app.post('/admin-api/guests', authMiddleware, (req, res) => {
  const { name, room, stayDays, guestTypeId, eventName } = req.body;

  if (!guestTypeId) {
    const validationError = validateGuestNameAndRoom(name, room);
    if (validationError) {
      return res.status(400).send(validationError);
    }
    if (!guestData.rooms.some(r => r.name === room)) {
      return res.status(400).send('Room not found');
    }
  }

  const registration = createGuestRegistration(
    name,
    guestTypeId || 'type_overnight',
    { room, stayDays, eventName },
    'Admin registration'
  );

  if (registration.error) {
    return res.status(400).send(registration.error);
  }

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
