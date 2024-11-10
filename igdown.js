import axios from 'axios';

export default (handler) => {
    handler.reg({
        cmd: ['igdown'],
        tags: 'downloader',
        desc: 'Instagram video downloader',
        isLimit: false,
        run: async (m, { sock }) => {
            // Cek apakah pengguna telah memasukkan link Instagram
            if (!m.text) return m.reply('Silahkan masukkan link Instagram (support reel/story)');

            try {
                // Panggil API eksternal untuk mendapatkan link download video
                const response = await axios.get(`https://instagram-video-downloader-henna.vercel.app/api/video?postUrl=${encodeURIComponent(m.text)}`);
                
                // Periksa status respons API
                if (response.data.status !== 'success' || !response.data.data.videoUrl) {
                    return m.reply('Permintaan tidak dapat diproses atau video tidak ditemukan!');
                }
                
                // Reaksi sementara proses berjalan
                m.react("⏱️");

                // Kirim video ke pengguna
                await sock.sendMedia(m.from, response.data.data.videoUrl, m, {
                    caption: `Berikut adalah video yang Anda minta:`
                });

                // Reaksi setelah selesai
                m.react("✅");
            } catch (error) {
                console.error('Error saat memproses permintaan:', error);
                m.reply('Terjadi kesalahan saat mengambil video. Coba lagi nanti.');
            }
        }
    });
}
