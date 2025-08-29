#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="${REPO_ROOT:-/home/caleb/repo/ibridaDB}"
OLD="ibrida-v0"
NEW="ibrida-v0"

cd "${REPO_ROOT}"
git rev-parse --is-inside-work-tree >/dev/null

echo "==> Updating references from '${OLD}' to '${NEW}' (excluding archival wrappers)"

# 1) Explicitly update the taxa expander default:
if [ -f "dbTools/taxa/expand/expand_taxa.sh" ]; then
  sed -i 's/DB_NAME="${DB_NAME:-ibrida-v0}"/DB_NAME="${DB_NAME:-ibrida-v0}"/' \
    dbTools/taxa/expand/expand_taxa.sh || true
fi

# 2) Update CLAUDE.md references
if [ -f "CLAUDE.md" ]; then
  sed -i "s/${OLD}/${NEW}/g" CLAUDE.md
fi

# 3) Bulk replace all other references EXCEPT archival wrappers and export files
#    (and of course exclude .git)
echo "==> Replacing '${OLD}' -> '${NEW}' (excluding archival wrappers)"
find . -type f \( -name "*.sh" -o -name "*.py" -o -name "*.md" -o -name "*.sql" \) \
     ! -path "./.git/*" \
     ! -path "./dbTools/ingest/v0/r0/*" \
     ! -path "./dbTools/ingest/v0/r1/*" \
     ! -path "./dbTools/export/v0/r0/*" \
     ! -path "./dbTools/export/v0/r1/*" \
     ! -name "*export.txt" \
     -exec grep -l "${OLD}" {} \; \
| xargs -r sed -i "s/${OLD}/${NEW}/g"

echo "==> References updated successfully"
echo "==> Remember to commit these changes on the current branch"