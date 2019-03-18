#!/usr/bin/env bash

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
SAM_SOLO_ROOT=${SCRIPT_DIR}
NAMESPACE=dev
ENVIRONMENT=dev
RENDERED_CLUSTER_PATH=k8s/cluster/rendered/${NAMESPACE}

cd ${SAM_SOLO_ROOT}
VAULT_TOKEN=${3:-$(cat ~/.vault-token)}

echo "Rendering Kubernetes YAML for: cluster"
./scripts/setup_k8s_files.sh cluster ${NAMESPACE} ${ENVIRONMENT} ${VAULT_TOKEN}

echo "creating cluster-wide resources"
kubectl create -f ${RENDERED_CLUSTER_PATH}

echo "Now you need to manually create the token secret in the dev namespace to bootstrap the cluster"
