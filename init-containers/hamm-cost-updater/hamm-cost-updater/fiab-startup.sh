#!/usr/bin/env bash

echo "Sleeping for $SLEEP seconds before hamm startup."
sleep $SLEEP
echo "Finished sleep, starting."
/opt/docker/bin/costupdater $JAVA_OPTS