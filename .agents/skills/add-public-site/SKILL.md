---
name: add-public-site
description: Add or onboard a private application repository as a public site in the homelab CI/CD and GitOps pipeline. Use when Codex must scaffold a site's container and GitHub Actions, declare it in homelab-apps, add homelab Cilium policy, guide GitHub App/runner/registry/Cloudflare/Uptime Kuma configuration, perform disabled-first rollout checks, or diagnose a new-site onboarding boundary.
---

# Add a public site

Treat onboarding as a cross-repository, cross-system change with explicit
approval gates. Keep credentials and external UI state out of this public
repository.

## Load the runbook

Read [`../../../docs/ADDING_A_PUBLIC_SITE.md`](../../../docs/ADDING_A_PUBLIC_SITE.md)
completely before changing files. Treat it as the authoritative boundary map,
command sequence, and rollback procedure. Read every applicable `AGENTS.md` in
`homelab-apps`, `homelab`, and the application repository.

## Establish inputs

Determine the application key, hostname, private source repository, protected
branch, port, health path, numeric non-root UID, stable container name, root
filesystem requirement, and whether the workload is one stateless HTTP
container.

Stop for design work if it needs persistence, databases, workers, multiple
containers, non-HTTP ingress, new secret values, broad egress, cluster-scoped
resources, or multiple environments. Do not force those into this chart.

## Work in gated phases

1. Inspect the current `elate-me` and `elate-biz` patterns; do not copy Action
   SHAs or assumptions from memory.
2. Prepare the Dockerfile, GitHub-hosted CI, runner preflight, publisher, and
   pinned reusable promotion call.
3. Declare the application with `enabled: false` and an immutable digest field.
4. Add exact reciprocal Cilium rules in `homelab` for its identity and port.
5. Validate every changed repository.
6. Present the manual GitHub, runner, registry, Cloudflare, and monitoring
   checklist. Never fabricate successful external state.
7. Prove publishing and digest promotion while deployment remains disabled.
8. Enable in a separate pull request only after every preceding check passes.
9. Observe Argo, rollout, digest, ingress, endpoint, and monitoring health.
10. Prove one later push-to-digest-to-rollout cycle.

Keep external mutations within the user's authorization. Inspect live state and
prepare files when allowed; request direction before creating or changing
credentials, accounts, DNS/Tunnel routes, repository settings, approval rules,
or monitoring notifications when authority is not explicit.

## Preserve platform contracts

- Deploy only `images.elate.me/APP_KEY@sha256:...`.
- Keep `app.kubernetes.io/name: public-site` and instance `APP_KEY`.
- Use ClusterIP and `kubernetes.io/ingress.class: traefik-public`; never add
  `spec.ingressClassName`.
- Keep application and public-Traefik Cilium rules reciprocal and exact.
- Route Cloudflare only to
  `http://traefik-public.traefik-public.svc.cluster.local:80`.
- Run PR code on GitHub-hosted runners; reserve `homelab` for trusted
  protected-branch publishing.
- Use the production environment for registry and promoter configuration.
- Pin Actions and reusable workflows to full commit SHAs.
- Never commit or print secret material.

## Validate before handoff

Run `./scripts/validate.sh` in `homelab-apps` and applicable validation in every
other changed repository. Before enablement, render production and run the
server-side dry run as
`system:serviceaccount:public-sites:argocd-public-applications` from the
runbook.

Report committed-file work separately from manual external actions. End with
the exact next gate, evidence gathered, rollback digest, and every unverified
boundary.
