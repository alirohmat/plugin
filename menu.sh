#!/bin/bash

# === FILE: menu.sh (Instalasi Otomatis dengan Log - FIXED) ===

echo "==========================================="
echo "     Instalasi Menu VNC Otomatis (Dengan Log)"
echo "==========================================="

# Cek apakah dijalankan sebagai root
if [ "$EUID" -ne 0 ]; then
  echo "❌ Error: Script ini harus dijalankan sebagai root!"
  echo "Gunakan: sudo ./menu.sh"
  exit 1
fi

# === Script menu kontrol (akan disimpan ke sistem) ===
MENU_SCRIPT='#!/bin/bash

# === CONFIG ===
USERNAME="vncuser"
DISPLAY_NUM="2"
SCREEN_RES="1244x600x24"
VNC_PASS="senori8899"
VNC_PORT="5902"
SERVICE_NAME="chrome-vnc.service"

# Fungsi untuk setup awal (instalasi)
setup_vnc() {
    echo "[*] Memulai setup VNC + Chrome..."

    # === CREATE USER IF NOT EXIST ===
    if ! id "$USERNAME" >/dev/null 2>&1; then
        echo "[*] Membuat user $USERNAME ..."
        useradd -m -s /bin/bash "$USERNAME"
    fi

    # === INSTALL DEPENDENCIES ===
    echo "[*] Menginstal dependensi..."
    apt update
    apt install -y xvfb x11vnc wget gnupg

    # === INSTALL GOOGLE CHROME ===
    if ! command -v google-chrome >/dev/null 2>&1; then
        echo "[*] Menginstal Google Chrome..."
        wget https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
        apt install -y ./google-chrome-stable_current_amd64.deb
    fi

    # === CREATE SYSTEMD SERVICE (FIXED) ===
    echo "[*] Membuat service systemd..."

    cat > /etc/systemd/system/$SERVICE_NAME << 'EOF'
[Unit]
Description=Chrome via Xvfb + x11vnc (Layar Landscape)
After=network.target

[Service]
Type=forking
User=vncuser
Environment=DISPLAY=:2
ExecStartPre=/bin/sleep 3
ExecStart=/bin/bash -c "Xvfb :2 -screen 0 1244x600x24 & x11vnc -display :2 -passwd senori8899 -forever -shared -rfbport 5902 -o /tmp/x11vnc.log & google-chrome --no-sandbox --disable-gpu --disable-dev-shm-usage --force-device-scale-factor=0.8 --window-size=1244,600 &"
ExecStop=/bin/bash -c "pkill -f Xvfb; pkill -f x11vnc; pkill -f google-chrome"
Restart=always

[Install]
WantedBy=multi-user.target
EOF

    # === RELOAD & ENABLE SERVICE ===
    systemctl daemon-reload
    systemctl enable $SERVICE_NAME
    systemctl restart $SERVICE_NAME

    # Cek status
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        echo
        echo "========================================================"
        echo " Chrome + VNC (layar landscape) sudah aktif!"
        echo " Akses VNC:  IP_VPS:$VNC_PORT"
        echo " Display:    :$DISPLAY_NUM"
        echo " Ukuran Layar: $SCREEN_RES"
        echo " Password:   $VNC_PASS"
        echo "========================================================"
    else
        echo
        echo "⚠️  Ada masalah saat memulai service."
        echo "Silakan cek status service dengan:"
        echo "  systemctl status $SERVICE_NAME"
        echo "  journalctl -u $SERVICE_NAME -n 20"
        echo
    fi
}

# Fungsi untuk mengecek status layanan
status_service() {
    systemctl is-active --quiet "$SERVICE_NAME"
    if [ $? -eq 0 ]; then
        echo "✅ Status: $SERVICE_NAME berjalan (active)"
    else
        echo "❌ Status: $SERVICE_NAME tidak berjalan (inactive)"
    fi
}

# Fungsi untuk restart service
restart_service() {
    echo "[*] Merestart $SERVICE_NAME..."
    systemctl restart "$SERVICE_NAME"
    sleep 3
    status_service
}

# Fungsi untuk stop service
stop_service() {
    echo "[*] Menghentikan $SERVICE_NAME..."
    systemctl stop "$SERVICE_NAME"
    sleep 2
    status_service
}

# Fungsi untuk start service
start_service() {
    echo "[*] Memulai $SERVICE_NAME..."
    systemctl start "$SERVICE_NAME"
    sleep 3
    status_service
}

# Fungsi untuk lihat log
show_logs() {
    echo "[*] Log dari $SERVICE_NAME:"
    journalctl -u "$SERVICE_NAME" -n 20 --no-pager
}

# Fungsi untuk restart hanya Xvfb dan x11vnc (tanpa restart Chrome)
restart_xvfb_vnc() {
    echo "[*] Restart Xvfb dan x11vnc (Chrome tetap jalan)..."
    sudo -u "$USERNAME" pkill -f "x11vnc"
    sudo -u "$USERNAME" pkill -f "Xvfb"

    sleep 3

    sudo -u "$USERNAME" bash -c "
        DISPLAY=:$DISPLAY_NUM Xvfb :$DISPLAY_NUM -screen 0 $SCREEN_RES &
        sleep 2
        x11vnc -display :$DISPLAY_NUM -passwd '"'"'$VNC_PASS'"'"' -forever -shared -rfbport $VNC_PORT &
    " &
    echo "✅ Xvfb dan x11vnc telah di-restart. Chrome tetap jalan."
}

# Fungsi untuk restart Chrome & Display tanpa restart service
restart_chrome_display() {
    echo "[*] Restart Chrome & Xvfb display (tanpa restart service)..."
    sudo -u "$USERNAME" pkill -f "google-chrome"
    sudo -u "$USERNAME" pkill -f "x11vnc"
    sudo -u "$USERNAME" pkill -f "Xvfb"

    sleep 3

    sudo -u "$USERNAME" bash -c "
        DISPLAY=:$DISPLAY_NUM Xvfb :$DISPLAY_NUM -screen 0 $SCREEN_RES &
        sleep 2
        x11vnc -display :$DISPLAY_NUM -passwd '"'"'$VNC_PASS'"'"' -forever -shared -rfbport $VNC_PORT &
        sleep 2
        google-chrome --no-sandbox --disable-gpu --disable-dev-shm-usage --force-device-scale-factor=0.8 --window-size=1244,600 &
    " &
    echo "✅ Chrome dan VNC display telah di-restart."
}

# Fungsi untuk menampilkan detail login VNC
show_vnc_details() {
    IP=$(curl -s ifconfig.co 2>/dev/null || echo "GAGAL_MENDAPAT_IP")

    echo
    echo "==========================================="
    echo "     Detail Login VNC"
    echo "==========================================="
    echo "Alamat IP VPS: $IP"
    echo "Port VNC:      $VNC_PORT"
    echo "Display:       :$DISPLAY_NUM"
    echo "Ukuran Layar:  $SCREEN_RES"
    echo "Password VNC:  $VNC_PASS"
    echo ""
    echo "Cara Akses:"
    echo "  VNC Viewer -> Masukkan: $IP:$VNC_PORT"
    echo "  Password: $VNC_PASS"
    echo "==========================================="
    echo
}

# Fungsi untuk menampilkan menu
show_menu() {
    clear
    echo "==========================================="
    echo "     Menu Kontrol VNC (Chrome Virtual)"
    echo "==========================================="
    echo "1. Setup VNC (Instalasi awal)"
    echo "2. Status Service"
    echo "3. Start Service"
    echo "4. Stop Service"
    echo "5. Restart Service"
    echo "6. Lihat Log"
    echo "7. Restart Xvfb + VNC (tanpa restart Chrome)"
    echo "8. Restart Chrome & Display (tanpa restart service)"
    echo "9. Lihat Detail Login VNC"
    echo "0. Keluar"
    echo "==========================================="
    read -p "Pilih opsi [0-9]: " choice
}

# Loop utama
while true; do
    show_menu
    case $choice in
        1)
            setup_vnc
            ;;
        2)
            status_service
            ;;
        3)
            start_service
            ;;
        4)
            stop_service
            ;;
        5)
            restart_service
            ;;
        6)
            show_logs
            ;;
        7)
            restart_xvfb_vnc
            ;;
        8)
            restart_chrome_display
            ;;
        9)
            show_vnc_details
            ;;
        0)
            echo "Keluar dari menu."
            exit 0
            ;;
        *)
            echo "Opsi tidak valid. Silakan pilih 0-9."
            ;;
    esac

    echo
    read -p "Tekan [Enter] untuk kembali ke menu..."
done
'

# === Simpan script ke sistem ===
echo "[*] Menyimpan script menu ke sistem..."
echo "$MENU_SCRIPT" > /usr/local/bin/menu

# === Beri izin eksekusi ===
chmod +x /usr/local/bin/menu

# === Selesai ===
echo
echo "✅ Instalasi selesai!"
echo "Sekarang kamu bisa mengetik 'menu' di terminal untuk mengontrol VNC."
echo
echo "Contoh:"
echo "  menu"
echo    case $choice in
        1)
            setup_vnc
            ;;
        2)
            status_service
            ;;
        3)
            start_service
            ;;
        4)
            stop_service
            ;;
        5)
            restart_service
            ;;
        6)
            show_logs
            ;;
        7)
            restart_xvfb_vnc
            ;;
        8)
            restart_chrome_display
            ;;
        9)
            show_vnc_details
            ;;
        0)
            echo "Keluar dari menu."
            exit 0
            ;;
        *)
            echo "Opsi tidak valid. Silakan pilih 0-9."
            ;;
    esac

    echo
    read -p "Tekan [Enter] untuk kembali ke menu..."
done
'

# === Simpan script ke sistem ===
echo "[*] Menyimpan script menu ke sistem..."
echo "$MENU_SCRIPT" > /usr/local/bin/menu

# === Beri izin eksekusi ===
chmod +x /usr/local/bin/menu

# === Selesai ===
echo
echo "✅ Instalasi selesai!"
echo "Sekarang kamu bisa mengetik 'menu' di terminal untuk mengontrol VNC."
echo
echo "Contoh:"
echo "  menu"
echo
