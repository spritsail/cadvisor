ARG CADVISOR_VER=v0.46.0
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

ENV GOROOT /usr/lib/go
ENV GOPATH /go
ENV GO_FLAGS="-tags=libpfm,netgo"

ARG GIT_REPO
ARG GIT_BRANCH

WORKDIR /go/src/github.com/google/cadvisor
RUN git clone $GIT_REPO -b $GIT_BRANCH . && \
    ./build/build.sh

# ~~~~~~~~~~~~~~~~~~~~~~~~~

FROM spritsail/alpine:3.17

ARG CADVISOR_VER

LABEL maintainer="Spritsail <cadvisor@spritsail.io>" \
      org.label-schema.vendor="Spritsail" \
      org.label-schema.name="cAdvisor" \
      org.label-schema.url="https://github.com/google/cadvisor" \
      org.label-schema.description="https://github.com/frebib/cadvisor" \
      org.label-schema.vcs-url="https://github.com/spritsail/cadvisor" \
      org.label-schema.version=${CADVISOR_VER}

RUN apk --no-cache add curl libc6-compat device-mapper thin-provisioning-tools findutils zfs ndctl && \
    echo 'hosts: files mdns4_minimal [NOTFOUND=return] dns mdns4' >> /etc/nsswitch.conf

# Grab cadvisor and libpfm4 from "build" container.
COPY --from=build /usr/local/lib/libpfm.so* /usr/local/lib/
COPY --from=build /go/src/github.com/google/cadvisor/_output/cadvisor /usr/bin/cadvisor

EXPOSE 8080

ENV CADVISOR_HEALTHCHECK_URL=http://localhost:8080/healthz

HEALTHCHECK --interval=30s --timeout=3s \
  CMD wget --quiet --tries=1 --spider $CADVISOR_HEALTHCHECK_URL || exit 1

ENTRYPOINT ["/usr/bin/cadvisor", "-logtostderr"]
