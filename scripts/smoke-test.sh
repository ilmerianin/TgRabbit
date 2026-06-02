#!/usr/bin/env bash
set -euo pipefail

PRODUCER_URL="${PRODUCER_URL:-http://localhost:3000}"
NOTIFIER_URL="${NOTIFIER_URL:-http://localhost:3001}"
CHAT_ID="${CHAT_ID:-1463559136}"
MESSAGE="${MESSAGE:-Smoke test from TgRabbit stage 5}"

echo "==> Health: Producer"
curl -sf "${PRODUCER_URL}/health" | tee /dev/stderr
echo

echo "==> Health: Notifier"
curl -sf "${NOTIFIER_URL}/health" | tee /dev/stderr
echo

echo "==> Publish event"
RESPONSE="$(curl -sf -X POST "${PRODUCER_URL}/events" \
  -H 'Content-Type: application/json' \
  -d "{\"payload\":{\"chatId\":\"${CHAT_ID}\",\"text\":\"${MESSAGE}\"}}")"
echo "${RESPONSE}"

EVENT_ID="$(echo "${RESPONSE}" | sed -n 's/.*"id":"\([^"]*\)".*/\1/p')"
if [[ -z "${EVENT_ID}" ]]; then
  echo "ERROR: event id not found in response" >&2
  exit 1
fi

echo
echo "==> OK: event ${EVENT_ID} published"
echo "    Check consumer/notifier logs for delivery to Telegram (chatId=${CHAT_ID})"
