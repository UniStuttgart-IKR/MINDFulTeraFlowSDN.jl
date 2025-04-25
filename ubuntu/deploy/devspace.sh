################################################################################
# CONDITIONAL DEV MODE: If TFS_DEV_MODE == "YES", start DevSpace in dev mode.
################################################################################

export TFS_K8S_NAMESPACE=${TFS_K8S_NAMESPACE:-"tfs"}

if [ "$TFS_DEV_MODE" == "YES" ]; then
    echo "-----------------------------------------------------"
    echo "DEV MODE enabled (TFS_DEV_MODE=YES). Starting DevSpace dev..."
    echo "Using namespace: $TFS_K8S_NAMESPACE"
    echo "Using devspace configuration file: $DEVSPACE_CONFIG"
    echo "Using target directory: $CONTROLLER_FOLDER"
    echo "-----------------------------------------------------"

    # Change to your controller folder so relative paths resolve correctly
    cd $CONTROLLER_FOLDER || { echo "Unable to cd to $CONTROLLER_FOLDER"; exit 1; }

    # Ensure the correct Kubernetes namespace is selected.
    devspace use namespace "$TFS_K8S_NAMESPACE"

    # Start DevSpace development mode using the configuration file from ma1024
    # and instruct DevSpace to resolve relative paths from the controller folder.
    devspace dev --config="$DEVSPACE_CONFIG"

    echo "DevSpace dev mode terminated. Exiting."
    exit 0
fi