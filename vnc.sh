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
JAVA_OPTS="-Xms32m -Xmx128m -noverify"
JAR_KEMU="KEmulator.jar"
JAR_GAME="ksatria_beta.jar"

LOCK="/tmp/vnc-manager.lock"

# =====================================================
# INIT
# =====================================================
exec 9>"$LOCK" || exit 1
flock -n 9 || { echo "❌ Script sedang dipakai admin lain"; exit 1; }

mkdir -p "$SESSIONS" "$META" "$LOG_DIR"
touch "$LOG" "$TOKENS"

LOCAL_IP=$(hostname -I | awk '{print $1}')

log() {
  echo "[$(date '+%F %T')] $*" | tee -a "$LOG"
}

valid_name() {
  [[ "$1" =~ ^[a-zA-Z0-9_]+$ ]]
}

# =====================================================
# PORT & DISPLAY
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
# METADATA SAFE READ
# =====================================================
get_meta() {
  grep "^$2=" "$META/$1.env" | cut -d= -f2-
}

# =====================================================
# PROCESS VALIDATION
# =====================================================
process_matches() {
  local pid="$1"
  local must="$2"
  local extra="$3"

  ps -p "$pid" -o cmd= 2>/dev/null | grep -q "$must" || return 1
  [[ -n "$extra" ]] && ps -p "$pid" -o cmd= | grep -q "$extra" || true
}

safe_kill() {
  local pid="$1" must="$2" extra="$3"
  [[ -z "$pid" ]] && return 0

  if process_matches "$pid" "$must" "$extra"; then
    kill "$pid" 2>/dev/null || true
    sleep 2
    kill -9 "$pid" 2>/dev/null || true
  fi
}

vnc_alive() {
  local pid="$1" port="$2"
  process_matches "$pid" x11vnc "$port" || return 1
  ss -ltn | grep -q ":$port " || return 1
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

  [[ -d "$MASTER_KEMU" ]] || { echo "❌ Template kemulator tidak ada"; return; }

  DISP=$(find_free_display) || { echo "❌ Tidak ada DISPLAY"; return; }
  VNC_PORT=$((5900 + DISP))
  WEB_PORT=$(find_free_web_port) || { echo "❌ Tidak ada port web"; return; }

  # Bersihkan lock X lama
  LOCKFILE="/tmp/.X${DISP}-lock"
  [[ -f "$LOCKFILE" ]] && ! ps -p "$(cat "$LOCKFILE" 2>/dev/null)" >/dev/null && rm -f "$LOCKFILE"

  USER_DIR="$SESSIONS/$USER/kemulator"
  TMP_META="$META/$USER.creating"

  mkdir -p "$SESSIONS/$USER"
  cp -a "$MASTER_KEMU" "$USER_DIR" || { rm -rf "$SESSIONS/$USER"; return; }
  echo "CREATING=1" > "$TMP_META"

  Xvfb ":$DISP" -screen 0 "$XVFB_RES" &
  XVFB_PID=$!
  sleep 1
  ps -p "$XVFB_PID" >/dev/null || { rm -rf "$SESSIONS/$USER" "$TMP_META"; return; }

  x11vnc -display ":$DISP" -rfbport "$VNC_PORT" \
    -passwd "$PASS" -forever -shared &
  VNC_PID=$!
  sleep 1

  DISPLAY=":$DISP" java $JAVA_OPTS \
    -jar "$USER_DIR/$JAR_KEMU" "$USER_DIR/$JAR_GAME" &
  JAVA_PID=$!
  sleep 2
  ps -p "$JAVA_PID" >/dev/null || {
    safe_kill "$XVFB_PID" Xvfb ":$DISP"
    safe_kill "$VNC_PID" x11vnc "$VNC_PORT"
    rm -rf "$SESSIONS/$USER" "$TMP_META"
    return
  }

  cat > "$META/$USER.env" <<EOF
USER=$USER
DISPLAY=:$DISP
PORT_VNC=$VNC_PORT
PORT_WEB=$WEB_PORT
XVFB_PID=$XVFB_PID
VNC_PID=$VNC_PID
JAVA_PID=$JAVA_PID
CREATED=$(date '+%F %T')
EOF

  sed -i "/^$USER:/d" "$TOKENS"
  echo "$USER: localhost:$VNC_PORT" >> "$TOKENS"
  rm -f "$TMP_META"

  log "CREATE user=$USER disp=$DISP vnc=$VNC_PORT"
  echo "✅ noVNC: http://$LOCAL_IP:$WEB_PORT/vnc.html?token=$USER"
}

# =====================================================
# DELETE USER (2-PHASE)
# =====================================================
delete_user() {
  read -rp "Nama user: " USER
  [[ -f "$META/$USER.env" ]] || { echo "❌ User tidak ada"; return; }

  DISP=$(get_meta "$USER" DISPLAY)
  VNC_PORT=$(get_meta "$USER" PORT_VNC)

  FAILED=0

  for P in XVFB_PID VNC_PID JAVA_PID; do
    PID=$(get_meta "$USER" "$P")
    case "$P" in
      XVFB_PID) safe_kill "$PID" Xvfb "$DISP" ;;
      VNC_PID)  safe_kill "$PID" x11vnc "$VNC_PORT" ;;
      JAVA_PID) safe_kill "$PID" java "KEmulator.jar" ;;
    esac
    ps -p "$PID" >/dev/null && FAILED=1
  done

  (( FAILED == 0 )) || { echo "❌ Gagal menghentikan semua proses"; return; }

  rm -rf "$SESSIONS/$USER" "$META/$USER.env"
  sed -i "/^$USER:/d" "$TOKENS"
  log "DELETE user=$USER"
  echo "✅ USER DIHAPUS"
}

# =====================================================
# LIST USER
# =====================================================
list_user() {
  printf "%-15s %-7s %-7s %-8s\n" USER DISP VNC STATUS
  for f in "$META"/*.env; do
    [[ -f "$f" ]] || continue
    u=$(basename "$f" .env)
    D=$(get_meta "$u" DISPLAY)
    V=$(get_meta "$u" PORT_VNC)
    VP=$(get_meta "$u" VNC_PID)
    JP=$(get_meta "$u" JAVA_PID)

    if vnc_alive "$VP" "$V" && ps -p "$JP" >/dev/null; then
      S="OK"
    else
      S="BROKEN"
    fi
    printf "%-15s %-7s %-7s %-8s\n" "$u" "$D" "$V" "$S"
  done
}

# =====================================================
# MENU
# =====================================================
while true; do
  echo
  echo "1) Create user VNC"
  echo "2) Delete user VNC"
  echo "3) List user"
  echo "4) Exit"
  read -rp "Pilih: " c
  case "$c" in
    1) create_user ;;
    2) delete_user ;;
    3) list_user ;;
    4) exit ;;
  esac
done
