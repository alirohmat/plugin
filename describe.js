import axios from "axios";
import FormData from "form-data";
import { GoogleGenerativeAI } from "@google/generative-ai";
import fs from "fs";

// API Key langsung dimasukkan di sini
const API_KEY = "AIzaSyAaoUcXXAowS1JFOEPnMWCbNJg7ys3GrPw"; // Ganti dengan API Key Anda
const genAI = new GoogleGenerativeAI(API_KEY);

export default {
  cmd: ["describe"],
  name: "describe",
  category: "tools",
  description: "Menghasilkan deskripsi dari gambar yang diterima atau di-reply",
  execute: async (m, { client }) => {
    const quoted = m.isQuoted ? m.quoted : m;

    // Mengecek apakah yang diterima adalah gambar
    if (!/image\/(jpe?g|png)/.test(quoted.mime)) {
      return m.reply(
        `Reply/Kirim gambar dengan caption ${m.prefix + m.command}\nFormat yang didukung: JPEG/PNG`
      );
    }

    try {
      m.reply("Sedang menganalisa gambar untuk deskripsi...");

      // Mengunduh gambar yang diterima
      const media = await quoted.download();
      const filePath = `/tmp/received_image_${Date.now()}.jpg`; // Menyimpan gambar sementara

      // Menyimpan gambar sementara
      fs.writeFileSync(filePath, media);

      // Membuat objek gambar untuk dikirim ke Google Generative AI
      const imagePart = fileToGenerativePart(filePath, quoted.mime);

      // Menggunakan model Gemini untuk menghasilkan deskripsi gambar
      const model = genAI.getGenerativeModel({ model: "gemini-1.5-flash" });
      const prompt = "Describe the content of this image:";

      const result = await model.generateContent([prompt, imagePart]);
      const response = await result.response;
      const text = await response.text();

      // Mengirimkan hasil deskripsi gambar kepada pengguna
      await m.reply(`Deskripsi gambar:\n${text}`);

      // Menghapus file gambar sementara
      fs.unlinkSync(filePath);
    } catch (error) {
      client.logger.error(error);
      m.reply(`❌ Terjadi kesalahan: ${error.message}`);
    }
  },
};

// Fungsi untuk mengonversi file menjadi bagian yang diterima oleh GoogleGenerativeAI
function fileToGenerativePart(path, mimeType) {
  return {
    inlineData: {
      data: Buffer.from(fs.readFileSync(path)).toString("base64"),
      mimeType
    },
  };
}
