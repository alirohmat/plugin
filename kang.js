import axios from 'axios';

export default (handler) => {
    handler.reg({
        cmd: ['kang'],
        tags: 'ai',
        desc: 'Gemini Pro token pribadi',
        isLimit: false,
        run: async (m) => {
            async function getGeminiAIResponse(text) {
                try {
                    const response = await axios.post(
                        'https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash-latest:generateContent?key=AIzaSyAaoUcXXAowS1JFOEPnMWCbNJg7ys3GrPw',
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

                    // Ambil teks dari respons API
                    const result = response.data.candidates[0].content.parts[0].text;
                    return result;
                } catch (error) {
                    console.error("Terjadi kesalahan:", error.message);
                    throw new Error("Gagal mendapatkan respons dari AI.");
                }
            }

            try {
                const budy = m.text;
                const result = await getGeminiAIResponse(budy);

                m.reply(result); // Balas dengan hasil teks
            } catch (error) {
                console.error("Error:", error.message);
                m.reply("Terjadi kesalahan dalam mendapatkan respons.");
            }
        },
    });
};
