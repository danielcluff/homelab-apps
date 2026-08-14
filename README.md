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

Public Ingresses use the `kubernetes.io/ingress.class: traefik-public`
annotation. The isolated controller deliberately disables cluster-scoped
resource discovery, so `spec.ingressClassName` must not be used here.

Workloads retain the cluster's public-site identity labels:
`app.kubernetes.io/name: public-site` and an
`app.kubernetes.io/instance` matching the application key. These labels are a
deployment contract: Cilium uses both to grant only the corresponding public
Traefik route, and preserving them permits an in-place migration from the
legacy Helm release without changing the Deployment's immutable selector.
The optional `containerName` value likewise preserves a legacy container's
merge key during initial adoption; new applications use `application` by
default.

Pull requests and changes to `main` also run Kubernetes schema validation,
Trivy configuration and secret scanning, and zizmor analysis of GitHub Actions.
Dependabot proposes updates to SHA-pinned Actions dependencies each week.

## Automated image promotion

Private application repositories call the reusable `Promote image digest`
workflow after publishing an image. The caller must pin this repository to an
immutable commit SHA. The workflow uses a dedicated GitHub App installation
token scoped only to this repository, updates the matching production digest,
validates the chart, and opens or refreshes an automation pull request.

The GitHub App requires only these repository permissions:

- Contents: Read and write
- Pull requests: Read and write

Install it only on `danielcluff/homelab-apps`. Store its client ID as
`HOMELAB_PROMOTER_CLIENT_ID` and its private key as
`HOMELAB_PROMOTER_PRIVATE_KEY` in each private application repository (or as
organization-level Actions configuration restricted to the selected
repositories). Do not store either value in this public repository.

## Secrets

This is a public repository. Commit only Secret references, never credentials,
tokens, kubeconfigs, private keys, `.env` files, or plaintext Secret resources.
