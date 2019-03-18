#!/usr/bin/env bash

####
# This file will do the following:
#
# 1. Render all .ctmpl files into: k8s/${SERVICE_NAME}/rendered/${NAMESPACE}
# 2. Copy all .yaml files from k8s/${SERVICE_NAME} into: k8s/${SERVICE_NAME}/rendered/${NAMESPACE}
#
####

# The service you want to render for, either set as an env variable or passed as $1
SERVICE_NAME=${1:-${SERVICE_NAME}}
if [[ -z ${SERVICE_NAME} ]]; then
    echo "You must specify the name of the service you want to deploy"
    exit 1
fi

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
SAM_SOLO_ROOT=$(dirname ${SCRIPT_DIR})
SERVICE_ROOT_PATH=${SAM_SOLO_ROOT}/k8s/${SERVICE_NAME}

cd ${SCRIPT_DIR}

shift 1
source parse_args.sh


docker run --rm \
    -v ${SERVICE_ROOT_PATH}:/working \
    -e NAMESPACE=${NAMESPACE} \
    -e ENVIRONMENT=${ENVIRONMENT} \
    -e VAULT_TOKEN=${VAULT_TOKEN} \
    -e K8S_VAULT_TOKEN=${K8S_VAULT_TOKEN} \
    -e INPUT_PATH=/working \
    -e OUT_PATH=/working/rendered/${NAMESPACE} \
    broadinstitute/dsde-toolbox render-templates.sh

find -E ${SERVICE_ROOT_PATH} -maxdepth 1 -iregex '.*\.ya?ml' -exec cp {} ${SERVICE_ROOT_PATH}/rendered/${NAMESPACE} \;