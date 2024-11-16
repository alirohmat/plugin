// Impor dependency yang diperlukan
const { makeWASocket, DisconnectReason } = require('@whiskeysockets/baileys');
const { useMultiFileAuthState } = require('@whiskeysockets/baileys');
const { setInterval, clearInterval } = require('timers');
const { Boom } = require('@hapi/boom');

// Membuat penyimpanan dalam memori
const store = require('@whiskeysockets/baileys').makeInMemoryStore({});
store.readFromFile('./baileys_store.json');

// Menyimpan data ke file setiap 10 detik
setInterval(() => {
  store.writeToFile('./baileys_store.json');
}, 10_000);

// Fungsi untuk delay
const delay = (ms) => new Promise(resolve => setTimeout(resolve, ms));

// Fungsi Helper untuk mengirim pesan
async function sendMessage(sock, jid, content) {
  try {
    await sock.sendMessage(jid, content);
    console.log('Pesan berhasil dikirim:', content);
  } catch (error) {
    console.error('Gagal mengirim pesan:', error.toString());
  }
}

// Fungsi validasi URL
const isValidUrl = (url) => {
  try {
    new URL(url);
    return true;
  } catch (error) {
    return false;
  }
};

// Fungsi untuk menangani pesan
async function handleMessage(sock, message) {
  const jid = message.key.remoteJid;

  if (message.message.conversation) {
    const text = message.message.conversation.toLowerCase();

    if (text === 'ping') {
      await sendMessage(sock, jid, { text: 'pong' });
    } else {
      console.log('Pesan lain:', message.message.conversation);
    }
  }
}

// Fungsi koneksi ke WhatsApp
async function connectToWhatsApp() {
  let presenceInterval;

  try {
    // Menggunakan auth state dari file
    const { state, saveCreds } = await useMultiFileAuthState('auth_info');

    // Membuat koneksi WhatsApp
    const sock = makeWASocket({
      auth: state,
      printQRInTerminal: true
    });

    // Set interval untuk update presence
    presenceInterval = setInterval(() => {
      sock.sendPresenceUpdate('unavailable');
    }, 3000);

    // Mendengarkan peristiwa messages.upsert
    sock.ev.on('messages.upsert', async ({ messages }) => {
      for (const m of messages) {
        if (!m.message || !m.key || !m.key.remoteJid) continue;
        await handleMessage(sock, m);
      }
    });

    // Mendengarkan peristiwa connection.update
    sock.ev.on('connection.update', async (update) => {
      const { connection, lastDisconnect } = update;

      switch (connection) {
        case 'close':
          clearInterval(presenceInterval);
          if (lastDisconnect.error) {
            const isBoom = lastDisconnect.error instanceof Boom;
            const shouldReconnect = isBoom && lastDisconnect.error.output?.statusCode !== DisconnectReason.loggedOut 
                                    && lastDisconnect.error.output?.statusCode !== DisconnectReason.badSession;
            console.log({ event: 'Connection closed', reason: lastDisconnect.error.message, shouldReconnect });

            if (shouldReconnect) {
              await delay(5000);
              connectToWhatsApp();
            }
          }
          break;

        case 'open':
          console.log({ event: 'Connection opened' });
          clearInterval(presenceInterval);
          presenceInterval = setInterval(() => {
            sock.sendPresenceUpdate('unavailable');
          }, 3000);
          break;
      }
    });

    // Binding store ke event
    store.bind(sock.ev);
    sock.ev.on('creds.update', saveCreds);

  } catch (error) {
    console.error({ event: 'Connection error', error: error.toString() });
    clearInterval(presenceInterval); // Pastikan interval selalu dibersihkan
  }
}

// Memulai koneksi WhatsApp
connectToWhatsApp();
