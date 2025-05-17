# Changelog

All notable changes to this project will be documented in this file. This
project adheres to [Semantic Versioning][SemVer].
## Unreleased

## 0.9.1 - 2025-05-17
### Changed
- Bump ejabberd image to `25.04-k8s1` - changelog: [ejabberd 25.04](https://github.com/processone/ejabberd/blob/master/CHANGELOG.md#version-2504).
- Update chart README.md to describe usage of `EJABBERD_MARCO_*`.

## 0.9.0 - 2025-02-15
### Added
- Allow to specify a `Secret` for `Values.erlangCookie`. (potentially breaking) (#15)

### Changed
- Do not use `Cluster` scopes for config and cert-watcher RBAC. (potentially breaking)
- Image renamed to `sando38/helm-ejabberd`
- `sando38/helm-ejabberd` are built for both: `x86_64` and `arm64` (#18)
- Bump ejabberd image to `24.12-k8s1` - changelog: [ejabberd 24.12](https://github.com/processone/ejabberd/blob/master/CHANGELOG.md#version-2412).

### Fixed
- Fix a bug in the configuration template for `Values.ldap` (#21)

### Removed
- `Values.ingress` definitions, they do not make much sense in a TCP context,
  future versions of the helm chart will allow to template Kubernetes Gateway
  API resources. (#22)

## 0.8.3 - 2024-09-29
### Changed
- Bump ejabberd image to `24.07-k8s1` - changelog: [ejabberd 24.07](https://github.com/processone/ejabberd/blob/master/CHANGELOG.md#version-2407).

## 0.8.2 - 2024-09-29
### Changed
- Bump ejabberd image to `24.06-k8s1` - changelog: [ejabberd 24.06](https://github.com/processone/ejabberd/blob/master/CHANGELOG.md#version-2406).
- Switch `Values.sqlDatabase.updateSqlSchema` to `true` (new ejabberd default).
- CI: temporarly deactivate "rtb" component, due to docker ipv6 mode.

## 0.8.1 - 2024-05-28
### Changed
- Bump ejabberd image to `24.02-k8s5` - This updates the container image to be
  based on `glibc`, Erlang OTP `26.2` as well as Elixir `1.16.3`. The image is
  now based on [Wolfi-OS](https://github.com/wolfi-dev/os). The switch will
  significantly improve the performance and reduce resource usage.

## 0.8.0 - 2024-03-16
### Added
- Add `seccompProfile` to sidecar and default `values.yaml`.
- Add option to define sidecar image via `Values.certFiles.sideCar.image`.

### Changed
- Bump ejabberd image to `24.02-k8s2` - changelog: [ejabberd 24.02](https://github.com/processone/ejabberd/blob/master/CHANGELOG.md#version-2402).

### Removed
- Remove `mod_captcha_rust`, because of a compilation error with erlang >26.

## 0.7.1 - 2024-01-19
### Added
- Add support for kubernetes native sidecars added in kubernetes version `1.29`.

## 0.7.0 - 2024-01-18
### Added
- Add option in `values.yaml` to use ejabberd's new `update_sql_schema` function
  starting from version `23.10`.

### Changed
- Refactor health-check mechanism to be more robust e.g. with networking issues.
- Bump ejabberd image to `23.10-k8s3` - update of runtime dependencies.

## 0.6.2 - 2023-11-18
### Changed
- Bump ejabberd image to `23.10-k8s2` - update of runtime dependencies.

## 0.6.1 - 2023-10-17
### Changed
- Bump ejabberd image to `23.10-k8s1` - changelog: [ejabberd 23.10](https://github.com/processone/ejabberd/blob/master/CHANGELOG.md#version-2310).
- healthcheck.sh: output to [entrypoint](https://stackoverflow.com/a/75257695)

## 0.6.0 - 2023-08-30
### Added
- Extend CI to include cluster chaos, e.g. pod kills, failures, etc., processone
  `rtb` to test XMPP connections as well as scaling up and down.
- Use kubernetes leases to elect an ejabberd leading pod for clustering. This
  improves the robustness of the helm chart overall. The elector is enabled at
  default. If disabled, it falls back to the old k8s-DNS-based method.
- Add extra sections in `values.yml` to define `host_config` and
  `append_host_config`.

### Changed
- **BREAKING:**
  Refactor `.Values.modules` to allow enabling/disabling, configuring and adding
  of ejabberd modules.
- Move image run scripts into the chart templates. This enables admins to easier
  exchange the container image.
- Bump ejabberd image to `78f81de252dc932cd47b91d1a84ca8e8f0647498-k8s6`.

### Fixed
- Fix parsing `host` values.

### Removed
- Remove the possibility to change the TCP healthcheck port. Healthchecks are
  now performed with a custom healthcheck script. You still can define custom
  healthchecks within the `values.yml` file.

## 0.5.1 - 2023-08-12
### Added
- Add support for flyway managed `mssql` database types.

### Changed
- Bumb ejabberd image to `78f81de252dc932cd47b91d1a84ca8e8f0647498-k8s5`.

### Fixed
- Fix missing dependency for mssql database driver in container image.

## 0.5.0 - 2023-08-11
### Added
- Add flyway as a SQL database manager. The chart currently supports `mysql` and
  `pgsql` `sql_type`s. The feature is experimental.
- Add a CI workflow to test charts deployment, SQL migrations and basic
  functions.

### Fixed
- Fix an issue with `NodePorts` and the internal ejabberd service.

## 0.4.2 - 2023-08-02
### Fixed
- chart/_pod.tpl: fix `RESOURCE` for sidecar to detect both secret & configmap.

## 0.4.1 - 2023-08-02
### Fixed
- chart/configmap: fix missing label for sidecar detection.

## 0.4.0 - 2023-08-02
### Added
- Also use the sidecar for configmap/ejabberd.yml reloading.
- Sidecar: TLS secrets must have an annotation
  `k8s-sidecar-target-directory: "certs/secretName"`, where `secretName` is the
  name of the corresponding secret, e.g. `secret-examplecom` in
  `.Values.certFiles.secretName`.

### Changed
- Bumb ejabberd image to `78f81de252dc932cd47b91d1a84ca8e8f0647498-k8s4`.
- Sidecar: API request retry reduced to 5 times (sidecar default).
- InitContainer: Improve logging.
- General improvements to documentation in various files.

## 0.3.5 - 2023-08-01
### Added
- Use an initContainer for cert mounting if sidecar is enabled.

### Changed
- Sidecar: API request retry bumped to 10 times.
- Depreciate `WAIT_PERIOD` as it became unnecessary due to the InitContainer.

## 0.3.4 - 2023-07-31
### Changed
- Sidecar: make renew API call more configurable.

### Fixed
- Sidecar: enable mod_http_api for ejabberd_ctl cmds

## 0.3.3 - 2023-07-31
### Changed
- Make apiAddress for sidecar configurable.
- Tie readiness/liveness probes to wait period.

## 0.3.2 - 2023-07-31
### Changed
- Bumb ejabberd image to `78f81de252dc932cd47b91d1a84ca8e8f0647498-k8s3`.
- Add a wait period for ejabberd at startup.
- General improvements to documentation in various files.

## 0.3.1 - 2023-07-31
### Removed
- Remove reloader directory, as it was still packaged.

## 0.3.0 - 2023-07-31
### Added
- Add support for k8s sidecar to reload TLS secrets.

### Changed
- General improvements to documentation in various files.

### Removed
- Remove reloader as dependency.

## 0.2.3 - 2023-07-29
### Changed
- Allow to specify more than one TLS certificate secret.

## 0.2.2 - 2023-07-15
### Changed
- Make readiness and liveness probes configurable

## 0.2.1 - 2023-07-15
### Changed
- Deploy listeners on default.

## 0.2.0 - 2023-07-14
### Changed
- Add quick-start documentation.

### Fixed
- Fix errors with default values.

## 0.1.1 - 2023-07-14
### Added
- Initial (pre-)release of the ejabberd helm chart.

[SemVer]: https://semver.org/spec/v2.0.0.html
