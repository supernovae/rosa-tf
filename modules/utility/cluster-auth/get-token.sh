#!/bin/bash
# OAuth token retrieval for OpenShift -- bootstrap only
#
# Used ONCE during GitOps Phase 2 to obtain an OAuth bearer token so Terraform
# can create the persistent ServiceAccount. After bootstrap, the SA token is
# used directly and this script is no longer invoked.
#
# Input: JSON on stdin with keys: api_url, oauth_url (optional), username, password
# Output: JSON with keys: token, authenticated, error
#
# Requirements:
# - curl must be available
# - Cluster OAuth server must be reachable from the machine running Terraform
#
# OAuth URL Discovery (automatic via .well-known endpoint):
#   Classic: https://oauth-openshift.apps.<cluster>.<domain>
#   HCP:     https://oauth.<cluster>.<domain> (hosted control plane)
#
# If .well-known discovery fails, both patterns are probed for connectivity
# and the reachable one is used. You can also override via oauth_url input.
#
# Retry Logic:
#   Exponential backoff (10s -> 30s cap) for up to ~5 minutes.
#   Handles temporary OAuth server unavailability during IDP reconciliation.
#
# NOTE: We intentionally do NOT use 'set -e' because we need to handle
# errors gracefully and always output valid JSON to Terraform.
# All error conditions are captured and returned as JSON.

# Retry configuration
# Default: ~5 minutes total wait (10 retries * 30s max = 300s)
# Retry schedule with exponential backoff: 10, 20, 30, 30, 30, 30, 30, 30, 30, 30 = ~270s + attempt time
MAX_RETRIES=${OAUTH_MAX_RETRIES:-10}     # Maximum retry attempts
INITIAL_WAIT=${OAUTH_INITIAL_WAIT:-10}   # Initial wait time in seconds
MAX_WAIT=${OAUTH_MAX_WAIT:-30}           # Maximum wait time between retries

# Function to output JSON result (defined early so it can be used for error handling)
output_json() {
  local token="$1"
  local authenticated="$2"
  local error="$3"
  # Escape any special characters in the token for JSON
  printf '{"token": "%s", "authenticated": "%s", "error": "%s"}\n' "$token" "$authenticated" "$error"
}

# Read JSON input from stdin
INPUT=$(cat) || INPUT=""

# Debug: log input (without password) to stderr
>&2 echo "Input received (length: ${#INPUT})"

# Parse JSON - prefer jq if available, fallback to regex
if command -v jq &> /dev/null; then
  >&2 echo "Using jq for JSON parsing"
  API_URL=$(echo "$INPUT" | jq -r '.api_url // empty' 2>/dev/null) || API_URL=""
  OAUTH_URL_OVERRIDE=$(echo "$INPUT" | jq -r '.oauth_url // empty' 2>/dev/null) || OAUTH_URL_OVERRIDE=""
  USERNAME=$(echo "$INPUT" | jq -r '.username // empty' 2>/dev/null) || USERNAME=""
  PASSWORD=$(echo "$INPUT" | jq -r '.password // empty' 2>/dev/null) || PASSWORD=""
else
  >&2 echo "jq not available, using regex parsing"
  # Parse JSON using bash (handles special characters properly since input is via stdin)
  # Extract values between quotes after the key
  extract_json_value() {
    local key="$1"
    local input="$2"
    # Use grep and sed to extract value - handles special chars in password
    echo "$input" | grep -o "\"$key\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" 2>/dev/null | sed "s/\"$key\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\"/\1/" 2>/dev/null | head -1 || echo ""
  }
  
  API_URL=$(extract_json_value "api_url" "$INPUT")
  OAUTH_URL_OVERRIDE=$(extract_json_value "oauth_url" "$INPUT")
  USERNAME=$(extract_json_value "username" "$INPUT")
  PASSWORD=$(extract_json_value "password" "$INPUT")
fi

# Debug: log parsed values (without password)
>&2 echo "Parsed - API_URL: '${API_URL}', USERNAME: '${USERNAME}', PASSWORD length: ${#PASSWORD}"

# Validate required inputs
if [ -z "$API_URL" ]; then
  output_json "" "false" "api_url not provided in input"
  exit 0
fi

if [ -z "$USERNAME" ] || [ -z "$PASSWORD" ]; then
  output_json "" "false" "username and password are required"
  exit 0
fi

# Check if curl is available
if ! command -v curl &> /dev/null; then
  output_json "" "false" "curl not found"
  exit 0
fi

# Determine OAuth URL
if [ -n "$OAUTH_URL_OVERRIDE" ]; then
  # Use provided OAuth URL
  OAUTH_URL="$OAUTH_URL_OVERRIDE"
  >&2 echo "Using provided OAuth URL: $OAUTH_URL"
else
  # Auto-discover OAuth URL from the API's .well-known endpoint
  # This works for both Classic and HCP when the API is reachable:
  #   Classic returns: https://oauth-openshift.apps.<cluster>.<domain>
  #   HCP returns:     https://oauth.<cluster>.<domain>:443 (or similar)
  >&2 echo "Discovering OAuth URL from API..."
  
  # -L follows redirects (HCP may redirect), --max-time caps total transfer
  WELLKNOWN_RESPONSE=$(curl -skL --connect-timeout 15 --max-time 30 "${API_URL}/.well-known/oauth-authorization-server" 2>/dev/null) || WELLKNOWN_RESPONSE=""
  
  if [ -n "$WELLKNOWN_RESPONSE" ]; then
    >&2 echo "Well-known response received (length: ${#WELLKNOWN_RESPONSE})"
    # Extract issuer URL - prefer jq if available
    if command -v jq &> /dev/null; then
      OAUTH_URL=$(echo "$WELLKNOWN_RESPONSE" | jq -r '.issuer // empty' 2>/dev/null) || OAUTH_URL=""
    else
      OAUTH_URL=$(echo "$WELLKNOWN_RESPONSE" | grep -o '"issuer"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/"issuer"[[:space:]]*:[[:space:]]*"\([^"]*\)"/\1/' | head -1)
    fi
    
    if [ -n "$OAUTH_URL" ]; then
      >&2 echo "Discovered OAuth URL: $OAUTH_URL"
    fi
  else
    >&2 echo "No well-known response from API"
  fi
  
  # Fallback: derive from API URL and probe both Classic and HCP patterns
  if [ -z "$OAUTH_URL" ]; then
    >&2 echo "Discovery failed, probing OAuth URL patterns..."
    CLUSTER_DOMAIN=$(echo "$API_URL" | sed 's|https://api\.||' | sed 's|:[0-9]*$||' | sed 's|/$||')

    # Classic pattern: oauth-openshift.apps.<domain>
    CLASSIC_OAUTH="https://oauth-openshift.apps.${CLUSTER_DOMAIN}"
    # HCP pattern: oauth.<domain> (control plane hosted by Red Hat)
    HCP_OAUTH="https://oauth.${CLUSTER_DOMAIN}"

    >&2 echo "Trying HCP pattern: $HCP_OAUTH"
    if curl -skL --connect-timeout 5 --max-time 10 -o /dev/null -w '' "$HCP_OAUTH/healthz" 2>/dev/null || \
       curl -skL --connect-timeout 5 --max-time 10 -o /dev/null -w '' "$HCP_OAUTH" 2>/dev/null; then
      OAUTH_URL="$HCP_OAUTH"
      >&2 echo "HCP OAuth reachable: $OAUTH_URL"
    else
      >&2 echo "HCP pattern not reachable, trying Classic pattern: $CLASSIC_OAUTH"
      if curl -skL --connect-timeout 5 --max-time 10 -o /dev/null -w '' "$CLASSIC_OAUTH/healthz" 2>/dev/null || \
         curl -skL --connect-timeout 5 --max-time 10 -o /dev/null -w '' "$CLASSIC_OAUTH" 2>/dev/null; then
        OAUTH_URL="$CLASSIC_OAUTH"
        >&2 echo "Classic OAuth reachable: $OAUTH_URL"
      else
        # Neither probed successfully -- default to Classic (original behavior)
        OAUTH_URL="$CLASSIC_OAUTH"
        >&2 echo "Neither pattern probed. Defaulting to Classic: $OAUTH_URL"
      fi
    fi
  fi
fi

>&2 echo "API URL: $API_URL"
>&2 echo "OAuth URL: $OAUTH_URL"
>&2 echo "Username: $USERNAME"
>&2 echo "Attempting OAuth token retrieval..."

# Create Basic auth header using base64 encoding
AUTH_BASE64=$(printf '%s:%s' "$USERNAME" "$PASSWORD" | base64 | tr -d '\n')

# Function to attempt token retrieval
attempt_token_retrieval() {
  # Check if OAuth server is reachable (-L follows redirects for HCP)
  if ! curl -skL --connect-timeout 10 "$OAUTH_URL/healthz" > /dev/null 2>&1; then
    if ! curl -skL --connect-timeout 10 -o /dev/null "$OAUTH_URL" 2>&1; then
      echo "oauth_not_reachable"
      return 1
    fi
  fi

  # Get token using the challenging client flow
  # NOTE: Do NOT use -L here. The OAuth flow returns 302 with the token in
  # the Location header. Following the redirect would lose the token.
  RESPONSE=$(curl -sk -i -X GET \
    -H "Authorization: Basic ${AUTH_BASE64}" \
    -H "X-CSRF-Token: 1" \
    "$OAUTH_URL/oauth/authorize?response_type=token&client_id=openshift-challenging-client" \
    2>&1) || true

  # Check for redirect with token (successful auth)
  if echo "$RESPONSE" | grep -qi "location:.*access_token="; then
    TOKEN=$(echo "$RESPONSE" | grep -i "^location:" | head -1 | grep -oE "access_token=[^&]+" | cut -d= -f2 | tr -d '\r')
    if [ -n "$TOKEN" ]; then
      echo "$TOKEN"
      return 0
    fi
  fi

  # Check for permanent error codes (don't retry these)
  if echo "$RESPONSE" | grep -q "HTTP/[0-9.]* 401"; then
    echo "invalid_credentials"
    return 2  # Permanent error - don't retry
  fi

  if echo "$RESPONSE" | grep -q "HTTP/[0-9.]* 403"; then
    echo "access_forbidden"
    return 2  # Permanent error - don't retry
  fi

  # Temporary failure - retry
  echo "auth_failed"
  return 1
}

# Retry loop with exponential backoff
ATTEMPT=0
WAIT_TIME=$INITIAL_WAIT
LAST_ERROR=""

while [ "$ATTEMPT" -lt "$MAX_RETRIES" ]; do
  ATTEMPT=$((ATTEMPT + 1))
  
  RESULT=$(attempt_token_retrieval)
  EXIT_CODE=$?
  
  if [ $EXIT_CODE -eq 0 ]; then
    # Success - output token and exit
    output_json "$RESULT" "true" ""
    exit 0
  elif [ $EXIT_CODE -eq 2 ]; then
    # Permanent error - don't retry
    case "$RESULT" in
      "invalid_credentials")
        output_json "" "false" "invalid credentials"
        ;;
      "access_forbidden")
        output_json "" "false" "access forbidden"
        ;;
    esac
    exit 0
  fi
  
  # Store last error for final output
  LAST_ERROR="$RESULT"
  
  # If we haven't exhausted retries, wait before next attempt
  if [ "$ATTEMPT" -lt "$MAX_RETRIES" ]; then
    # Log retry attempt to stderr (won't affect JSON output)
    >&2 echo "OAuth token retrieval attempt $ATTEMPT failed ($RESULT), retrying in ${WAIT_TIME}s..."
    sleep "$WAIT_TIME"
    
    # Exponential backoff with cap
    WAIT_TIME=$((WAIT_TIME * 2))
    if [ "$WAIT_TIME" -gt "$MAX_WAIT" ]; then
      WAIT_TIME=$MAX_WAIT
    fi
  fi
done

# All retries exhausted
>&2 echo ""
>&2 echo "============================================="
>&2 echo "  OAuth token retrieval timed out"
>&2 echo "============================================="
>&2 echo ""
>&2 echo "  All $MAX_RETRIES attempts exhausted. Last error: $LAST_ERROR"
>&2 echo ""
>&2 echo "  The OAuth server may still be reconciling after IDP changes."
>&2 echo "  This is common during initial cluster setup or after adding"
>&2 echo "  the htpasswd identity provider."
>&2 echo ""
>&2 echo "  To resolve:"
>&2 echo "    1. Wait a few minutes for OAuth to finish reconciling"
>&2 echo "    2. Re-run: terraform apply -var-file=<your>.tfvars"
>&2 echo ""
>&2 echo "  To verify manually:"
>&2 echo "    curl -sk <api_url>/.well-known/oauth-authorization-server"
>&2 echo ""
>&2 echo "============================================="
>&2 echo ""
case "$LAST_ERROR" in
  "oauth_not_reachable")
    output_json "" "false" "oauth server not reachable after $MAX_RETRIES attempts (~5 min). OAuth may still be reconciling - re-run terraform apply to retry."
    ;;
  "auth_failed")
    output_json "" "false" "authentication failed after $MAX_RETRIES attempts (~5 min). IDP may still be initializing - re-run terraform apply to retry."
    ;;
  *)
    output_json "" "false" "authentication failed after $MAX_RETRIES attempts (~5 min): $LAST_ERROR. Re-run terraform apply to retry."
    ;;
esac
exit 0
