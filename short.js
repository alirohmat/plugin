import axios from 'axios';

export default (handler) => {
    handler.reg({
        cmd: ['extract'],
        tags: 'tools',
        desc: 'Ekstrak konten dari URL dan ringkas menggunakan AI',
        isLimit: false,
        run: async (m) => {
            const tavilyApiKey = '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'; // Ganti dengan Tavily API Key kamu
            const groqApiKey = 'GROQ_API_KEY'; // Ganti dengan API Key Groq
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

                    let message = '📄 *Hasil Ekstraksi Konten* 📄\n\n';
                    for (const result of results) {
                        const paragraphs = result.raw_content.split('\n').filter(p => p.trim() !== '').join('\n\n');
                        message += `🌐 *URL*: ${result.url}\n\n📖 *Konten Ekstraksi*: \n${paragraphs}\n\n`;

                        // Ringkas konten menggunakan API AI
                        const summary = await summarizeContent(paragraphs);
                        message += `✍️ *Ringkasan Konten*: \n${summary}\n\n======\n\n`;
                    }

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

            async function summarizeContent(content) {
                try {
                    const response = await axios.post(
                        'https://api.groq.com/openai/v1/chat/completions',
                        {
                            messages: [
                                { role: 'system', content: 'Kamu bertugas membuat ringkasan dari konten yang diberikan' },
                                { role: 'user', content: `Hasil Ekstraksi:\n\n${content}` }
                            ],
                            model: 'llama-3.2-90b-text-preview',
                            temperature: 1,
                            max_tokens: 1024,
                            top_p: 1,
                            stream: false
                        },
                        {
                            headers: {
                                'Content-Type': 'application/json',
                                'Authorization': `Bearer ${groqApiKey}`
                            }
                        }
                    );

                    const summary = response.data.choices[0].message.content.trim();
                    return summary;
                } catch (error) {
                    console.error("Gagal merangkum konten:", error.message);
                    return "Gagal merangkum konten.";
                }
            }

            try {
                const resultMessage = await extractContentFromUrls(urls);
                m.reply(resultMessage); // Balas dengan hasil ekstraksi dan ringkasan
            } catch (error) {
                console.error("Error:", error.message);
                m.reply("Terjadi kesalahan dalam mengekstrak atau merangkum konten.");
            }
        },
    });
};
