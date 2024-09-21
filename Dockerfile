ARG CADVISOR_VER=v0.49.1
ARG GIT_REPO=https://github.com/frebib/cadvisor.git
ARG GIT_BRANCH=feat/tls

FROM alpine:edge AS build

RUN apk --no-cache add \
        bash \
        build-base \
        cmake \
        device-mapper \
        findutils \
        git \
        go \
        libc6-compat \
        linux-headers \
        ndctl-dev \
        pkgconfig \
        python3 \
        thin-provisioning-tools \
        wget \
        zfs \
        && \
    echo 'hosts: files mdns4_minimal [NOTFOUND=return] dns mdns4' >> /etc/nsswitch.conf

RUN wget https://sourceforge.net/projects/perfmon2/files/libpfm4/libpfm-4.11.0.tar.gz && \
  echo "112bced9a67d565ff0ce6c2bb90452516d1183e5  libpfm-4.11.0.tar.gz" | sha1sum -c  && \
  tar -xzf libpfm-4.11.0.tar.gz && \
  rm libpfm-4.11.0.tar.gz

RUN export DBG="-g -Wall" && \
  make -e -C libpfm-4.11.0 && \
  make install -C libpfm-4.11.0

ENV GO_FLAGS="-tags=libpfm,netgo -trimpath"

ARG GIT_REPO
ARG GIT_BRANCH

WORKDIR /tmp/cadvisor
RUN git clone $GIT_REPO -b $GIT_BRANCH . && \
    ./build/build.sh

# ~~~~~~~~~~~~~~~~~~~~~~~~~

FROM spritsail/alpine:3.20

ARG CADVISOR_VER

LABEL org.opencontainers.image.authors="Spritsail <cadvisor@spritsail.io>" \
      org.opencontainers.image.title="cAdvisor" \
      org.opencontainers.image.url="https://github.com/google/cadvisor" \
      org.opencontainers.image.description="https://github.com/frebib/cadvisor" \
      org.opencontainers.image.source="https://github.com/spritsail/cadvisor" \
      org.opencontainers.image.version=${CADVISOR_VER}

RUN apk --no-cache add curl libc6-compat device-mapper thin-provisioning-tools findutils zfs ndctl && \
    echo 'hosts: files mdns4_minimal [NOTFOUND=return] dns mdns4' >> /etc/nsswitch.conf

# Grab cadvisor and libpfm4 from "build" container.
COPY --from=build /usr/local/lib/libpfm.so* /usr/local/lib/
COPY --from=build /tmp/cadvisor/_output/cadvisor /usr/bin/cadvisor

EXPOSE 8080

ENV CADVISOR_HEALTHCHECK_URL=http://localhost:8080/healthz

HEALTHCHECK --interval=30s --timeout=3s \
  CMD \
    set -ex && \
    if [ -n "$CADVISOR_HEALTHCHECK_CERT" ]; then \
        exec test "$(curl -fsS -o /dev/null --cert "$CADVISOR_HEALTHCHECK_CERT" --key "$CADVISOR_HEALTHCHECK_KEY" --cacert "$CADVISOR_HEALTHCHECK_CA" "$CADVISOR_HEALTHCHECK_URL" -w '%{http_code}')" = 200; \
    else \
        exec test "$(curl -fsS -o /dev/null "$CADVISOR_HEALTHCHECK_URL" -w '%{http_code}')" = 200; \
    fi

ENTRYPOINT ["/usr/bin/cadvisor", "-logtostderr"]
