import pkg from 'nayan-media-downloader'
const twitterdown = pkg.twitterdown

export default (handler) => {
    handler.reg({
        cmd: ['twitter', 'twtdl', 'twdl'],
        tags: 'downloader',
        desc: 'Twitter video downloader',
        isLimit: true,
        run: async (m, { sock }) => {
            if (!m.text) return m.reply('Silahkan masukkan link Twitter.')

            // Validasi URL Twitter
            const isValidURL = /^(https?:\/\/)?(www\.)?twitter\.com/.test(m.text)
            if (!isValidURL) return m.reply('Link tidak valid. Pastikan menggunakan link Twitter yang benar.')

            try {
                // Menggunakan nayan-media-downloader untuk mengunduh media Twitter
                const result = await twitterdown(m.text)

                if (!result || !result.status) {
                    return m.reply('Permintaan tidak dapat diproses!')
                }

                m.react("⏱️")

                // Kirim setiap media yang ada di dalam result.data
                await Promise.all(result.data.map(it => sock.sendMedia(m.from, it.url, m)))

                m.react("✅")
            } catch (error) {
                console.error(error)
                m.reply('Terjadi kesalahan saat memproses permintaan.')
            }
        }
    })
}
