# TeraFlowSDN Installation Guide

This guide provides step-by-step instructions for installing and deploying TeraFlowSDN in your environment.

## Prerequisites

Before starting the installation process, please ensure you have the following:

- Linux operating system
- At least 8GB of RAM
- At least 20GB of free disk space
- An internet connection

## Installation Process

### 1. Initial Setup

The deployment is done by creating an incus or LXD virtual machine with TFS inside. 

LXD is only recommended if your host system is native Ubuntu 20.04 or newer. In this case, run `deploy-tfs/tfs-lxd-distributed/tfs-lxd.sh` with sudo permissions.

In the other cases, incus virtual machine must be created. Please follow the official incus installation guide available at https://linuxcontainers.org/incus/docs/main/installing/ for many different Linux systems. Then, it is possible to run `deploy-tfs/tfs-incus-distributed/tfs-incus.sh` with sudo permissions.



### 2. Custom Deployment

By default, the script will set up all the prerequisites and deploy an empty TFS controller inside a virtual machine called `tfs-vm`. However, it is possible to pass some arguments when running the shell script:
- Name of the virtual machine: `VM_NAME="vmname"`
- Load a network configuration: `RUN_JULIA=true` and `CONFIG_PATH="path/to/configX.toml"`

What Gets Created:
- LXD/incus VM: `tfs-vm`
- User inside VM: `tfsuser`
- MicroK8s 1.29 with addons (dns, storage, ingress, registry, metrics, prometheus, linkerd)
- Repos: `controller`, `MINDFulTeraFlowSDN.jl`
- TeraFlow services in namespace `tfs`
- (Optional) Stable admin context + topology
- (Optional) Device graph loaded via Julia

After completion:
- Direct access: http://{VM_IP}:80/webui
- VSCode Server: Forward port {VM_IP}:80 in VSCode, check the auto forward and the access will be at http://localhost:{forwarded-port}/webui
- Shell access if needed: `lxc exec tfs-vm -- bash`

After loading a network configuration to TFS, it is possible to stop the virtual machine with `incus stop tfs-vm` and start it again with `incus start tfs-vm`. This will clean the TFS database, so it it possible to load new network configurations without uninstalling the VM.



### 3. Our Script Setup

**Important:** Our deployment process has slight modifications from the official guide at https://tfs.etsi.org/documentation/latest/deployment_guide/. The first steps are the same until the section "Prepare a deployment script with the deployment settings" in "1.3. Deploy TeraFlowSDN". This includes:
- Installing MicroK8s
- Setting up prerequisites
- Cloning the TeraFlowSDN repository

After this point, our `my_deploy.sh` script as well as the scripts in our `deploy` folder are based on the official example but include some improvements:

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



## Troubleshooting

If you encounter any issues during virtual machine deployment (equivalent with `lxc` instead of `incus`):

1. Check created VMs and the IP address assigned: `incus list`
2. List storage pools: `incus storage list`
3. Check default profile: `incus profile show default`
4. List available networks: `incus network list`
5. Force stop: `incus stop tfs-vm --force`
6. Delete virtual machine (only possible if it is stopped): `incus delete tfs-vm`


If you encounter any issues during MicroK8s deployment:

1. Check MicroK8s status: `microk8s status`
2. View pod status: `microk8s kubectl get pods -A`
3. Check logs for failing pods: `microk8s kubectl logs <pod-name> -n <namespace>`


## Additional Information

For more detailed information about TeraFlowSDN configuration options, please refer to the official documentation.
