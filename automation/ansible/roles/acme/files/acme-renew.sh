#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

COMPOSE_DIR="/opt/homelab-platform/services/acme"
CERT_DIR="/srv/appdata/acme/certs"

RELOAD_MARKER="${CERT_DIR}/.caddy-reload-pending"
RENEWAL_MARKER="${CERT_DIR}/.acme-renewal-notify-pending"
LOCK_FILE="/run/lock/homelab-acme.lock"

NTFY_TOKEN_FILE="/etc/homelab/secrets/ntfy/acme.token"
NTFY_URL="https://ntfy.cronmancer.de/homelab-infrastructure"

MODE="${1:-renew}"

log() {
  printf '[acme] %s\n' "$*"
}

error_log() {
  printf '[acme] ERROR: %s\n' "$*" >&2
}

# Read the local token and transmit it without placing it in curl arguments.
# Notification failures must never override an ACME operation result.
notify() {
  local priority="$1"
  local title="$2"
  local message="$3"
  local token

  if [[ ! -r "$NTFY_TOKEN_FILE" || ! -s "$NTFY_TOKEN_FILE" ]]; then
    log "WARNING: ntfy token file missing, empty or unreadable" >&2
    return 1
  fi

  if ! token="$(cat -- "$NTFY_TOKEN_FILE")"; then
    log "WARNING: Cannot read ntfy token" >&2
    return 1
  fi

  if [[ -z "$token" ]]; then
    log "WARNING: ntfy token is empty" >&2
    return 1
  fi

  if ! printf 'Authorization: Bearer %s\n' "$token" |
    curl --fail --silent --show-error \
      --connect-timeout 10 \
      --max-time 20 \
      --retry 2 \
      --retry-delay 2 \
      --header @- \
      --header "Title: $title" \
      --header "Priority: $priority" \
      --data-binary "$message" \
      "$NTFY_URL" >/dev/null; then
    log "WARNING: ntfy notification failed" >&2
    return 1
  fi

  return 0
}

# Report failures in operational modes only.
# Installation and notification tests do not generate failure alerts.
report_failure() {
  local message="$1"

  case "$MODE" in
    renew|reload)
      notify high \
        "ACME operation failed" \
        "ACME mode '${MODE}' failed: ${message}" || true
      ;;
  esac
}

# Explicitly handled failure.
fail() {
  local message="$*"

  error_log "$message"
  report_failure "$message"

  exit 1
}

# Unexpected command failure.
# Preserve the original exit code and prevent recursive ERR handling.
on_error() {
  local exit_code="$1"
  local line="$2"

  trap - ERR

  error_log "Unexpected failure at line ${line} (exit ${exit_code})"
  report_failure "Unexpected command failure at line ${line} (exit ${exit_code})"

  exit "$exit_code"
}

trap 'on_error "$?" "$LINENO"' ERR

# Return the fingerprint of the installed leaf certificate.
cert_fingerprint() {
  openssl x509 \
    -in "$CERT_DIR/fullchain.pem" \
    -noout \
    -fingerprint \
    -sha256
}

# Validate the requested operation before accessing the infrastructure.
case "$MODE" in
  install|renew|reload|notify-test)
    ;;
  *)
    error_log "Usage: $0 {install|renew|reload|notify-test}"
    exit 2
    ;;
esac

# ACME state, certificate files and Docker operations require root.
[[ "$EUID" -eq 0 ]] || fail "Root privileges required"

# Explicit, non-destructive end-to-end notification test.
if [[ "$MODE" == "notify-test" ]]; then
  log "Sending ntfy test notification"

  notify default \
    "ACME notification test" \
    "Test notification from the ACME renewal script"

  log "Test notification delivered to ntfy"
  exit 0
fi

# Prevent parallel ACME operations.
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
    log "Caddy reload pending"
    exit 0
    ;;

  renew)
    log "Checking ACME certificate renewal"

    # Record the currently installed certificate before the check.
    cert_before=""

    if [[ -s "$CERT_DIR/fullchain.pem" ]]; then
      cert_before="$(cert_fingerprint)" ||
        fail "Cannot read certificate fingerprint before renewal"
    fi

    # Run ACME in its existing isolated Compose service.
    docker compose run --rm --entrypoint sh acme -c '
      set -eu
      umask 077

      # Check ACME API connectivity before renewal.
      curl --fail --silent --show-error \
        --connect-timeout 10 \
        --max-time 30 \
        --retry 3 \
        --retry-delay 3 \
        --output /dev/null \
        https://acme-v02.api.letsencrypt.org/directory

      set -a
      . /run/secrets/netcup.env
      set +a

      /acmebin/acme.sh \
        --cron \
        --home /acme.sh
    '

    [[ -s "$CERT_DIR/fullchain.pem" ]] ||
      fail "Installed certificate missing after renewal check"

    cert_after="$(cert_fingerprint)" ||
      fail "Cannot read certificate fingerprint after renewal"

    # A changed certificate must have a pending Caddy reload.
    # Persist proof of the renewal across subsequent retry runs.
    if [[ "$cert_before" != "$cert_after" ]]; then
      [[ -f "$RELOAD_MARKER" ]] ||
        fail "Certificate changed without a Caddy reload marker"

      printf '%s\n' "$cert_after" > "$RENEWAL_MARKER"
      log "New certificate detected; renewal completion pending"
    fi
    ;;

  reload)
    log "Checking pending Caddy reload"
    ;;

esac

# No certificate installation pending: nothing to reload.
if [[ ! -f "$RELOAD_MARKER" ]]; then
  [[ ! -f "$RENEWAL_MARKER" ]] ||
    fail "Renewal completion pending without a Caddy reload marker"

  log "No pending certificate change"
  exit 0
fi

log "Certificate reload pending"

# Validate certificate and private-key files.
[[ -s "$CERT_DIR/fullchain.pem" ]] ||
  fail "Certificate chain missing"

[[ -s "$CERT_DIR/privkey.pem" ]] ||
  fail "Private key missing"

# The installed certificate must not be expired.
openssl x509 \
  -in "$CERT_DIR/fullchain.pem" \
  -noout \
  -checkend 0 >/dev/null ||
  fail "Certificate is expired or invalid"

# Compare public keys without exposing private-key contents.
cert_pubkey="$(
  openssl x509 \
    -in "$CERT_DIR/fullchain.pem" \
    -pubkey \
    -noout
)" || fail "Cannot read certificate public key"

key_pubkey="$(
  openssl pkey \
    -in "$CERT_DIR/privkey.pem" \
    -pubout
)" || fail "Cannot read private key"

[[ "$cert_pubkey" == "$key_pubkey" ]] ||
  fail "Certificate and private key do not match"

# Determine whether this reload completes a tracked renewal.
# A marker from manual 'install' alone must not trigger success.
renewal_completed=0

if [[ -f "$RENEWAL_MARKER" ]]; then
  pending_fingerprint="$(cat -- "$RENEWAL_MARKER")" ||
    fail "Cannot read pending renewal fingerprint"

  current_fingerprint="$(cert_fingerprint)" ||
    fail "Cannot read installed certificate fingerprint"

  [[ "$pending_fingerprint" == "$current_fingerprint" ]] ||
    fail "Pending renewal fingerprint does not match installed certificate"

  renewal_completed=1
fi

# Verify that Caddy can access the mounted certificate files.
docker exec caddy sh -c '
  test -r /etc/caddy/certs/fullchain.pem &&
  test -r /etc/caddy/certs/privkey.pem
' || fail "Caddy cannot access ACME certificates"

# Validate Caddy configuration before reloading.
docker exec caddy caddy validate \
  --config /etc/caddy/Caddyfile ||
  fail "Caddy configuration validation failed"

log "Reloading Caddy"

docker exec caddy caddy reload \
  --config /etc/caddy/Caddyfile \
  --force ||
  fail "Caddy reload failed"

# Remove the reload marker only after the reload command succeeded.
rm -f -- "$RELOAD_MARKER"

log "Caddy reloaded successfully"

# Only a previously detected renewal triggers a success notification.
# The state marker also allows success after a later retry.
if (( renewal_completed )); then
  rm -f -- "$RENEWAL_MARKER"

  log "Tracked certificate renewal completed"

  notify default \
    "ACME certificate renewed" \
    "Wildcard certificate for *.cronmancer.de renewed and Caddy reloaded successfully." || true
fi

exit 0
