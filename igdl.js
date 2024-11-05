import pkg from 'nayan-media-downloader'
const { instagram } = pkg

export default (handler) => {
    handler.reg({
        cmd: ['ig', 'igdl'],
        tags: 'downloader',
        desc: 'Instagram downloader (support reel/story)',
        isLimit: true,
        run: async (m, { sock }) => {
            if (!m.text) return m.reply('Silahkan masukkan link Instagram (support reel/story)')

            // Validasi URL Instagram
            const isValidURL = /^(https?:\/\/)?(www\.)?instagram\.com/.test(m.text)
            if (!isValidURL) return m.reply('Link tidak valid. Pastikan menggunakan link Instagram yang benar.')

            try {
                // Menggunakan nayan-media-downloader untuk mengunduh media
                const result = await instagram(m.text)

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
