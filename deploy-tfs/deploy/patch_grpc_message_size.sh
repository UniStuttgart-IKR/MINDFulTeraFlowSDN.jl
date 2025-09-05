#!/bin/bash
# filepath: /home/kshpthk/MINDFulTeraFlowSDN.jl/deploy-tfs/patch_grpc_message_size.sh

# Copyright 2022-2024 ETSI SDG TeraFlowSDN (TFS) (https://tfs.etsi.org/)
# Script to patch gRPC message size limits to 32MB before deployment

set -e

echo "Patching gRPC message size limits to 32MB..."

# Check if CONTROLLER_FOLDER is set
if [ -z "$CONTROLLER_FOLDER" ]; then
    echo "Error: CONTROLLER_FOLDER environment variable is not set."
    echo "Please source your deployment script first (e.g., source my_deploy.sh)"
    exit 1
fi

# Check if controller folder exists
if [ ! -d "$CONTROLLER_FOLDER" ]; then
    echo "Error: Controller folder not found at $CONTROLLER_FOLDER"
    exit 1
fi

# File paths
GENERIC_GRPC_SERVICE_FILE="$CONTROLLER_FOLDER/src/common/tools/service/GenericGrpcService.py"
CONTEXT_CLIENT_FILE="$CONTROLLER_FOLDER/src/context/client/ContextClient.py"

# Function to patch GenericGrpcService.py
patch_generic_grpc_service() {
    echo "  Patching GenericGrpcService.py..."
    
    if [ ! -f "$GENERIC_GRPC_SERVICE_FILE" ]; then
        echo "    Warning: GenericGrpcService.py not found at expected location"
        return 1
    fi
    
    # Check if already patched
    if grep -q "32 \* 1024 \* 1024" "$GENERIC_GRPC_SERVICE_FILE"; then
        echo "    GenericGrpcService.py already patched"
        return 0
    fi
    
    # Create backup
    cp "$GENERIC_GRPC_SERVICE_FILE" "${GENERIC_GRPC_SERVICE_FILE}.backup"
    
    # Apply patch - replace the grpc.server line with options
    sed -i 's/self\.server = grpc\.server(self\.pool) # , interceptors=(tracer_interceptor,))/self.server = grpc.server(\
            self.pool,\
            options=[\
                ("grpc.max_receive_message_length", 32 * 1024 * 1024),  # 32 MB\
                ("grpc.max_send_message_length", 32 * 1024 * 1024),  # 32 MB\
            ],\
        )  # , interceptors=(tracer_interceptor,))/' "$GENERIC_GRPC_SERVICE_FILE"
    
    echo "    GenericGrpcService.py patched successfully"
}

# Function to patch ContextClient.py
patch_context_client() {
    echo "  Patching ContextClient.py..."
    
    if [ ! -f "$CONTEXT_CLIENT_FILE" ]; then
        echo "    Warning: ContextClient.py not found at expected location"
        return 1
    fi
    
    # Check if already patched
    if grep -q "32 \* 1024 \* 1024" "$CONTEXT_CLIENT_FILE"; then
        echo "    ContextClient.py already patched"
        return 0
    fi
    
    # Create backup
    cp "$CONTEXT_CLIENT_FILE" "${CONTEXT_CLIENT_FILE}.backup"
    
    # Apply patch - replace the grpc.insecure_channel line with options
    sed -i 's/self\.channel = grpc\.insecure_channel(self\.endpoint)/self.channel = grpc.insecure_channel(\
            self.endpoint,\
            options=[\
                ("grpc.max_receive_message_length", 32 * 1024 * 1024),  # 32 MB\
                ("grpc.max_send_message_length", 32 * 1024 * 1024),  # 32 MB\
            ],\
        )/' "$CONTEXT_CLIENT_FILE"
    
    echo "    ContextClient.py patched successfully"
}

# Function to restore from backup
restore_backups() {
    echo "Restoring original files from backup..."
    
    if [ -f "${GENERIC_GRPC_SERVICE_FILE}.backup" ]; then
        mv "${GENERIC_GRPC_SERVICE_FILE}.backup" "$GENERIC_GRPC_SERVICE_FILE"
        echo "  GenericGrpcService.py restored"
    fi
    
    if [ -f "${CONTEXT_CLIENT_FILE}.backup" ]; then
        mv "${CONTEXT_CLIENT_FILE}.backup" "$CONTEXT_CLIENT_FILE"
        echo "  ContextClient.py restored"
    fi
}

# Function to clean backups
clean_backups() {
    echo "Cleaning backup files..."
    
    if [ -f "${GENERIC_GRPC_SERVICE_FILE}.backup" ]; then
        rm "${GENERIC_GRPC_SERVICE_FILE}.backup"
        echo "  GenericGrpcService.py backup removed"
    fi
    
    if [ -f "${CONTEXT_CLIENT_FILE}.backup" ]; then
        rm "${CONTEXT_CLIENT_FILE}.backup"
        echo "  ContextClient.py backup removed"
    fi
}

# Main logic
case "${1:-patch}" in
    "patch")
        patch_generic_grpc_service
        patch_context_client
        echo "gRPC message size patching completed!"
        ;;
    "restore")
        restore_backups
        echo "Original files restored!"
        ;;
    "clean")
        clean_backups
        echo "Backup files cleaned!"
        ;;
    *)
        echo "Usage: $0 [patch|restore|clean]"
        echo "  patch   - Apply gRPC message size patches (default)"
        echo "  restore - Restore original files from backup"
        echo "  clean   - Remove backup files"
        exit 1
        ;;
esac