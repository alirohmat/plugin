import pkg from 'nayan-media-downloader';
const { instagram } = pkg;

export default (handler) => {
    handler.reg({
        cmd: ['igdown'],
        tags: 'downloader',
        desc: 'Instagram downloader Library nayan media',
        isLimit: false,
        run: async (m, { sock }) => {
            if (!m.text) return m.reply('Silahkan masukkan link Instagram (support reel/story)');

            // Validasi URL Instagram
            const isValidURL = /^(https?:\/\/)?(www\.)?instagram\.com\/(reel|stories)\//.test(m.text);
            if (!isValidURL) return m.reply('Link tidak valid. Pastikan menggunakan link Instagram reel atau story yang benar.');

            try {
                // Menggunakan nayan-media-downloader untuk mengunduh media
                const result = await instagram(m.text);

                if (!result || !result.status) {
                    return m.reply('Permintaan tidak dapat diproses!');
                }

                // Reaksi saat proses berlangsung
                if (m.react) m.react("⏱️");

                // Kirim setiap media yang ada di dalam result.data
                await Promise.all(result.data.map(it => sock.sendMedia(m.from, it.url, m)));

                if (m.react) m.react("✅");
            } catch (error) {
                console.error('Error saat mengunduh media:', error);
                m.reply('Terjadi kesalahan saat memproses permintaan.');
            }
        }
    });
}
