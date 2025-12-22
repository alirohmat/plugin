#!/usr/bin/env bash
set -Eeuo pipefail

### =========================
### KONFIGURASI
### =========================
BASE_DIR="/opt/vnc-manager"
SESSIONS="$BASE_DIR/sessions"
TOKENS="$BASE_DIR/tokens.list"
MASTER_KEMU="/home/devtalk/kemulator"
LOG_FILE="$BASE_DIR/vnc-manager.log"

XVFB_BIN="$(command -v Xvfb || { echo "[ERROR] Xvfb tidak ditemukan. Install: apt install xvfb" >&2; exit 1; })"
X11VNC_BIN="$(command -v x11vnc || { echo "[ERROR] x11vnc tidak ditemukan. Install: apt install x11vnc" >&2; exit 1; })"
JAVA_BIN="$(command -v java || { echo "[ERROR] Java tidak ditemukan. Install OpenJDK" >&2; exit 1; })"

JAVA_OPTS="-Xms32m -Xmx128m -noverify"
DISPLAY_START=1
DISPLAY_END=99

mkdir -p "$SESSIONS"
touch "$TOKENS" "$LOG_FILE"

LOCAL_IP="$(hostname -I | awk '{print $1}' || hostname -i | awk '{print $1}')"

### =========================
### LOGGING & TRAP
### =========================
log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$$] $*" | tee -a "$LOG_FILE"
}

die() { log "ERROR: $*"; exit 1; }
info() { log "INFO: $*"; }
warn() { log "WARN: $*"; }

# Trap untuk cleanup global
cleanup() {
  info "Cleanup trap dipicu (PID: $$)"
  # Cleanup lock files semua display
  for d in $(seq "$DISPLAY_START" "$DISPLAY_END"); do
    cleanup_x_lock "$d"
  done
}
trap cleanup EXIT INT TERM

### =========================
### UTIL (Diperbaiki)
### =========================
valid_name() {
  [[ "$1" =~ ^[a-zA-Z0-9][a-zA-Z0-9_-]{2,31}$ ]]
}

process_matches_cmd() {
  local pid="$1" expected="$2"
  [[ -d "/proc/$pid" ]] || return 1
  tr '\0' ' ' <"/proc/$pid/cmdline" | grep -q -- "$expected"
}

safe_kill() {
  local pid="$1" sig="${2:-TERM}" expected="$3"
  [[ -n "$pid" && -d "/proc/$pid" ]] || return 0
  process_matches_cmd "$pid" "$expected" || { warn "PID $pid tidak cocok ($expected)"; return 0; }
  kill "-$sig" "$pid" 2>/dev/null || true
  sleep 1
  [[ -d "/proc/$pid" ]] && kill -KILL "$pid" 2>/dev/null || true
}

cleanup_x_lock() {
  local disp="$1"
  local lock="/tmp/.X${disp}-lock"
  [[ -f "$lock" ]] && rm -f "$lock" && info "X lock $lock dibersihkan"
}

display_free() {
  local d="$1"
  ! ss -ln | grep -q ":$((5900 + d)) " && [[ ! -e "/tmp/.X${d}-lock" ]]
}

find_free_display() {
  for d in $(seq "$DISPLAY_START" "$DISPLAY_END"); do
    display_free "$d" && { echo "$d"; return 0; }
  done
  return 1
}

### =========================
### CLEANUP GHOST (Diperluas)
### =========================
cleanup_ghost() {
  local cleaned=0
  for s in "$SESSIONS"/*; do
    [[ -d "$s" && ! -f "$s/session.meta" ]] || continue
    warn "Ghost session $(basename "$s") dibersihkan"
    rm -rf "$s"
    ((cleaned++))
  done
  [[ $cleaned -gt 0 ]] && info "Total $cleaned ghost session dibersihkan"
}

### =========================
### CREATE USER (Robust)
### =========================
create_user() {
  read -rp "Nama user (3-32 char alfanum_-): " USER
  [[ -z "$USER" ]] && { die "Nama user kosong"; return 1; }
  valid_name "$USER" || { die "Nama '$USER' tidak valid (alfanum, _, - only)"; return 1; }

  read -rsp "Password VNC (min 6 char): " PASS; echo
  [[ ${#PASS} -lt 6 ]] && { die "Password terlalu pendek"; return 1; }

  local SESS="$SESSIONS/$USER"
  [[ -f "$SESS/session.meta" ]] && { die "User $USER sudah aktif"; return 1; }

  [[ ! -d "$MASTER_KEMU" ]] && { die "MASTER_KEMU $MASTER_KEMU tidak ditemukan"; return 1; }

  local DISP PORT
  DISP=$(find_free_display) || { die "Tidak ada display kosong (1-$DISPLAY_END)"; return 1; }
  PORT=$((5900 + DISP))

  info "Membuat sesi untuk $USER di :$DISP ($PORT)"

  mkdir -p "$SESS"
  cp -a "$MASTER_KEMU" "$SESS/kemulator"

  cleanup_x_lock "$DISP"

  # Xvfb dengan timeout lebih reliable
  info "Start Xvfb :$DISP"
  "$XVFB_BIN" ":$DISP" -screen 0 240x340x16 -ac -noreset &
  local XVFB_PID=$!
  
  if ! wait_for_process "$XVFB_PID" "Xvfb" 10; then
    die "Xvfb gagal start"
  fi

  # x11vnc
  info "Start x11vnc :$PORT"
  "$X11VNC_BIN" -display ":$DISP" -rfbport "$PORT" -passwd "$PASS" -forever -shared -noxdamage &
  local VNC_PID=$!
  
  if ! wait_for_port "$PORT" 10; then
    safe_kill "$XVFB_PID" TERM Xvfb
    die "x11vnc gagal bind port $PORT"
  fi

  # Java
  info "Start Java KEmulator"
  DISPLAY=":$DISP" "$JAVA_BIN" $JAVA_OPTS \
    -jar "$SESS/kemulator/KEmulator.jar" \
    "$SESS/kemulator/ksatria_beta.jar" &
  local JAVA_PID=$!
  
  if ! wait_for_process "$JAVA_PID" "java" 15; then
    safe_kill "$VNC_PID" TERM x11vnc
    safe_kill "$XVFB_PID" TERM Xvfb
    die "Java gagal start"
  fi

  # Metadata
  cat >"$SESS/session.meta" <<EOF
USER=$USER
DISPLAY=$DISP
PORT=$PORT
XVFB_PID=$XVFB_PID
VNC_PID=$VNC_PID
JAVA_PID=$JAVA_PID
CREATED=$(date +%s)
PASS_HASH=$(echo -n "$PASS" | sha256sum | cut -d' ' -f1)
EOF

  # Update tokens (atomic)
  grep -v "^$USER:" "$TOKENS" >"$TOKENS.tmp" && mv "$TOKENS.tmp" "$TOKENS"
  echo "$USER:$LOCAL_IP:$PORT" >>"$TOKENS"

  info "✅ User $USER siap! URL: http://$LOCAL_IP:6080/vnc.html?token=$USER"
}

wait_for_process() {
  local pid="$1" name="$2" timeout="$3"
  for i in $(seq 1 "$timeout"); do
    [[ -d "/proc/$pid" && "$(ps -p $pid -o comm=)" == *"$name"* ]] && return 0
    sleep 1
  done
  return 1
}

wait_for_port() {
  local port="$1" timeout="$2"
  for i in $(seq 1 "$timeout"); do
    ss -ln | grep -q ":$port " && return 0
    sleep 1
  done
  return 1
}

### =========================
### DELETE USER (Diperbaiki)
### =========================
delete_user() {
  read -rp "Nama user: " USER
  local SESS="$SESSIONS/$USER"
  [[ -f "$SESS/session.meta" ]] || { die "User $USER tidak ditemukan"; return 1; }

  source "$SESS/session.meta"
  info "Menghentikan sesi $USER (:$DISPLAY, $PORT)"

  safe_kill "$JAVA_PID" TERM java
  safe_kill "$VNC_PID" TERM x11vnc
  safe_kill "$XVFB_PID" TERM Xvfb

  cleanup_x_lock "$DISPLAY"
  rm -rf "$SESS"

  grep -v "^$USER:" "$TOKENS" >"$TOKENS.tmp" && mv "$TOKENS.tmp" "$TOKENS"
  info "✅ User $USER dihapus total"
}

### =========================
### LIST USER (Diperluas)
### =========================
list_user() {
  printf "\n%-12s %-6s %-8s %-12s %-12s\n" "USER" "DISP" "PORT" "STATUS" "CREATED"
  printf "%s\n" "----------------------------------------"

  local found=0 total_ok=0 total_down=0
  for s in "$SESSIONS"/*; do
    [[ -f "$s/session.meta" ]] || continue
    found=1
    source "$s/session.meta"
    
    local STATUS="OK"
    local issues=()
    ss -ln | grep -q ":$PORT " || issues+=("VNC_DOWN")
    [[ -d "/proc/$JAVA_PID" ]] || issues+=("JAVA_DOWN")
    [[ -d "/proc/$XVFB_PID" ]] || issues+=("XVFB_DOWN")
    
    [[ ${#issues[@]} -gt 0 ]] && STATUS="${issues[*]}" && ((total_down++)) || ((total_ok++))
    
    local created=$(date -d "@$CREATED" '+%Y-%m-%d' 2>/dev/null || echo "unknown")
    printf "%-12s %-6s %-8s %-12s %s\n" "$USER" ":$DISPLAY" "$PORT" "$STATUS" "$created"
  done

  if [[ $found -eq 0 ]]; then
    echo "(tidak ada user aktif)"
  else
    info "Total: $total_ok OK, $total_down DOWN"
  fi
  echo
}

### =========================
### MAIN MENU
### =========================
cleanup_ghost
info "VNC Manager v2.0 started"

while true; do
  echo
  echo "=== VNC MANAGER (Active: $(find "$SESSIONS" -name 'session.meta' | wc -l)) ==="
  echo "1) Create user    2) Delete user"
  echo "3) List user      4) Cleanup ghosts"
  echo "5) View logs      6) Exit"
  read -rp "> " c
  
  case "$c" in
    1) create_user ;;
    2) delete_user ;;
    3) list_user ;;
    4) cleanup_ghost ;;
    5) tail -20 "$LOG_FILE" ;;
    6) info "Keluar. Semua cleanup otomatis"; exit 0 ;;
    *) echo "Pilihan salah (1-6)" ;;
  esac
done
