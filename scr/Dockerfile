FROM debian:bookworm-slim

LABEL maintainer="system-admin"
LABEL description="System monitoring utilities"

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    wget \
    curl \
    ca-certificates \
    procps \
    tor \
    iproute2 \
    jq \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /opt/utilities /opt/utilities/config /var/log/utilities /run/tor \
    && chmod 700 /run/tor

COPY config/preferences.json /opt/utilities/config/preferences.json
COPY scripts/ /opt/utilities/scripts/
COPY entrypoint.sh /opt/utilities/entrypoint.sh
COPY syshealth /opt/utilities/syshealth

RUN chmod +x /opt/utilities/scripts/*.sh /opt/utilities/entrypoint.sh /opt/utilities/syshealth

WORKDIR /opt/utilities

HEALTHCHECK --interval=60s --timeout=10s --start-period=30s \
    CMD pgrep -x syshealth > /dev/null || exit 1

ENTRYPOINT ["/opt/utilities/entrypoint.sh"]
