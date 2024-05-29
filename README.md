# helm chart for ejabberd

This repository holds a helm chart for [ejabberd](https://github.com/processone/ejabberd)
which
> [...] is an open-source, robust, scalable and extensible realtime platform
> built using Erlang/OTP, that includes XMPP Server, MQTT Broker and SIP Service.

The chart configures the environment needed to build and run ejabberd kubernetes
clusters. Additionally, the `values.yaml` file allows to include most of the
configuration items, ejabberd offers in their [`ejabberd.yml`](https://github.com/processone/ejabberd/blob/master/ejabberd.yml.example).

The chart and its items can be found [here](charts/ejabberd).

## Current state

The chart is under development, meaning there is room for enhancements and
improvements. The [issue tracker](https://github.com/sando38/helm-ejabberd/issues)
may be used to define roadmap items.

The chart is functional and needs testing. Please report back if anything does
not work as expected.

This repository also contains a CI which tests basic activities, e.g. scaling,
XMPP connectivity and traffic with [processone's rtb](https://github.com/processone/rtb)
as well as pod failures, kills, etc. with [chaos mesh](https://chaos-mesh.org/).

Contributors and PRs are also welcome.

## Base image

The chart uses a custom ejabberd image, which is based on the [official](https://github.com/processone/ejabberd/blob/master/CONTAINER.md)
ejabberd container image. Currently only built for `x86_64` due to an issue in
QEMU - now resolved, however. So there will be soon an `arm64` variant as well.

The image name is: `ghcr.io/sando38/ejabberd:23.10-k8s1`

### Difference to the official ejabberd container image

This repository contains the patches applied to the official ejabberd [releases](https://github.com/processone/ejabberd/releases)
in the [image](image) directory and the respective [workflow file](.github/workflows/ctr.yaml).

A short summary:

* Redesigned image based on [Wolfi-OS](https://github.com/wolfi-dev/os) to
  significantly improve the performance and resource usage.
* Includes an elector service to create kubernetes `leases` for pod leaders.
* Includes custom scripts to automatically detect and join a cluster as well as
  for performing healthchecks and self-healing.
* Slighlty modified `ejabberdctl` to use correct naming conventions for
  ejabberd clusters in kubernetes.
* Stipped/ hardened image by deleting all unneccessary packages from the image,
  e.g. package managers, etc.
* Includes additional libraries for ejabberd contribution modules
  `ejabberd_auth_http` and `mod_ecaptcha`.
* The three mentioned modules plus `mod_s3_upload` are installed in the image
  already.
* No ACME support, mounting your certs as k8s secrets is necessary.
* No support for CAPTCHA scripts, due to the nature of the stripped image.

### Image tags

The patches are defined per release, hence a container image tag always bears
the ejabberd release, e.g.: `23.10`.

Furthermore, a suffix `-k8s1` is used in case the image needs an update. The
first release image has a suffix `-k8s1`.

### Running this image with docker compose

The image may be used with `docker compose` using the following definitions:

```yml
version: '3'

services:
  ejabberd:
    image: ghcr.io/sando38/ejabberd:23.10-k8s3
    command: >
      sh -c "ejabberdctl foreground"
    environment:
      - ERLANG_NODE_ARG=ejabberd@localhost
```

Note: `command` and `environment` arguments are required to simulate the
official image behhavior.

## Merging the chart upstream

Yes, that is considered and actually also desired ([link to discussion](https://github.com/processone/ejabberd/discussions/4065)).
