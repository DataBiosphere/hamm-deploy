#!/usr/bin/env bash

NAMESPACE=${1:-${NAMESPACE}}
if [[ -z ${NAMESPACE} ]]; then
    echo "You must specify the namespace you want to delete"
    exit 1
fi

echo ""
echo "WARNING! You are about to delete the Kubernetes Namespace: ${NAMESPACE}"
echo -n "This operation is permanent and cannot be undone.  Are you sure you want to delete this Namespace? (y/n)? "
read answer

# Variable expansion of ${answer#[Yy]} will eliminate the matching characters in [Yy] from the beginning of $answer
# So if the variable expansion fails to change $answer, then we did not answer "Yes", so abort abort abort!
if [[ "$answer" == "${answer#[Yy]}" ]]; then
    exit 1
fi

# https://stackoverflow.com/questions/47128586/how-to-delete-all-resources-from-kubernetes-one-time
# There may be things for which we want to gracefully shut them down in order to save logs or metadata or something.
# For now, it's HAMMER TIME!
kubectl delete namespace ${NAMESPACE}