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
# Read deployment settings
########################################################################################################################

# If not already set, set the namespace where Apache Kafka will be deployed.
export KFK_NAMESPACE=${KFK_NAMESPACE:-"kafka"}

# If not already set, set the port Apache Kafka server will be exposed to.
export KFK_SERVER_PORT=${KFK_SERVER_PORT:-"9092"}

# If not already set, if flag is YES, Apache Kafka will be redeployed and all topics will be lost.
export KFK_REDEPLOY=${KFK_REDEPLOY:-""}


########################################################################################################################
# Automated steps start here
########################################################################################################################

    # Constants
    TMP_FOLDER="./tmp"
    KFK_MANIFESTS_PATH="manifests/kafka"
    KFK_ZOOKEEPER_MANIFEST="01-zookeeper.yaml"
    KFK_MANIFEST="02-kafka.yaml"

    # Create a tmp folder for files modified during the deployment
    TMP_MANIFESTS_FOLDER="${TMP_FOLDER}/${KFK_NAMESPACE}/manifests"
    mkdir -p ${TMP_MANIFESTS_FOLDER}

function kafka_deploy() {
     # copy zookeeper and kafka manifest files to temporary manifest location
    cp "${KFK_MANIFESTS_PATH}/${KFK_ZOOKEEPER_MANIFEST}" "${TMP_MANIFESTS_FOLDER}/${KFK_ZOOKEEPER_MANIFEST}"
    cp "${KFK_MANIFESTS_PATH}/${KFK_MANIFEST}" "${TMP_MANIFESTS_FOLDER}/${KFK_MANIFEST}"

    # echo "Apache Kafka Namespace"
    echo "Delete Apache Kafka Namespace"
    kubectl delete namespace ${KFK_NAMESPACE} --ignore-not-found

    echo "Create Apache Kafka Namespace"
    kubectl create namespace ${KFK_NAMESPACE}

    # echo ">>> Deplying Apache Kafka Zookeeper"
    # Kafka zookeeper service should be deployed before the kafka service
    kubectl --namespace ${KFK_NAMESPACE} apply -f "${TMP_MANIFESTS_FOLDER}/${KFK_ZOOKEEPER_MANIFEST}"

    KFK_ZOOKEEPER_SERVICE="zookeeper-service"    # this command may be replaced with command to extract service name automatically
    KFK_ZOOKEEPER_IP=$(kubectl --namespace ${KFK_NAMESPACE} get service ${KFK_ZOOKEEPER_SERVICE} -o 'jsonpath={.spec.clusterIP}')

    # Kafka service should be deployed after the zookeeper service
    sed -i "s/<ZOOKEEPER_INTERNAL_IP>/${KFK_ZOOKEEPER_IP}/" "${TMP_MANIFESTS_FOLDER}/$KFK_MANIFEST"

    # echo ">>> Deploying Apache Kafka Broker"
    kubectl --namespace ${KFK_NAMESPACE} apply -f "${TMP_MANIFESTS_FOLDER}/$KFK_MANIFEST"

    # echo ">>> Verifing Apache Kafka deployment"
    sleep 5
    # KFK_PODS_STATUS=$(kubectl --namespace ${KFK_NAMESPACE} get pods)
    # if echo "$KFK_PODS_STATUS" | grep -qEv 'STATUS|Running'; then
    #     echo "Deployment Error: \n $KFK_PODS_STATUS"
    # else
    #     echo "$KFK_PODS_STATUS"
    # fi
}

echo ">>> Apache Kafka"
echo "Checking if Apache Kafka is deployed ... "
if [ "$KFK_REDEPLOY" == "YES" ]; then
    echo "Redeploying kafka namespace"
    kafka_deploy
elif kubectl get namespace "${KFK_NAMESPACE}" &> /dev/null; then
    echo "Apache Kafka already present; skipping step." 
else
    echo "Kafka namespace doesn't exists. Deploying kafka namespace"
    kafka_deploy
fi
echo
