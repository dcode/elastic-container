#!/bin/bash


CA_PASSWORD_FILE=/run/secrets/ca_provisioner_password
ROOT_CA_PATH=/run/secrets/certificates/ca.crt


step ca init --deployment-type=standalone \
    --name pki --dns setup \
    --address 0.0.0.0:443 \
    --provisioner=elastic@stack.local \
    --password-file="${CA_PASSWORD_FILE}"
step ca provisioner add acme --type ACME

step certificate install "$(step path)/certs/root_ca.crt"
cp "$(step path)/certs/root_ca.crt" "${ROOT_CA_PATH}"
nohup step-ca --password-file="${CA_PASSWORD_FILE}" "$(step path)/config/ca.json" > /var/log/step-ca.log 2>/var/log/step-ca.err

wait-for echo "Waiting for Elasticsearch to be ready"
wait-for --timeout=120 https://elasticsearch:9200 -- echo "Elasticsearch is ready!"