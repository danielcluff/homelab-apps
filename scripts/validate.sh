#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
rendered="$(mktemp)"
trap 'rm -f "${rendered}"' EXIT

helm lint "${repo_dir}" -f "${repo_dir}/tests/values.yaml"
helm lint "${repo_dir}" -f "${repo_dir}/environments/production.yaml"
"${repo_dir}/scripts/render-for-scan.sh" "${rendered}"

if grep -Eq 'image: .*:(latest|main)([[:space:]]|$)' "${rendered}"; then
  echo "rendered workloads must not use mutable production image tags" >&2
  exit 1
fi

grep -q 'image: "images.example.com/validation-site@sha256:' "${rendered}"
grep -q 'ingressClassName: traefik-public' "${rendered}"
grep -q 'type: ClusterIP' "${rendered}"
# Keep the selector contract used by the public Cilium policies and by the
# legacy Helm workloads that Argo CD adopts during migration.
grep -q 'app.kubernetes.io/name: public-site' "${rendered}"
grep -q 'app.kubernetes.io/instance: validation-site' "${rendered}"

"${repo_dir}/tests/update-image-digest.sh"

echo "Helm lint and render validation passed"
