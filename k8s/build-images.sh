#!/usr/bin/env bash
# Builds the Phase 3 images with local tags (see build-images.ps1 for notes).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"   # parent of orchestration

docker build -t fcg-users-api:local              "$ROOT/fiap-cloud-games-users-api"
docker build -t fcg-catalog-api:local            "$ROOT/fiap-cloud-games-catalog-api"
docker build -t fcg-payments-api:local           "$ROOT/fiap-cloud-games-payments-api"
docker build -t fcg-notifications-function:local "$ROOT/fiap-cloud-games-notifications-function"
echo "Done: fcg-{users,catalog,payments}-api:local, fcg-notifications-function:local"
