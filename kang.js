import axios from 'axios';

export default (handler) => {
    handler.reg({
        cmd: ['gemini', 'geminiai'],
        tags: 'ai',
        desc: 'Gemini Pro',
        isLimit: true,
        run: async (m) => {
            async function getGeminiAIResponse(text, user) {
                try {
                    const response = await axios.post(
                        'https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash-latest:generateContent?key=YOUR_API_KEY',
                        {
                            contents: [
                                {
                                    parts: [
                                        {
                                            text: text
                                        }
                                    ]
                                }
                            ]
                        },
                        {
                            headers: {
                                'Content-Type': 'application/json'
                            }
                        }
                    );

                    return response.data; // Sesuaikan dengan struktur respons API
                } catch (error) {
                    console.error("Terjadi kesalahan:", error.message);
                    throw new Error("Gagal mendapatkan respons dari AI.");
                }
            }

            try {
                const budy = m.text;
                const user = m.sender;
                const result = await getGeminiAIResponse(budy, user);

                const output = typeof result === 'object' ? JSON.stringify(result, null, 2) : result;

                m.reply(output)
            } catch (error) {
                console.error("Error:", error.message);
                m.reply("Terjadi kesalahan dalam mendapatkan respons.");
            }
        },
    });
};
