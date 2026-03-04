#!/usr/bin/env bash
#
# lint_shell_critical.sh
#
# Fast parser/lint gate for high-risk operational shell scripts.
# Runs bash parser checks always, and ShellCheck when available.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

TARGETS=(
  "dbTools/admin/post_carryover_elevation.sh"
  "dbTools/admin/ingest_dec2025_r2_stream.sh"
  "dbTools/ingest/v0/utils/elevation/load_dem_fixed.sh"
)

fail=0

echo "[lint] repo=${REPO_ROOT}"
for rel in "${TARGETS[@]}"; do
  path="${REPO_ROOT}/${rel}"
  if [[ ! -f "${path}" ]]; then
    echo "[lint] MISSING: ${rel}" >&2
    fail=1
    continue
  fi

  echo "[lint] bash -n ${rel}"
  if ! bash -n "${path}"; then
    echo "[lint] parser failed: ${rel}" >&2
    fail=1
  fi
done

if command -v shellcheck >/dev/null 2>&1; then
  echo "[lint] shellcheck enabled"
  # Treat warnings as errors for the post-carryover runner itself.
  if ! shellcheck -x "${REPO_ROOT}/dbTools/admin/post_carryover_elevation.sh"; then
    echo "[lint] shellcheck failed: dbTools/admin/post_carryover_elevation.sh" >&2
    fail=1
  fi

  # Run informational checks for adjacent scripts without blocking on legacy style warnings.
  shellcheck -x "${REPO_ROOT}/dbTools/admin/ingest_dec2025_r2_stream.sh" || true
  shellcheck -x "${REPO_ROOT}/dbTools/ingest/v0/utils/elevation/load_dem_fixed.sh" || true
else
  echo "[lint] shellcheck not found; parser checks only."
fi

if [[ "${fail}" -ne 0 ]]; then
  echo "[lint] FAILED" >&2
  exit 1
fi

echo "[lint] OK"
