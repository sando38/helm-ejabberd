# helm chart for ejabberd

This repository holds a helm chart for [ejabberd](https://github.com/processone/ejabberd)
which
> is an open-source, robust, scalable and extensible realtime platform built
> using Erlang/OTP, that includes XMPP Server, MQTT Broker and SIP Service.

The chart configures the environment needed to build and run ejabberd clusters.
Additionally, the `values.yaml` file allows to include most of the configuration
items, ejabberd offers in their [`ejabberd.yml`](https://github.com/processone/ejabberd/blob/master/ejabberd.yml.example).

## Current state

The chart is under development, meaning there is much room for enhancements and
improvements. The [issue tracker](https://github.com/sando38/helm-ejabberd/issues)
may be used to additionally define a roadmap.

The chart is basically functional and needs testing. Please report back if
anything does not work as expected.

Contributors and PRs are also welcome.

## Base image

The chart uses a custom ejabberd image, which is based on the [official](https://github.com/processone/ejabberd/blob/master/CONTAINER.md)
ejabberd container image. Currently only built for `x86_64` due to an issue in
QEMU - now resolved, however. So there will be soon an `arm64` variant as well.

The image name is: `ghcr.io/sando38/ejabberd:23.xx-k8s1`

### Difference to the official ejabberd container image

This repository contains the patches applied to the official ejabberd [releases](https://github.com/processone/ejabberd/releases)
in the [image](image) directory.

A short summary:

* Includes a custom script to automatically detect and join a cluster
* Slighlty modified `ejabberdctl` to use correct naming conventions for
  ejabberd clusters
* Stipped/ hardened image by deleting all unneccessary packages from the image,
  e.g. package managers, etc.
* Includes additional libraries for ejabberd contribution modules
  `ejabberd_auth_http`, `mod_captcha_rust` and `mod_ecaptcha`
* The three mentioned modules plus `mod_s3_upload` are installed in the image
  already.
* No ACME support, mounting your certs as k8s secrets is necessary
* No support for CAPTCHA scripts, due to the nature of the stripped image

### Image tags

The patches are defined per release, hence a container image tag always bears
the ejabberd release, e.g.: `23.xx`.

Furthermore, a suffix `-k8s1` is used in case the image needs an update. The
first release image has a suffix `-k8s1`.

## Merging the chart upstream

Yes, that is considered and actually also desired.
