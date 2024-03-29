#' Define default build variables
## specifc ARGs for METHOD='direct'
ARG OTP_VSN='25.3'
ARG ELIXIR_VSN='1.14.4'
## specifc ARGs for METHOD='package'
ARG ALPINE_VSN='3.17'
## specifc ARGs for elector
ARG GO_VSN='1.22'
## general ARGs
ARG VARIANT='hardened'
ARG UID='9000'
ARG USER='ejabberd'
ARG HOME="opt/$USER"
ARG METHOD='direct'
ARG BUILD_DIR="/$USER"
ARG VERSION='master'

################################################################################
#' METHOD='direct' - build and install ejabberd directly from source
FROM docker.io/golang:${GO_VSN}-alpine AS elector
RUN apk -U add --no-cache \
        build-base \
        git

WORKDIR /elector
RUN git clone https://github.com/sando38/k8s-elector \
        --branch update-packages --depth 1 .

RUN make build-linux

################################################################################
#' METHOD='direct' - build and install ejabberd directly from source
FROM docker.io/erlang:${OTP_VSN}-alpine AS direct

RUN apk -U add --no-cache \
        autoconf \
        automake \
        bash \
        build-base \
        curl \
        expat-dev \
        file \
        gd-dev \
        git \
        jpeg-dev \
        libpng-dev \
        libwebp-dev \
        linux-pam-dev \
        openssl-dev \
        sqlite-dev \
        yaml-dev \
        zlib-dev

ARG ELIXIR_VSN
RUN wget -O - https://github.com/elixir-lang/elixir/archive/v$ELIXIR_VSN.tar.gz \
        | tar -xzf -

WORKDIR elixir-$ELIXIR_VSN
RUN make install clean

RUN mix local.hex --force \
    && mix local.rebar --force

ARG BUILD_DIR
COPY / $BUILD_DIR/

WORKDIR $BUILD_DIR/.ejabberd-modules/sources/ejabberd-contrib

# include some ejabberd contribution modules which may be nice for clusters
RUN git clone https://github.com/processone/ejabberd-contrib --depth 1 . \
    && install mod_s3_upload/src/*.erl $BUILD_DIR/src \
    && install mod_s3_upload/include/*.hrl $BUILD_DIR/include \
    && install mod_ecaptcha/src/*.erl $BUILD_DIR/src \
    && install ejabberd_auth_http/src/*.erl $BUILD_DIR/src \
    && rm -rf mod_ecaptcha mod_http_redirect mod_s3_upload

WORKDIR $BUILD_DIR

RUN mv .github/container/ejabberdctl.template . \
    && ./autogen.sh \
    && ./configure --with-rebar=mix --enable-all \
    && make deps \
    && make rel

WORKDIR /rootfs
ARG VERSION
ARG HOME
RUN mkdir -p $HOME $HOME-$VERSION \
    && cp -r $BUILD_DIR/_build/prod/rel/ejabberd/* $HOME-$VERSION \
    && mv $HOME-$VERSION/conf $HOME/conf

RUN cp -p $BUILD_DIR/tools/captcha*.sh $HOME-$VERSION/lib

RUN find "$HOME-$VERSION/bin" -name 'ejabberd' -delete \
    && find "$HOME-$VERSION/releases" -name 'COOKIE' -delete

RUN wget -O "$HOME/conf/cacert.pem" 'https://curl.se/ca/cacert.pem' \
    && sed -i '/^loglevel:/a \ \
        \nca_file: /opt/ejabberd/conf/cacert.pem \
        \ncertfiles: \
        \n  - /opt/ejabberd/conf/server.pem' "$HOME/conf/ejabberd.yml"

################################################################################
#' METHOD='package' - install ejabberd from binary tarball package
FROM docker.io/alpine:${ALPINE_VSN} AS package
COPY tarballs/ejabberd-*-linux-musl-*.tar.gz /tmp/
WORKDIR /rootfs
ARG HOME
RUN home_root_dir=$(echo $HOME | sed 's|\(.*\)/.*|\1 |') \
    && mkdir -p $home_root_dir \
    && ARCH=$(uname -m | sed -e 's/x86_64/x64/;s/aarch64/arm64/') \
    && tar -xzf /tmp/ejabberd-*-linux-musl-$ARCH.tar.gz -C $home_root_dir

################################################################################
#' Prepare ejabberd for runtime
FROM ${METHOD} AS ejabberd
RUN apk -U add --no-cache \
        git \
        libcap \
        openssl

WORKDIR /rootfs
ARG HOME
RUN mkdir -p usr/local/bin $HOME/conf $HOME/database $HOME/logs $HOME/upload

ARG BUILD_DIR
RUN if [ ! -d $HOME/.ejabberd-modules ]; \
    then \
        if [ -d $BUILD_DIR/.ejabberd-modules ]; \
        then cp -r $BUILD_DIR/.ejabberd-modules $HOME; \
        else git clone https://github.com/processone/ejabberd-contrib --depth 1 \
                $HOME/.ejabberd-modules/sources/ejabberd-contrib; \
        fi \
    fi

RUN export PEM=$HOME/conf/server.pem \
    && openssl req -x509 \
            -batch \
            -nodes \
            -newkey rsa:4096 \
            -keyout $PEM \
            -out $PEM \
            -days 3650 \
            -subj "/CN=localhost"

RUN home_root_dir=$(echo $HOME | sed 's|\(.*\)/.*|\1 |') \
    && echo -e \
        "#!/bin/sh \
        \n[ -z \$ERLANG_NODE_ARG ] && export ERLANG_NODE_ARG=ejabberd@localhost \
        \nexport CONFIG_DIR=/$HOME/conf \
        \nexport LOGS_DIR=/$HOME/logs \
        \nexport SPOOL_DIR=/$HOME/database \
        \nexec /$(find $home_root_dir -name ejabberdctl) \"\$@\"" \
            > usr/local/bin/ejabberdctl \
    && chmod +x usr/local/bin/* \
    && scanelf --needed --nobanner --format '%n#p' --recursive $home_root_dir \
        | tr ',' '\n' \
        | sort -u \
        | awk 'system("[ -e $home_root_dir" $1 " ]") == 0 { next } { print "so:" $1 }' \
        | sed -e "s|so:libc.so|so:libc.musl-$(uname -m).so.1|" \
            > /tmp/runDeps

ARG UID
RUN chown -R $UID:$UID $HOME

################################################################################
#' METHOD='direct' - Remove erlang/OTP & rebar3
FROM docker.io/erlang:${OTP_VSN}-alpine AS runtime-direct
RUN apk del .erlang-rundeps \
    && rm -f $(which rebar3) \
    && find /usr -type d -name 'erlang' -exec rm -rf {} + \
    && find /usr -type l -exec test ! -e {} \; -delete

################################################################################
#' METHOD='package' - define runtime base image
FROM docker.io/alpine:${ALPINE_VSN} AS runtime-package

################################################################################
#' Update alpine, finalize runtime environment
FROM runtime-${METHOD} AS runtime
COPY --from=ejabberd /tmp/runDeps /tmp/runDeps
RUN apk -U upgrade --available --no-cache \
    && apk add --no-cache \
        $(cat /tmp/runDeps) \
        gettext \
        jq \
        so:libcap.so.2 \
        so:libtdsodbc.so.0 \
        tini \
    && ln -fs /usr/lib/libtdsodbc.so.0 /usr/lib/libtdsodbc.so

ARG USER
ARG UID
ARG HOME
RUN addgroup $USER -g $UID \
    && adduser -s /sbin/nologin -D -u $UID -h /$HOME -G $USER $USER

################################################################################
#' Build together production image
FROM scratch AS prod

COPY --from=runtime / /
COPY --from=ejabberd /rootfs /
COPY --from=elector /elector/elector /usr/local/bin/elector

################################################################################
#' Remove unneccessary packages from runtime environment
FROM runtime AS runtime-hardened
# we need busybox' 'ash', which became a sub-package in alpine 3.17
RUN check=$(printf "$(cat /etc/alpine-release)\n3.17" | sort -V | head -n1) \
    && if [ "$check" = '3.17' ]; then sub='-binsh'; fi \
    && apk add --no-cache \
        busybox${sub} \
        ca-certificates
RUN apk del --repositories-file /dev/null \
        alpine-baselayout \
        alpine-keys \
        apk-tools \
        libc-utils \
    && rm -rf /var/cache/apk /etc/apk /tmp \
    && find /lib/apk/db -type f -not -name 'installed' -delete

################################################################################
#' Build together hardened production image
FROM scratch AS hardened

COPY --from=runtime-hardened / /
COPY --from=ejabberd /rootfs /
COPY --from=elector /elector/elector /usr/local/bin/elector

################################################################################
#' Build together production image
FROM ${VARIANT} AS final
ARG USER
ARG HOME

HEALTHCHECK \
    --interval=1m \
    --timeout=5s \
    --start-period=5s \
    --retries=10 \
    CMD ejabberdctl status

WORKDIR /$HOME
USER $USER
VOLUME ["/$HOME"]
EXPOSE 1883 4369-4399 5210 5222 5269 5280 5443

ENTRYPOINT ["/sbin/tini","--","ejabberdctl"]
CMD ["foreground"]
