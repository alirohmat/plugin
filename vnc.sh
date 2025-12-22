#!/usr/bin/env bash
set -Eeuo pipefail

### ================= CONFIG =================
BASE="/opt/vnc-manager"
MASTER="$BASE/master_kemulator"
SESSIONS="$BASE/sessions"
TOKENS="$BASE/tokens"
LOCKFILE="/var/run/vnc-manager.lock"

JAVA_BIN="/usr/bin/java"
XVFB_BIN="/usr/bin/Xvfb"
X11VNC_BIN="/usr/bin/x11vnc"

DISPLAY_START=10
PORT_BASE=5900

IP_LOCAL=$(hostname -I | awk '{print $1}')

mkdir -p "$SESSIONS"
touch "$TOKENS"

exec 9>"$LOCKFILE" || exit 1
flock -n 9 || { echo "Manager sedang digunakan"; exit 1; }

### ================ UTIL ====================

die() { echo "[ERROR] $*" >&2; exit 1; }

valid_name() {
  [[ "$1" =~ ^[a-zA-Z0-9_-]+$ ]]
}

free_display() {
  for d in $(seq $DISPLAY_START 99); do
    if ! pgrep -f "Xvfb :$d" >/dev/null; then
      if [[ -f "/tmp/.X$d-lock" ]]; then
        rm -f "/tmp/.X$d-lock"
      fi
      echo "$d"
      return
    fi
  done
  die "Tidak ada DISPLAY kosong"
}

proc_valid() {
  local pid="$1" cmdhash="$2"
  [[ -d "/proc/$pid" ]] || return 1
  local curhash
  curhash=$(tr '\0' ' ' < /proc/$pid/cmdline | sha256sum | cut -d' ' -f1)
  [[ "$curhash" == "$cmdhash" ]]
}

safe_kill() {
  local pid="$1" cmdhash="$2"

  proc_valid "$pid" "$cmdhash" || return 0

  kill "$pid" 2>/dev/null || true
  sleep 2

  proc_valid "$pid" "$cmdhash" && kill -9 "$pid" 2>/dev/null || true
}

### ============== CREATE ====================

create_user() {
  read -rp "Nama user: " USER
  read -rsp "Password VNC: " PASS; echo

  valid_name "$USER" || die "Nama user tidak valid"

  [[ -d "$SESSIONS/$USER" ]] && die "User sudah ada"
  [[ -d "$MASTER" ]] || die "Master kemulator tidak ditemukan"

  DISPLAY=$(free_display)
  PORT=$((PORT_BASE + DISPLAY))

  SESSION="$SESSIONS/$USER"
  mkdir -p "$SESSION"

  cp -a "$MASTER" "$SESSION/kemulator"

  "$XVFB_BIN" ":$DISPLAY" -screen 0 240x320x16 &
  PID_XVFB=$!
  sleep 1

  DISPLAY=":$DISPLAY" \
  "$X11VNC_BIN" -display ":$DISPLAY" -passwd "$PASS" -forever -shared -rfbport "$PORT" &
  PID_VNC=$!
  sleep 1

  DISPLAY=":$DISPLAY" \
  "$JAVA_BIN" -noverify -jar "$SESSION/kemulator/KEmulator.jar" >/dev/null 2>&1 &
  PID_JAVA=$!

  for p in $PID_XVFB $PID_VNC $PID_JAVA; do
    ps -p "$p" >/dev/null || die "Proses gagal start"
  done

  HASH_XVFB=$(tr '\0' ' ' < /proc/$PID_XVFB/cmdline | sha256sum | cut -d' ' -f1)
  HASH_VNC=$(tr '\0' ' ' < /proc/$PID_VNC/cmdline | sha256sum | cut -d' ' -f1)
  HASH_JAVA=$(tr '\0' ' ' < /proc/$PID_JAVA/cmdline | sha256sum | cut -d' ' -f1)

  cat > "$SESSION/session.meta" <<EOF
USER=$USER
DISPLAY=$DISPLAY
PORT=$PORT
PID_XVFB=$PID_XVFB
PID_VNC=$PID_VNC
PID_JAVA=$PID_JAVA
HASH_XVFB=$HASH_XVFB
HASH_VNC=$HASH_VNC
HASH_JAVA=$HASH_JAVA
EOF

  echo "$USER $DISPLAY $PORT" >> "$TOKENS"

  echo "User $USER dibuat"
  echo "VNC: $IP_LOCAL:$PORT"
}

### ============== DELETE ====================

delete_user() {
  read -rp "Nama user: " USER
  SESSION="$SESSIONS/$USER"
  META="$SESSION/session.meta"

  [[ -f "$META" ]] || die "User tidak ditemukan"

  get() { grep "^$1=" "$META" | cut -d= -f2; }

  safe_kill "$(get PID_JAVA)" "$(get HASH_JAVA)"
  safe_kill "$(get PID_VNC)"  "$(get HASH_VNC)"
  safe_kill "$(get PID_XVFB)" "$(get HASH_XVFB)"

  for p in PID_JAVA PID_VNC PID_XVFB; do
    pid=$(get "$p")
    ps -p "$pid" >/dev/null && die "Proses $p masih hidup, abort delete"
  done

  sed -i "/^$USER /d" "$TOKENS"
  rm -rf "$SESSION"

  echo "User $USER dihapus"
}

### ============== LIST ======================

list_user() {
  printf "%-12s %-8s %-6s %-10s\n" USER DISP PORT STATUS
  for s in "$SESSIONS"/*; do
    [[ -f "$s/session.meta" ]] || continue
    USER=$(grep USER= "$s/session.meta"|cut -d= -f2)
    DISP=$(grep DISPLAY= "$s/session.meta"|cut -d= -f2)
    PORT=$(grep PORT= "$s/session.meta"|cut -d= -f2)
    PID=$(grep PID_VNC= "$s/session.meta"|cut -d= -f2)

    if ss -lntp | grep -q ":$PORT"; then
      STATUS=OK
    else
      STATUS=DOWN
    fi

    printf "%-12s %-8s %-6s %-10s\n" "$USER" "$DISP" "$PORT" "$STATUS"
  done
}

### ================= MENU ===================

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
