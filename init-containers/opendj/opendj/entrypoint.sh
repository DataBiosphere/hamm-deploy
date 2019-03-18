#!/bin/bash

# This script is intended to override the default cromwell 
# startup script built into the docker image.  The reason for it is so
# that an env file can be used to load the environment instead of
# relying on configmaps and env vars defined in kubernetes

# env file should be a shell export var compatible

# location of env file to load
OPENDJ_ENVFILE=${OPENDJ_ENVFILE:-"/etc/opendj.env"}

# If env file exists then load environment from file
if [ -r "${OPENDJ_ENVFILE}" ]
then
   # load shell exports into env
   .  "${OPENDJ_ENVFILE}"
fi

# exec startup as normal
exec /opt/opendj/run.sh
