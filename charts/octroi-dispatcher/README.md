# octroi-dispatcher

The octroi.ai dispatcher — the component that runs approved jobs inside your own
infrastructure, and the only one holding the credentials they need. **No inbound API
whatsoever**: this chart renders no `Service` and no `Ingress`, ever; the dispatcher only makes
outbound HTTPS calls to the octroi.ai core.

Installed standalone, in its own cluster / namespace / VPC, next to what its jobs act on.
Bundles nothing: no database, no cache, no object storage subchart.

## Install

```console
helm install octroi-dispatcher oci://ghcr.io/octroiai/charts/octroi-dispatcher \
  --set config.coreUrl=https://core.example.com \
  --set secrets.enrolmentToken=djn_...
```

The chart and the image (`ghcr.io/octroiai/dispatcher`, at the chart's `appVersion` by
default) are public: no pull secret is needed.

### Verify the chart

Releases are signed with cosign. The public key is `cosign.pub` in
[github.com/octroiai/helm-charts](https://github.com/octroiai/helm-charts):

```console
cosign verify --key cosign.pub ghcr.io/octroiai/charts/octroi-dispatcher:<version>
```

`secrets.enrolmentToken` is a single-use `djn_` runner-enrolment token minted by the core
(the admin enrolment flow, `POST /api/dispatcher/v1/enrol`) — on a successful first
enrolment the dispatcher persists the resulting `dsp_` auth token under
`OCTROI_DISPATCHER_DATA_DIR` (`/data`, see `persistence.enabled`) and never needs the
enrolment token again.

## Scope, tags and routing

**One dispatcher per scope.** Production and staging must not share credentials or network: install
one release per scope, and place it where that scope should stop (inside the production VPC for
production, and so on). What a release declares at enrolment:

| Value | Env var | Meaning |
|---|---|---|
| `scope.env` | `OCTROI_SCOPE_ENV` | the environment it serves; empty = any |
| `scope.platforms` | `OCTROI_SCOPE_PLATFORMS` | the platforms of that environment; `["*"]` or empty = all |
| `tags` | `OCTROI_TAGS` | executor kinds (`shell`, `container`, `ansible`) and the capability tags Actions name |
| `maxAutoApprovedRisk` | `OCTROI_MAX_AUTO_APPROVED_RISK` | highest risk run without a human approval: `readonly` (default), `reversible`, `destructive` |

**Job container limits.** Every job container (Docker) or Job Pod (Kubernetes) the dispatcher
starts runs under limits set here, never by the core or the Action. An image not pinned to a
digest (`…@sha256:<64 hex>`) is refused before any pull.

| Value | Env var | Default | Meaning |
|---|---|---|---|
| `limits.cpu` | `OCTROI_LIMITS_CPU` | `1` | CPU (`500m`, `1`, `1.5`) |
| `limits.memory` | `OCTROI_LIMITS_MEMORY` | `512MB` | memory hard limit, no swap |
| `limits.pids` | `OCTROI_LIMITS_PIDS` | `256` | processes — Docker only; a node setting (`podPidsLimit`) in Kubernetes |
| `limits.outputBytes` | `OCTROI_LIMITS_OUTPUT_BYTES` | `1MB` | output forwarded to the core, then truncated with a marker and a warning |
| `limits.scratch` | `OCTROI_LIMITS_SCRATCH` | `64MB` | each writable tmpfs: `/tmp` and the job's output directory |
| `limits.readOnlyRootFs` | `OCTROI_LIMITS_READ_ONLY_ROOT_FS` | `true` | read-only image filesystem |

The enrolment token carries what an admin *authorised* (`POST /api/v1/dispatchers/enrolment-tokens`
with `platforms` / `environments` / `tags`); the release requests a subset. A scope or tag
outside the grant is refused at enrolment — the core is the authority. The core only routes a
job to a dispatcher whose scope covers it, that announces every tag the Action needs,
and — for a job that runs without a human approval — whose ceiling is at least the Action's risk.
The dispatcher re-checks the same (scope, ceiling, protected-environment rule) right after each
claim and fails the job with the reason if they disagree.

```console
helm install dispatcher-prod-payments oci://ghcr.io/octroiai/charts/octroi-dispatcher \
  --set config.coreUrl=https://core.example.com \
  --set secrets.enrolmentToken=djn_... \
  --set scope.env=production --set 'scope.platforms={payments-api}' \
  --set maxAutoApprovedRisk=readonly
```

## Job credentials — the job environment file

octroi.ai knows no infrastructure secret — not a value, not even a name. What a job needs to reach
its targets is this deployment's business: put it in a dotenv file, store the file as the
`job.env` key of a Secret, and point `jobEnv.existingSecret` at it:

```console
cat > job.env <<'ENV'
# one NAME=value per line; quotes optional
SSH_PRIVATE_KEY="-----BEGIN OPENSSH PRIVATE KEY-----…"
PG_PASSWORD='…'
ENV
kubectl create secret generic dispatcher-prod-job-env --from-file=job.env
helm upgrade … --set jobEnv.existingSecret=dispatcher-prod-job-env
```

The file is mounted read-only at `/etc/octroi/job.env` (the dispatcher's default
`OCTROI_JOB_ENV_FILE`) and **every** entry is passed to **every** job container this dispatcher
runs — through a per-job Secret and `envFrom`, never inline in the Pod spec; an Action's own
variable of the same name wins. The values are masked out of the logs sent to the core. The
file is re-read before each run, so updating the Secret rotates a credential without a restart
(allow for the kubelet's sync delay). A malformed line fails the job with its line number; a
still-set `OCTROI_SECRET_*` variable (a retired per-secret scheme) fails startup.

Least privilege is placement: a production credential belongs only in the file of a dispatcher
whose scope and `maxAutoApprovedRisk` fit it — a job cannot be steered away from a credential
its dispatcher holds.

An operator can drain (`POST /api/v1/dispatchers/{id}/drain` — no new claims, the running job
finishes) or revoke (`POST /api/v1/dispatchers/{id}/revoke`) a dispatcher from the core.

## Egress-only NetworkPolicy

`networkPolicy.enabled` (default `true`) renders a `NetworkPolicy` selecting this chart's own
pods for both `Ingress` and `Egress` with **no `ingress:` rules at all** — that denies every
inbound connection by construction, there is nothing to allow in. Egress is DNS (53) + HTTPS
(443) to anywhere, since the core's address is operator-configured and not knowable ahead of
time; `networkPolicy.extraEgress` narrows this further for a destination that *can* be
pinned (e.g. a registry on a fixed CIDR). There is no secret service to allow: job credentials
come from the mounted job environment file (see "Job credentials" above).

## RBAC

`rbac.create` (default `true`) renders a namespaced `Role` + `RoleBinding` — never a
`ClusterRole` — granting exactly what the in-cluster driver (`KubernetesJobExecutor`) needs to
run a job: create/get/list/watch/delete on `batch/v1` Jobs, get/list/watch/delete + the
`pods/log` subresource on Pods, create/get/list/delete on Secrets (the ephemeral per-job
Secret carrying the job environment). Every dispatcher deployed via this chart runs in-cluster by definition —
`KUBERNETES_SERVICE_HOST` is always set for a pod — so this RBAC is always needed, not an
opt-in feature. Set `rbac.targetNamespace` only if
`OCTROI_DISPATCHER_KUBERNETES_NAMESPACE` (in `extraEnv`) points the driver at a different
namespace than this release's own (that namespace must already exist).

## Persistence & multi-replica

`persistence.enabled` (default `false`, `emptyDir`) — the enrolled `dsp_` token is lost on
pod deletion/rescheduling without it, and the dispatcher just re-enrols with a fresh `djn_`
token on next start (harmless, but noisy, and needs a fresh token minted each time). Set
`persistence.enabled: true` (a `PersistentVolumeClaim`) for a single-replica deployment
expected to survive restarts without re-enrolling.

`replicaCount` is safe to scale beyond 1 — each replica enrols
independently on its own first boot and is granted its own `svc-dispatcher-<team>-<n>`
Principal + `dsp_` token by the core's runner-style enrolment; nothing here coordinates
identity across replicas, the core does. **Not compatible with `persistence.enabled: true`**:
a single PVC mounted by every replica would let them overwrite each other's token file — a
template guard refuses to render that combination rather than risk it silently. Run multiple
replicas with the default `emptyDir` instead.

## Values

See `values.yaml` for the full set with inline comments, and `values.schema.json` for the
validated shape. The shared conventions (names, labels, security contexts, probes) come from
the bundled `octroi-common` library chart.
