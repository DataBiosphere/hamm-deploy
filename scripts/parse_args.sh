#!/usr/bin/env bash

# The new namespace to create/use, either set as an env variable or passed as $1
NAMESPACE=${1:-${NAMESPACE}}
if [[ -z ${NAMESPACE} ]]; then
    echo "You must specify the namespace you want to create/use"
    exit 1
fi

# We will probably want to pass in an ENVIRONMENT argument at some point.  At the moment, I'm NOT passing this in
# because in a bunch of the k8s yaml files, this would be the only variable we need to tweak.
ENVIRONMENT=${2:-dev}

# Your personal vault token that will be used when rendering the k8s yaml files
VAULT_TOKEN=${3:-$(cat ~/.vault-token)}

# The vault token that will be used by k8s when rendering configs in init containers for your services
# NOTE: This value is expected to be a base64 encoded string per: https://kubernetes.io/docs/concepts/configuration/secret/#creating-a-secret-manually
K8S_VAULT_TOKEN=$(kubectl --namespace=dev get secret token -o=json | jq -r .data.token)