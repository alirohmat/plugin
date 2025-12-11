#!/bin/bash

# ===============================
# AUTO SETUP VPS DENGAN ANIMASI
# ===============================

spinner() {
    local pid=$1
    local delay=0.15
    local spin=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')

    while kill -0 "$pid" 2>/dev/null; do
        for i in "${spin[@]}"; do
            echo -ne "\r$i $SPIN_TEXT"
            sleep $delay
        done
    done
    echo -ne "\r✔ $SPIN_TEXT\n"
}

run_with_spinner() {
    SPIN_TEXT="$1"
    shift
    ("$@" &> /dev/null) &
    cmd_pid=$!
    spinner $cmd_pid
}

echo "========================================"
echo " AUTO SETUP VPS DEBIAN (GUI + DEV TOOLS)"
echo "========================================"

# ------------------------------
# 1. Ganti repository Debian
# ------------------------------
run_with_spinner "Mengganti repository..." bash -c '
cat <<EOF > /etc/apt/sources.list
deb http://deb.debian.org/debian/ trixie main contrib non-free non-free-firmware
deb http://deb.debian.org/debian/ trixie-updates main contrib non-free non-free-firmware
deb http://security.debian.org/debian-security trixie-security main contrib non-free non-free-firmware
EOF
'

# ------------------------------
# 2. Update + upgrade Debian
# ------------------------------
run_with_spinner "Update paket..." apt update
run_with_spinner "Upgrade paket..." apt upgrade -y

# ------------------------------
# 3. Install XRDP + XFCE
# ------------------------------
run_with_spinner "Menginstal XFCE4..." apt install -y xfce4
run_with_spinner "Menginstal XRDP..." apt install -y xrdp
systemctl enable xrdp --now

# ------------------------------
# 4. Buat user ali
# ------------------------------
run_with_spinner "Membuat user ali..." bash -c '
useradd -m -s /bin/bash ali
echo "ali:senori8899" | chpasswd
usermod -aG sudo ali
echo "xfce4-session" > /home/ali/.xsession
chown ali:ali /home/ali/.xsession
chmod +x /home/ali/.xsession
'

# ------------------------------
# 5. Install Google Chrome
# ------------------------------
run_with_spinner "Menginstal Chrome..." bash -c '
apt install -y wget gpg
wget https://dl.google.com/linux/linux_signing_key.pub -O - | gpg --dearmor > /usr/share/keyrings/google-linux-keyring.gpg
chmod 644 /usr/share/keyrings/google-linux-keyring.gpg
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/google-linux-keyring.gpg] https://dl.google.com/linux/chrome/deb/ stable main" > /etc/apt/sources.list.d/google-chrome.list
apt update
apt install -y google-chrome-stable
'

# ------------------------------
# 6. Install NVM (v0.40.3)
# ------------------------------
run_with_spinner "Menginstal NVM..." sudo -u ali bash -c '
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash
echo "export NVM_DIR=\"\$HOME/.nvm\"" >> ~/.bashrc
echo "[ -s \"\$NVM_DIR/nvm.sh\" ] && \\. \"\$NVM_DIR/nvm.sh\"" >> ~/.bashrc
'

# ------------------------------
# 7. Install VS Code
# ------------------------------
run_with_spinner "Menginstal VS Code..." bash -c '
wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > /usr/share/keyrings/packages.microsoft.gpg
chmod 644 /usr/share/keyrings/packages.microsoft.gpg
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/vscode stable main" > /etc/apt/sources.list.d/vscode.list
apt update
apt install -y code
'

echo "============================================="
echo "  SEMUA PROSES SELESAI!"
echo "  Login XRDP memakai:"
echo "  User     : ali"
echo "  Password : senori8899"
echo "============================================="
