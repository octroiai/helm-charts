# Changelog — octroi-dispatcher

## Unreleased

First release under this name.

- Every variable the chart sets is `OCTROI_*` (`OCTROI_DISPATCHER_CORE_URL`,
  `OCTROI_DISPATCHER_ENROLMENT_TOKEN`, `OCTROI_SCOPE_*`, `OCTROI_TAGS`,
  `OCTROI_MAX_AUTO_APPROVED_RISK`, `OCTROI_LIMITS_*`, `OCTROI_DISPATCHER_DATA_DIR`). The
  dispatcher image of the same release reads them; it still reads the previous names for this
  release only, with a startup warning, and their support is removed in the release after next.
  Rename any you set through `extraEnv`, `extraEnvFrom` or `existingSecret` (its key is
  `OCTROI_DISPATCHER_ENROLMENT_TOKEN`).
- The job environment file is mounted at `/etc/octroi/job.env`.
- Published publicly at `oci://ghcr.io/octroiai/charts/octroi-dispatcher` (cosign-signed); the
  image defaults to the public `ghcr.io/octroiai/dispatcher`.
- Labels come from `octroi-common`: brick label `octroi.ai/brick: dispatcher`.
- **Upgrading from the previously named chart:** `app.kubernetes.io/name` changes and a
  `Deployment`'s `spec.selector` is immutable. Install this chart as a new release (its objects
  get new names) and uninstall the old one; an existing `fullnameOverride` that keeps an old
  object name makes an in-place upgrade fail. A persisted enrolment (`persistence.enabled`)
  lives in the old release's volume: enrol the new release with a fresh `djn_` token.
