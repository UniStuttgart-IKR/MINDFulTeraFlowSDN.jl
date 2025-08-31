#!/usr/bin/env bash
set -euo pipefail

VM_NAME="${VM_NAME:-tfs-vm}"
DEVSPACE_MODE="${DEVSPACE_MODE:-no}"
RUN_JULIA="${RUN_JULIA:-false}" 
CONFIG_PATH="${CONFIG_PATH:-test/data/config3.toml}"

# 0) Setup incus
if ! snap list 2>/dev/null | grep -q '^incus '; then
  echo "[incus] Installing incus snap..."
  sudo snap install incus
fi

if ! groups | grep -q incus; then
  USE_SUDO="sudo"
else
  USE_SUDO=""
fi

if ! ${USE_SUDO} incus info >/dev/null 2>&1; then
  echo "[incus] Initializing incus..."
  sudo incus init --minimal
fi

# Check VM state
VM_EXISTS=false
PART1_COMPLETE=false
DEPLOYMENT_COMPLETE=false

if ${USE_SUDO} incus info "${VM_NAME}" >/dev/null 2>&1; then
  VM_STATE=$(${USE_SUDO} incus list "${VM_NAME}" -c s --format csv)
  if [[ "$VM_STATE" == "RUNNING" ]]; then
    echo "[incus] VM ${VM_NAME} exists and is running"
    VM_EXISTS=true
    
    # Check if part 1 completed - multiple methods for reliability
    echo "[incus] Checking if Part 1 is completed..."
    
    # Method 1: Check if microk8s binary exists
    if ${USE_SUDO} incus exec "${VM_NAME}" -- test -f "/snap/bin/microk8s" >/dev/null 2>&1; then
      echo "[incus] Part 1 completed, MicroK8s binary found"
      PART1_COMPLETE=true
      
      # Check if TeraFlow deployment is complete by checking critical services
      echo "[incus] Checking TeraFlow deployment status..."
      DEPLOYMENT_CHECK=$(${USE_SUDO} incus exec "${VM_NAME}" -- sudo -u tfsuser bash -c '
        if kubectl get namespace tfs >/dev/null 2>&1; then
          MAIN_SERVICES=("deviceservice" "nbiservice" "webuiservice")
          RUNNING_SERVICES=0
          
          for service in "${MAIN_SERVICES[@]}"; do
            POD_STATUS=$(kubectl get pods -n tfs -l app="$service" -o jsonpath="{.items[0].status.phase}" 2>/dev/null || echo "NotFound")
            
            if [[ "$POD_STATUS" == "Running" ]]; then
              RUNNING_SERVICES=$((RUNNING_SERVICES + 1))
            fi
          done
          
          if [[ $RUNNING_SERVICES -eq ${#MAIN_SERVICES[@]} ]]; then
            echo "COMPLETE"
          else
            echo "INCOMPLETE"
          fi
        else
          echo "NO_NAMESPACE"
        fi
      ' 2>/dev/null || echo "ERROR")
      
      if [[ "$DEPLOYMENT_CHECK" == "COMPLETE" ]]; then
        DEPLOYMENT_COMPLETE=true
        echo "[incus] TeraFlow deployment already complete"
      else
        echo "[incus] TeraFlow deployment incomplete or not found"
      fi
    else
      echo "[incus] Part 1 not completed"
      PART1_COMPLETE=false
    fi
  else
    echo "[incus] VM exists but not running, removing..."
    ${USE_SUDO} incus stop "${VM_NAME}" --force || true
    ${USE_SUDO} incus delete "${VM_NAME}" || true
  fi
fi

# Create VM if needed
if [[ "$VM_EXISTS" == "false" ]]; then
  echo "[incus] Creating new VM..."
  ${USE_SUDO} incus launch images:ubuntu/24.04 "${VM_NAME}" --vm \
    -c limits.cpu=4 \
    -c limits.memory=8GiB \
    -c security.secureboot=false \
    --device root,size=100GiB

  echo "[incus] Waiting for VM to start..."
  timeout=600
  elapsed=0
  while [ $elapsed -lt $timeout ]; do
    if ${USE_SUDO} incus exec "${VM_NAME}" -- echo "VM ready" >/dev/null 2>&1; then
      break
    fi
    sleep 15
    elapsed=$((elapsed + 15))
  done

  ${USE_SUDO} incus exec "${VM_NAME}" -- cloud-init status --wait || true

  echo "[incus] Setting up VM..."
  ${USE_SUDO} incus exec "${VM_NAME}" -- bash -c '
    useradd -m -s /bin/bash tfsuser
    echo "tfsuser ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/99-tfsuser
    chmod 440 /etc/sudoers.d/99-tfsuser
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y docker.io docker-buildx jq git curl snapd openssh-server
    systemctl enable docker ssh
    systemctl start docker ssh
  '
fi

# Run appropriate bootstrap part
if [[ "$DEPLOYMENT_COMPLETE" == "true" ]]; then
  echo "[incus] Deployment already complete, setting up access only..."

  # # Clone repositories inside the VM if needed
  # echo "[incus] Ensuring repositories are cloned inside VM..."
  # ${USE_SUDO} incus exec "${VM_NAME}" -- sudo -u tfsuser bash -c '
  #   cd /home/tfsuser
  #   if [ ! -d "controller" ]; then
  #       git clone https://labs.etsi.org/rep/tfs/controller.git
  #   fi
    
  #   rm -rf MINDFulTeraFlowSDN.jl && git clone https://github.com/UniStuttgart-IKR/MINDFulTeraFlowSDN.jl
  # '

  # After part 2 completes, run Julia setup
  if [[ "$RUN_JULIA" == "true" ]]; then
    echo "[incus] Part 2 complete, running Julia setup..."
    ${USE_SUDO} incus file push "./bootstrap-julia.sh" "${VM_NAME}/home/tfsuser/bootstrap-julia.sh"
    ${USE_SUDO} incus exec "${VM_NAME}" -- bash -c 'chown tfsuser:tfsuser /home/tfsuser/bootstrap-julia.sh && chmod +x /home/tfsuser/bootstrap-julia.sh'
    ${USE_SUDO} incus exec "${VM_NAME}" -- sudo -u tfsuser env CONFIG_PATH="${CONFIG_PATH}" bash -c "/home/tfsuser/bootstrap-julia.sh"
  fi

elif [[ "$PART1_COMPLETE" == "false" ]]; then
  echo "[incus] Running bootstrap part 1..."
  ${USE_SUDO} incus file push "./bootstrap-part1.sh" "${VM_NAME}/home/tfsuser/bootstrap-part1.sh"
  ${USE_SUDO} incus exec "${VM_NAME}" -- bash -c 'chown tfsuser:tfsuser /home/tfsuser/bootstrap-part1.sh && chmod +x /home/tfsuser/bootstrap-part1.sh'
  
  # Run part 1 in background since it will reboot
  ${USE_SUDO} incus exec "${VM_NAME}" -- sudo -u tfsuser bash -c "/home/tfsuser/bootstrap-part1.sh --devspace=${DEVSPACE_MODE}" &
  
  echo "[incus] Part 1 started, VM will reboot. Waiting for restart..."
  sleep 10
  
  # Wait for VM to go down and come back up
  echo "[incus] Waiting for VM to reboot..."
  timeout=300
  elapsed=0
  while [ $elapsed -lt $timeout ]; do
    if ! ${USE_SUDO} incus exec "${VM_NAME}" -- echo "test" >/dev/null 2>&1; then
      echo "[incus] VM is rebooting..."
      break
    fi
    sleep 5
    elapsed=$((elapsed + 5))
  done
  
  # Wait for VM to come back up
  timeout=300
  elapsed=0
  while [ $elapsed -lt $timeout ]; do
    if ${USE_SUDO} incus exec "${VM_NAME}" -- echo "VM ready" >/dev/null 2>&1; then
      echo "[incus] VM is back up!"
      PART1_COMPLETE=true
      break
    fi
    sleep 10
    elapsed=$((elapsed + 10))
  done
fi

# Run part 2 if needed
if [[ "$PART1_COMPLETE" == "true" && "$DEPLOYMENT_COMPLETE" == "false" ]]; then
  echo "[incus] Copying local MINDFulTeraFlowSDN.jl to VM..."
  ${USE_SUDO} incus file push -r "../../../MINDFulTeraFlowSDN.jl" "${VM_NAME}/home/tfsuser/"
  ${USE_SUDO} incus exec "${VM_NAME}" -- bash -c 'chown -R tfsuser:tfsuser /home/tfsuser/MINDFulTeraFlowSDN.jl'

  echo "[incus] Running bootstrap part 2..."
  ${USE_SUDO} incus file push "./bootstrap-part2.sh" "${VM_NAME}/home/tfsuser/bootstrap-part2.sh"
  ${USE_SUDO} incus exec "${VM_NAME}" -- bash -c 'chown tfsuser:tfsuser /home/tfsuser/bootstrap-part2.sh && chmod +x /home/tfsuser/bootstrap-part2.sh'
  ${USE_SUDO} incus exec "${VM_NAME}" -- sudo -u tfsuser bash -c "/home/tfsuser/bootstrap-part2.sh"

  # After part 2 completes, run Julia setup
  if [[ "$RUN_JULIA" == "true" ]]; then
    echo "[incus] Part 2 complete, running Julia setup..."
    ${USE_SUDO} incus file push "./bootstrap-julia.sh" "${VM_NAME}/home/tfsuser/bootstrap-julia.sh"
    ${USE_SUDO} incus exec "${VM_NAME}" -- bash -c 'chown tfsuser:tfsuser /home/tfsuser/bootstrap-julia.sh && chmod +x /home/tfsuser/bootstrap-julia.sh'
    ${USE_SUDO} incus exec "${VM_NAME}" -- sudo -u tfsuser env CONFIG_PATH="${CONFIG_PATH}" bash -c "/home/tfsuser/bootstrap-julia.sh"
  fi

fi

# Get VM IP address
VM_IP=$(${USE_SUDO} incus list "${VM_NAME}" -c 4 --format csv | grep -v "172.17.0.1" | head -n1 | cut -d' ' -f1)
echo "[incus] VM IP: $VM_IP"

echo "✅ Setup complete!"
echo ""
echo "🌐 Access URLs:"
echo "  Direct access: http://${VM_IP}:80/webui"
echo "  VSCode Server: Forward port ${VM_IP}:80 in VSCode, check the auto forward and the access will be at http://localhost:<forwarded-port>/webui (likely port 80)"
echo ""
echo "VM shell: ${USE_SUDO} incus exec ${VM_NAME} -- bash"
