#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
output="${1:-${repo_dir}/.rendered.yaml}"

helm template homelab-apps "${repo_dir}" \
  --namespace public-sites \
  -f "${repo_dir}/tests/values.yaml" > "${output}"

echo "Rendered security-validation manifests to ${output}"
