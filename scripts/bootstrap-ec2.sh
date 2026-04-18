#!/usr/bin/env bash
set -euo pipefail

REPO_URL=""
APP_DIR="/opt/ia-model-ec2-deploy"
BRANCH="main"
MODEL="gemma4:e2b"
DEPLOY_USER="ubuntu"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo-url)
      REPO_URL="$2"
      shift 2
      ;;
    --app-dir)
      APP_DIR="$2"
      shift 2
      ;;
    --branch)
      BRANCH="$2"
      shift 2
      ;;
    --model)
      MODEL="$2"
      shift 2
      ;;
    --deploy-user)
      DEPLOY_USER="$2"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1"
      exit 1
      ;;
  esac
done

if [[ -z "$REPO_URL" ]]; then
  echo "Missing required flag: --repo-url"
  exit 1
fi

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Run as root: sudo ./scripts/bootstrap-ec2.sh ..."
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive

echo "[1/7] Installing base packages"
apt-get update -y
apt-get install -y ca-certificates curl gnupg jq git lsb-release ubuntu-drivers-common

echo "[2/7] Installing Docker"
if ! command -v docker >/dev/null 2>&1; then
  curl -fsSL https://get.docker.com | sh
fi
systemctl enable docker
systemctl restart docker

if id -u "$DEPLOY_USER" >/dev/null 2>&1; then
  usermod -aG docker "$DEPLOY_USER"
fi

echo "[3/7] Installing NVIDIA driver (if missing)"
if ! nvidia-smi >/dev/null 2>&1; then
  ubuntu-drivers install || true
fi

if [[ -f /var/run/reboot-required ]]; then
  echo "NVIDIA driver installed/updated. Reboot required before continuing."
  echo "Run: sudo reboot"
  exit 0
fi

if ! nvidia-smi >/dev/null 2>&1; then
  echo "NVIDIA driver is not operational (nvidia-smi failed)."
  echo "Run diagnostics:"
  echo "  lspci | grep -i nvidia"
  echo "  ubuntu-drivers list --gpgpu"
  echo "If no NVIDIA device appears in lspci, the instance type likely has no GPU."
  exit 1
fi

echo "[4/7] Installing NVIDIA container toolkit"
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey \
  | gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
curl -fsSL "https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list" \
  | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' \
  > /etc/apt/sources.list.d/nvidia-container-toolkit.list
apt-get update -y
apt-get install -y nvidia-container-toolkit
nvidia-ctk runtime configure --runtime=docker
systemctl restart docker

echo "[5/7] Cloning or updating app repo"
if [[ -d "${APP_DIR}/.git" ]]; then
  git -C "$APP_DIR" fetch origin "$BRANCH"
  git -C "$APP_DIR" checkout "$BRANCH"
  git -C "$APP_DIR" pull --ff-only origin "$BRANCH"
else
  rm -rf "$APP_DIR"
  git clone --branch "$BRANCH" "$REPO_URL" "$APP_DIR"
fi

if id -u "$DEPLOY_USER" >/dev/null 2>&1; then
  chown -R "$DEPLOY_USER":"$DEPLOY_USER" "$APP_DIR"
fi

echo "[6/7] Creating .env"
if [[ ! -f "${APP_DIR}/.env" ]]; then
  cp "${APP_DIR}/.env.example" "${APP_DIR}/.env"
fi
sed -i "s/^OLLAMA_MODEL=.*/OLLAMA_MODEL=${MODEL}/" "${APP_DIR}/.env"

echo "[7/7] First deployment"
cd "$APP_DIR"
docker compose up -d --remove-orphans

echo "Waiting for Ollama API..."
for _ in $(seq 1 30); do
  if curl -fsS "http://127.0.0.1:11434/api/tags" >/dev/null; then
    break
  fi
  sleep 2
done

docker exec ollama ollama pull "$MODEL"

echo "Removing old Ollama images"
CURRENT_IMAGE_ID="$(docker inspect --format='{{.Image}}' ollama)"
mapfile -t OLLAMA_IMAGE_IDS < <(docker image ls --no-trunc --quiet ollama/ollama | sort -u)
for IMAGE_ID in "${OLLAMA_IMAGE_IDS[@]}"; do
  if [[ -n "$IMAGE_ID" && "$IMAGE_ID" != "$CURRENT_IMAGE_ID" ]]; then
    docker image rm -f "$IMAGE_ID" >/dev/null || true
  fi
done
docker image prune -f >/dev/null || true

echo "Bootstrap finished."
