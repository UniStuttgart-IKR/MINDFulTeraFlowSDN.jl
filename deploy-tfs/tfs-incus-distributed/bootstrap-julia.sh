#!/bin/bash
set -e

echo "=== Julia Setup for TeraFlow SDN ==="

# Always ensure julia is in PATH first (in case it was installed previously)
export PATH="$HOME/.juliaup/bin:$PATH"

# Check if Julia is already installed and working
JULIA_INSTALLED=false
if command -v julia >/dev/null 2>&1; then
    JULIA_VERSION=$(julia --version 2>/dev/null || echo "unknown")
    echo "[INFO] Julia already installed: $JULIA_VERSION"
    JULIA_INSTALLED=true
else
    echo "[INFO] Julia not found in PATH, checking for existing installation..."
    
    # Check if juliaup config exists but julia isn't working
    if [ -f "$HOME/.julia/juliaup/juliaup.json" ]; then
        echo "[INFO] Found existing juliaup config, cleaning up..."
        rm -rf "$HOME/.julia/juliaup/"
        echo "[INFO] Cleaned up old juliaup configuration"
    fi
fi

# Install Julia if not present using juliaup
if [ "$JULIA_INSTALLED" = false ]; then
    echo "[1/2] Installing Julia using juliaup..."
    
    # Install juliaup
    echo "Installing juliaup..."
    curl -fsSL https://install.julialang.org | sh -s -- --yes
    
    # Add juliaup to PATH for current session
    export PATH="$HOME/.juliaup/bin:$PATH"
    
    # Update shell profile to include juliaup in PATH for future sessions
    echo 'export PATH="$HOME/.juliaup/bin:$PATH"' >> ~/.bashrc
    
    echo "Julia installation complete"
    # Verify julia is now accessible
    if command -v julia >/dev/null 2>&1; then
        julia --version
    else
        echo "ERROR: Julia still not found in PATH after installation"
        exit 1
    fi
else
    echo "[1/2] Julia already installed ✓"
fi

# Setup Julia project
echo "[2/2] Setting up Julia project..."
cd $HOME/MINDFulTeraFlowSDN.jl

# Check if project is already instantiated and activate it
echo "Activating and instantiating Julia project..."
julia --project=. -e 'using Pkg; Pkg.activate("."); Pkg.instantiate()'

CONFIG_PATH="${CONFIG_PATH:-test/data/config3.toml}"
export CONFIG_PATH
julia --project=. -e 'using MINDFulTeraFlowSDN; MINDFulTeraFlowSDN.main()' $CONFIG_PATH "127.0.0.1"

echo "=== Julia Setup Complete ==="