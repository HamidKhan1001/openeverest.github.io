#!/usr/bin/env bash

# Fetches the full list of stargazers for openeverest/openeverest from the
# GitHub REST API and writes a static JSON file consumed by the Stargazers
# page (see layouts/stargazers/single.html).
#
# As of 2026-06-30 the /stargazers endpoint is restricted to repo admins and
# collaborators, so the request must be authenticated. Provide a token with
# read access to the target repo via the STARGAZERS_TOKEN environment
# variable. GITHUB_TOKEN is used as a fallback (only works when this script
# runs inside a workflow located in a repo where the token has collaborator
# access).
#
# Output JSON shape:
#   {
#     "total": <int>,
#     "generated_at": "<ISO8601>",
#     "users": [ { "login": "...", "avatar_url": "...", "html_url": "..." }, ... ]
#   }
#
# Users are ordered newest-first (most recent stargazer first).

set -o errexit -o nounset -o pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "${REPO_ROOT}"

REPO_OWNER="${STARGAZERS_REPO_OWNER:-openeverest}"
REPO_NAME="${STARGAZERS_REPO_NAME:-openeverest}"
OUTPUT_FILE="${STARGAZERS_OUTPUT:-${REPO_ROOT}/static/data/stargazers.json}"
PER_PAGE=100

TOKEN="${STARGAZERS_TOKEN:-${GITHUB_TOKEN:-}}"
if [ -z "${TOKEN}" ]; then
    echo "ERROR: STARGAZERS_TOKEN (or GITHUB_TOKEN) must be set to authenticate against the GitHub API." >&2
    echo "Since 2026-06-30 the /stargazers endpoint requires collaborator access." >&2
    exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
    echo "ERROR: jq is required." >&2
    exit 1
fi

mkdir -p "$(dirname "${OUTPUT_FILE}")"

api_call() {
    local url="$1"
    curl --fail --silent --show-error \
        -H "Accept: application/vnd.github+json" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        -H "Authorization: Bearer ${TOKEN}" \
        -H "User-Agent: openeverest-stargazers-fetch" \
        "${url}"
}

echo "Fetching repository metadata for ${REPO_OWNER}/${REPO_NAME}..."
repo_json="$(api_call "https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}")"
total_stars="$(echo "${repo_json}" | jq -r '.stargazers_count')"

if [ -z "${total_stars}" ] || [ "${total_stars}" = "null" ]; then
    echo "ERROR: could not read stargazers_count from repo response." >&2
    exit 1
fi

echo "Repository has ${total_stars} stargazers. Fetching paginated list..."

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

page=1
while : ; do
    page_file="${TMP_DIR}/page-${page}.json"
    url="https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/stargazers?per_page=${PER_PAGE}&page=${page}"
    echo "  page ${page}..."
    api_call "${url}" > "${page_file}"

    count="$(jq 'length' "${page_file}")"
    if [ "${count}" = "0" ]; then
        rm -f "${page_file}"
        break
    fi
    if [ "${count}" -lt "${PER_PAGE}" ]; then
        break
    fi
    page=$((page + 1))

    # Safety cap: 400 pages * 100 = 40k users. Anything past that means
    # something is wrong or the community grew beyond expectations — fail
    # loudly instead of looping forever.
    if [ "${page}" -gt 400 ]; then
        echo "ERROR: exceeded 400 pages, aborting." >&2
        exit 1
    fi
done

# Combine, keep only fields we render, and reverse to newest-first order.
generated_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

# shellcheck disable=SC2016
jq -s \
    --argjson total "${total_stars}" \
    --arg generated_at "${generated_at}" \
    '{
        total: $total,
        generated_at: $generated_at,
        users: (add // [] | map({login, avatar_url, html_url}) | reverse)
    }' \
    "${TMP_DIR}"/page-*.json > "${OUTPUT_FILE}"

fetched_count="$(jq '.users | length' "${OUTPUT_FILE}")"
echo "Wrote ${fetched_count} stargazers to ${OUTPUT_FILE} (total per repo metadata: ${total_stars})."
