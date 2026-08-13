#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
values="$(mktemp)"
output="$(mktemp)"
trap 'rm -f "${values}" "${output}"' EXIT

cp "${repo_dir}/environments/production.yaml" "${values}"

digest="sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
GITHUB_OUTPUT="${output}" "${repo_dir}/scripts/update-image-digest.rb" elate-me "${digest}" "${values}"

grep -q "^      digest: ${digest}$" "${values}"
grep -q '^changed=true$' "${output}"

: > "${output}"
GITHUB_OUTPUT="${output}" "${repo_dir}/scripts/update-image-digest.rb" elate-me "${digest}" "${values}"
grep -q '^changed=false$' "${output}"

if "${repo_dir}/scripts/update-image-digest.rb" missing-app "${digest}" "${values}" >/dev/null 2>&1; then
  echo "missing applications must fail" >&2
  exit 1
fi

if "${repo_dir}/scripts/update-image-digest.rb" elate-me latest "${values}" >/dev/null 2>&1; then
  echo "mutable image references must fail" >&2
  exit 1
fi

echo "Image digest update tests passed"
