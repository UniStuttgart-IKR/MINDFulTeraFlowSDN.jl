#!/bin/bash
export CRDB_EXT_PORT_SQL="26257"
export CRDB_NAMESPACE="crdb"
echo "CockroachDB Port Mapping"
echo ">>> Expose CockroachDB SQL port (26257->${CRDB_EXT_PORT_SQL})"
CRDB_PORT_SQL=$(kubectl --namespace ${CRDB_NAMESPACE} get service cockroachdb-public -o 'jsonpath={.spec.ports[?(@.name=="sql")].port}')
echo here 1
PATCH='{"data": {"'${CRDB_EXT_PORT_SQL}'": "'${CRDB_NAMESPACE}'/cockroachdb-public:'${CRDB_PORT_SQL}'"}}'
echo here 2
kubectl patch configmap ingress-nginx-controller-7657f6db5f-kqbfk --namespace ingress --patch "${PATCH}"
echo here 3