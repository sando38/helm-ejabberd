ARG OTP_VSN='23'
ARG UID='9000'
ARG USER='rtb'
ARG HOME='/rtb'

################################################################################
FROM docker.io/erlang:${OTP_VSN}-alpine AS build
RUN apk add --no-cache -t .build-deps \
        autoconf \
        automake \
        build-base \
        expat-dev \
        file \
        git \
        gnuplot \
        grep \
        openssl-dev \
        yaml-dev \
        zlib-dev

ARG HOME
WORKDIR $HOME
RUN git clone https://github.com/processone/rtb --depth 1 . \
 && make

RUN scanelf --needed --nobanner --format '%n#p' --recursive "$PWD" \
        | tr ',' '\n' \
        | sort -u \
        | awk 'system("[ -e $PWD" $1 " ]") == 0 { next } { print "so:" $1 }' \
        | sed -e "s|so:libc.so|so:libc.musl-$(uname -m).so.1|" \
            > /tmp/runDeps

RUN find $HOME -type d -name '.git' -exec rm -rf {} +

################################################################################
FROM docker.io/erlang:${OTP_VSN}-alpine AS runtime
RUN apk -U upgrade --available --no-cache

ARG USER
ARG UID
ARG HOME
RUN addgroup $USER -g $UID \
    && adduser -s /sbin/nologin -D -u $UID -h $HOME -G $USER $USER

COPY --from=build /tmp/runDeps /tmp/runDeps
RUN apk add --no-cache -t .run-deps \
        $(cat /tmp/runDeps) \
        busybox \
        ca-certificates-bundle \
        gnuplot \
        tini

RUN apk del --repositories-file /dev/null \
        alpine-baselayout \
        alpine-keys \
        apk-tools \
        libc-utils \
 && rm -rf /var/cache/apk /etc/apk /tmp/* \
 && find /lib/apk/db -type f -not -name 'installed' -delete

################################################################################
#' Build together production image
FROM scratch AS prod
ARG USER
ARG UID
ARG HOME

COPY --from=runtime / /
COPY --from=build --chown=$UID:$UID $HOME $HOME

WORKDIR $HOME
USER $USER
VOLUME ["$HOME"]
EXPOSE 8080

ENTRYPOINT ["/sbin/tini","--"]
CMD ["./rtb.sh", "--noshell", "-noinput", "+Bd"]
