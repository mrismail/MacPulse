#!/bin/bash
# Applies MacPulse's repository rules to GitHub (ADR-021). Run it once from your Mac as
# the repository owner, after the pull request that adds this script is merged:
#
#   gh auth login                      # as mrismail, with the "repo" scope
#   scripts/repo/apply-protection.sh   # or --dry-run to only show what would change
#
# It is safe to run again: it updates the existing rulesets instead of adding new ones.
# What it does:
#   1. Merge settings: merge commits only, squash and rebase off, delete merged branches.
#   2. Turns on private vulnerability reporting (SECURITY.md relies on it).
#   3. Creates the cla-signatures branch the CLA workflow writes to, if missing.
#   4. Applies .github/rulesets/main.json (replacing the older ruleset on main) and
#      .github/rulesets/release-tags.json.
#   5. Prints the result.
set -euo pipefail
cd "$(dirname "$0")/../.."

REPO="${MACPULSE_REPO:-mrismail/MacPulse}"
DRY_RUN=false
[ "${1:-}" = "--dry-run" ] && DRY_RUN=true

say() { printf '%s\n' "$*"; }
run() {
  if $DRY_RUN; then say "  [dry run] gh $*"; else gh "$@" > /dev/null; fi
}

command -v gh > /dev/null || { say "Install the GitHub CLI first: brew install gh"; exit 1; }
gh auth status > /dev/null 2>&1 || { say "Sign in first: gh auth login"; exit 1; }

PERMISSION=$(gh api "repos/$REPO" --jq '.permissions.admin')
[ "$PERMISSION" = "true" ] || { say "You need admin rights on $REPO."; exit 1; }
DEFAULT_BRANCH=$(gh api "repos/$REPO" --jq '.default_branch')

# The main ruleset requires the "CLA signed" check. That check only runs once the CLA
# workflow is on the default branch, so applying the rules earlier would block every PR.
if ! gh api "repos/$REPO/contents/.github/workflows/cla.yml?ref=$DEFAULT_BRANCH" > /dev/null 2>&1; then
  say "The CLA workflow isn't on $DEFAULT_BRANCH yet. Merge the governance pull request first."
  $DRY_RUN || exit 1
fi

say "1. Merge settings"
run api -X PATCH "repos/$REPO" \
  -F allow_merge_commit=true -F allow_squash_merge=false -F allow_rebase_merge=false \
  -F delete_branch_on_merge=true

say "2. Private vulnerability reporting"
run api -X PUT "repos/$REPO/private-vulnerability-reporting"

say "3. cla-signatures branch"
if gh api "repos/$REPO/branches/cla-signatures" > /dev/null 2>&1; then
  say "  already exists"
else
  SHA=$(gh api "repos/$REPO/git/ref/heads/$DEFAULT_BRANCH" --jq '.object.sha')
  run api -X POST "repos/$REPO/git/refs" -f ref=refs/heads/cla-signatures -f sha="$SHA"
fi

# Finds the id of an existing ruleset to update: one with the same name, or (for the
# branch ruleset) any ruleset that targets the default branch, such as the older
# "Build, test and launch" ruleset.
existing_ruleset() {
  local name="$1" target="$2"
  local ids
  ids=$(gh api "repos/$REPO/rulesets?includes_parents=false" \
    --jq ".[] | select(.name == \"$name\") | .id")
  if [ -z "$ids" ] && [ "$target" = "branch" ]; then
    for id in $(gh api "repos/$REPO/rulesets?includes_parents=false" \
                  --jq '.[] | select(.target == "branch") | .id'); do
      if gh api "repos/$REPO/rulesets/$id" \
           --jq '.conditions.ref_name.include | index("~DEFAULT_BRANCH")' | grep -qv null; then
        ids="$id"; break
      fi
    done
  fi
  printf '%s' "$ids" | head -1
}

apply_ruleset() {
  local file="$1"
  local name target id
  name=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["name"])' "$file")
  target=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["target"])' "$file")
  id=$(existing_ruleset "$name" "$target")
  if [ -n "$id" ]; then
    say "  updating ruleset $id → \"$name\""
    run api -X PUT "repos/$REPO/rulesets/$id" --input "$file"
  else
    say "  creating ruleset \"$name\""
    run api -X POST "repos/$REPO/rulesets" --input "$file"
  fi
}

say "4. Rulesets"
apply_ruleset .github/rulesets/main.json
apply_ruleset .github/rulesets/release-tags.json

say "5. Result"
gh api "repos/$REPO" --jq \
  '"  merge commit: \(.allow_merge_commit), squash: \(.allow_squash_merge), rebase: \(.allow_rebase_merge), delete merged branches: \(.delete_branch_on_merge)"'
for id in $(gh api "repos/$REPO/rulesets?includes_parents=false" --jq '.[].id'); do
  gh api "repos/$REPO/rulesets/$id" --jq \
    '"  \(.name) [\(.target), \(.enforcement)]: " + ([.rules[].type] | join(", ")) +
     (if any(.rules[]; .type == "required_status_checks")
      then "; checks: " + ([.rules[] | select(.type == "required_status_checks")
             | .parameters.required_status_checks[].context] | join(", "))
      else "" end) +
     (if any(.rules[]; .type == "pull_request")
      then "; merge methods: " + ([.rules[] | select(.type == "pull_request")
             | .parameters.allowed_merge_methods[]] | join(", "))
      else "" end)'
done
$DRY_RUN && say "Dry run: nothing was changed."
say "Paste this output into the governance pull request."
