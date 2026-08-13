# AGENTS.md

## Purpose

This public repository is the GitOps source of truth for application workloads
running on the homelab Kubernetes cluster. The separate `homelab` repository
owns cluster infrastructure, namespaces, Argo CD bootstrap resources, ingress
controllers, registry infrastructure, and gateway-side network policy.

## Safety boundaries

- Never commit credentials, tokens, kubeconfigs, private keys, environment
  files, registry auth, or plaintext Kubernetes Secrets.
- Workloads may reference pre-provisioned Secret names, but secret values are
  managed outside this repository.
- Container images must be deployed by immutable `sha256` digest. Do not use
  `latest` or another mutable production tag.
- New applications remain `enabled: false` until their namespace, public
  ingress route, and exact Cilium policies have been approved in the `homelab`
  repository.
- This repository manages namespaced application resources only. Do not add
  CRDs, ClusterRoles, cluster-wide bindings, storage classes, ingress
  controllers, or other cluster-scoped infrastructure.
- Public applications use the `traefik-public` IngressClass and ClusterIP
  Services. Do not add LoadBalancer or NodePort Services.

## Validation

Run the complete local validation before committing:

```bash
./scripts/validate.sh
```

The production environment file intentionally contains disabled applications
with empty digests until the private application registry and Argo CD bootstrap
are ready.

