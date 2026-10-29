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

# Client code compiles to JavaScript, and the browser runtime of jaclang 0.16.7
# lacks some Python string methods. Calls to them pass `jac check` and then
# fail silently in the browser (e.g. a button that does nothing), so flag them.
UNSUPPORTED='\.(join|isdigit|isalpha|isalnum|isspace|isupper|islower|isdecimal|isidentifier|isprintable|ljust|rjust|encode)\('
if hits=$(grep -nE "$UNSUPPORTED" components/*.cl.jac components/*.impl.jac 2>/dev/null); then
  echo "FAIL client code uses string methods the browser runtime does not have:"
  echo "$hits"
  echo "     use the helpers in components/ui.cl.jac, or do the work on the server"
  status=1
else
  echo "ok   client code avoids unsupported string methods"
fi
exit $status
