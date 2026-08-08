#!/usr/bin/env bash
set -euo pipefail

mkdir -p artifacts/ci

dotnet_version="$(dotnet --version 2>/dev/null || echo unavailable)"
node_version="$(node --version 2>/dev/null || echo unavailable)"
npm_version="$(npm --version 2>/dev/null || echo unavailable)"
commit_sha="${GITHUB_SHA:-local}"
workflow="${GITHUB_WORKFLOW:-local}"
run_id="${GITHUB_RUN_ID:-local}"
run_number="${GITHUB_RUN_NUMBER:-local}"
run_attempt="${GITHUB_RUN_ATTEMPT:-local}"
utc_now="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

{
  echo "backlog_item=BL-MVP-004"
  echo "generated_at_utc=$utc_now"
  echo "commit_sha=$commit_sha"
  echo "workflow=$workflow"
  echo "run_id=$run_id"
  echo "run_number=$run_number"
  echo "run_attempt=$run_attempt"
  echo "dotnet=$dotnet_version"
  echo "node=$node_version"
  echo "npm=$npm_version"
  echo "target_framework=net9.0"
  echo "postgres_target=18"
} > artifacts/ci/manifest.txt

if [[ -f package-lock.json ]]; then
  sha256sum package-lock.json | awk '{print "package_lock_sha256="$1}' >> artifacts/ci/manifest.txt
fi

if [[ -f global.json ]]; then
  sha256sum global.json | awk '{print "global_json_sha256="$1}' >> artifacts/ci/manifest.txt
fi

echo "CI evidence manifest written to artifacts/ci/manifest.txt"
