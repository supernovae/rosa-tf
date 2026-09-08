#!/usr/bin/env bash
# Offline fake curl for bootstrap auth security tests. Never contacts a network.
set -euo pipefail
for arg in "$@"; do
    case "$arg" in
        *insecure*|-k|-sk*|*'Basic '*) exit 88 ;;
    esac
done
[[ "$*" == *"--proto =https"* ]] || exit 89
[[ "${FAKE_MODE:-}" != "tls-failure" ]] || exit 60
if [[ "$*" == *".well-known/oauth-authorization-server"* ]]; then
    if [[ "${FAKE_MODE:-}" == "bad-issuer" ]]; then
        printf '%s\n' '{"issuer":"http://untrusted.test"}'
    else
        printf '%s\n' '{"issuer":"https://oauth.example.test"}'
    fi
else
    [[ "$*" == *"--config -"* ]] || exit 90
    header=$(cat)
    [[ "$header" == 'header = "Authorization: Basic '* ]] || exit 91
    if [[ "${FAKE_MODE:-}" == "rejected" ]]; then
        printf 'HTTP/1.1 401 Unauthorized\r\n\r\n'
    else
        printf 'HTTP/1.1 302 Found\r\nLocation: https://oauth.example.test/#access_token=test-token&token_type=Bearer\r\n\r\n'
    fi
fi
