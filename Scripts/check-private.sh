#!/usr/bin/env bash
# Guards the public repo against leaking personal info.
# Install as git pre-commit hook:   ln -sf ../../Scripts/check-private.sh .git/hooks/pre-commit
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

fail=0

# 1) Xcode writes your Team ID into the project file when you pick a team in the UI.
if grep -qE 'DEVELOPMENT_TEAM = [A-Z0-9]{10};' RepFolio.xcodeproj/project.pbxproj; then
  echo "✋ RepFolio.xcodeproj/project.pbxproj contains a DEVELOPMENT_TEAM."
  echo "   Remove it in Xcode (Signing & Capabilities → Team: None) and put it into Config/Signing.xcconfig instead."
  fail=1
fi

# 2) Never commit backups / exports / databases.
staged=$(git diff --cached --name-only || true)
if echo "$staged" | grep -qE '(RepFolio-.*\.json|\.csv|\.store|\.sqlite|Signing\.xcconfig)$'; then
  echo "✋ You are about to commit personal data or signing config:"
  echo "$staged" | grep -E '(RepFolio-.*\.json|\.csv|\.store|\.sqlite|Signing\.xcconfig)$' | sed 's/^/   /'
  fail=1
fi

[ $fail -eq 0 ] && echo "✓ No personal data staged." || exit 1
