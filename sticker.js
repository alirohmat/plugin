import ffmpegPath from 'ffmpeg-static'; // Mengimpor ffmpeg-static
import ffmpeg from 'fluent-ffmpeg';

ffmpeg.setFfmpegPath(ffmpegPath); // Menetapkan path ffmpeg dari ffmpeg-static

export default (handler) => {
    // Menu Sticker
    handler.reg({
        cmd: ["sticker", "stiker"],
        tags: "convert",
        desc: "Convert image/video to sticker",
        isLimit: true,
        run: async (m, { sock }) => {
            const quoted = m.isQuoted ? m.quoted : m;

            // Debug: Log MIME dan informasi file
            console.log("Quoted MIME: ", quoted.mime);
            console.log("Quoted Message: ", quoted);

            // Periksa apakah file yang dikutip adalah gambar atau video
            if (/image|video|webp/i.test(quoted.mime)) {
                m.reply("Processing, please wait...");

                try {
                    // Mengunduh buffer dari pesan yang dikutip
                    const buffer = await quoted.download();
                    console.log("Buffer received: ", buffer);

                    // Memeriksa jika video melebihi durasi 10 detik
                    if (quoted?.msg?.seconds > 10) {
                        return m.reply("Max video length is 10 seconds.");
                    }

                    // Metadata untuk stiker
                    let exif = {
                        packName: "Made by Bot",
                        author: "YourName",
                    };

                    // Mengambil packName dan author jika diinput oleh pengguna
                    if (m.text) {
                        let [packname, author] = m.text.split("|");
                        exif.packName = packname ? packname.trim() : exif.packName;
                        exif.author = author ? author.trim() : exif.author;
                    }

                    // Mengonversi buffer menjadi stiker dan mengirimnya kembali
                    await sock.sendMessage(m.chat, { sticker: buffer }, { 
                        quoted: m,
                        asSticker: true, 
                        packname: exif.packName, 
                        author: exif.author 
                    });
                    
                } catch (error) {
                    console.error("Error converting to sticker:", error);
                    m.reply("Failed to process sticker. Please try again.");
                }
            } else {
                m.reply("Please send an image or video to convert to sticker.");
            }
        }
    });
};
