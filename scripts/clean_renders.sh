#!/usr/bin/env bash

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
SAM_SOLO_ROOT=$(dirname ${SCRIPT_DIR})

for DIR in $(find ${SAM_SOLO_ROOT}/k8s -mindepth 1 -maxdepth 1 -type d)
do
    rm -rfv ${DIR}/rendered
done