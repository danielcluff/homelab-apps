# Add a public site to the deployment pipeline

This runbook adds a private application repository to the production path:

```text
protected main push
  -> GitHub-hosted CI validates source and image
  -> self-hosted M1 runner builds linux/amd64 with Colima/Buildx
  -> images.elate.me stores the image
  -> GitHub App opens a digest-only homelab-apps PR
  -> merge records desired production state
  -> Argo CD reconciles public-sites
  -> public Traefik serves the site through Cloudflare Tunnel
```

Declare the application with `enabled: false`, prove every external boundary,
and enable it only in a final pull request.

## Scope and stop conditions

The current chart supports one stateless HTTP container, a ClusterIP Service,
public Ingress, PodDisruptionBudget, and optional CPU autoscaling. Stop and
extend the design before onboarding an application that needs a database,
persistent volume, queue, cache, worker, cron job, multiple containers,
non-HTTP ingress, broad egress, new secret values, cluster-scoped resources,
another namespace, or multiple environments. Those require explicit resource,
backup, secret, policy, and promotion designs.

## Decide these values

| Name | Example | Constraint |
| --- | --- | --- |
| `APP_KEY` | `example-site` | DNS label; becomes image, resources, labels, and promotion key |
| `DOMAIN` | `example.com` | Public hostname managed in Cloudflare |
| `SOURCE_REPO` | `danielcluff/example-site` | Private GitHub repository |
| `DEFAULT_BRANCH` | `main` | Protected production branch |
| `CONTAINER_PORT` | `8080` | Unprivileged listening port |
| `HEALTH_PATH` | `/healthz` | Anonymous HTTP 2xx without redirects |
| `RUN_AS_USER` | `101` | Numeric non-root runtime UID |
| `CONTAINER_NAME` | `application` | Stable Kubernetes merge key |
| `READ_ONLY_ROOT` | `true` | Prefer true; justify false |

The stable identity is `app.kubernetes.io/name: public-site` plus
`app.kubernetes.io/instance: APP_KEY`. Cilium and Services depend on it.

## External boundary map

| Boundary | Owner | Required outcome |
| --- | --- | --- |
| GitHub source repo | GitHub settings and app repo | Private repo, protected branch, required CI, production environment |
| Promoter GitHub App | GitHub App and source environment | Installed only on `homelab-apps`; credential available to source workflow |
| Build runner | Dedicated M1 Mac | Online `homelab` runner, Colima, Docker CLI, Buildx, LAN DNS |
| Registry | `images.elate.me` | Authenticated push and cluster pull succeed |
| GitOps | `homelab-apps` | Disabled declaration, immutable digest, validated render |
| Cluster policy | `homelab` | Reciprocal exact Cilium rules for key and port |
| Edge | Cloudflare DNS/Tunnel | Host targets only public Traefik before 404 catch-all |
| Reconciler | Argo CD | Allowed resources are synced and healthy |
| Monitoring | Uptime Kuma | HTTPS monitor and notification test exist |

## Phase 1: application repository

### Build a production image

Add a multi-stage `Dockerfile` and `.dockerignore`. Pin base images by digest.
The runtime must run as `RUN_AS_USER`, listen on
`0.0.0.0:CONTAINER_PORT`, expose an anonymous `HEALTH_PATH`, tolerate two
replicas and termination, and contain no credentials. Use `elate-biz` as the
nginx/static reference and `elate-me` as the Node server reference.

```bash
docker build -t local/APP_KEY:test .
docker run --rm -p 18080:CONTAINER_PORT local/APP_KEY:test
curl --fail http://127.0.0.1:18080/HEALTH_PATH
```

### Add ordinary CI

Create `.github/workflows/ci.yaml` from a current application. Run it on pull
requests and the production branch. Install from the lockfile, test/build, and
build the production image without pushing. Keep `contents: read`, pin Actions
to full commit SHAs, and set timeouts and concurrency.

Never run untrusted pull-request code on the self-hosted runner. GitHub-hosted
infrastructure validates PRs; only a trusted production commit may enter the
home network.

### Add trusted publisher files

Copy the latest working `scripts/prepare-ci-runner.sh` and
`scripts/publish-image.sh`, changing only the application image name. Preserve:

- registry `images.elate.me`, platform `linux/amd64`, builder
  `homelab-builder`, and the Colima Unix socket;
- a temporary `DOCKER_CONFIG` that avoids macOS Keychain interaction;
- Buildx metadata digest parsing and strict `sha256:<64 hex>` validation;
- DNS expectation `192.168.1.50` and unauthenticated registry status `401`.

Run `shellcheck` when available and execute the preflight as the runner service
account.

### Add publish and promotion

Create `.github/workflows/publish.yaml` from a current application. Replace the
image summary, `application: APP_KEY`, and branch trigger. Pin
`danielcluff/homelab-apps/.github/workflows/promote-image.yaml` to a full,
reviewed commit SHA—never `main`.

The publish job uses `runs-on: homelab`, `environment: production`,
`contents: read`, a timeout, and `cancel-in-progress: false`.

## Phase 2: GitHub external state

These settings cannot be committed.

### Runner access

In GitHub runner settings, confirm the dedicated Mac is online with labels
`self-hosted`, `macOS`, `ARM64`, and `homelab`; allow `SOURCE_REPO` in its runner
group; keep public repositories disallowed.

On the runner account:

```bash
colima status
docker buildx version
docker buildx inspect homelab-builder --bootstrap
dig +short images.elate.me A
curl -o /dev/null -sS -w '%{http_code}\n' https://images.elate.me/v2/
```

Expected results are `192.168.1.50` and HTTP `401`.

### Production environment and GitHub App

Create a `production` environment in `SOURCE_REPO` with secrets:

- `REGISTRY_USERNAME`
- `REGISTRY_PASSWORD`
- `HOMELAB_PROMOTER_PRIVATE_KEY`

Add variable `HOMELAB_PROMOTER_CLIENT_ID`. Use the App's **Client ID**, not its
numeric App ID. Store values in the password manager; never commit or print
them.

The promoter App stays installed only on `homelab-apps` with Contents read/write
and Pull requests read/write. It needs no webhook. The reusable workflow
restricts its installation token to `danielcluff/homelab-apps`.

Optional environment reviewers approve publishing. Without them, the protected
branch publishes automatically and the digest PR merge remains deployment
approval.

### Branch protection

Require source CI before merging. Disallow force pushes and branch deletion;
prefer pull requests. Do not require the self-hosted publisher on PRs.

## Phase 3: disabled GitOps declaration

Add this to `environments/production.yaml`:

```yaml
  APP_KEY:
    enabled: false
    domain: DOMAIN
    image:
      repository: images.elate.me/APP_KEY
      digest: sha256:REPLACE_WITH_REAL_PUBLISHED_DIGEST
    containerPort: CONTAINER_PORT
    containerName: CONTAINER_NAME
    healthPath: HEALTH_PATH
    runAsUser: RUN_AS_USER
    readOnlyRootFilesystem: true
    autoscaling:
      enabled: false
```

The digest field must exist because promotion updates exactly one digest under
the key. A placeholder may exist only on a short-lived branch; use a real
registry digest before enabling.

Do not change the public-site labels, ClusterIP Service, digest rule, or
annotation `kubernetes.io/ingress.class: traefik-public`.
`spec.ingressClassName` is intentionally absent because public Traefik cannot
perform cluster-scoped IngressClass discovery.

Validate and merge the disabled declaration:

```bash
./scripts/validate.sh
helm template homelab-apps . --namespace public-sites \
  -f environments/production.yaml
```

Required GitHub checks are:

- `Validate / helm`
- `Security scan / Repository and Kubernetes configuration`
- `Security scan / GitHub Actions configuration`

## Phase 4: cluster authorization

In `homelab`, edit both:

- `helm/network-policies/templates/public-sites.yaml`
- `helm/network-policies/templates/traefik-public.yaml`

Add an application policy selecting `public-site` and `APP_KEY`. Allow ingress
only from public Traefik to `CONTAINER_PORT`, plus the existing
host/remote-node probe path. Keep `egress: []` for static sites. Add the
reciprocal public-Traefik egress rule with the same namespace, selector, and
port. One side alone is insufficient under Cilium.

If external APIs or DNS are needed, stop and design narrow egress. Never add
blanket internet or cluster access. Validate, merge, and deploy policy before
enablement.

Verify shared prerequisites:

```bash
kubectl get secret application-registry-pull -n public-sites
kubectl auth can-i create deployments \
  --as=system:serviceaccount:public-sites:argocd-public-applications \
  -n public-sites
kubectl get application homelab-apps-production -n argocd
kubectl get pods -n traefik-public
kubectl get pods -n cloudflare-tunnel
```

Argo currently permits Deployment, Service, PodDisruptionBudget, Ingress, and
HorizontalPodAutoscaler. A new kind requires reviewed AppProject, resource
inclusion, and namespaced RBAC changes.

## Phase 5: Cloudflare edge

In Cloudflare Zero Trust, add `DOMAIN` to the remotely managed `homelab-k8s`
tunnel with service:

```text
http://traefik-public.traefik-public.svc.cluster.local:80
```

Never target the application Service, internal Traefik, a node, or MetalLB.
Keep the final `http_status:404` rule after all hostnames and confirm the DNS
record. Before the Kubernetes Ingress exists, the hostname should return the
controlled public-Traefik 404. Configure Cloudflare Access first for management
or authenticated applications.

## Phase 6: first publish and promotion

Push or dispatch `Publish image` on the protected branch. Confirm the runner
preflight, `linux/amd64` push, immutable digest, and
`automation/promote-APP_KEY` PR. The PR must change only the intended digest.
Merge it after checks; `enabled: false` means Argo still deploys nothing.

| Symptom | Inspect |
| --- | --- |
| Job waits | Runner online state, `homelab` label, runner-group access |
| Buildx missing | CLI plugin registration and service PATH |
| Docker host `colima` parse error | Unix socket and shared Buildx config |
| Keychain interaction denied | Temporary `DOCKER_CONFIG` |
| Registry 521/DNS mismatch | LAN DNS, internal Traefik, registry pods, network path |
| Empty promoter client ID | Production environment variable, not secret |
| Promotion cannot open PR | App installation scope and permissions |

## Phase 7: enable production

Set `enabled: true` on a branch, validate, and preflight with Argo's identity:

```bash
./scripts/validate.sh
helm template homelab-apps . --namespace public-sites \
  -f environments/production.yaml > /tmp/APP_KEY-production.yaml
kubectl apply --dry-run=server \
  --as=system:serviceaccount:public-sites:argocd-public-applications \
  -f /tmp/APP_KEY-production.yaml
```

The render includes all enabled applications. Stop on immutable-selector
errors, duplicate containers, missing kinds/RBAC, invalid probes, or image-pull
failures.

Merge the one-line enablement only after every boundary passes. Observe:

```bash
kubectl get application homelab-apps-production -n argocd \
  -o jsonpath='{.status.sync.status}{"\\t"}{.status.health.status}{"\\n"}'
kubectl rollout status deployment/APP_KEY -n public-sites --timeout=5m
kubectl get pods -n public-sites \
  -l app.kubernetes.io/instance=APP_KEY -o wide
kubectl get deployment APP_KEY -n public-sites \
  -o jsonpath='{.spec.template.spec.containers[0].image}{"\\n"}'
curl --fail --max-time 20 https://DOMAIN/HEALTH_PATH
curl --fail --max-time 20 https://DOMAIN/
```

Expected: `Synced`, `Healthy`, two ready replicas, and the promoted digest. A
plain Traefik `404 page not found` usually means the Ingress annotation is
missing or `spec.ingressClassName` was incorrectly added.

## Phase 8: monitoring and steady state

Add the HTTPS monitor to the canonical list in the `homelab` repository
(`scripts/setup-uptime-kuma-socketio.js`, plus the older shell list while it is
supported), or create it in Uptime Kuma. Monitor `HEALTH_PATH` when meaningful,
configure notifications and certificate-expiry warning, and test an alert.

Then make one harmless source change through a PR. Prove CI, one trusted push,
one digest PR, Argo rollout, and uninterrupted endpoint availability. This
second cycle validates the pipeline rather than only bootstrap state.

## Rollback

- Before enablement, leave `enabled: false` and repair the failed boundary.
- For a bad image, revert the promotion PR or restore the previous digest.
- For bad enablement, revert `enabled` to false; Argo prunes that application.
- For a bad edge route, remove only that hostname and retain the 404 catch-all.
- For bad policy, revert the exact rules; never broaden access to diagnose.

After rollback, verify Argo, pods, public response, and monitoring.

## Completion record

Record the source repo/branch; key, domain, port, UID, and health path; reusable
workflow SHA; first source commit and digest; network-policy PR; Cloudflare
target; declaration/promotion/enablement PRs; successful Argo revision;
monitor test; and rollback digest. Never record credentials, keys, runner
tokens, registry auth, or kubeconfigs.
