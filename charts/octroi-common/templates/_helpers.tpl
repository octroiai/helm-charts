{{/*
Shared named templates for every octroi.ai brick chart (core, dispatcher, umbrella). This is a
Helm *library* chart: it renders nothing on its own, `helm install` refuses it directly, and
every `include` below runs in the calling chart's own context (its own .Values / .Chart /
.Release) — a consuming chart must define the value keys these helpers read (image.*,
serviceAccount.*, podSecurityContext, securityContext, probes, resources,
podDisruptionBudget.*, nodeSelector, tolerations, affinity). The frontend charts follow the
same naming with their own copy of these helpers; keep them in lockstep.
*/}}

{{- define "octroi-common.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "octroi-common.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{- define "octroi-common.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
`octroi.ai/brick` names which piece of the platform a resource belongs to (core / dispatcher /
frontend). Defaults to the calling chart's own name with an "octroi-" prefix stripped —
"octroi-core" -> "core", "octroi-dispatcher" -> "dispatcher" with zero configuration. Override
with `.Values.brick` for a chart whose name doesn't follow that convention.
*/}}
{{- define "octroi-common.brick" -}}
{{- .Values.brick | default (trimPrefix "octroi-" .Chart.Name) -}}
{{- end -}}

{{- define "octroi-common.labels" -}}
helm.sh/chart: {{ include "octroi-common.chart" . }}
{{ include "octroi-common.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
octroi.ai/brick: {{ include "octroi-common.brick" . }}
{{- end -}}

{{- define "octroi-common.selectorLabels" -}}
app.kubernetes.io/name: {{ include "octroi-common.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{/*
"registry/repository:tag" — tag defaults to .Chart.AppVersion (image tag tracks the app
release, not the chart version — see ADR 0008's versioning policy, H5).
*/}}
{{- define "octroi-common.image" -}}
{{- $tag := .Values.image.tag | default .Chart.AppVersion -}}
{{- printf "%s/%s:%s" .Values.image.registry .Values.image.repository $tag -}}
{{- end -}}

{{/*
Pod-level securityContext. Secure-by-default (non-root, RuntimeDefault seccomp); a chart's
own `values.yaml` sets `podSecurityContext` to the same shape to override any key.
*/}}
{{- define "octroi-common.podSecurityContext" -}}
{{- $default := dict "runAsNonRoot" true "runAsUser" 1000 "runAsGroup" 1000 "fsGroup" 1000 "seccompProfile" (dict "type" "RuntimeDefault") -}}
{{- $merged := mergeOverwrite $default (.Values.podSecurityContext | default dict) -}}
{{- toYaml $merged -}}
{{- end -}}

{{/*
Container-level securityContext. Secure-by-default (read-only root filesystem, all Linux
capabilities dropped, no privilege escalation); override the same way as the pod-level one.
A container that genuinely needs to write to disk mounts an `emptyDir`, it does not relax
this default (see the dispatcher chart's `/data` volume).
*/}}
{{- define "octroi-common.containerSecurityContext" -}}
{{- $default := dict "runAsNonRoot" true "readOnlyRootFilesystem" true "allowPrivilegeEscalation" false "capabilities" (dict "drop" (list "ALL")) -}}
{{- $merged := mergeOverwrite $default (.Values.securityContext | default dict) -}}
{{- toYaml $merged -}}
{{- end -}}

{{/*
`envFrom:` projecting a non-secret ConfigMap (always the release's own, named after the
fullname) and a Secret (the release's own, or `.Values.existingSecret` when the operator
supplies one out of band — e.g. from an External-Secrets sync). The consuming chart still owns
writing the ConfigMap/Secret manifests themselves; this only wires the container up to them.
*/}}
{{- define "octroi-common.envFrom" -}}
envFrom:
  - configMapRef:
      name: {{ include "octroi-common.fullname" . }}
  - secretRef:
      name: {{ .Values.existingSecret | default (include "octroi-common.fullname" .) }}
{{- end -}}

{{/*
liveness/readiness/startup probes against the app's dedicated Spring Boot management port and
probe groups (ROADMAP-helm-charts H0): `/actuator/health/liveness` and
`/actuator/health/readiness`. `.Values.probes` tunes timing; `.Values.managementPort` (default
8081) points every probe at the management port, never the app port.
*/}}
{{- define "octroi-common.probes" -}}
{{- $port := .Values.managementPort | default 8081 -}}
{{- $p := .Values.probes | default dict -}}
livenessProbe:
  httpGet:
    path: /actuator/health/liveness
    port: {{ $port }}
  initialDelaySeconds: {{ $p.initialDelaySeconds | default 10 }}
  periodSeconds: {{ $p.periodSeconds | default 10 }}
  timeoutSeconds: {{ $p.timeoutSeconds | default 3 }}
  failureThreshold: {{ $p.failureThreshold | default 3 }}
readinessProbe:
  httpGet:
    path: /actuator/health/readiness
    port: {{ $port }}
  initialDelaySeconds: {{ $p.readinessInitialDelaySeconds | default 5 }}
  periodSeconds: {{ $p.periodSeconds | default 10 }}
  timeoutSeconds: {{ $p.timeoutSeconds | default 3 }}
  failureThreshold: {{ $p.failureThreshold | default 3 }}
{{- end -}}

{{- define "octroi-common.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{- default (include "octroi-common.fullname" .) .Values.serviceAccount.name -}}
{{- else -}}
{{- default "default" .Values.serviceAccount.name -}}
{{- end -}}
{{- end -}}

{{/*
Full `ServiceAccount` resource, guarded by `.Values.serviceAccount.create`. A consuming
chart's own `templates/serviceaccount.yaml` is just `{{- include "octroi-common.serviceAccount" . }}`.

When `.Values.serviceAccount.hookWeight` is set, the ServiceAccount is itself rendered as a
`pre-install,pre-upgrade` hook at that weight instead of a normal resource. Helm applies a
chart's normal resources only after its pre-install hooks succeed, so a chart with its own
pre-install hook Job (e.g. the core chart's migration Job, `migrationJob.hookWeight`) that runs as
this ServiceAccount would otherwise find it missing on a fresh install — set this lower (more
negative) than that hook's weight so the ServiceAccount is created first within the same phase.
*/}}
{{- define "octroi-common.serviceAccount" -}}
{{- if .Values.serviceAccount.create -}}
apiVersion: v1
kind: ServiceAccount
metadata:
  name: {{ include "octroi-common.serviceAccountName" . }}
  labels:
    {{- include "octroi-common.labels" . | nindent 4 }}
  {{- $annotations := .Values.serviceAccount.annotations | default dict }}
  {{- if .Values.serviceAccount.hookWeight }}
  {{- $annotations = merge $annotations (dict "helm.sh/hook" "pre-install,pre-upgrade" "helm.sh/hook-weight" (.Values.serviceAccount.hookWeight | toString) "helm.sh/hook-delete-policy" "before-hook-creation") }}
  {{- end }}
  {{- if $annotations }}
  annotations:
    {{- toYaml $annotations | nindent 4 }}
  {{- end }}
{{- end -}}
{{- end -}}

{{/*
Full `PodDisruptionBudget` resource, guarded by `.Values.podDisruptionBudget.enabled`. A
consuming chart's own `templates/pdb.yaml` is just `{{- include "octroi-common.pdb" . }}`.
Reads `.Values.podDisruptionBudget.minAvailable` when set, else `.maxUnavailable`, else
defaults to `minAvailable: 1`.
*/}}
{{- define "octroi-common.pdb" -}}
{{- if .Values.podDisruptionBudget.enabled -}}
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: {{ include "octroi-common.fullname" . }}
  labels:
    {{- include "octroi-common.labels" . | nindent 4 }}
spec:
  {{- if .Values.podDisruptionBudget.minAvailable }}
  minAvailable: {{ .Values.podDisruptionBudget.minAvailable }}
  {{- else if .Values.podDisruptionBudget.maxUnavailable }}
  maxUnavailable: {{ .Values.podDisruptionBudget.maxUnavailable }}
  {{- else }}
  minAvailable: 1
  {{- end }}
  selector:
    matchLabels:
      {{- include "octroi-common.selectorLabels" . | nindent 6 }}
{{- end -}}
{{- end -}}
