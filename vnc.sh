#!/usr/bin/env bash
set -Eeuo pipefail

### =========================
### KONFIGURASI
### =========================
BASE_DIR="/opt/vnc-manager"
SESSIONS="$BASE_DIR/sessions"
TOKENS="$BASE_DIR/tokens.list"
MASTER_KEMU="/home/devtalk/kemulator"

XVFB_BIN="$(command -v Xvfb)"
X11VNC_BIN="$(command -v x11vnc)"
JAVA_BIN="$(command -v java)"

JAVA_OPTS="-Xms32m -Xmx128m -noverify"

DISPLAY_START=1
DISPLAY_END=99

mkdir -p "$SESSIONS"
touch "$TOKENS"

LOCAL_IP="$(hostname -I | awk '{print $1}')"

### =========================
### UTIL
### =========================
die() { echo "[ERROR] $*" >&2; }
info() { echo "[INFO] $*"; }
warn() { echo "[WARN] $*"; }

valid_name() {
  [[ "$1" =~ ^[a-zA-Z0-9_-]+$ ]]
}

process_matches_cmd() {
  local pid="$1" expected="$2"
  [[ -d "/proc/$pid" ]] || return 1
  tr '\0' ' ' <"/proc/$pid/cmdline" | grep -q -- "$expected"
}

safe_kill() {
  local pid="$1" sig="${2:-TERM}" expected="$3"

  [[ -n "$pid" ]] || return 0
  [[ -d "/proc/$pid" ]] || return 0

  if ! process_matches_cmd "$pid" "$expected"; then
    warn "PID $pid tidak cocok ($expected), dilewati"
    return 0
  fi

  kill "-$sig" "$pid" 2>/dev/null || true
}

cleanup_x_lock() {
  local disp="$1"
  local lock="/tmp/.X${disp}-lock"
  [[ -f "$lock" ]] && rm -f "$lock"
}

display_free() {
  local d="$1"
  ! ss -ln | grep -q ":$((5900 + d)) " && [[ ! -e "/tmp/.X${d}-lock" ]]
}

find_free_display() {
  for d in $(seq "$DISPLAY_START" "$DISPLAY_END"); do
    display_free "$d" && echo "$d" && return
  done
  return 1
}

### =========================
### CLEANUP GHOST SESSION
### =========================
cleanup_ghost() {
  for s in "$SESSIONS"/*; do
    [[ -d "$s" ]] || continue
    [[ -f "$s/session.meta" ]] || {
      warn "Ghost session ditemukan: $(basename "$s"), dihapus"
      rm -rf "$s"
    }
  done
}

### =========================
### CREATE USER
### =========================
create_user() {
  read -rp "Nama user: " USER
  read -rsp "Password VNC: " PASS; echo

  valid_name "$USER" || { die "Nama user tidak valid"; return; }

  local SESS="$SESSIONS/$USER"
  [[ -d "$SESS" && -f "$SESS/session.meta" ]] && { die "User sudah ada"; return; }
  [[ -d "$SESS" ]] && rm -rf "$SESS"

  [[ -d "$MASTER_KEMU" ]] || { die "Folder kemulator tidak ditemukan"; return; }

  local DISP
  DISP="$(find_free_display)" || { die "Tidak ada DISPLAY kosong"; return; }

  local PORT=$((5900 + DISP))

  mkdir -p "$SESS"
  cp -a "$MASTER_KEMU" "$SESS/kemulator"

  cleanup_x_lock "$DISP"

  ### ======== START Xvfb ========
  info "Menjalankan Xvfb :$DISP"
  "$XVFB_BIN" ":$DISP" -screen 0 240x340x16 &
  XVFB_PID=$!

  # Tunggu Xvfb siap (cek lock file)
  for i in {1..10}; do
    [[ -d "/proc/$XVFB_PID" ]] || { die "Xvfb mati"; rm -rf "$SESS"; return; }
    [[ -e "/tmp/.X${DISP}-lock" ]] && break
    sleep 0.5
  done

  ### ======== START x11vnc ========
  info "Menjalankan x11vnc :$PORT"
  "$X11VNC_BIN" -display ":$DISP" -rfbport "$PORT" -passwd "$PASS" -forever -shared &
  VNC_PID=$!

  # Tunggu x11vnc bind port
  for i in {1..10}; do
    ss -ln | grep -q ":$PORT " && break
    [[ -d "/proc/$VNC_PID" ]] || { die "x11vnc mati"; safe_kill "$XVFB_PID" Xvfb; rm -rf "$SESS"; return; }
    sleep 0.5
  done

  ### ======== START JAVA ========
  info "Menjalankan Java"
  DISPLAY=":$DISP" "$JAVA_BIN" $JAVA_OPTS \
    -jar "$SESS/kemulator/KEmulator.jar" \
    "$SESS/kemulator/ksatria_beta.jar" &
  JAVA_PID=$!

  sleep 1
  [[ -d "/proc/$JAVA_PID" ]] || {
    die "Java gagal start"
    safe_kill "$VNC_PID" x11vnc
    safe_kill "$XVFB_PID" Xvfb
    rm -rf "$SESS"
    return
  }

  ### ======== BUAT METADATA ========
  cat >"$SESS/session.meta" <<EOF
USER=$USER
DISPLAY=$DISP
PORT=$PORT
XVFB_PID=$XVFB_PID
VNC_PID=$VNC_PID
JAVA_PID=$JAVA_PID
CREATED=$(date +%s)
EOF

  # Update tokens
  grep -v "^$USER:" "$TOKENS" >"$TOKENS.tmp" || true
  mv "$TOKENS.tmp" "$TOKENS"
  echo "$USER:$LOCAL_IP:$PORT" >>"$TOKENS"

  info "User $USER berhasil dibuat"
  info "URL: http://$LOCAL_IP:6080/vnc.html?token=$USER"
}

### =========================
### DELETE USER
### =========================
delete_user() {
  read -rp "Nama user: " USER
  local SESS="$SESSIONS/$USER"

  [[ -f "$SESS/session.meta" ]] || { die "User tidak ditemukan"; return; }

  source "$SESS/session.meta"

  safe_kill "$JAVA_PID" TERM java
  sleep 1
  safe_kill "$JAVA_PID" KILL java

  safe_kill "$VNC_PID" TERM x11vnc
  sleep 1
  safe_kill "$VNC_PID" KILL x11vnc

  safe_kill "$XVFB_PID" TERM Xvfb
  sleep 1
  safe_kill "$XVFB_PID" KILL Xvfb

  cleanup_x_lock "$DISPLAY"

  rm -rf "$SESS"

  grep -v "^$USER:" "$TOKENS" >"$TOKENS.tmp" || true
  mv "$TOKENS.tmp" "$TOKENS"

  info "User $USER dihapus total"
}

### =========================
### LIST USER
### =========================
list_user() {
  printf "%-12s %-6s %-6s %-10s\n" USER DISP PORT STATUS
  local found=0

  for s in "$SESSIONS"/*; do
    [[ -f "$s/session.meta" ]] || continue
    found=1
    source "$s/session.meta"

    STATUS="OK"
    ss -ln | grep -q ":$PORT " || STATUS="VNC_DOWN"
    [[ -d "/proc/$JAVA_PID" ]] || STATUS="JAVA_DOWN"
    [[ -d "/proc/$XVFB_PID" ]] || STATUS="XVFB_DOWN"

    printf "%-12s %-6s %-6s %-10s\n" "$USER" "$DISPLAY" "$PORT" "$STATUS"
  done

  [[ "$found" -eq 0 ]] && echo "(tidak ada user aktif)"
}

### =========================
### MENU
### =========================
cleanup_ghost

while true; do
  echo "1) Create user VNC"
  echo "2) Delete user VNC"
  echo "3) List user"
  echo "4) Exit"
  read -rp "> " c
  case "$c" in
    1) create_user ;;
    2) delete_user ;;
    3) list_user ;;
    4) exit ;;
    *) echo "Pilihan salah" ;;
  esac
done
