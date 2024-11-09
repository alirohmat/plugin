import axios from 'axios';

export default (handler) => {
    handler.reg({
        cmd: ['extract'],
        tags: 'tools',
        desc: 'Ekstrak konten dari URL',
        isLimit: false,
        run: async (m) => {
            const tavilyApiKey = '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'; // Ganti dengan Tavily API Key kamu
            const urls = m.text.split(' '); // Mengambil URL dari pesan yang dikirim

            async function extractContentFromUrls(urls) {
                try {
                    const response = await axios.post(
                        'https://api.tavily.com/extract',
                        {
                            api_key: tavilyApiKey,
                            urls: urls
                        },
                        {
                            headers: {
                                'Content-Type': 'application/json'
                            }
                        }
                    );

                    const { results, failed_results } = response.data;

                    // Proses hasil ekstraksi
                    let message = '📄 *Hasil Ekstraksi Konten* 📄\n\n';
                    results.forEach(result => {
                        // Pisahkan konten menjadi paragraf dan tampilkan dengan format rapi
                        const paragraphs = result.raw_content.split('\n').filter(p => p.trim() !== '').join('\n\n');

                        message += `🌐 *URL*: ${result.url}\n\n📖 *Konten Ekstraksi*: \n${paragraphs}\n\n======\n\n`;
                    });

                    if (failed_results.length > 0) {
                        message += '❗ *Gagal Ekstraksi* ❗\n\n';
                        failed_results.forEach(failed => {
                            message += `🚫 URL: ${failed.url}\n🔍 Error: ${failed.error}\n\n`;
                        });
                    }

                    return message;
                } catch (error) {
                    console.error("Terjadi kesalahan:", error.message);
                    throw new Error("Gagal mengekstrak konten dari URL.");
                }
            }

            try {
                const resultMessage = await extractContentFromUrls(urls);
                m.reply(resultMessage); // Balas dengan hasil ekstraksi
            } catch (error) {
                console.error("Error:", error.message);
                m.reply("Terjadi kesalahan dalam mengekstrak konten.");
            }
        },
    });
};
