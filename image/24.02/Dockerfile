#' Define default build variables
## source ARGs
ARG ALPINE_VSN='3.19.1'
ARG DISTROLESS_VSN='base-nossl-debian12'
ARG GO_VSN='1.22'
## general ARGs
ARG UID='9000'
ARG USER='ejabberd'
ARG HOME="opt/$USER"
ARG TINI_VERSION="0.19.0"

################################################################################
#' build elector
FROM docker.io/golang:${GO_VSN}-alpine AS elector
RUN apk -U add --no-cache \
        build-base \
        git

WORKDIR /elector
RUN git clone https://github.com/sando38/k8s-elector \
        --branch update-packages --depth 1 .

RUN make build-linux

################################################################################
#' Build and prepare ejabberd
FROM docker.io/hexpm/elixir:1.16.1-erlang-26.2.1-debian-bookworm-20231009-slim AS build
RUN apt-get update && apt-get upgrade -y && apt-get install -y \
        automake \
        build-essential \
        ca-certificates \
        dirmngr \
        git \
        gpg \
        libexpat-dev \
        libgd-dev \
        libodbc2 \
        libpam0g-dev \
        libssl-dev \
        libsqlite3-dev \
        libwebp-dev \
        libyaml-dev \
        pax-utils \
        wget \
        zlib1g-dev

RUN mix local.hex --force \
    && mix local.rebar --force

COPY / /ejabberd
WORKDIR /ejabberd
ARG USER
RUN mv .github/container/ejabberdctl.template . \
    && ./autogen.sh \
    && ./configure --with-rebar=mix --enable-all \
    && make deps \
    && make rel

# prepare ejabberd
WORKDIR /rootfs
ARG VERSION
ARG HOME
ARG UID
RUN mkdir -p $HOME/cacert $HOME-$VERSION \
    && cp -r /ejabberd/_build/prod/rel/ejabberd/* $HOME-$VERSION \
    && mv $HOME-$VERSION/conf $HOME/conf \
    && wget -O "$HOME/cacert/cacert.pem" 'https://curl.se/ca/cacert.pem' \
    && chown -R $UID:$UID $HOME


# Copy libraries
WORKDIR /
RUN libs="$(scanelf --needed --nobanner --format '%n#p' --recursive "/rootfs" \
        | tr ',' '\n' \
        | sort -u)" \
    && mkdir -p /rootfs/usr/lib/"$(gcc --print-multiarch)" \
    && for lib in $libs; do ln -vL $(find /usr -name $lib) /rootfs"$(find /usr -name $lib)"; done \
    && ln -vL $(find /usr -name libaudit.so.1) /rootfs"$(find /usr -name libaudit.so.1)" \
    && ln -vL $(find /usr -name libcap-ng.so.0) /rootfs"$(find /usr -name libcap-ng.so.0)"

################################################################################
#' Get AlpineÄs busybox for ejabberdctl script
FROM docker.io/library/alpine:${ALPINE_VSN} AS busybox
RUN apk add busybox-static --no-cache \
    && mkdir -p /rootfs/bin \
    && ln -v /bin/busybox.static /rootfs/bin/busybox \
    && chroot rootfs /bin/busybox --install /bin

# install runtime init for zombie reaping
ARG TINI_VERSION
RUN ARCH=$(uname -m | sed -e 's/x86_64/amd64/;s/aarch64/arm64/') \
    && apk add curl --no-cache \
    && curl -fL -o /rootfs/tini https://github.com/krallin/tini/releases/download/v$TINI_VERSION/tini-$ARCH \
    && chmod +x /rootfs/tini

# Create ejabberdctl script for smoke test
RUN mkdir -p /rootfs/usr/local/bin \
    && echo -e \
        "#!/bin/sh \
        \n[ -z \$ERLANG_NODE_ARG ] && export ERLANG_NODE_ARG=ejabberd@localhost \
        \nexport CONFIG_DIR=\$HOME/conf \
        \nexport LOGS_DIR=\$HOME/logs \
        \nexport SPOOL_DIR=\$HOME/database \
        \nexec \$(find /opt -name ejabberdctl) \"\$@\"" \
            > /rootfs/usr/local/bin/ejabberdctl \
    && chmod +x /rootfs/usr/local/bin/ejabberdctl

################################################################################
#' Forge release image
FROM gcr.io/distroless/${DISTROLESS_VSN} AS release

ARG USER
ARG UID
ARG HOME
ENV ERL_DIST_PORT='5210' \
    LC_ALL='C.UTF-8' \
    LANG='C.UTF-8'

COPY --from=busybox /rootfs /
COPY --from=build /rootfs /
COPY --from=build /usr/lib/locale/C.utf8 /usr/lib/locale/C.utf8
COPY --from=elector /elector/elector /usr/local/bin/elector
COPY --from=ghcr.io/jqlang/jq:1.7 /jq /usr/local/bin/jq

RUN echo "$USER:x:$UID:$USER" >> /etc/group \
 && echo "$USER:x:$UID:$UID:$USER,,,:/$HOME:/sbin/nologin" >> /etc/passwd

WORKDIR /$HOME
USER $USER
VOLUME ["/$HOME"]
EXPOSE 5222 5223 5280

ENTRYPOINT ["/tini","--"]
CMD ["ejabberdctl", "foreground"]
