
const fs = require('fs');
const dbPath = '/etc/guest-portal/storage.json';
let db = { rooms: [], guests: [] };

if (fs.existsSync(dbPath)) {
  db = JSON.parse(fs.readFileSync(dbPath));
}

function listGuests() {
  console.log("📋 Current Guests:");
  db.guests.forEach(g => {
    console.log(`- ${g.name} (${g.room}) on ${g.timestamp}`);
  });
}

function listRooms() {
  console.log("🛏️ Guest Rooms:");
  db.rooms.forEach(r => {
    console.log(`- ${r.name}: ${r.dashboardUrl}`);
  });
}

listRooms();
console.log('');
listGuests();
