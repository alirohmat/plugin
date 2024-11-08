import axios from 'axios';

export default (handler) => {
    handler.reg({
        cmd: ['ayat', 'quran'],
        tags: 'main',
        desc: 'Kirim ayat, terjemahan, dan media dari Quran',
        isLimit: false,
        run: async (m, { sock }) => {
            const url = 'https://quran-api-id-smoky.vercel.app/random';  // Ganti dengan URL API Anda

            try {
                // Ambil data dari API menggunakan axios
                const response = await axios.get(url);
                const data = response.data;

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
