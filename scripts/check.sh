#!/usr/bin/env bash
# Type-check every Jac module in the repository. Exits non-zero on the first failure.
set -euo pipefail
cd "$(dirname "$0")/.."
status=0
while IFS= read -r -d '' f; do
  if ! out=$(jac check "$f" 2>&1); then
    echo "FAIL $f"; echo "$out" | grep -E "^(✖|error)" -A6 | head -40
    status=1
  else
    echo "ok   $f"
  fi
done < <(find main.jac domain adapters runtime instruments insights api tools examples verify components pages \
           -type f -name '*.jac' ! -name '*.impl.jac' -print0 | sort -z)
exit $status
