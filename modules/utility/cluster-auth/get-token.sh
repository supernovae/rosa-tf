#!/usr/bin/env bash
# Bootstrap fallback only. Prefer short-lived credentials supplied by the runner.
# Input/output are JSON. Never log credentials or bypass TLS.
# Private API/OAuth CAs: set CURL_CA_BUNDLE to a trusted PEM file on the runner.
set -uo pipefail
if ! command -v jq >/dev/null || ! command -v curl >/dev/null; then
    printf '%s\n' '{"token":"","authenticated":"false","error":"jq and curl are required"}'
    exit 0
fi
result() {
    printf '%s' "$1" | jq -Rsc --arg authenticated "$2" --arg error "$3" \
        '{token:.,authenticated:$authenticated,error:$error}'
}
input=$(cat)
if ! jq -e 'type == "object"' >/dev/null 2>&1 <<< "$input"; then
    result "" false "Invalid input JSON"
    exit 0
fi
api_url=$(jq -r '.api_url // empty' <<< "$input")
oauth_url=$(jq -r '.oauth_url // empty' <<< "$input")
username=$(jq -r '.username // empty' <<< "$input")
password=$(jq -r '.password // empty' <<< "$input")
secure_url() {
    [[ "$1" =~ ^https://[^/@?#[:space:]]+(/[^?#[:space:]]*)?$ ]]
}
if ! secure_url "$api_url" || [[ -z "$username" || -z "$password" ]]; then
    result "" false "A verified HTTPS API URL and bootstrap credentials are required"
    exit 0
fi
if [[ -z "$oauth_url" ]]; then
    discovery=$(curl -fsSL --proto '=https' --proto-redir '=https' \
        --connect-timeout 10 --max-time 30 "${api_url%/}/.well-known/oauth-authorization-server" 2>/dev/null) || discovery=""
    oauth_url=$(jq -r '.issuer // empty' <<< "$discovery" 2>/dev/null) || oauth_url=""
fi
if ! secure_url "$oauth_url"; then
    result "" false "No trusted HTTPS OAuth issuer; check discovery, CA trust or explicit OAuth URL"
    exit 0
fi
auth=$(printf '%s:%s' "$username" "$password" | base64 | tr -d '\n')
attempts=${OAUTH_MAX_RETRIES:-10}
delay=${OAUTH_INITIAL_WAIT:-10}
max_delay=${OAUTH_MAX_WAIT:-30}
if [[ ! "$attempts" =~ ^[1-9][0-9]*$ || ! "$delay" =~ ^[0-9]+$ || ! "$max_delay" =~ ^[0-9]+$ ]]; then
    result "" false "Invalid retry settings"
    exit 0
fi
for ((attempt=1; attempt<=attempts; attempt++)); do
    # Send the authorization header on stdin, not in process arguments.
    # Do NOT follow the token redirect or print response headers.
    response=$(printf 'header = "Authorization: Basic %s"\n' "$auth" | \
        curl --config - -sS -i --proto '=https' --connect-timeout 10 --max-time 30 \
        -H 'X-CSRF-Token: 1' "${oauth_url%/}/oauth/authorize?response_type=token&client_id=openshift-challenging-client" 2>/dev/null) || response=""
    token=$(printf '%s\n' "$response" | sed -nE 's/^[Ll][Oo][Cc][Aa][Tt][Ii][Oo][Nn]:.*[#&?]access_token=([^&[:space:]]+).*/\1/p' | head -1)
    if [[ -n "$token" ]] && printf '%s\n' "$response" | grep -Eq '^HTTP/[0-9.]+ 302'; then
        result "$token" true ""
        exit 0
    fi
    if printf '%s\n' "$response" | grep -Eq '^HTTP/[0-9.]+ (401|403)'; then
        result "" false "Bootstrap credentials rejected"
        exit 0
    fi
    if ((attempt < attempts)); then
        printf 'OAuth not ready; retry %s/%s\n' "$attempt" "$attempts" >&2
        sleep "$delay"
        delay=$((delay * 2))
        ((delay > max_delay)) && delay=$max_delay
    fi
done
result "" false "OAuth failed; check private connectivity, CA trust, issuer and identity provider"
