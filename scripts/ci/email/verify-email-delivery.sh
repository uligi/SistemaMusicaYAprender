#!/usr/bin/env bash
set -euo pipefail

mkdir -p artifacts/postgres

docker compose up --detach smtp-sink

for attempt in $(seq 1 30); do
  if curl --fail --silent \
    http://127.0.0.1:8025/api/v1/messages >/dev/null; then
    break
  fi

  if [[ "$attempt" == "30" ]]; then
    docker compose logs smtp-sink
    exit 1
  fi

  sleep 1
done

export SMTP_HOST=127.0.0.1
export SMTP_PORT=1025
export MAILPIT_API_BASE=http://127.0.0.1:8025/

dotnet run \
  --project tools/EmailDeliveryVerifier/MusicaAprender.EmailDeliveryVerifier.csproj \
  --no-restore \
  | tee artifacts/postgres/email-delivery-summary.txt
