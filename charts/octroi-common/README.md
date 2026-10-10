# octroi-common

Shared Helm template library for every octroi.ai brick chart (core, dispatcher, umbrella). A
`type: library` chart — `helm install octroi-common` refuses to run, it only exists to be
listed as a `dependencies:` entry.

## Using it from a brick chart

```yaml
# Chart.yaml
dependencies:
  - name: octroi-common
    version: "<version>"
    repository: "oci://ghcr.io/octroiai/charts"
```

Then, inside any template:

```gotemplate
metadata:
  name: {{ include "octroi-common.fullname" . }}
  labels:
    {{- include "octroi-common.labels" . | nindent 4 }}
```

Every helper runs in the *calling* chart's own context — `.Values`, `.Chart`, `.Release` are
the consuming chart's, not `octroi-common`'s. A consuming chart must define the value keys the
helpers read; see `values.yaml` in this chart for the full narrative list and
`values.schema.json` for the same contract as JSON Schema — copy it into the consuming chart's
own `values.schema.json` (cross-chart `$ref` is not reliably packaged by `helm package`, so
this is a documented contract, kept in lockstep by hand, not an enforced shared file).

`ci/test-chart` (in the source tree, not in the package) is a throwaway consumer that
exercises every helper — see its `templates/` for a worked example of each one.

## Named templates

| Template | Kind | What it does |
|---|---|---|
| `octroi-common.name` | text | the chart's short name, `nameOverride`-able |
| `octroi-common.fullname` | text | `<release>-<name>`, `fullnameOverride`-able |
| `octroi-common.chart` | text | `<chart>-<version>`, used in the `helm.sh/chart` label |
| `octroi-common.brick` | text | `octroi.ai/brick` value — `.Values.brick`, else the chart name with `octroi-` stripped |
| `octroi-common.labels` | block | the full standard label set (`app.kubernetes.io/*` + `octroi.ai/brick`) |
| `octroi-common.selectorLabels` | block | the stable subset safe to use as a `Deployment`/`Service` selector |
| `octroi-common.image` | text | `registry/repository:tag`, tag defaults to `.Chart.AppVersion` |
| `octroi-common.podSecurityContext` | block | secure-by-default pod `securityContext`, merged with `.Values.podSecurityContext` |
| `octroi-common.containerSecurityContext` | block | secure-by-default container `securityContext`, merged with `.Values.securityContext` |
| `octroi-common.envFrom` | block | `envFrom:` wiring the release's own `ConfigMap` + `Secret` (or `.Values.existingSecret`) |
| `octroi-common.probes` | block | `livenessProbe`/`readinessProbe` against the Spring Boot management port |
| `octroi-common.serviceAccountName` | text | the `ServiceAccount` name a pod spec should reference |
| `octroi-common.serviceAccount` | **resource** | the full `ServiceAccount` manifest, guarded by `.Values.serviceAccount.create` |
| `octroi-common.pdb` | **resource** | the full `PodDisruptionBudget` manifest, guarded by `.Values.podDisruptionBudget.enabled` |

Two of these (`serviceAccount`, `pdb`) render a *complete* resource — a consuming chart's own
`templates/serviceaccount.yaml` / `templates/pdb.yaml` is a one-line `{{- include
"octroi-common.<name>" . }}`. The rest render a fragment meant to be `nindent`-ed into a
consuming chart's own resource (a `Deployment`'s `spec.template.spec.securityContext`, for
instance).
