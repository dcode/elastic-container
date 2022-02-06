FROM ubuntu:20.04


ADD https://dl.step.sm/gh-release/cli/docs-ca-install/v0.18.1/step-cli_0.18.1_amd64.deb /tmp/step-cli.deb
ADD https://dl.step.sm/gh-release/certificates/docs-ca-install/v0.18.1/step-ca_0.18.1_amd64.deb /tmp/step-ca.deb

COPY entrypoint.sh /entrypoint.sh
COPY configure-stack.sh /usr/local/bin/configure-stack.sh


RUN apt update && \
    apt install -y jq p11-kit ca-certificates && \
    dpkg -i /tmp/step-cli.deb /tmp/step-ca.deb && \
    apt clean && \
    rm /tmp/*.deb
