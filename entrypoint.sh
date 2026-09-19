#!/usr/bin/env bash
set -Eeuo pipefail

: "${VNC_PASSWORD:?VNC_PASSWORD must be set; refusing to start without VNC authentication}"
if (( ${#VNC_PASSWORD} < 8 )); then
  echo "VNC_PASSWORD must contain at least 8 characters" >&2
  exit 1
fi

declare -a CHILDREN=()
cleanup() {
  trap - TERM INT EXIT
  if ((${#CHILDREN[@]})); then
    kill "${CHILDREN[@]}" 2>/dev/null || true
    wait "${CHILDREN[@]}" 2>/dev/null || true
  fi
  rm -f /tmp/vnc.pass /tmp/.X1-lock /tmp/.X11-unix/X1
}
trap cleanup TERM INT EXIT

echo "=== Ubuntu Chrome VNC environment ==="
mkdir -p /var/run/dbus
dbus-daemon --system --fork 2>/dev/null || true
dbus-daemon --session --fork --address="unix:path=/tmp/dbus-session" 2>/dev/null || true
export DBUS_SESSION_BUS_ADDRESS=unix:path=/tmp/dbus-session

Xvfb :1 -screen 0 "${RESOLUTION}" -ac +extension RANDR &
CHILDREN+=("$!")
sleep 1
su - browser -c 'DISPLAY=:1 openbox >/tmp/openbox.log 2>&1' &
CHILDREN+=("$!")

# Store the secret in a mode-600 file instead of exposing it in ps output.
umask 077
x11vnc -storepasswd "${VNC_PASSWORD}" /tmp/vnc.pass >/dev/null
unset VNC_PASSWORD
x11vnc -display :1 -forever -quiet -rfbport "${VNC_PORT}" -rfbauth /tmp/vnc.pass &
CHILDREN+=("$!")
websockify --web /usr/share/novnc "${NOVNC_PORT}" "localhost:${VNC_PORT}" &
CHILDREN+=("$!")

rm -f "${CHROME_PROFILE}/SingletonLock" "${CHROME_PROFILE}/SingletonSocket" "${CHROME_PROFILE}/SingletonCookie"
su - browser -c "
  DISPLAY=:1 DBUS_SESSION_BUS_ADDRESS='${DBUS_SESSION_BUS_ADDRESS}' \
  google-chrome-stable \
    --remote-debugging-address=127.0.0.1 \
    --remote-debugging-port=${CDP_PORT} \
    --user-data-dir='${CHROME_PROFILE}' \
    --no-first-run --no-default-browser-check \
    --disable-background-networking --disable-sync \
    --disable-features=TranslateUI --window-size=1920,1080 about:blank
" &
CHILDREN+=("$!")

# CDP has no authentication; keep it private inside the container too.
socat TCP-LISTEN:9223,bind=127.0.0.1,fork,reuseaddr TCP:127.0.0.1:"${CDP_PORT}" &
CHILDREN+=("$!")

for attempt in {1..30}; do
  if curl -fsS "http://127.0.0.1:${CDP_PORT}/json/version" >/dev/null; then
    echo "[OK] Chrome CDP is ready on localhost:${CDP_PORT}"
    break
  fi
  if (( attempt == 30 )); then
    echo "Chrome CDP did not become ready" >&2
    exit 1
  fi
  sleep 1
done

echo "[OK] noVNC: http://127.0.0.1:${NOVNC_PORT}/vnc.html"
echo "[OK] VNC:   127.0.0.1:${VNC_PORT}"
echo "[OK] CDP:   127.0.0.1:9223"

# If an essential child exits, let Compose restart the container.
wait -n "${CHILDREN[@]}"
status=$?
echo "A browser service exited with status ${status}" >&2
exit "${status}"

