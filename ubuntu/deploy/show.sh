#!/bin/bash
# Copyright 2022-2024 ETSI SDG TeraFlowSDN (TFS) (https://tfs.etsi.org/)
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

########################################################################################################################
# Define your deployment settings here
########################################################################################################################

# If not already set, set the name of the Kubernetes namespace to deploy to.
export TFS_K8S_NAMESPACE=${TFS_K8S_NAMESPACE:-"tfs"}

########################################################################################################################
# Automated steps start here
########################################################################################################################

echo "Deployment Resources:"
kubectl --namespace $TFS_K8S_NAMESPACE get all
printf "\n"

echo "Deployment Ingress:"
kubectl --namespace $TFS_K8S_NAMESPACE get ingress
printf "\n"
