#!/usr/bin/env bash
# Docker Engine + NVIDIA Container Toolkit inside WSL2 AlmaLinux.
#
#   bash ./scripts/install-docker-wsl.sh
#   bash ./scripts/install-docker-wsl.sh --check     # verify only
#
# WHY NATIVE DOCKER AND NOT DOCKER DESKTOP
# Docker Desktop works, and if you already rely on it just enable WSL
# integration for this distro instead of running this script. Two reasons this
# repo installs the engine directly:
#
#   1. configs/wsl/wsl.conf sets appendWindowsPath=false. Today `docker` inside
#      AlmaLinux resolves to /mnt/c/.../docker.exe purely because the Windows
#      PATH leaks in. Once that is off, the leak stops and there is no docker
#      in the distro at all unless one is installed here.
#   2. GPU containers want the NVIDIA Container Toolkit wired into the daemon
#      you actually control, and systemd is already PID 1 in this distro.
#
# Requirements already satisfied on this machine, but checked anyway:
#   * systemd as PID 1              (configs/wsl/wsl.conf -> [boot] systemd=true)
#   * the WSL GPU driver stubs      (/usr/lib/wsl/lib/libcuda.so.1)

set -euo pipefail

CHECK_ONLY=0
[[ "${1:-}" == "--check" ]] && CHECK_ONLY=1

say()  { printf '\n==> %s\n' "$1"; }
ok()   { printf '    ok   %s\n' "$1"; }
warn() { printf '    WARN %s\n' "$1"; }
die()  { printf '    FAIL %s\n' "$1" >&2; exit 1; }

# --- preflight ---------------------------------------------------------------
say "Checking the environment"

grep -qi microsoft /proc/version || die "this is not WSL"
ok "running under WSL"

if [[ "$(ps -p 1 -o comm=)" != "systemd" ]]; then
  die "systemd is not PID 1. Put [boot] systemd=true in /etc/wsl.conf, then run 'wsl --shutdown' from Windows."
fi
ok "systemd is PID 1"

if [[ -e /dev/dxg ]]; then
  ok "/dev/dxg present (GPU paravirtualisation)"
else
  warn "/dev/dxg missing - GPU containers will not work"
fi

if [[ -x /usr/lib/wsl/lib/nvidia-smi ]]; then
  ok "$(/usr/lib/wsl/lib/nvidia-smi --query-gpu=name,memory.total --format=csv,noheader 2>/dev/null | head -1)"
else
  warn "no WSL nvidia-smi - install the NVIDIA driver on Windows (not inside WSL)"
fi

if [[ $CHECK_ONLY -eq 1 ]]; then
  say "Check mode"
  command -v docker >/dev/null 2>&1 && ok "docker: $(docker --version)" || warn "docker not installed"
  command -v nvidia-ctk >/dev/null 2>&1 && ok "nvidia-ctk: $(nvidia-ctk --version | head -1)" || warn "nvidia-container-toolkit not installed"
  systemctl is-active --quiet docker && ok "docker service active" || warn "docker service not active"
  exit 0
fi

# --- Docker Engine -----------------------------------------------------------
say "Installing Docker Engine"

if command -v docker >/dev/null 2>&1 && [[ "$(command -v docker)" != /mnt/* ]]; then
  ok "already installed: $(docker --version)"
else
  # AlmaLinux 9 is RHEL 9; Docker publishes that under the centos path.
  sudo dnf install -y dnf-plugins-core
  sudo dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
  sudo dnf install -y \
    docker-ce docker-ce-cli containerd.io \
    docker-buildx-plugin docker-compose-plugin
  ok "installed $(docker --version)"
fi

say "Enabling the service"
sudo systemctl enable --now docker
sudo systemctl is-active --quiet docker && ok "docker service active" || die "docker service failed to start"

# Whose docker this is. install-localllm.ps1 runs this script as root - the
# account the distro step creates has a sudo password and there is no console
# to type it into - and names the real user in OMACHEESE_USER. Run by hand as
# yourself, it is you.
TARGET_USER="${OMACHEESE_USER:-$USER}"

say "Adding $TARGET_USER to the docker group"
if id -nG "$TARGET_USER" | grep -qw docker; then
  ok "already a member"
else
  sudo usermod -aG docker "$TARGET_USER"
  # Measured on WSL 2.7: every NEW `wsl` process sees the group at once. Only
  # a shell that was already open misses it, so no `wsl --shutdown` is needed.
  ok "added - new shells have it; one already open needs reopening"
fi

# --- NVIDIA Container Toolkit ------------------------------------------------
say "Installing the NVIDIA Container Toolkit"

if command -v nvidia-ctk >/dev/null 2>&1; then
  ok "already installed: $(nvidia-ctk --version | head -1)"
else
  curl -fsSL https://nvidia.github.io/libnvidia-container/stable/rpm/nvidia-container-toolkit.repo |
    sudo tee /etc/yum.repos.d/nvidia-container-toolkit.repo >/dev/null
  sudo dnf install -y nvidia-container-toolkit
  ok "installed $(nvidia-ctk --version | head -1)"
fi

say "Wiring the toolkit into the Docker daemon"
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker
ok "daemon restarted with the nvidia runtime"

# --- Verify ------------------------------------------------------------------
say "Verifying GPU access from a container"

# Root, or a member of the docker group in THIS process. A group added a moment
# ago is in /etc/group but not in this shell's credentials, and sudo may have no
# console to ask on, so fall back to sg, which reads /etc/group afresh.
docker_cmd() {
  if [ "$(id -u)" -eq 0 ] || id -nG | grep -qw docker; then
    docker "$@"
  else
    sg docker -c "docker $(printf '%q ' "$@")"
  fi
}

if docker_cmd run --rm --gpus all nvidia/cuda:12.6.2-base-ubi9 nvidia-smi \
     --query-gpu=name,memory.total --format=csv,noheader 2>/dev/null; then
  ok "containers can see the GPU"
else
  warn "GPU test failed. Usual causes:"
  warn "  - Windows NVIDIA driver too old for the CUDA image"
  warn "  - /dev/dxg missing (see the preflight above)"
  warn "  Retry with: docker run --rm --gpus all nvidia/cuda:12.6.2-base-ubi9 nvidia-smi"
fi

# No "run wsl --shutdown, then docker compose up" list any more: a new wsl
# process already has the group, and install-localllm.ps1 - which runs this
# script - starts the model server itself.
printf '\nDocker is ready.\n'
