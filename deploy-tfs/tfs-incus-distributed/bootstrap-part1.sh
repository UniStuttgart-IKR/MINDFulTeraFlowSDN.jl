#!/bin/bash
set -e

echo "=== TeraFlow SDN Setup - Part 1 ==="

# Parse devspace argument
DEVSPACE_MODE="no"
if [[ "${1}" == "--devspace=yes" ]]; then
    DEVSPACE_MODE="yes"
fi

echo "[1/5] Configure Docker daemon with insecure registries"
TEMP_DAEMON_JSON="$HOME/tmp.daemon.json"

if sudo [ -s /etc/docker/daemon.json ]; then 
    sudo cat /etc/docker/daemon.json
else 
    echo '{}'
fi | jq 'if has("insecure-registries") then . else .+ {"insecure-registries": []} end' -- \
    | jq '."insecure-registries" |= (.+ ["localhost:32000"] | unique)' -- \
    | tee "$TEMP_DAEMON_JSON"

sudo mv "$TEMP_DAEMON_JSON" /etc/docker/daemon.json
sudo chown root:root /etc/docker/daemon.json
sudo chmod 600 /etc/docker/daemon.json

echo "[2/5] Start Docker daemon"
sudo systemctl restart docker

echo "[3/5] Install MicroK8s"
# systemctl is-active snapd
# systemctl is-active snapd.socket
# sudo snap --version

sleep 10

# systemctl is-active snapd.socket
# systemctl is-active snapd
# sudo snap --version
# sudo snap version
# echo "Waiting for snapd service to be active..."
# timeout=60
# elapsed=0
# systemctl is-active snapd
# while ! systemctl is-active --quiet snapd; do
#     echo "loop"
#     sleep 2
#     elapsed=$((elapsed + 2))
#     if [ $elapsed -ge $timeout ]; then
#         echo "ERROR: snapd service did not start within $timeout seconds."
#         exit 1
#     fi
# done
sudo snap install microk8s --classic --channel=1.29/stable

echo "[4/5] Create aliases"
sudo snap alias microk8s.kubectl kubectl || true
sudo snap alias microk8s.helm3 helm3 || true

echo "[5/5] Add user to docker and microk8s groups"
# sudo usermod -a -G docker $USER
# sudo usermod -a -G microk8s $USER
mkdir -p $HOME/.kube
sudo chown -f -R $USER $HOME/.kube

# Save devspace mode for part 2
echo "$DEVSPACE_MODE" > /home/tfsuser/.devspace_mode

echo "========================================="
echo "Part 1 complete. REBOOTING for group membership..."
echo "========================================="
sudo reboot