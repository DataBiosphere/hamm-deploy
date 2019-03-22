#!/bin/bash

# This script is intended to override the default 
# startup script built into the docker image.  The reason for it is so
# that an env file can be used to load the environment instead of
# relying on configmaps and env vars defined in kubernetes

# env file should be a shell export var compatible

# location of env file to load
ENVFILE=${ENVFILE:-"/etc/app.env"}

# If env file exists then load environment from file
if [ -r "${ENVFILE}" ]
then
   # load shell exports into env
   .  "${ENVFILE}"
fi

# exec startup as normal
exec /opt/docker/bin/costupdater $JAVA_OPTS
