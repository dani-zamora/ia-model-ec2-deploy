#!/usr/bin/env bash
set -euo pipefail

APP_DIR="${APP_DIR:-/opt/ia-model-ec2-deploy}"
BRANCH="${BRANCH:-main}"

if [[ ! -d "$APP_DIR" ]]; then
  echo "APP_DIR not found: $APP_DIR"
  exit 1
fi

if [[ -f "${APP_DIR}/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "${APP_DIR}/.env"
  set +a
fi

OLLAMA_PORT="${OLLAMA_PORT:-11434}"
OLLAMA_MODEL="${OLLAMA_MODEL:-gemma4:e2b}"
USE_GPU="${USE_GPU:-false}"

cd "$APP_DIR"

echo "[deploy] Updating code"
git fetch origin "$BRANCH"
git checkout "$BRANCH"
git pull --ff-only origin "$BRANCH"

echo "[deploy] Starting containers"
COMPOSE_FILES=(-f docker-compose.yml)
if [[ "${USE_GPU,,}" == "true" ]]; then
  COMPOSE_FILES+=(-f docker-compose.gpu.yml)
  echo "[deploy] GPU mode enabled (USE_GPU=true)"
else
  echo "[deploy] CPU mode enabled (USE_GPU=${USE_GPU})"
fi
docker compose "${COMPOSE_FILES[@]}" up -d --remove-orphans

echo "[deploy] Waiting for Ollama"
READY=0
for _ in $(seq 1 45); do
  if curl -fsS "http://127.0.0.1:${OLLAMA_PORT}/api/tags" >/dev/null; then
    READY=1
    break
  fi
  sleep 2
done

if [[ "$READY" -ne 1 ]]; then
  echo "Ollama API is not responding on port ${OLLAMA_PORT}"
  exit 1
fi

echo "[deploy] Ensuring model ${OLLAMA_MODEL}"
docker exec ollama ollama pull "${OLLAMA_MODEL}"

echo "[deploy] Removing old Ollama images"
CURRENT_IMAGE_ID="$(docker inspect --format='{{.Image}}' ollama)"
mapfile -t OLLAMA_IMAGE_IDS < <(docker image ls --no-trunc --quiet ollama/ollama | sort -u)
for IMAGE_ID in "${OLLAMA_IMAGE_IDS[@]}"; do
  if [[ -n "$IMAGE_ID" && "$IMAGE_ID" != "$CURRENT_IMAGE_ID" ]]; then
    docker image rm -f "$IMAGE_ID" >/dev/null || true
  fi
done
docker image prune -f >/dev/null || true

echo "[deploy] Current tags"
curl -fsS "http://127.0.0.1:${OLLAMA_PORT}/api/tags"
echo

echo "[deploy] Done"
