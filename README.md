# octroi.ai Helm charts

Helm charts for running parts of [octroi.ai](https://octroi.ai) on your own infrastructure.

> **Read-only.** This repository is a copy written by our release pipeline, one commit per
> release. Pull requests and issues are not processed here; contact
> [hello@octroi.ai](mailto:hello@octroi.ai).

## Charts

| Chart | What it is |
|---|---|
| [`octroi-dispatcher`](charts/octroi-dispatcher) | The dispatcher: runs the jobs your organization approved, inside your network, with the credentials you give it. Outbound HTTPS only — no inbound API, no Service, no Ingress. |
| [`octroi-common`](charts/octroi-common) | Library chart (shared templates) bundled inside `octroi-dispatcher`; not installed on its own. |

## Install

Charts and images are public — no registry login, no pull secret:

```console
helm install octroi-dispatcher oci://ghcr.io/octroiai/charts/octroi-dispatcher \
  --version <version> \
  --set config.coreUrl=<your octroi.ai API URL> \
  --set secrets.enrolmentToken=djn_...
```

The enrolment token is created in octroi.ai (Dispatchers → Add a dispatcher). See
[`charts/octroi-dispatcher/README.md`](charts/octroi-dispatcher/README.md) for scope, tags,
limits and job credentials.

The image is `ghcr.io/octroiai/dispatcher`, at the chart's `appVersion` by default.

## Verify

Releases are signed with [cosign](https://docs.sigstore.dev/cosign/). With `cosign.pub` from this
repository:

```console
cosign verify --key cosign.pub ghcr.io/octroiai/charts/octroi-dispatcher:<version>
```
