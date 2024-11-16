const makeWASocket = require('@whiskeysockets/baileys').default;
const { useMultiFileAuthState } = require('@whiskeysockets/baileys');
const { DisconnectReason } = require('@whiskeysockets/baileys');
const { Boom } = require('@hapi/boom');

let presenceInterval; // Mendefinisikan presenceInterval di luar fungsi
let isLoggedIn = false; // Mendefinisikan isLoggedIn di luar fungsi

// Fungsi untuk menunda eksekusi
function delay(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

// Fungsi utama untuk koneksi ke WhatsApp
async function connectToWhatsApp() {
  try {
    // Menggunakan auth state dari file
    const { state, saveCreds } = await useMultiFileAuthState('auth_info');

    // Membuat koneksi WhatsApp
    const sock = makeWASocket({
      auth: state,
      printQRInTerminal: true,
    });

    // Mendengarkan event connection.update
    sock.ev.on('connection.update', async (update) => {
      const { connection, lastDisconnect } = update;

      if (connection === 'close') {
        // Koneksi ditutup
        clearInterval(presenceInterval); // Hentikan interval
        isLoggedIn = false; // Set status login ke false

        if (lastDisconnect?.error) {
          const isBoom = lastDisconnect.error instanceof Boom;
          const shouldReconnect =
            isBoom &&
            lastDisconnect.error.output?.statusCode !== DisconnectReason.loggedOut &&
            lastDisconnect.error.output?.statusCode !== DisconnectReason.badSession;

          console.log({
            event: 'Connection closed',
            reason: lastDisconnect.error.message,
            shouldReconnect,
          });

          if (shouldReconnect) {
            console.log('Reconnecting in 5 seconds...');
            await delay(5000);
            connectToWhatsApp();
          }
        }
      } else if (connection === 'open') {
        // Koneksi berhasil
        console.log({ event: 'Connection opened' });
        isLoggedIn = true; // Set status login ke true

        clearInterval(presenceInterval); // Hapus interval sebelumnya jika ada
        presenceInterval = setInterval(() => {
          if (isLoggedIn) {
            sock.sendPresenceUpdate('unavailable'); // Kirim presence update
          }
        }, 3000);
      }
    });

    // Binding auth state ke event
    sock.ev.on('creds.update', saveCreds);

    // Mendengarkan event messages.upsert dan menampilkan pesan masuk
    sock.ev.on('messages.upsert', ({ messages }) => {
      console.log('Got messages:', messages);
      for (const m of messages) {
        if (!m.message || !m.key || !m.key.remoteJid) continue;
        // Tangani pesan masuk
        handleMessage(sock, m);
      }
    });
  } catch (error) {
    console.error({ event: 'Connection error', error: error.toString() });
    clearInterval(presenceInterval); // Hentikan interval jika ada error
  }
}

// Fungsi untuk menangani pesan masuk
async function handleMessage(sock, message) {
  try {
    // Tangani pesan masuk
    if (message.message && message.message.conversation) {
      const msgText = message.message.conversation.trim().toLowerCase();

      if (msgText === 'ping') {
        console.log('Received "Ping", sending "Pong"...');
        // Mengirimkan balasan "Pong" ke pengirim pesan
        await sock.sendMessage(message.key.remoteJid, { text: 'Pong' });
      }
    }
  } catch (error) {
    console.error('Error handling message:', error);
  }
}

// Memulai koneksi ke WhatsApp
connectToWhatsApp();
