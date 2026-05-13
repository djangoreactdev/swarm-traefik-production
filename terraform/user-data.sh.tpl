#!/bin/bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

# ---------------------------------------------------------------------------
# 1) Swap. t3.micro has only 1 GiB RAM; the production stack (Postgres + Redis
#    + 2 Django stacks + 4 frontends + Traefik) needs more or it gets OOM-killed
#    immediately. Swap on EBS is slow but lets every container actually start.
# ---------------------------------------------------------------------------
SWAP_SIZE_GB="${swap_size_gb}"
if [ ! -f /swapfile ] && [ "$SWAP_SIZE_GB" -gt 0 ]; then
  fallocate -l "$${SWAP_SIZE_GB}G" /swapfile || dd if=/dev/zero of=/swapfile bs=1M count=$((SWAP_SIZE_GB*1024))
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  echo '/swapfile none swap sw 0 0' >> /etc/fstab
  sysctl vm.swappiness=10 || true
  echo 'vm.swappiness=10' >> /etc/sysctl.d/99-swap.conf
fi

# ---------------------------------------------------------------------------
# 2) Docker engine + compose plugin
# ---------------------------------------------------------------------------
apt-get update -y
apt-get install -y ca-certificates curl gnupg git
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" > /etc/apt/sources.list.d/docker.list
apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
usermod -aG docker ubuntu
systemctl enable --now docker
docker network inspect production_default >/dev/null 2>&1 || docker network create production_default

%{ if deploy_enabled ~}
# ---------------------------------------------------------------------------
# 3) Clone repo + write env files (same layout as Jenkins script.groovy)
# ---------------------------------------------------------------------------
DEPLOY_DIR="${deploy_app_dir}"
rm -rf "$DEPLOY_DIR"
mkdir -p "$(dirname "$DEPLOY_DIR")"
git clone --depth 1 -b "${deploy_git_branch}" "${deploy_git_repo}" "$DEPLOY_DIR"
mkdir -p "$DEPLOY_DIR/cosmetic/.envs/.production" "$DEPLOY_DIR/codehelp/.envs/.production"
echo "${b64_cosmetic_postgres}" | base64 -d > "$DEPLOY_DIR/cosmetic/.envs/.production/.postgres"
chmod 600 "$DEPLOY_DIR/cosmetic/.envs/.production/.postgres"
echo "${b64_codehelp_postgres}" | base64 -d > "$DEPLOY_DIR/codehelp/.envs/.production/.postgres"
chmod 600 "$DEPLOY_DIR/codehelp/.envs/.production/.postgres"
echo "${b64_cosmetic_django}" | base64 -d > "$DEPLOY_DIR/cosmetic/.envs/.production/.django"
chmod 600 "$DEPLOY_DIR/cosmetic/.envs/.production/.django"
echo "${b64_codehelp_django}" | base64 -d > "$DEPLOY_DIR/codehelp/.envs/.production/.django"
chmod 600 "$DEPLOY_DIR/codehelp/.envs/.production/.django"

cd "$DEPLOY_DIR"

# From here on, do not abort the whole boot if a single image fails - we still
# want SSH access to debug. Errors are visible in /var/log/cloud-init-output.log.
set +e

# ---------------------------------------------------------------------------
# 4) Build the local-only images that production.yml expects but no registry
#    has: cosmetic_production_postgres, cosmetic_production_awscli,
#    cosmetic_local_nginx, production_traefik:1.1
# ---------------------------------------------------------------------------
docker compose -f production-build.yml build postgres awscli cosmetic-nginx traefik

# ---------------------------------------------------------------------------
# 5) Pull every public image referenced by ${deploy_compose_file}; never fail
#    on the local-only tags (we already built them above or alias them below).
# ---------------------------------------------------------------------------
docker compose -f "${deploy_compose_file}" pull --ignore-pull-failures || true

# ---------------------------------------------------------------------------
# 6) cosmetic-celery* services in production.yml point at image tags that no
#    Dockerfile builds. They are meant to reuse the cosmetic-api Django image
#    with a different command (/start-celeryworker etc., baked into the image).
#    Re-tag the public cosmetic-api image so those containers can start.
# ---------------------------------------------------------------------------
COSMETIC_API_IMAGE="djangoreactdev/cosmetic-api:1.0.2"
docker pull "$COSMETIC_API_IMAGE"
docker tag "$COSMETIC_API_IMAGE" cosmeticpro_production_celeryworker
docker tag "$COSMETIC_API_IMAGE" cosmeticpro_production_celerybeat
docker tag "$COSMETIC_API_IMAGE" cosmeticpro_production_flower

# ---------------------------------------------------------------------------
# 7) Compose override: restart policies + memory caps so the whole stack fits
#    on a 1 GiB instance (with the swap added in step 1). Docker Compose v2
#    merges this with production.yml at runtime.
# ---------------------------------------------------------------------------
cat > "$DEPLOY_DIR/compose.override.yml" <<'YAMLEOF'
services:
  postgres:              { restart: unless-stopped, mem_limit: 256m }
  redis:                 { restart: unless-stopped, mem_limit: 64m  }
  traefik:               { restart: unless-stopped, mem_limit: 96m  }
  portfolio:             { restart: unless-stopped, mem_limit: 96m  }
  portfolio-sanity:      { restart: unless-stopped, mem_limit: 96m  }
  wow-effecting:         { restart: unless-stopped, mem_limit: 96m  }
  cosmetic-api:          { restart: unless-stopped, mem_limit: 256m }
  cosmetic-celeryworker: { restart: unless-stopped, mem_limit: 192m }
  cosmetic-celerybeat:   { restart: unless-stopped, mem_limit: 96m  }
  cosmetic-flower:       { restart: unless-stopped, mem_limit: 96m  }
  cosmetic-front:        { restart: unless-stopped, mem_limit: 192m }
  cosmetic-dashboard:    { restart: unless-stopped, mem_limit: 192m }
  cosmetic-nginx:        { restart: unless-stopped, mem_limit: 64m  }
  awscli:                { restart: "no",            mem_limit: 64m  }
  codehelp-api:          { restart: unless-stopped, mem_limit: 256m }
  codehelp-celeryworker: { restart: unless-stopped, mem_limit: 192m }
  codehelp-celerybeat:   { restart: unless-stopped, mem_limit: 96m  }
  codehelp-flower:       { restart: unless-stopped, mem_limit: 96m  }
  codehelp-front:        { restart: unless-stopped, mem_limit: 192m }
YAMLEOF

# ---------------------------------------------------------------------------
# 8) Bring the stack up in waves so a 1 GiB instance does not OOM during the
#    initial Postgres/Redis warm-up.
# ---------------------------------------------------------------------------
COMPOSE_FILES="-f ${deploy_compose_file} -f compose.override.yml"
docker compose $COMPOSE_FILES up -d postgres redis
chmod +x "$DEPLOY_DIR/scripts/ensure-postgres-databases.sh"
export REPO_ROOT="$DEPLOY_DIR"
export COMPOSE_OPTS="-f ${deploy_compose_file} -f compose.override.yml"
"$DEPLOY_DIR/scripts/ensure-postgres-databases.sh"
sleep 20
docker compose $COMPOSE_FILES up -d cosmetic-api codehelp-api
sleep 15
docker compose $COMPOSE_FILES up -d
%{ endif ~}
