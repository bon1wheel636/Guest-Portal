'use strict';

const fs = require('fs');

// Serialize per-file writes so overlapping save* calls cannot interleave
// writeFile truncates (corrupt JSON) or finish out of order (lost notes/events).
// Stringify inside the chain callback so each write persists the latest
// in-memory value — not a stale snapshot captured when save was scheduled.
function createSerializedJsonSaver(filePath, label, getValue, writeFile = fs.promises.writeFile.bind(fs.promises)) {
  let chain = Promise.resolve();
  function saveSerialized() {
    chain = chain
      .catch(() => {})
      .then(() => {
        const payload = JSON.stringify(getValue(), null, 2);
        return writeFile(filePath, payload);
      })
      .catch(err => {
        console.error(`Failed to save ${label}:`, err);
      });
    return chain;
  }
  saveSerialized.flush = () => chain.catch(() => {});
  return saveSerialized;
}

module.exports = { createSerializedJsonSaver };
