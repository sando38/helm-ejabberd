#' Define default build variables
## source ARGs
ARG GO_VSN='1.22'
ARG ERLANG_VSN='26.2.5'
ARG ELIXIR_VSN='1.16.3'
## general ARGs
ARG UID='9000'
ARG USER='ejabberd'
ARG HOME="opt/$USER"
ARG BUILD_DIR="/$USER"
ARG VERSION='master'

################################################################################
#' build elector
FROM cgr.dev/chainguard/wolfi-base AS elector
ARG GO_VSN
RUN apk -U upgrade --available && apk add --no-cache \
        build-base \
        git \
        go-$GO_VSN

WORKDIR /elector
RUN git clone https://github.com/sando38/k8s-elector \
        --branch update-packages --depth 1 .

RUN go get google.golang.org/protobuf@v1.33.0 \
    && go get golang.org/x/net@v0.23.0 \
    && go mod tidy

RUN make build-linux

################################################################################
#' Build and base image
FROM cgr.dev/chainguard/wolfi-base AS erlang
ARG ERLANG_VSN
ENV LC_ALL='C.UTF-8' \
    LANG='C.UTF-8'

RUN apk -U upgrade --available && apk add --no-cache  \
        autoconf \
        automake \
        bash \
        build-base \
        ca-certificates-bundle \
        curl \
        expat-dev \
        file \
        freetds freetds-dev \
        freetype-dev \
        gd-dev \
        git \
        libjpeg-dev \
        libpng-dev \
        libwebp-dev \
        linux-pam-dev \
        ncurses-dev \
        pax-utils \
        perl-dev \
        openssl \
        openssl-dev \
        sqlite-dev \
        unixodbc unixodbc-dev \
        wget \
        yaml-dev \
        zlib-dev

ARG ERLANG_VSN
RUN wget -O - https://github.com/erlang/otp/releases/download/OTP-"$ERLANG_VSN"/otp_src_"$ERLANG_VSN".tar.gz \
        | tar -xzf -

WORKDIR /otp_src_"$ERLANG_VSN"
## https://github.com/processone/ejabberd/commit/b288d5c76370e44fef3a9caa6fbb888435057a2a
RUN sed -i 's|if(size == 0 && (sql_type == SQL_LONGVARCHAR|if((sql_type == SQL_LONGVARCHAR|g' lib/odbc/c_src/odbcserver.c
RUN ./configure \
        --prefix=/usr \
        --sysconfdir=/etc \
        --mandir=/usr/share/man \
        --infodir=/usr/share/info \
        --host="$CHOST" \
        --build="$CBUILD" \
        --enable-threads \
        --enable-shared-zlib \
        --enable-ssl=dynamic-ssl-lib \
        --enable-jit \
    && make install

WORKDIR /
ARG ELIXIR_VSN
RUN wget -O - https://github.com/elixir-lang/elixir/archive/v"$ELIXIR_VSN".tar.gz \
        | tar -xzf -

WORKDIR /elixir-"$ELIXIR_VSN"
RUN make install clean

RUN mix local.hex --force \
    && mix local.rebar --force

################################################################################
#' Build and prepare ejabberd
FROM erlang AS build
ENV LC_ALL='C.UTF-8' \
    LANG='C.UTF-8'

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

## openssl does not find /etc/ssl/openssl.cnf in workflow, check later
# RUN wget -O "$HOME/conf/cacert.pem" 'https://curl.se/ca/cacert.pem' \
#     && sed -i '/^loglevel:/a \ \
#         \nca_file: /opt/ejabberd/conf/cacert.pem \
#         \ncertfiles: \
#         \n  - /opt/ejabberd/conf/server.pem' "$HOME/conf/ejabberd.yml"
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

## openssl does not find /etc/ssl/openssl.cnf in workflow, check later
# RUN export PEM=$HOME/conf/server.pem \
#     && openssl req -x509 \
#             -batch \
#             -nodes \
#             -newkey rsa:4096 \
#             -keyout $PEM \
#             -out $PEM \
#             -days 3650 \
#             -subj "/CN=localhost"

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
    && scanelf --needed --nobanner --format '%n#p' --recursive "$PWD" \
        | tr ',' '\n' \
        | sort -u \
        | awk 'system("[ -e $PWD" $1 " ]") == 0 { next } { print "so:" $1 }' \
            > /tmp/runDeps

ARG UID
RUN chown -R $UID:$UID $HOME

################################################################################
#' Get AlpineÄs busybox for ejabberdctl script
FROM cgr.dev/chainguard/wolfi-base AS runtime
RUN apk -U upgrade --available --no-cache

ARG USER
ARG UID
ARG HOME
RUN addgroup $USER -g $UID \
    && adduser -s /sbin/nologin -D -u $UID -h /$HOME -G $USER $USER

COPY --from=build /tmp/runDeps /tmp/runDeps
RUN apk add --no-cache -t .ejabberd-rundeps \
        $(cat /tmp/runDeps) \
        freetds unixodbc \
        bind-tools \
        busybox \
        ca-certificates-bundle \
        gettext \
        jq \
        netcat-openbsd \
        tini \
        wget

RUN apk del --repositories-file /dev/null \
        wolfi-base \
        wolfi-keys \
        apk-tools \
    && rm -rf /var/cache/apk /etc/apk /tmp/* \
    && find /lib/apk/db -type f -not -name 'installed' -delete

################################################################################
#' Forge release image
FROM scratch AS release
ARG USER
ARG HOME
ENV ERL_DIST_PORT='5210' \
    LC_ALL='C.UTF-8' \
    LANG='C.UTF-8'

COPY --from=runtime / /
COPY --from=build /rootfs /
COPY --from=elector /elector/elector /usr/local/bin/elector

HEALTHCHECK \
    --interval=1m \
    --timeout=5s \
    --start-period=5s \
    --retries=10 \
    CMD ejabberdctl status

WORKDIR /$HOME
USER $USER
VOLUME ["/$HOME"]
EXPOSE 5210 5222 5223 5280

ENTRYPOINT ["/sbin/tini","--","ejabberdctl"]
CMD ["foreground"]
