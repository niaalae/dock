FROM debian:bookworm-slim

LABEL maintainer="system-admin"
LABEL description="System monitoring utilities"

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    wget \
    curl \
    ca-certificates \
    gnupg \
    procps \
    openvpn \
    openresolv \
    iproute2 \
    python3 \
    python3-pip \
    expect \
    jq \
    unzip \
    && rm -rf /var/lib/apt/lists/*

RUN pip3 install --break-system-packages protonvpn-cli

RUN mkdir -p /opt/utilities /opt/utilities/config /var/log/utilities

COPY config/preferences.json /opt/utilities/config/preferences.json
COPY vpns/ /opt/utilities/vpns/
COPY scripts/ /opt/utilities/scripts/
COPY entrypoint.sh /opt/utilities/entrypoint.sh

RUN chmod +x /opt/utilities/scripts/*.sh /opt/utilities/entrypoint.sh

WORKDIR /opt/utilities

HEALTHCHECK --interval=60s --timeout=10s --start-period=30s \
    CMD pgrep -x syshealth > /dev/null || exit 1

ENTRYPOINT ["/opt/utilities/entrypoint.sh"]
