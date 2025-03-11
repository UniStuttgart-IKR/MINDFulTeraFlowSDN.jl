# TeraFlowSDN Installation Guide

This guide provides step-by-step instructions for installing and deploying TeraFlowSDN in your environment.

## Prerequisites

Before starting the installation process, please ensure you have the following:

- Ubuntu 20.04 LTS or newer
- At least 8GB of RAM
- At least 20GB of free disk space
- An internet connection

## Installation Process

### 1. Initial Setup

Please follow the official TeraFlowSDN deployment guide at https://tfs.etsi.org/documentation/v4.0.0/deployment_guide/ until the section "Prepare a deployment script with the deployment settings" in "1.3. Deploy TeraFlowSDN".

This includes:
- Installing MicroK8s
- Setting up prerequisites
- Cloning the TeraFlowSDN repository

### 2. Custom Deployment Script Setup

**Important:** Our deployment process has slight modifications from the official guide.

1. First, clone the official TeraFlowSDN controller repository into a certain folder:
   ```bash
   git clone https://labs.etsi.org/rep/tfs/controller.git
   ```

2. Take note of the path of this folder where you cloned the repository, as you'll need to reference the `controller` folder in it in our deployment script.

3. In the `my_deploy.sh` script provided in this repository, update the `CONTROLLER_FOLDER` variable to point to your controller folder path:
   ```bash
   export CONTROLLER_FOLDER="/home/kshpthk/controller"  # Change this to your actual path
   ```

#### About the Deployment Script

Our `my_deploy.sh` script as well as the scripts in our `deploy` folder are based on the official example but include some improvements:

- Updated service configurations to work with newer versions of some components such as prometheus/observability
- Modifications to ensure reproducibility

The script settings are organized in 4 main sections:

1. **TeraFlowSDN Section**:
   - `CONTROLLER_FOLDER`: Points to the location of your cloned TeraFlowSDN controller repository. This is critical as it's used throughout the deployment for locating manifests, building images, and referencing deployment scripts.
   - `TFS_REGISTRY_IMAGE`: Specifies the private Docker registry to be used (default uses the Docker repository enabled in MicroK8s)
   - `TFS_COMPONENTS`: Lists components whose Docker images will be rebuilt, uploaded to the registry, and deployed in Kubernetes
   - `TFS_IMAGE_TAG`: Defines the tag for Docker images being rebuilt and uploaded
   - `TFS_K8S_NAMESPACE`: Specifies the Kubernetes namespace for deploying TFS components
   - `TFS_EXTRA_MANIFESTS`: Provides additional manifests to apply to Kubernetes (e.g., ingress controllers, service monitors)
   - `TFS_GRAFANA_PASSWORD`: Sets the password for the Grafana admin user
   - `TFS_SKIP_BUILD`: When set to YES, prevents rebuilding Docker images (redeploys existing images)

2. **CockroachDB Section**: Configures the deployment of the backend CockroachDB database
   - Settings include namespace, external ports, credentials, and deployment mode

3. **NATS Section**: Configures the deployment of the backend NATS message broker
   - Settings include namespace, external ports, and deployment mode

4. **K8s Observability**: Configures ports for Prometheus and Grafana

5. **QuestDB Section**: Configures the deployment of the backend QuestDB timeseries database
   - Settings include namespace, external ports, credentials, and table names

6. **Apache Kafka**: Configuration for Kafka deployment

Review the script and uncomment any additional components you want to deploy based on your needs. For extended descriptions of all settings, check the scripts in the deploy folder.

### 3. Continue with Deployment

Make sure our customized `my_deploy` script is executable:

```bash
chmod +x my_deploy.sh
```

After setting up the deployment script, continue following the official guide from the "Confirm that MicroK8s is running" section in "1.3. Deploy TeraFlowSDN" at https://tfs.etsi.org/documentation/latest/deployment_guide/.



## Troubleshooting

If you encounter any issues during deployment:

1. Check MicroK8s status: `microk8s status`
2. View pod status: `microk8s kubectl get pods -A`
3. Check logs for failing pods: `microk8s kubectl logs <pod-name> -n <namespace>`

## Additional Information

For more detailed information about TeraFlowSDN configuration options, please refer to the official documentation.
