#!/usr/bin/env bash

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
SAM_SOLO_ROOT=${SCRIPT_DIR}

cd ${SAM_SOLO_ROOT}
source scripts/parse_args.sh

RENDERED_COMMON_PATH=k8s/common/rendered/${NAMESPACE}
RENDERED_OPENDJ_PATH=k8s/opendj/rendered/${NAMESPACE}
RENDERED_SAM_PATH=k8s/sam/rendered/${NAMESPACE}

rm -f ${RENDERED_COMMON_PATH}/*
rm -f ${RENDERED_OPENDJ_PATH}/*
rm -f ${RENDERED_SAM_PATH}/*

SERVICES=(common opendj sam)
for SERVICE_NAME in "${SERVICES[@]}"
do
    echo "Rendering Kubernetes YAML for: ${SERVICE_NAME}"
    ./scripts/setup_k8s_files.sh ${SERVICE_NAME} ${NAMESPACE} ${ENVIRONMENT} ${VAULT_TOKEN}
done

echo ""
echo "Done rendering/copying Kubernetes yaml files"
echo ""

echo "Creating Kubernetes Objects..."

# Begin Pre-requisites section
# We are going to create all k8s objects in the requested namespace, so the namespace needs to be created first
# Each of these commands should be blocking

kubectl create -f ${RENDERED_COMMON_PATH}/namespace.yaml
kubectl --namespace=${NAMESPACE} create -f ${RENDERED_COMMON_PATH}/token-secret.yaml
kubectl --namespace=${NAMESPACE} create -f ${RENDERED_COMMON_PATH}/role.yaml
# Create the tls keys
docker run --rm -it -v "$PWD":/working -v ${HOME}/.vault-token:/root/.vault-token broadinstitute/dsde-toolbox vault read --format=json secret/dsde/firecloud/${ENVIRONMENT}/common/server.crt | jq -r .data.value | tr -d '\r' > tls.crt
docker run --rm -it -v "$PWD":/working -v ${HOME}/.vault-token:/root/.vault-token broadinstitute/dsde-toolbox vault read --format=json secret/dsde/firecloud/${ENVIRONMENT}/common/server.key | jq -r .data.value | tr -d '\r' > tls.key
kubectl --namespace=${NAMESPACE} create secret generic wildcard.dsde-${ENVIRONMENT}.broadinstitute.org --from-file=tls.key --from-file=tls.crt
rm -f tls.crt tls.key
# End Pre-requisites section

# Begin Apps/Services section
# Each of these commands should be able to be kicked off simultaneously in any order
# The individual k8s objects should have Readiness and Liveness checks for restarting as needed and marking pods as
# ready
kubectl --namespace=${NAMESPACE} create -f ${RENDERED_OPENDJ_PATH}
kubectl --namespace=${NAMESPACE} create -f ${RENDERED_SAM_PATH}
# End Apps/Services section

echo ""
echo "Opendj and Sam are starting up in Namespace: ${NAMESPACE}"
echo "Check the status of these services by running command:"
echo ""
echo "kubectl --namespace=${NAMESPACE} get pods"
echo ""
