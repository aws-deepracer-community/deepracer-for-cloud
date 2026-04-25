#!/usr/bin/env bash

set -euo pipefail
trap ctrl_c INT

function ctrl_c() {
    echo "Requested to stop."
    exit 1
}

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"

## Only allow macOS
if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "ERROR: This script is for macOS only. Use prepare.sh for Linux."
    exit 1
fi

MACOS_VERSION=$(sw_vers -productVersion)
MACOS_MAJOR=$(echo "$MACOS_VERSION" | cut -d. -f1)

# Supported: Monterey (12), Ventura (13), Sonoma (14), Sequoia (15)
SUPPORTED_MACOS_MAJOR=(12 13 14 15)
VERSION_OK=false
for V in "${SUPPORTED_MACOS_MAJOR[@]}"; do
    if [[ "${MACOS_MAJOR}" -eq "$V" ]]; then
        VERSION_OK=true
        break
    fi
done

if [[ "$VERSION_OK" != true ]]; then
    echo "WARNING: macOS ${MACOS_VERSION} is not a tested version."
    echo "         Supported: Monterey (12), Ventura (13), Sonoma (14), Sequoia (15)"
fi

echo "Detected macOS ${MACOS_VERSION}"

## macOS does not support NVIDIA GPUs -- always CPU
ARCH="cpu"
echo "macOS does not support NVIDIA GPUs. Using CPU mode."

## Detect Apple Silicon vs Intel
CPU_ARCH=$(uname -m)
if [[ "${CPU_ARCH}" == "arm64" ]]; then
    echo "Apple Silicon (arm64) detected."
    BREW_PREFIX="/opt/homebrew"
else
    echo "Intel (x86_64) detected."
    BREW_PREFIX="/usr/local"
fi

## Install Homebrew if not present
if ! command -v brew >/dev/null 2>&1; then
    echo "Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    eval "$("${BREW_PREFIX}/bin/brew" shellenv)"
fi

## Update Homebrew
brew update

## Install required packages (no awscli here -- installed separately below)
brew install jq python3 git screen bash

## Set Homebrew bash as the default shell if not already
BREW_BASH="${BREW_PREFIX}/bin/bash"
if ! grep -qF "${BREW_BASH}" /etc/shells; then
    echo "Adding ${BREW_BASH} to /etc/shells..."
    echo "${BREW_BASH}" | sudo tee -a /etc/shells
fi
if [[ "$(dscl . -read /Users/"$(id -un)" UserShell | awk '{print $2}')" != "${BREW_BASH}" ]]; then
    echo "Setting default shell to ${BREW_BASH}..."
    sudo chsh -s "${BREW_BASH}" "$(id -un)"
fi

## Ensure bash 5 + Homebrew PATH are set up for all SSH sessions.
## Sets PATH first so --login re-entry is safe (BASH_VERSINFO guard prevents looping).
BASH_PROFILE="${HOME}/.bash_profile"
BOOTSTRAP_MARKER="# drfc-bash5-bootstrap"
if ! grep -qF "${BOOTSTRAP_MARKER}" "${BASH_PROFILE}" 2>/dev/null; then
    cat >> "${BASH_PROFILE}" <<EOF

${BOOTSTRAP_MARKER}
eval "\$(${BREW_PREFIX}/bin/brew shellenv)"
export PATH="/usr/local/bin:\$PATH"  # AWS CLI v2
if [ -x "${BREW_BASH}" ] && [ "\${BASH_VERSINFO[0]:-0}" -lt 5 ]; then
    exec "${BREW_BASH}" --login
fi
EOF
    echo "Added bash 5 + PATH bootstrap to ${BASH_PROFILE}."
fi

## Install boto3 and pyyaml
if pip3 install boto3 pyyaml --break-system-packages 2>/dev/null; then
    echo "boto3 and pyyaml installed."
else
    pip3 install boto3 pyyaml
fi

## Install AWS CLI v2 via official pkg installer (avoids Homebrew Python conflicts)
if command -v aws >/dev/null 2>&1; then
    echo "AWS CLI already installed: $(aws --version 2>&1)"
else
    echo "Installing AWS CLI v2 via official installer..."
    TMP_PKG=$(mktemp /tmp/AWSCLIV2.XXXXXX.pkg)
    curl -fsSL "https://awscli.amazonaws.com/AWSCLIV2.pkg" -o "${TMP_PKG}"
    sudo installer -pkg "${TMP_PKG}" -target /
    rm -f "${TMP_PKG}"
    echo "AWS CLI installed: $(aws --version 2>&1)"
fi

## Detect cloud
# detect.sh relies on cloud-init which is typically absent on macOS.
# Fall back to probing the AWS Instance Metadata Service (IMDSv2).
CLOUD_NAME="local"
if [[ -f /var/run/cloud-init/instance-data.json ]]; then
    source "$DIR/detect.sh"
else
    if IMDS_TOKEN=$(curl -s --connect-timeout 2 \
            -X PUT "http://169.254.169.254/latest/api/token" \
            -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" 2>/dev/null) \
        && [[ -n "${IMDS_TOKEN}" ]]; then
        CLOUD_NAME="aws"
        CLOUD_INSTANCETYPE=$(curl -s --connect-timeout 2 \
            -H "X-aws-ec2-metadata-token: ${IMDS_TOKEN}" \
            "http://169.254.169.254/latest/meta-data/instance-type" 2>/dev/null || echo "unknown")
        export CLOUD_NAME
        export CLOUD_INSTANCETYPE
    else
        export CLOUD_NAME
    fi
fi
echo "Detected cloud type ${CLOUD_NAME}"

## Install Docker CLI and Colima (headless Docker runtime for macOS)
## Colima is preferred over Docker Desktop for headless/EC2 use.

if brew list --formula colima &>/dev/null; then
    echo "Colima already installed."
else
    brew install colima
fi

if command -v docker >/dev/null 2>&1; then
    echo "Docker CLI already installed."
else
    brew install docker
fi

## Install docker-compose v2 (as CLI plugin)
if brew list --formula docker-compose &>/dev/null; then
    echo "docker-compose already installed."
else
    brew install docker-compose
fi

## Register docker-compose as a Docker CLI plugin
mkdir -p "${HOME}/.docker/cli-plugins"
ln -sfn "$(brew --prefix)/opt/docker-compose/bin/docker-compose" \
    "${HOME}/.docker/cli-plugins/docker-compose"

## Start Colima if not already running
if colima status 2>/dev/null | grep -q "Running"; then
    echo "Colima is already running."
else
    echo "Starting Colima..."
    if [[ "${CPU_ARCH}" == "arm64" ]] && [[ "${MACOS_MAJOR}" -ge 13 ]]; then
        # Apple Silicon + macOS 13+: use Virtualization.framework (vz) for much
        # lower hypervisor overhead vs QEMU. virtiofs gives better I/O than sshfs.
        colima start --cpu 8 --memory 12 --disk 60 \
            --vm-type vz --mount-type virtiofs
    elif [[ "${CPU_ARCH}" == "arm64" ]]; then
        colima start --cpu 8 --memory 12 --disk 60 --mount-type virtiofs
    else
        # Intel Mac
        colima start --cpu 4 --memory 8 --disk 60 --mount-type virtiofs
    fi
fi

## Ensure docker socket is reachable
if ! docker info >/dev/null 2>&1; then
    echo "ERROR: Docker is not reachable. Check that Colima is running: colima status"
    exit 1
fi
echo "Docker is available via Colima."

## Create /tmp/sagemaker inside the Colima VM.
## On macOS, Docker runs inside Colima's Linux VM so bind-mounts must exist there,
## not on the macOS host. /tmp persists across colima stop/start but not colima delete.
colima ssh -- sudo mkdir -p /tmp/sagemaker
colima ssh -- sudo chmod -R ug+w /tmp/sagemaker
echo "/tmp/sagemaker created inside Colima VM."

## Ensure Colima auto-starts on login (launchd)
if ! launchctl list 2>/dev/null | grep -q "com.abiosoft.colima.default"; then
    brew services start colima || true
fi

## Completion message
echo ""
echo "First stage done. Log out and back in, then run init.sh -c ${CLOUD_NAME} -a ${ARCH}"
echo ""
echo "Notes:"
echo "  - Log out and back in for the new default shell (bash 5) to take effect."
echo "  - Colima must be running before using DeepRacer-for-Cloud."
echo "    Start it manually with: colima start"
echo "  - On Apple Silicon (arm64), amd64/x86_64 container images require"
echo "    Rosetta 2. Install it with: softwareupdate --install-rosetta"
echo "    Then restart Colima with: colima start --arch x86_64"
echo "  - No reboot is required."
