#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

COMPOSE_DIR="/opt/homelab-platform/services/acme"
CERT_DIR="/srv/appdata/acme/certs"
RELOAD_MARKER="${CERT_DIR}/.caddy-reload-pending"
LOCK_FILE="/run/lock/homelab-acme.lock"

MODE="${1:-renew}"

log() {
  echo "[acme] $*"
}

fail() {
  echo "[acme] ERROR: $*" >&2
  exit 1
}

# Nur Root darf Zertifikate und den Docker-Daemon verwalten.
[[ "$EUID" -eq 0 ]] || fail "Root privileges required"

# Keine parallelen ACME-Läufe zulassen.
exec 9>"$LOCK_FILE"
flock -n 9 || fail "Another ACME operation is running"

cd "$COMPOSE_DIR"

case "$MODE" in

  install)
    log "Installing existing wildcard certificate"

    docker compose run --rm --entrypoint sh acme -c '
      set -eu
      umask 077

      /acmebin/acme.sh \
        --install-cert \
        -d "*.cronmancer.de" \
        --ecc \
        --fullchain-file /certs/fullchain.pem \
        --key-file /certs/privkey.pem \
        --reloadcmd "touch /certs/.caddy-reload-pending" \
        --home /acme.sh
    '

    chmod 0600 \
      "$CERT_DIR/fullchain.pem" \
      "$CERT_DIR/privkey.pem"

    log "Certificate installed"
    log "Caddy reload pending until integration is ready"
    exit 0
    ;;

  renew)
    log "Checking ACME certificate renewal"

    docker compose run --rm --entrypoint sh acme -c '
      set -eu
      umask 077

      set -a
      . /run/secrets/netcup.env
      set +a

      /acmebin/acme.sh \
        --cron \
        --home /acme.sh
    '
    ;;

  reload)
    log "Checking pending Caddy reload"
    ;;

  *)
    fail "Usage: $0 {install|renew|reload}"
    ;;
esac

# Kein Zertifikatswechsel: kein Reload erforderlich.
if [[ ! -f "$RELOAD_MARKER" ]]; then
  log "No pending certificate change"
  exit 0
fi

log "Certificate change detected"

# Prüfen, ob beide Zertifikatsdateien vorhanden sind.
[[ -s "$CERT_DIR/fullchain.pem" ]] ||
  fail "Certificate chain missing"

[[ -s "$CERT_DIR/privkey.pem" ]] ||
  fail "Private key missing"

# Zertifikat muss gültig sein.
openssl x509 \
  -in "$CERT_DIR/fullchain.pem" \
  -noout \
  -checkend 0 >/dev/null ||
  fail "Certificate is expired or invalid"

# Zertifikat und privater Schlüssel müssen zusammenpassen.
cmp -s \
  <(openssl x509 -in "$CERT_DIR/fullchain.pem" -pubkey -noout) \
  <(openssl pkey -in "$CERT_DIR/privkey.pem" -pubout) ||
  fail "Certificate and private key do not match"

# Caddy muss die eingebundenen Dateien lesen können.
docker exec caddy sh -c '
  test -r /etc/caddy/certs/fullchain.pem &&
  test -r /etc/caddy/certs/privkey.pem
' || fail "Caddy cannot access ACME certificates"

# Konfiguration vor dem Reload validieren.
docker exec caddy caddy validate \
  --config /etc/caddy/Caddyfile ||
  fail "Caddy configuration validation failed"

log "Reloading Caddy"

docker exec caddy caddy reload \
  --config /etc/caddy/Caddyfile \
  --force ||
  fail "Caddy reload failed"

# Marker erst nach erfolgreichem Reload entfernen.
rm -f -- "$RELOAD_MARKER"

log "Caddy reloaded successfully"
