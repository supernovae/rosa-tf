#!/bin/bash
# OAuth token retrieval script for OpenShift
#
# Input: JSON on stdin with keys: api_url, oauth_url (optional), username, password
# Output: JSON with keys: token, authenticated, error
#
# Requirements:
# - curl must be available
# - Cluster OAuth server must be reachable from the machine running Terraform
#
# OAuth URL Discovery:
#   Standard OCP 4.x: https://oauth-openshift.apps.<cluster>.<domain>
#   HCP External Auth: May vary - use: oc get route -n openshift-authentication
#   Older versions: May have different routing
#
# Retry Logic:
#   The OAuth server may be restarting after IDP configuration changes.
#   This script retries token retrieval with exponential backoff to handle
#   temporary unavailability during OAuth server restarts.
#
# NOTE: We intentionally do NOT use 'set -e' because we need to handle
# errors gracefully and always output valid JSON to Terraform.
# All error conditions are captured and returned as JSON.

# Retry configuration
MAX_RETRIES=${OAUTH_MAX_RETRIES:-6}      # Maximum retry attempts
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
  # This works for both Classic and HCP:
  #   Classic: https://oauth-openshift.apps.<cluster>.<domain>
  #   HCP: https://oauth.<cluster>.<domain>:443
  >&2 echo "Discovering OAuth URL from API..."
  
  WELLKNOWN_RESPONSE=$(curl -sk --connect-timeout 10 "${API_URL}/.well-known/oauth-authorization-server" 2>/dev/null) || WELLKNOWN_RESPONSE=""
  
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
  
  # Fallback to Classic-style derivation if discovery failed
  if [ -z "$OAUTH_URL" ]; then
    >&2 echo "Discovery failed, falling back to Classic-style OAuth URL derivation..."
    CLUSTER_DOMAIN=$(echo "$API_URL" | sed 's|https://api\.||' | sed 's|:[0-9]*$||' | sed 's|/$||')
    OAUTH_URL="https://oauth-openshift.apps.${CLUSTER_DOMAIN}"
    >&2 echo "Derived OAuth URL: $OAUTH_URL"
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
  # Check if OAuth server is reachable
  if ! curl -sk --connect-timeout 10 "$OAUTH_URL/healthz" > /dev/null 2>&1; then
    if ! curl -sk --connect-timeout 10 -o /dev/null "$OAUTH_URL" 2>&1; then
      echo "oauth_not_reachable"
      return 1
    fi
  fi

  # Get token using the challenging client flow
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
>&2 echo "All $MAX_RETRIES retry attempts exhausted. Last error: $LAST_ERROR"
case "$LAST_ERROR" in
  "oauth_not_reachable")
    output_json "" "false" "oauth server not reachable after $MAX_RETRIES attempts"
    ;;
  "auth_failed")
    output_json "" "false" "authentication failed after $MAX_RETRIES attempts - check IDP is ready"
    ;;
  *)
    output_json "" "false" "authentication failed after $MAX_RETRIES attempts: $LAST_ERROR"
    ;;
esac
exit 0
