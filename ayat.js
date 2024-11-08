import fetch from 'node-fetch';

export default (handler) => {
    handler.reg({
        cmd: ['ayat', 'quran'],
        tags: 'main',
        desc: 'Kirim ayat, terjemahan, dan media dari Quran secara random',
        isLimit: true,
        run: async (m, { sock }) => {
            const url = 'URL_API_YANG_KAMU_GUNAKAN';  // Ganti dengan URL API Anda

            try {
                // Ambil data dari API
                const response = await fetch(url);
                const data = await response.json();

                // Menyiapkan pesan dengan teks Arab, terjemahan, dan tautan audio
                const textMessage = `*Ayat di dalam Quran:* ${data.number.inQuran} (Surah ${data.number.inSurah})
                
*Arab:* ${data.arab}

*Terjemahan:* ${data.translation}`;

                // Mengirim gambar utama ayat
                await sock.sendMessage(m.from, { image: { url: data.image.primary }, caption: textMessage });

                // Mengirim audio dari qari tertentu, misalnya alafasy
                await sock.sendMessage(m.from, { audio: { url: data.audio.alafasy }, mimetype: 'audio/mp4' });

                // Menambahkan tafsir pendek dari Kemenag
                const tafsirMessage = `*Tafsir Pendek:*\n${data.tafsir.kemenag.short}`;
                await sock.sendMessage(m.from, { text: tafsirMessage });

            } catch (error) {
                m.reply(`Gagal mengambil data: ${error.message}`);
            }
        }
    });
}
