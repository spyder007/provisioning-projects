#!/usr/bin/env bash
set -euo pipefail

chmod go-w ~/
chmod 700 ~/.ssh || true
chmod 600 ~/.ssh/authorized_keys || true

sudo mkdir -p /myagent
cd /myagent

sudo touch .env
sudo chmod 666 .env
# Copy environment variables to .env file (ignore if a var isn't present)
env | grep Image >> .env || true
env | grep ANDROID_ >> .env || true
env | grep JAVA_ >> .env || true
env | grep HOMEBREW_ >> .env || true
env | grep ANT_ >> .env || true
env | grep GRADLE_ >> .env || true
env | grep LEIN_ >> .env || true
env | grep CONDA >> .env || true
env | grep PIPX_ >> .env || true
env | grep AGENT_ >> .env || true
env | grep EDGEWEBDRIVER >> .env || true
env | grep CHROMEWEBDRIVER >> .env || true
env | grep CHROME_BIN >> .env || true
env | grep BOOTSTRAP_ >> .env || true
env | grep GHCUP_ >> .env || true
env | grep NVM_ >> .env || true
env | grep SELENIUM_ >> .env || true
env | grep SWIFT_ >> .env || true
env | grep VCPKG_ >> .env || true
env | grep DOTNET_ >> .env || true
env | grep LANG >> .env || true
env | grep M2_ >> .env || true
env | grep VSTS_ >> .env || true
env | grep LD_ >> .env || true
env | grep PERL5LIB >> .env || true

export AZP_AGENT_USE_LEGACY_HTTP=true
sudo wget "$MS_AGENT_URL/$MS_AGENT_FILENAME"
sudo tar zxvf ./$MS_AGENT_FILENAME
sudo chmod -R 777 /myagent
./config.sh --unattended --url "$MS_AGENT_ORG_URL" --auth pat --token "$MS_AGENT_PAT" --pool "$MS_AGENT_POOL_NAME"
sudo ./svc.sh install

# Determine agent user (prefer SUDO_USER when run under sudo)
AGENT_USER=""
if [ -n "${SUDO_USER:-}" ] && [ "${SUDO_USER:-}" != "root" ]; then
  AGENT_USER="${SUDO_USER}"
else
  AGENT_USER=$(stat -c '%U' /myagent 2>/dev/null || true)
  AGENT_USER=${AGENT_USER:-${USER:-}}
fi

# Add agent user to the docker group so the agent can use `docker` without sudo
if [ -n "$AGENT_USER" ] && id -u "$AGENT_USER" >/dev/null 2>&1; then
  if ! id -nG "$AGENT_USER" | grep -qw docker; then
    sudo usermod -aG docker "$AGENT_USER" || true
    echo "Added $AGENT_USER to docker group"
  else
    echo "User $AGENT_USER already in docker group"
  fi
else
  echo "Warning: could not determine agent user; skipping docker group modification"
fi

# Ensure Docker is enabled and running so /var/run/docker.sock exists
sudo systemctl enable --now docker || true

# Restart agent service so group membership takes effect for the agent process
sudo ./svc.sh stop || true
sudo ./svc.sh start || true

mkdir -p ~/.aspnet/https
exit 0