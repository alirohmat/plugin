const { makeWASocket, DisconnectReason, useMultiFileAuthState } = require('@whiskeysockets/baileys');
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

// Fungsi untuk menangani pesan
async function handleMessage(sock, message) {
  const jid = message.key.remoteJid;
  console.log('Received message:', message); // Log untuk memeriksa pesan yang diterima

  if (message.message.conversation) {
    const text = message.message.conversation.toLowerCase();
    console.log(`Received message text: ${text}`); // Log pesan yang diterima

    if (text === 'ping') {
      try {
        await sock.sendMessage(jid, { text: 'pong' });
        console.log(`Sent response: pong to ${jid}`); // Log pesan yang dikirim
      } catch (error) {
        console.error('Error sending response:', error);
      }
    } else {
      console.log('Received non-ping message:', text);
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
      console.log('Received messages:', messages); // Log untuk memeriksa pesan yang diterima
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
