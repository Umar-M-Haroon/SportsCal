#!/usr/bin/env bash
#
# Opens (or comments on) a GitHub issue when a workflow fails on main, so a failed
# deploy or build reaches the owner as an issue notification instead of sitting
# unseen in the Actions tab. One open issue per workflow: repeat failures comment
# on it; close it once main is green again.
#
# Usage: report-failure.sh "<workflow name>"   (needs GH_TOKEN with issues: write)

set -euo pipefail

name="$1"
title="CI failure: ${name}"
run_url="${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}"
commit="${GITHUB_SHA:0:7}"
body="**${name}** failed on \`main\` at ${commit}.

Run: ${run_url}"

existing=$(gh issue list --state open --search "\"${title}\" in:title" --json number,title \
  --jq ".[] | select(.title == \"${title}\") | .number" | head -1)

if [ -n "${existing}" ]; then
  gh issue comment "${existing}" --body "${body}"
else
  gh issue create --title "${title}" --body "${body}"
fi
