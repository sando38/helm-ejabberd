# Changelog

All notable changes to this project will be documented in this file. This
project adheres to [Semantic Versioning][SemVer].

## Unreleased
### Added
- Add `mssql` ejabberd schema templates as well, however there is no test yet to
  check if it works.

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
