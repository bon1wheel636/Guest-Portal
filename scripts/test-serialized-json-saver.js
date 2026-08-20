'use strict';

/**
 * Regression test: createSerializedJsonSaver must stringify at write time.
 *
 * If JSON is captured when save() is scheduled, a later mutation can be lost
 * when an earlier queued write finishes and a subsequent write fails (disk
 * full, process kill, etc.). Snapshotting inside the chain callback keeps
 * the latest in-memory state.
 */

const fs = require('fs');
const os = require('os');
const path = require('path');
const { createSerializedJsonSaver } = require('../serialized-json-saver');

async function main() {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'gp-saver-'));
  const filePath = path.join(tmp, 'storage.json');
  let data = { notes: [], events: [] };
  fs.writeFileSync(filePath, JSON.stringify(data, null, 2));

  let releaseFirstWrite;
  const firstWriteGate = new Promise(resolve => {
    releaseFirstWrite = resolve;
  });

  let writeCount = 0;
  const writeFile = async (targetPath, payload) => {
    writeCount += 1;
    if (writeCount === 1) {
      await firstWriteGate;
    }
    if (writeCount === 2) {
      throw new Error('simulated write failure');
    }
    return fs.promises.writeFile(targetPath, payload);
  };

  const save = createSerializedJsonSaver(filePath, 'test data', () => data, writeFile);

  data.notes.push({ id: 'note-1' });
  save();
  data.events.push({ id: 'event-1' });
  save();

  releaseFirstWrite();
  await save.flush();
  // Allow the rejected second write's catch handler to settle.
  await new Promise(resolve => setImmediate(resolve));

  const disk = JSON.parse(fs.readFileSync(filePath, 'utf8'));
  fs.rmSync(tmp, { recursive: true, force: true });

  if (!disk.notes.some(note => note.id === 'note-1')) {
    console.error('FAIL: note missing from durable JSON');
    process.exit(1);
  }
  if (!disk.events.some(event => event.id === 'event-1')) {
    console.error('FAIL: event lost after earlier stale snapshot write + later write failure');
    process.exit(1);
  }

  console.log('PASS: serialized saver persists latest in-memory state at write time');
}

main().catch(err => {
  console.error(err);
  process.exit(1);
});
