ARG POSTGRES_VERSION
FROM postgres:${POSTGRES_VERSION}

RUN apt-get update && apt-get install -y --no-install-recommends awscli \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /scripts
COPY backup.sh .
ENTRYPOINT [ "bash", "backup.sh" ]
