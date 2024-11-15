import { fileURLToPath } from 'url'; // Mengimpor fileURLToPath untuk mengonversi URL ke path
import { dirname } from 'path'; // Mengimpor dirname untuk mendapatkan direktori dari path
import ffmpegPath from 'ffmpeg-static'; 
import ffmpeg from 'fluent-ffmpeg';
import fs from 'fs';
import path from 'path';
import { promisify } from 'util';

ffmpeg.setFfmpegPath(ffmpegPath); 
const unlinkAsync = promisify(fs.unlink); 

// Mengonversi import.meta.url menjadi path yang bisa digunakan
const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

export default (handler) => {
    handler.reg({
        cmd: ["sticker", "stiker"],
        tags: "convert",
        desc: "Convert image/video to sticker",
        isLimit: true,
        run: async (m, { sock }) => {
            const quoted = m.isQuoted ? m.quoted : m;

            // Debug: Log MIME dan informasi file
            console.log("Quoted MIME: ", quoted?.message?.imageMessage?.mimetype);
            console.log("Quoted Message: ", quoted);

            // Periksa apakah file yang dikutip adalah gambar atau video
            const mimeType = quoted?.message?.imageMessage?.mimetype;
            if (mimeType && /image|video|webp/i.test(mimeType)) {
                m.reply("Processing, please wait...");

                try {
                    // Mengunduh buffer dari pesan yang dikutip
                    const buffer = await quoted.download();
                    console.log("Buffer received: ", buffer);

                    // Simpan file sementara
                    const extension = mimeType.split('/')[1];
                    if (!extension) {
                        m.reply("Invalid file type.");
                        return;
                    }
                    const tempFilePath = path.join(__dirname, `tempfile.${extension}`);
                    await fs.promises.writeFile(tempFilePath, buffer);
                    console.log(`File temporarily saved at: ${tempFilePath}`);

                    // Memeriksa jika video melebihi durasi 10 detik
                    if (quoted?.msg?.seconds > 10) {
                        await unlinkAsync(tempFilePath); // Hapus file sementara jika durasi video terlalu panjang
                        return m.reply("Max video length is 10 seconds.");
                    }

                    // Metadata untuk stiker
                    let exif = {
                        packName: "Made by Bot",
                        author: "YourName",
                    };

                    if (m.text) {
                        let [packname, author] = m.text.split("|");
                        exif.packName = packname ? packname.trim() : exif.packName;
                        exif.author = author ? author.trim() : exif.author;
                    }

                    // Mengonversi buffer menjadi stiker dan mengirimnya kembali
                    await sock.sendMessage(m.chat, { sticker: { url: tempFilePath } }, { 
                        quoted: m,
                        asSticker: true, 
                        packname: exif.packName, 
                        author: exif.author 
                    });

                    // Hapus file sementara setelah proses selesai
                    await unlinkAsync(tempFilePath);
                    console.log(`Temporary file deleted: ${tempFilePath}`);
                    
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
