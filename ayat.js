import axios from 'axios'

export default (handler) => {
    handler.reg({
        cmd: ['ayat', 'ayat'],
        tags: 'main',
        desc: 'Mengambil ayat Alquran',
        isLimit: true,
        run: async (m, { sock }) => {
            // Memastikan ada nomor ayat yang diminta
            const ayatNumber = m.text ? m.text.trim() : null;
            if (!ayatNumber) return m.reply('Silahkan masukkan nomor ayat Alquran yang ingin diambil.');

            // Mengambil data ayat dari API
            try {
                const response = await axios.get(`https://api.quran.sindbad.dev/ayat/${ayatNumber}`);
                const ayat = response.data.data;

                // Memeriksa apakah data ayat ditemukan
                if (!ayat) return m.reply('Ayat tidak ditemukan.');

                // Menyusun pesan untuk mengirimkan ayat
                const message = `
Ayat: ${ayat.verse}
Teks: ${ayat.text}
Terjemahan: ${ayat.translation}
Audio: ${ayat.audio_url}
Tafsir: ${ayat.tafsir}
                `.trim();

                // Mengirim pesan ayat ke chat
                await sock.sendMessage(m.from, { text: message });
                m.react("✅");
            } catch (error) {
                console.error(error);
                m.reply('Terjadi kesalahan saat mengambil ayat Alquran. Silahkan coba lagi.');
            }
        }
    });
}
