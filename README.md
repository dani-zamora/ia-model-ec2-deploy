# IA Model on EC2 (Deploy configurable)

Repositorio independiente para desplegar modelos de IA con Ollama en una EC2 GPU (`g4dn.xlarge` minimo recomendado) usando Docker + GitHub Actions.

## Que incluye

- `docker-compose.yml` para levantar Ollama con GPU.
- `scripts/bootstrap-ec2.sh` para instalar Docker, NVIDIA toolkit y preparar la instancia.
- `scripts/deploy.sh` para actualizar desde GitHub y redeploy.
- Workflow `.github/workflows/deploy.yml` con deploy manual y deploy automatico opcional.

## Arquitectura

- EC2 Ubuntu 24.04 (x86_64), tipo `g4dn.xlarge`.
- Contenedor `ollama/ollama` con acceso a GPU NVIDIA.
- Modelo configurable por `.env` (`OLLAMA_MODEL`).
- API de Ollama en puerto `11434`.

## 1) Crear y subir este repo a GitHub

Desde esta carpeta:

```bash
git init
git add .
git commit -m "chore: bootstrap ia model ec2 deploy repo"
git branch -M main
git remote add origin <TU_URL_GITHUB>
git push -u origin main
```

Con `DEPLOY_ON_PUSH=true` (valor actual), cada `push` a `main` dispara deploy.

## 2) Bootstrap inicial en la EC2 (una sola vez)

Conectate por SSH y ejecuta:

```bash
git clone https://github.com/dani-zamora/ia-model-ec2-deploy /opt/ia-model-ec2-deploy
cd /opt/ia-model-ec2-deploy
sudo bash ./scripts/bootstrap-ec2.sh \
  --repo-url https://github.com/dani-zamora/ia-model-ec2-deploy \
  --branch main \
  --app-dir /opt/ia-model-ec2-deploy \
  --model gemma4:e2b \
  --deploy-user ubuntu
```

Si el script indica reinicio por drivers NVIDIA, reinicia la instancia y vuelve a ejecutar el script.

## 3) Configurar GitHub Actions (secrets)

En tu repo de GitHub (`Settings > Secrets and variables > Actions`), crea:

- Secrets requeridos:
  - `EC2_HOST`: IP o DNS publico de la EC2.
  - `EC2_USER`: normalmente `ubuntu`.
  - `EC2_SSH_KEY`: clave privada PEM para SSH (contenido completo).
- Secret opcional:
  - `EC2_APP_DIR`: por defecto `/opt/ia-model-ec2-deploy`.

## 4) Como se dispara el deploy

Tienes 2 formas:

1. Manual (recomendado al inicio): `Actions > Deploy EC2 IA Model > Run workflow`
2. Automatico en cada push a `main`: depende de `DEPLOY_ON_PUSH` en `.env`

No existe trigger por mensaje de commit.
Si `DEPLOY_ON_PUSH=true`, un `push` en `main` despliega.
Si `DEPLOY_ON_PUSH=false`, un `push` en `main` no despliega.

## 5) Checklist rapido de puesta en marcha

1. Crear los secrets `EC2_HOST`, `EC2_USER`, `EC2_SSH_KEY`.
2. (Opcional) Crear `EC2_APP_DIR` si usas ruta distinta.
3. Revisar `.env` y definir `DEPLOY_ON_PUSH=true` o `false`.
4. Hacer push a `main` o ejecutar workflow manual.

Cuando se ejecuta deploy:

1. SSH a la EC2
2. `git pull --ff-only`
3. `docker compose up -d`
4. Pull del modelo configurado (`OLLAMA_MODEL`)
5. Verificacion de `api/tags`

## 6) Variables de entorno (`.env`)

Parti de `.env.example`:

```env
OLLAMA_PORT=11434
OLLAMA_MODEL=gemma4:e2b
OLLAMA_KEEP_ALIVE=24h
DEPLOY_ON_PUSH=true
```

Puedes cambiar `OLLAMA_MODEL` a cualquier tag de Ollama sin tocar codigo.
Puedes cambiar `DEPLOY_ON_PUSH` para activar/desactivar deploy automatico por push.

`DEPLOY_ON_PUSH` se lee desde el `.env` versionado en el repositorio.
No guardes secretos en `.env`; usa GitHub Secrets para eso.

## 7) Verificacion manual

En la EC2:

```bash
curl http://127.0.0.1:11434/api/tags
docker logs --tail=100 ollama
```

Desde otra maquina dentro de la VPC (si SG lo permite):

```bash
curl http://<IP_PRIVADA_EC2>:11434/api/tags
```

## 8) Coste cuando la instancia esta apagada

Con EC2 en `Stopped` pagas normalmente:

- EBS (disco)
- IPv4 publica si la mantienes asignada
- snapshots (si existen)

No pagas computo mientras esta detenida.
