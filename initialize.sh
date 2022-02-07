#!/bin/bash

# Make sure the permissions are user only
umask 0177

if [ ! -f secrets/elastic_password.txt ]; then
    # Generate 20-byte password for elastic user
    LC_ALL=C tr -dc '[:alnum:]' < /dev/urandom | fold -w 20 | head -n 1 > secrets/elastic_password.txt
fi

if [ ! -f secrets/ca_provisioner_password.txt ]; then
    # Generate 32-byte password for cert authority
    LC_ALL=C tr -dc '[:print:]' < /dev/urandom | fold -w 32 | head -n 1 > secrets/ca_provisioner_password.txt
fi


if [ ! -f secrets/xpack_security_encryptionkey.txt ]; then
    # Generate 32-byte encryption key for Kibana
    LC_ALL=C tr -dc '[:print:]' < /dev/urandom | fold -w 32 | head -n 1 > secrets/xpack_security_encryptionkey.txt
fi