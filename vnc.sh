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

# Validasi binary DULU sebelum set -e (critical fix)
check_deps() {
  command -v Xvfb >/dev/null    || { echo "[ERROR] Install: apt install xvfb"; exit 1; }
  command -v x11vnc >/dev/null  || { echo "[ERROR] Install: apt install x11vnc"; exit 1; }
  command -v java >/dev/null    || { echo "[ERROR] Install OpenJDK"; exit 1; }
}

check_deps

XVFB_BIN="$(command -v Xvfb)"
X11VNC_BIN="$(command -v x11vnc)"
JAVA_BIN="$(command -v java)"

JAVA_OPTS="-Xms32m -Xmx128m -noverify"
DISPLAY_START=1
DISPLAY_END=99

mkdir -p "$SESSIONS"
touch "$TOKENS" "$LOG_FILE"

LOCAL_IP="$(hostname -I | awk '{print $1}' || echo "127.0.0.1")"

### =========================
### LOGGING (Simplified)
### =========================
log() {
  echo "[$(date '+%H:%M:%S')] $*"
}

die() { echo "[ERROR] $*" >&2; exit 1; }
info() { log "INFO: $*"; }
warn() { log "WARN: $*"; }

# Trap DIMKAN dulu, aktifkan per sesi saja
trap '' EXIT INT TERM  # Disable default trap

### =========================
### UTIL (Simplified)
### =========================
valid_name() {
  [[ "$1" =~ ^[a-zA-Z0-9][a-zA-Z0-9_-]{2,31}$ ]]
}

process_matches_cmd() {
  local pid="$1" expected="$2"
  [[ -d "/proc/$pid" ]] || return 1
  tr '\0' ' ' <"/proc/$pid/cmdline" 2>/dev/null | grep -q -- "$expected"
}

safe_kill() {
  local pid="$1" sig="${2:-TERM}" expected="$3"
  [[ -n "$pid" && -d "/proc/$pid" ]] || return 0
  process_matches_cmd "$pid" "$expected" || { warn "PID $pid skip ($expected)"; return 0; }
  kill "-$sig" "$pid" 2>/dev/null || true
  sleep 0.5
  [[ -d "/proc/$pid" ]] && kill -KILL "$pid" 2>/dev/null || true
}

cleanup_x_lock() {
  local disp="$1"
  local lock="/tmp/.X${disp}-lock"
  [[ -f "$lock" ]] && rm -f "$lock"
}

display_free() {
  local d="$1"
  ! ss -ln 2>/dev/null | grep -q ":$((5900 + d)) " && [[ ! -e "/tmp/.X${d}-lock" ]]
}

find_free_display() {
  for d in $(seq "$DISPLAY_START" "$DISPLAY_END"); do
    display_free "$d" && echo "$d" && return 0
  done
  return 1
}

### =========================
### CLEANUP GHOST
### =========================
cleanup_ghost() {
  local cleaned=0
  for s in "$SESSIONS"/*; do
    [[ -d "$s" && ! -f "$s/session.meta" ]] || continue
    warn "Ghost $(basename "$s") cleaned"
    rm -rf "$s"
    ((cleaned++))
  done
  [[ $cleaned -gt 0 ]] && info "Cleaned $cleaned ghosts"
}

### =========================
### CREATE USER (Simplified)
### =========================
create_user() {
  echo -n "Nama user: "; read -r USER
  [[ -z "$USER" ]] && { die "Nama kosong"; return 1; }
  valid_name "$USER" || { die "Nama invalid"; return 1; }

  echo -n "Password VNC: "; read -rs PASS; echo
  [[ ${#PASS} -lt 6 ]] && { die "Password pendek"; return 1; }

  local SESS="$SESSIONS/$USER"
  [[ -f "$SESS/session.meta" ]] && { die "User exists"; return 1; }

  [[ ! -d "$MASTER_KEMU" ]] && { die "KEmulator missing"; return 1; }

  local DISP PORT
  DISP=$(find_free_display) || { die "No free display"; return 1; }
  PORT=$((5900 + DISP))

  info "Creating $USER :$DISP ($PORT)"
  mkdir -p "$SESS"
  cp -a "$MASTER_KEMU" "$SESS/kemulator"
  cleanup_x_lock "$DISP"

  # Xvfb
  info "Xvfb :$DISP"
  "$XVFB_BIN" ":$DISP" -screen 0 240x320x16 -ac &
  XVFB_PID=$!
  sleep 1

  # x11vnc  
  info "x11vnc :$PORT"
  "$X11VNC_BIN" -display ":$DISP" -rfbport "$PORT" -passwd "$PASS" -forever -shared &
  VNC_PID=$!
  sleep 1

  # Java
  info "Java KEmulator"
  DISPLAY=":$DISP" "$JAVA_BIN" $JAVA_OPTS \
    -jar "$SESS/kemulator/KEmulator.jar" \
    "$SESS/kemulator/ksatria_beta.jar" &
  JAVA_PID=$!
  sleep 2

  # Metadata
  cat >"$SESS/session.meta" <<EOF
USER=$USER
DISPLAY=$DISP
PORT=$PORT
XVFB_PID=$XVFB_PID
VNC_PID=$VNC_PID
JAVA_PID=$JAVA_PID
CREATED=$(date +%s)
EOF

  echo "$USER:$LOCAL_IP:$PORT" >>"$TOKENS"
  info "✅ $USER ready: http://$LOCAL_IP:6080/vnc.html?token=$USER"
}

### =========================
### DELETE USER
### =========================
delete_user() {
  echo -n "Nama user: "; read -r USER
  local SESS="$SESSIONS/$USER"
  [[ -f "$SESS/session.meta" ]] || { die "User not found"; return 1; }

  source "$SESS/session.meta"
  info "Stopping $USER"

  safe_kill "$JAVA_PID" TERM java
  safe_kill "$VNC_PID" TERM x11vnc  
  safe_kill "$XVFB_PID" TERM Xvfb

  cleanup_x_lock "$DISPLAY"
  rm -rf "$SESS"
  grep -v "^$USER:" "$TOKENS" > "${TOKENS}.tmp" && mv "${TOKENS}.tmp" "$TOKENS"
  info "✅ $USER deleted"
}

### =========================
### LIST USER
### =========================
list_user() {
  echo "USER       DISP  PORT   STATUS     CREATED"
  echo "------------------------------------------------"
  local found=0
  for s in "$SESSIONS"/*; do
    [[ -f "$s/session.meta" ]] || continue
    found=1
    source "$s/session.meta"
    STATUS="OK"
    ss -ln | grep -q ":$PORT " || STATUS="VNC_DOWN"
    [[ -d "/proc/$JAVA_PID" ]] || STATUS+=" JAVA?"
    printf "%-10s :%-3s %5s  %s\n" "$USER" "$DISPLAY" "$PORT" "$STATUS"
  done
  [[ $found -eq 0 ]] && echo "(no active users)"
}

### =========================
### MAIN (Fixed!)
### =========================
cleanup_ghost
info "VNC Manager started OK"

while true; do
  echo
  echo "=== VNC MANAGER ==="
  echo "1) Create  2) Delete  3) List"
  echo "4) Cleanup 5) Exit"
  echo -n "> "; read -r choice
  
  case "$choice" in
    1) create_user ;;
    2) delete_user ;;
    3) list_user ;;
    4) cleanup_ghost ;;
    5) info "Exit"; exit 0 ;;
    *) echo "Pilih 1-5" ;;
  esac
done
