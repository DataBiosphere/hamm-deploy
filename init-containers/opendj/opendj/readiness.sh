#!/usr/bin/env bash

# If any commands in this file return non-zero, then this container is not ready
set -e

# Check that opendj is up and responsive and has the "proxy user" loaded up
ldapsearch -H ldap://localhost -D "cn=Directory Manager" -w $(cat ${DIR_MANAGER_PW_FILE}) -b "cn=proxy-ro,ou=people,dc=dsde-dev,dc=broadinstitute,dc=org"