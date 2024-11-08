import { exec } from 'child_process';

export default (handler) => {
    handler.reg({
        cmd: ['wget'],
        tags: 'main',
        desc: 'Simple downloader to display response only',
        isLimit: true,
        run: async (m) => {
            if (!m.text) return m.reply('Silahkan masukan link untuk mengunduh');

            // Jalankan wget dan tampilkan hasil respon saja
            exec(`wget --spider ${m.text}`, (error, stdout, stderr) => {
                if (error) {
                    return m.reply(`Gagal mengunduh: ${error.message}`);
                }
                
                // Jika ada output atau error dari wget, tampilkan ke pengguna
                const response = stdout || stderr;
                m.reply(response || 'Tidak ada respon dari wget');
            });
        }
    });
}
