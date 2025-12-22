#!/bin/bash
set -euo pipefail

# =====================================================
# KONFIGURASI
# =====================================================
BASE_DIR="/opt/vnc-manager"
MASTER_KEMU="/home/devtalk/kemulator"

SESSIONS="$BASE_DIR/sessions"
META="$BASE_DIR/meta"
LOG_DIR="$BASE_DIR/logs"
LOG="$LOG_DIR/activity.log"
TOKENS="$BASE_DIR/tokens.list"

XVFB_RES="240x340x16"
# Perbaikan: Hapus -noverify jika pakai Java 17, tambahkan penanganan sistem
JAVA_OPTS="-Xms32m -Xmx128m -Djava.awt.headless=false"
JAR_KEMU="KEmulator.jar"
JAR_GAME="ksatria_beta.jar"

LOCK="/tmp/vnc-manager.lock"

# =====================================================
# INIT & UTIL
# =====================================================
exec 9>"$LOCK" || exit 1
flock -n 9 || { echo "❌ Script sedang dipakai admin lain"; exit 1; }

mkdir -p "$SESSIONS" "$META" "$LOG_DIR"
touch "$LOG" "$TOKENS"

# Ambil IP Publik/Lokal secara otomatis
LOCAL_IP=$(hostname -I | awk '{print $1}')

log() {
  echo "[$(date '+%F %T')] $*" | tee -a "$LOG"
}

valid_name() {
  [[ "$1" =~ ^[a-zA-Z0-9_]+$ ]]
}

# =====================================================
# PORT & DISPLAY ENGINE
# =====================================================
port_free() {
  ! ss -ltn | grep -q ":$1 "
}

find_free_display() {
  for d in {1..99}; do
    [[ -f "/tmp/.X${d}-lock" ]] && continue
    port_free $((5900 + d)) && echo "$d" && return
  done
  return 1
}

find_free_web_port() {
  for p in {6080..6180}; do
    port_free "$p" && echo "$p" && return
  done
  return 1
}

# =====================================================
# PROCESS & SAFE KILL
# =====================================================
process_matches() {
  local pid="$1" must="$2"
  ps -p "$pid" -o cmd= 2>/dev/null | grep -q "$must"
}

safe_kill() {
  local pid="$1" must="$2"
  [[ -z "$pid" ]] && return 0
  if process_matches "$pid" "$must"; then
    kill "$pid" 2>/dev/null || true
    sleep 1
    kill -9 "$pid" 2>/dev/null || true
  fi
}

# =====================================================
# CREATE USER
# =====================================================
create_user() {
  read -rp "Nama user: " USER
  valid_name "$USER" || { echo "❌ Nama tidak valid"; return; }
  [[ ! -f "$META/$USER.env" ]] || { echo "❌ User sudah ada"; return; }

  read -rsp "Password VNC: " PASS
  echo

  DISP=$(find_free_display) || { echo "❌ Tidak ada DISPLAY"; return; }
  VNC_PORT=$((5900 + DISP))
  WEB_PORT=$(find_free_web_port) || { echo "❌ Tidak ada port web"; return; }

  # Bersihkan Lock X11 sisa crash
  rm -f "/tmp/.X${DISP}-lock" "/tmp/.X11-unix/X${DISP}"

  USER_DIR="$SESSIONS/$USER/kemulator"
  mkdir -p "$SESSIONS/$USER"
  cp -a "$MASTER_KEMU" "$USER_DIR"

  # 1. Jalankan Xvfb
  Xvfb ":$DISP" -screen 0 "$XVFB_RES" -ac +extension RANDR &
  XVFB_PID=$!
  sleep 2 # Beri waktu lebih lama

  # 2. Jalankan x11vnc
  x11vnc -display ":$DISP" -rfbport "$VNC_PORT" -passwd "$PASS" -forever -shared -bg -o "$SESSIONS/$USER/vnc.log"
  VNC_PID=$(pgrep -f "x11vnc.*$VNC_PORT")

  # 3. Jalankan Java (Output diarahkan ke log khusus user)
  cd "$USER_DIR"
  DISPLAY=":$DISP" java $JAVA_OPTS -jar "$JAR_KEMU" "$JAR_GAME" > "../session_java.log" 2>&1 &
  JAVA_PID=$!
  
  sleep 3 # Tunggu Java inisialisasi
  
  if ! ps -p "$JAVA_PID" >/dev/null; then
    echo "❌ Java gagal start. Cek log: $SESSIONS/$USER/session_java.log"
    safe_kill "$XVFB_PID" "Xvfb"
    return
  fi

  # Simpan Metadata
  cat > "$META/$USER.env" <<EOF
USER=$USER
DISPLAY=:$DISP
PORT_VNC=$VNC_PORT
PORT_WEB=$WEB_PORT
XVFB_PID=$XVFB_PID
VNC_PID=$VNC_PID
JAVA_PID=$JAVA_PID
EOF

  echo "$USER: localhost:$VNC_PORT" >> "$TOKENS"
  log "CREATE: $USER pada Display $DISP"
  
  echo "✅ Berhasil!"
  echo "URL: http://$LOCAL_IP:6080/vnc.html?token=$USER"
}

# =====================================================
# DELETE USER
# =====================================================
delete_user() {
  read -rp "Nama user: " USER
  [[ -f "$META/$USER.env" ]] || { echo "❌ User tidak ada"; return; }

  # Load metadata manual untuk menghindari 'source' yang tidak aman
  XV_PID=$(grep "XVFB_PID=" "$META/$USER.env" | cut -d= -f2)
  VN_PID=$(grep "VNC_PID=" "$META/$USER.env" | cut -d= -f2)
  JV_PID=$(grep "JAVA_PID=" "$META/$USER.env" | cut -d= -f2)

  safe_kill "$JV_PID" "java"
  safe_kill "$VN_PID" "x11vnc"
  safe_kill "$XV_PID" "Xvfb"

  rm -rf "$SESSIONS/$USER" "$META/$USER.env"
  sed -i "/^$USER:/d" "$TOKENS"
  echo "✅ User $USER telah dihapus."
}

# (Fungsi list_user tetap sama seperti sebelumnya)
list_user() {
  printf "%-15s %-7s %-7s %-8s\n" USER DISP VNC STATUS
  for f in "$META"/*.env; do
    [[ -f "$f" ]] || continue
    u=$(basename "$f" .env)
    JP=$(grep "JAVA_PID=" "$f" | cut -d= -f2)
    if ps -p "$JP" >/dev/null 2>&1; then S="RUNNING"; else S="CRASHED"; fi
    printf "%-15s %-7s %-7s %-8s\n" "$u" "$(grep "DISPLAY=" "$f" | cut -d= -f2)" "$(grep "PORT_VNC=" "$f" | cut -d= -f2)" "$S"
  done
}

while true; do
  echo -e "\n1) Create  2) Delete  3) List  4) Exit"
  read -rp "Pilih: " c
  case "$c" in
    1) create_user ;;
    2) delete_user ;;
    3) list_user ;;
    4) exit ;;
  esac
done
