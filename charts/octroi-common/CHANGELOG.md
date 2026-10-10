# Changelog — octroi-common

## Unreleased

First release under this name. Named templates: `name`, `fullname`, `chart`, `brick`,
`labels`, `selectorLabels`, `image`, `podSecurityContext`, `containerSecurityContext`,
`envFrom`, `probes`, `serviceAccountName`, `serviceAccount` (resource), `pdb` (resource).

- The brick label is `octroi.ai/brick`; its override value is `brick`; by default it is the
  chart name with `octroi-` stripped.
- **Upgrading from the previously named library:** `app.kubernetes.io/name` follows the
  consuming chart's name, and a `Deployment`'s `spec.selector` is immutable. Switching a
  release to a renamed consuming chart works because the object names change with it (the old
  objects are deleted, new ones created). A `fullnameOverride` that keeps an old object name
  makes the upgrade fail: remove it, or delete the old `Deployment` first.
