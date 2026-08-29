'use strict';

/**
 * Regression: case-only event folder rename must not merge-into-self.
 *
 * On case-insensitive NAS/SMB volumes, Birthday-Party and birthday-party are
 * the same directory. The old rename path saw existsSync(newPath) and ran
 * uniqueMergedFilename, renaming every photo to *-merged-*.
 *
 * Linux reproduction: point the new slug at the old directory via symlink
 * (same inode), then run the fixed rename helper logic.
 */

const fs = require('fs');
const os = require('os');
const path = require('path');
const crypto = require('crypto');

function uniqueMergedFilename(targetDir, filename) {
  const ext = path.extname(filename);
  const base = path.basename(filename, ext);
  let candidate = filename;
  while (fs.existsSync(path.join(targetDir, candidate))) {
    candidate = `${base}-merged-${crypto.randomBytes(3).toString('hex')}${ext}`;
  }
  return candidate;
}

function sameDirectoryOnDisk(pathA, pathB) {
  try {
    if (!fs.existsSync(pathA) || !fs.existsSync(pathB)) {
      return false;
    }
    const statA = fs.statSync(pathA);
    const statB = fs.statSync(pathB);
    return statA.isDirectory() && statB.isDirectory() && statA.dev === statB.dev && statA.ino === statB.ino;
  } catch {
    return false;
  }
}

function renameEventFoldersOnDisk(oldSlug, newSlug, stayPath) {
  if (!oldSlug || !newSlug || oldSlug === newSlug) {
    return;
  }

  const caseOnlySlugChange = oldSlug.toLowerCase() === newSlug.toLowerCase();
  const oldPath = path.resolve(path.join(stayPath, oldSlug));
  const newPath = path.resolve(path.join(stayPath, newSlug));

  if (!fs.existsSync(oldPath) || !fs.statSync(oldPath).isDirectory()) {
    return;
  }

  if (caseOnlySlugChange || sameDirectoryOnDisk(oldPath, newPath)) {
    if (oldPath !== newPath) {
      try {
        fs.renameSync(oldPath, newPath);
      } catch {
        // Case-insensitive / symlink collision: leave folder name as-is.
      }
    }
    return;
  }

  if (fs.existsSync(newPath)) {
    fs.readdirSync(oldPath, { withFileTypes: true }).forEach(entry => {
      if (!entry.isFile()) return;
      const source = path.join(oldPath, entry.name);
      const targetName = uniqueMergedFilename(newPath, entry.name);
      fs.renameSync(source, path.join(newPath, targetName));
    });
    return;
  }

  fs.renameSync(oldPath, newPath);
}

function buggyRename(oldSlug, newSlug, stayPath) {
  const oldPath = path.resolve(path.join(stayPath, oldSlug));
  const newPath = path.resolve(path.join(stayPath, newSlug));
  if (!fs.existsSync(oldPath)) return;
  if (fs.existsSync(newPath)) {
    fs.readdirSync(oldPath, { withFileTypes: true }).forEach(entry => {
      if (!entry.isFile()) return;
      const source = path.join(oldPath, entry.name);
      const targetName = uniqueMergedFilename(newPath, entry.name);
      fs.renameSync(source, path.join(newPath, targetName));
    });
  }
}

function assert(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}

function main() {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'gp-case-rename-'));
  try {
    const buggyStay = path.join(tmp, 'buggy');
    const fixedStay = path.join(tmp, 'fixed');
    for (const stay of [buggyStay, fixedStay]) {
      fs.mkdirSync(path.join(stay, 'Birthday-Party'), { recursive: true });
      fs.writeFileSync(path.join(stay, 'Birthday-Party', 'photo.jpg'), 'x');
      fs.symlinkSync('Birthday-Party', path.join(stay, 'birthday-party'));
    }

    buggyRename('Birthday-Party', 'birthday-party', buggyStay);
    const buggyFiles = fs.readdirSync(path.join(buggyStay, 'Birthday-Party'));
    assert(
      buggyFiles.some(name => name.includes('-merged-')),
      'expected buggy path to produce *-merged-* filenames'
    );

    renameEventFoldersOnDisk('Birthday-Party', 'birthday-party', fixedStay);
    const fixedDir = fs.existsSync(path.join(fixedStay, 'Birthday-Party'))
      ? path.join(fixedStay, 'Birthday-Party')
      : path.join(fixedStay, 'birthday-party');
    const fixedFiles = fs.readdirSync(fixedDir).filter(name => !name.startsWith('.'));
    assert(
      fixedFiles.includes('photo.jpg'),
      `expected photo.jpg preserved, got: ${fixedFiles.join(', ')}`
    );
    assert(
      !fixedFiles.some(name => name.includes('-merged-')),
      `fixed path must not create *-merged-* files, got: ${fixedFiles.join(', ')}`
    );

    console.log('PASS: case-only event rename skips merge-into-self (preserves filenames)');
  } finally {
    fs.rmSync(tmp, { recursive: true, force: true });
  }
}

main();
