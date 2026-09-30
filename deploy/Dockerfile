FROM ubuntu:22.04
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates libssl3 \
    && rm -rf /var/lib/apt/lists/*
COPY configmirror /usr/local/bin/kubemoon-configmirror
USER 65532:65532
ENTRYPOINT ["/usr/local/bin/kubemoon-configmirror"]
