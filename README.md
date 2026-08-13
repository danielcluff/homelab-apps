# Homelab applications

Public GitOps source of truth for application workloads hosted on the homelab
Kubernetes cluster. Application source repositories remain private; this
repository records the auditable deployment state that Argo CD will reconcile.

## Repository boundary

| Repository | Responsibility |
| --- | --- |
| Application repositories | Source, tests, production Dockerfile, and CI image build |
| `homelab-apps` | Namespaced workload configuration and immutable image digests |
| `homelab` | Cluster infrastructure, registry, Argo CD bootstrap, namespaces, public ingress, and gateway policy |

This repository is linked to the cluster through an Argo CD `Application`, not
as a Git submodule. The bootstrap resource and its restricted `AppProject` will
live in the `homelab` repository.

## Release contract

Application CI produces an OCI image in the private `images.elate.me` registry.
Production workloads always reference the returned immutable digest:

```yaml
image:
  repository: images.elate.me/example
  digest: sha256:...
```

For simple sites, a successful build from the protected application `main`
branch may update production automatically. More complex products promote the
same digest through development, staging, and production environment changes.
Images are never rebuilt during promotion.

## Current bootstrap state

`elate.me` and `elate.biz` are declared in `environments/production.yaml` with
tested bootstrap image digests, but remain disabled. Enabling either
application requires all of the following:

1. The authenticated private Distribution Registry v3 is available internally.
2. The application image has been built, scanned, pushed, and recorded by digest.
3. The `application-registry-pull` Secret exists in the target namespace.
4. The homelab repository has approved the namespace and exact Cilium rules.
5. Argo CD has a restricted project and bootstrap Application for this repo.

## Validation

```bash
./scripts/validate.sh
```

The validation chart exercises immutable digest enforcement, public Traefik
Ingress, ClusterIP-only exposure, Pod Security settings, disruption protection,
and optional horizontal autoscaling.

Pull requests and changes to `main` also run Kubernetes schema validation,
Trivy configuration and secret scanning, and zizmor analysis of GitHub Actions.
Dependabot proposes updates to SHA-pinned Actions dependencies each week.

## Secrets

This is a public repository. Commit only Secret references, never credentials,
tokens, kubeconfigs, private keys, `.env` files, or plaintext Secret resources.
