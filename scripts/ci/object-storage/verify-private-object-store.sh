#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$ROOT"

endpoint="http://127.0.0.1:9000"
bucket="${OBJECT_STORE_BUCKET:-musica-aprender-private}"
secret_dir="$ROOT/secrets/local"

echo "Asegurando object store privado de desarrollo en CI..."
docker compose up --detach object-store

ready=0
for _ in $(seq 1 30); do
  if curl --fail --silent "$endpoint/minio/health/ready" >/dev/null; then
    ready=1
    break
  fi
  sleep 1
done

if [[ "$ready" -ne 1 ]]; then
  docker compose logs object-store
  echo "MinIO no alcanzo readiness." >&2
  exit 1
fi

echo "Verificando cifrado, checksum, metadatos y ausencia de URL publica directa..."

dotnet run \
  --project tools/ObjectStoreVerifier/MusicaAprender.ObjectStoreVerifier.csproj \
  --configuration Release \
  --no-build \
  --no-restore \
  -- \
  --endpoint "$endpoint" \
  --bucket "$bucket" \
  --secret-dir "$secret_dir" \
  --pg-host "${PGHOST:-127.0.0.1}" \
  --pg-port "${PGPORT:-5432}" \
  --pg-database "${PGDATABASE:-musica_aprender_ci}" \
  | tee artifacts/postgres/object-store-summary.txt

echo "OK: BL-MVP-016 object store privado verificado en CI."
