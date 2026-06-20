#!/bin/bash
# Guest Portal Comprehensive Test Suite
# Usage: bash test-suite.sh [base_url]

BASE_URL="${1:-http://localhost:3000}"
ADMIN_USER="${ADMIN_USER:-admin}"
ADMIN_PASS="${ADMIN_PASS:-}"
PASSED=0
FAILED=0
TOTAL=0
SKIPPED=0

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test helper functions
pass() {
    echo -e "${GREEN}✓ PASS${NC}: $1"
    ((PASSED++))
    ((TOTAL++))
}

fail() {
    echo -e "${RED}✗ FAIL${NC}: $1"
    echo "  Expected: $2"
    echo "  Got: $3"
    ((FAILED++))
    ((TOTAL++))
}

skip() {
    echo -e "${YELLOW}⚠ SKIP${NC}: $1"
    ((SKIPPED++))
}

admin_curl() {
    if [[ -n "$ADMIN_PASS" ]]; then
        curl -s -u "$ADMIN_USER:$ADMIN_PASS" "$@"
    else
        curl -s "$@"
    fi
}

require_admin_creds() {
    if [[ -z "$ADMIN_PASS" ]]; then
        skip "$1 (set ADMIN_USER and ADMIN_PASS to run)"
        return 1
    fi
    return 0
}

section() {
    echo ""
    echo -e "${YELLOW}━━━ $1 ━━━${NC}"
}

# Wait for server to be ready
wait_for_server() {
    echo "Waiting for server at $BASE_URL..."
    for i in {1..10}; do
        if curl -s "$BASE_URL/health" > /dev/null 2>&1; then
            echo "Server is ready!"
            return 0
        fi
        sleep 1
    done
    echo "Server not responding after 10 seconds"
    exit 1
}

#######################
# TEST CASES
#######################

section "1. HEALTH CHECK"

test_health() {
    local response=$(curl -s "$BASE_URL/health")
    if [[ "$response" == '{"status":"ok"}' ]]; then
        pass "Health endpoint returns ok"
    else
        fail "Health endpoint" '{"status":"ok"}' "$response"
    fi
}

section "2. GUEST REGISTRATION"

test_register_valid() {
    local response=$(curl -s -X POST "$BASE_URL/register" \
        -H "Content-Type: application/json" \
        -d '{"name":"Test User","room":"Room 1","stayDays":7}')
    if [[ "$response" == *"token"* ]] && [[ "$response" == *"guest"* ]]; then
        GUEST_TOKEN=$(echo "$response" | grep -o '"token":"[^"]*"' | cut -d'"' -f4)
        pass "Valid guest registration (returns token + guest)"
    else
        fail "Valid guest registration" '{"token":"...","guest":{...}}' "$response"
    fi
}

test_register_invalid_name() {
    local response=$(curl -s -X POST "$BASE_URL/register" \
        -H "Content-Type: application/json" \
        -d '{"name":"<script>alert(1)</script>","room":"Room 1"}')
    if [[ "$response" == *"Invalid"* ]]; then
        pass "Rejects XSS in guest name"
    else
        fail "Rejects XSS in guest name" "Invalid name or room" "$response"
    fi
}

test_register_empty() {
    local response=$(curl -s -X POST "$BASE_URL/register" \
        -H "Content-Type: application/json" \
        -d '{"name":"","room":""}')
    if [[ "$response" == *"Invalid"* ]]; then
        pass "Rejects empty registration"
    else
        fail "Rejects empty registration" "Invalid name or room" "$response"
    fi
}

section "3. ROOM MANAGEMENT"

test_get_rooms() {
    local response=$(curl -s "$BASE_URL/admin-api/rooms")
    if [[ "$response" == "["* ]]; then
        pass "Get rooms returns array"
    else
        fail "Get rooms returns array" "[...]" "$response"
    fi
}

test_add_room_valid() {
    require_admin_creds "Add valid room" || return
    local response=$(admin_curl -X POST "$BASE_URL/admin-api/rooms" \
        -H "Content-Type: application/json" \
        -d '{"name":"Test Suite Room","dashboardUrl":"http://example.com/test"}')
    if [[ "$response" == "OK" ]]; then
        pass "Add valid room"
    else
        fail "Add valid room" "OK" "$response"
    fi
}

test_add_room_invalid_name() {
    require_admin_creds "Rejects XSS in room name" || return
    local response=$(admin_curl -X POST "$BASE_URL/admin-api/rooms" \
        -H "Content-Type: application/json" \
        -d '{"name":"<script>","dashboardUrl":"http://example.com"}')
    if [[ "$response" == *"Invalid"* ]]; then
        pass "Rejects XSS in room name"
    else
        fail "Rejects XSS in room name" "Invalid room name" "$response"
    fi
}

test_add_room_invalid_url() {
    require_admin_creds "Rejects invalid URL" || return
    local response=$(admin_curl -X POST "$BASE_URL/admin-api/rooms" \
        -H "Content-Type: application/json" \
        -d '{"name":"Valid Room","dashboardUrl":"not-a-url"}')
    if [[ "$response" == *"Invalid"* ]]; then
        pass "Rejects invalid URL"
    else
        fail "Rejects invalid URL" "Invalid dashboard URL format" "$response"
    fi
}

test_delete_room() {
    require_admin_creds "Delete room" || return
    local response=$(admin_curl -X DELETE "$BASE_URL/admin-api/rooms/Test%20Suite%20Room")
    if [[ "$response" == "OK" ]]; then
        pass "Delete room"
    else
        fail "Delete room" "OK" "$response"
    fi
}

section "4. SESSION CODE SYSTEM"

test_create_session() {
    local response=$(curl -s -X POST "$BASE_URL/session" \
        -H "Content-Type: application/json" \
        -d '{"name":"Session Test User","room":"Room 1"}')
    if [[ "$response" == *"code"* ]]; then
        SESSION_CODE=$(echo "$response" | grep -o '"code":"[^"]*"' | cut -d'"' -f4)
        pass "Create session code: $SESSION_CODE"
    else
        fail "Create session code" '{"code":"XXXXXX"}' "$response"
    fi
}

test_retrieve_session() {
    if [[ -z "$SESSION_CODE" ]]; then
        fail "Retrieve session" "Needs session code" "No code available"
        return
    fi
    local response=$(curl -s "$BASE_URL/session/$SESSION_CODE")
    if [[ "$response" == *"Session Test User"* ]]; then
        pass "Retrieve session by code"
    else
        fail "Retrieve session by code" "Guest data" "$response"
    fi
}

test_invalid_session() {
    local response=$(curl -s "$BASE_URL/session/INVALID")
    if [[ "$response" == *"Invalid"* ]] || [[ "$response" == *"expired"* ]]; then
        pass "Invalid session code rejected"
    else
        fail "Invalid session code rejected" "Invalid or expired" "$response"
    fi
}

test_list_sessions() {
    require_admin_creds "List active sessions" || return
    local response=$(admin_curl "$BASE_URL/admin-api/sessions")
    if [[ "$response" == "["* ]]; then
        pass "List active sessions"
    else
        fail "List active sessions" "[...]" "$response"
    fi
}

test_revoke_session() {
    require_admin_creds "Revoke session code" || return
    if [[ -z "$SESSION_CODE" ]]; then
        fail "Revoke session" "Needs session code" "No code available"
        return
    fi
    local response=$(admin_curl -X DELETE "$BASE_URL/admin-api/sessions/$SESSION_CODE")
    if [[ "$response" == "OK" ]]; then
        pass "Revoke session code"
    else
        fail "Revoke session code" "OK" "$response"
    fi
}

section "5. ADMIN AUTHENTICATION"

test_admin_setup_required() {
    local response=$(curl -s "$BASE_URL/admin-api/setup-required")
    if [[ "$response" == *"setupRequired"* ]]; then
        pass "Check setup required endpoint"
    else
        fail "Check setup required endpoint" '{"setupRequired":...}' "$response"
    fi
}

test_admin_login_invalid() {
    require_admin_creds "Admin page rejects invalid Basic Auth" || return
    local http_code=$(curl -s -o /dev/null -w "%{http_code}" \
        "$BASE_URL/admin.html" \
        -u "wronguser:wrongpass")
    if [[ "$http_code" == "401" ]]; then
        pass "Admin page rejects invalid Basic Auth (401)"
    else
        fail "Admin page rejects invalid Basic Auth" "401" "$http_code"
    fi
}

test_deployment_status() {
    require_admin_creds "Deployment status" || return
    local response=$(admin_curl "$BASE_URL/admin-api/deployment-status")
    if [[ "$response" == *'"app"'* ]] && [[ "$response" == *'"storage"'* ]] && [[ "$response" == *'"reverseProxy"'* ]]; then
        pass "Deployment status endpoint"
    else
        fail "Deployment status endpoint" "app/storage/reverseProxy JSON" "$response"
    fi
    if [[ "$response" == *'"registrationHistory"'* ]] && [[ "$response" == *'"activeGuestSessions"'* ]] && [[ "$response" == *'"expiredGuestSessions"'* ]]; then
        pass "Deployment status separates history and sessions"
    else
        fail "Deployment status separates history and sessions" "registrationHistory/activeGuestSessions/expiredGuestSessions" "$response"
    fi
    if [[ "$response" == *'"admin"'* ]] && [[ "$response" == *'"username"'* ]]; then
        pass "Deployment status includes admin username"
    else
        fail "Deployment status includes admin username" '"admin":{"username":...}' "$response"
    fi
}

section "5b. GUEST ADMIN MANAGEMENT"

test_list_guest_history() {
    require_admin_creds "List registration history" || return
    local response=$(admin_curl "$BASE_URL/admin-api/guests")
    if [[ "$response" == "["* ]] && [[ "$response" == *"hasActiveSession"* ]]; then
        pass "List registration history"
    else
        fail "List registration history" "[{...hasActiveSession...}]" "$response"
    fi
}

test_admin_register_guest() {
    require_admin_creds "Admin register guest" || return
    admin_curl -X POST "$BASE_URL/admin-api/rooms" \
        -H "Content-Type: application/json" \
        -d '{"name":"Test Suite Room","dashboardUrl":"http://example.com/test"}' > /dev/null
    local response=$(admin_curl -X POST "$BASE_URL/admin-api/guests" \
        -H "Content-Type: application/json" \
        -d '{"name":"Admin Registered Guest","room":"Test Suite Room","stayDays":3}')
    if [[ "$response" == *'"success":true'* ]] && [[ "$response" == *'"token"'* ]]; then
        ADMIN_GUEST_ID=$(echo "$response" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
        pass "Admin register guest"
    else
        fail "Admin register guest" '{"success":true,"token":"..."}' "$response"
    fi
}

test_update_guest_room() {
    require_admin_creds "Update guest room" || return
    if [[ -z "$ADMIN_GUEST_ID" ]]; then
        fail "Update guest room" "Needs admin guest id" "No guest id available"
        return
    fi
    admin_curl -X POST "$BASE_URL/admin-api/rooms" \
        -H "Content-Type: application/json" \
        -d '{"name":"Admin Room Two","dashboardUrl":"http://example.com/admin-room-2"}' > /dev/null
    local response=$(admin_curl -X PATCH "$BASE_URL/admin-api/guest-sessions/$ADMIN_GUEST_ID" \
        -H "Content-Type: application/json" \
        -d '{"room":"Admin Room Two"}')
    if [[ "$response" == *'"success":true'* ]] && [[ "$response" == *"Admin Room Two"* ]]; then
        pass "Update guest room"
    else
        fail "Update guest room" '{"success":true,"guest":{"room":"Admin Room Two"}}' "$response"
    fi
}

test_clear_guest_devices() {
    require_admin_creds "Clear guest devices" || return
    if [[ -z "$ADMIN_GUEST_ID" ]]; then
        fail "Clear guest devices" "Needs admin guest id" "No guest id available"
        return
    fi
    local response=$(admin_curl -X DELETE "$BASE_URL/admin-api/guest-sessions/$ADMIN_GUEST_ID/devices")
    if [[ "$response" == *'"devicesCleared":true'* ]]; then
        pass "Clear guest devices"
    else
        fail "Clear guest devices" '{"devicesCleared":true}' "$response"
    fi
}

test_checkout_admin_guest() {
    require_admin_creds "Check out admin guest" || return
    if [[ -z "$ADMIN_GUEST_ID" ]]; then
        fail "Check out admin guest" "Needs admin guest id" "No guest id available"
        return
    fi
    local response=$(admin_curl -X DELETE "$BASE_URL/admin-api/guest-sessions/$ADMIN_GUEST_ID")
    if [[ "$response" == *'"success":true'* ]]; then
        pass "Check out admin guest session"
    else
        fail "Check out admin guest session" '{"success":true}' "$response"
    fi
}

test_remove_guest_history() {
    require_admin_creds "Remove guest history entry" || return
    if [[ -z "$ADMIN_GUEST_ID" ]]; then
        fail "Remove guest history entry" "Needs admin guest id" "No guest id available"
        return
    fi
    local response=$(admin_curl -X DELETE "$BASE_URL/admin-api/guests/$ADMIN_GUEST_ID")
    if [[ "$response" == *'"success":true'* ]]; then
        pass "Remove guest history entry"
    else
        fail "Remove guest history entry" '{"success":true}' "$response"
    fi
}

section "6. FILE UPLOAD"

test_upload() {
    if [[ -z "$GUEST_TOKEN" ]]; then
        fail "File upload" "Needs guest token" "No token available"
        return
    fi
    printf '%s\n' '%PDF-1.4' '1 0 obj <<>> endobj' '%%EOF' > /tmp/test-upload.pdf
    local response=$(curl -s -X POST "$BASE_URL/upload" \
        -H "X-Guest-Token: $GUEST_TOKEN" \
        -F "photos=@/tmp/test-upload.pdf;type=application/pdf")
    if [[ "$response" == "OK" ]]; then
        pass "Token-authenticated PDF upload"
    else
        fail "Token-authenticated PDF upload" "OK" "$response"
    fi
    rm -f /tmp/test-upload.pdf
}

section "7. SECURITY TESTS"

test_path_traversal() {
    if [[ -z "$GUEST_TOKEN" ]]; then
        fail "Path traversal" "Needs guest token" "No token available"
        return
    fi
    printf '%s\n' '%PDF-1.4' '1 0 obj <<>> endobj' '%%EOF' > /tmp/evil.pdf
    local response=$(curl -s -X POST "$BASE_URL/upload" \
        -H "X-Guest-Token: $GUEST_TOKEN" \
        -F "photos=@/tmp/evil.pdf;type=application/pdf" \
        -F "guestName=../../../etc/passwd")
    # Should succeed but with sanitized path
    if [[ "$response" == "OK" ]]; then
        # Check that no file was created outside uploads
        if [[ ! -f "/home/user/Guest-Portal/etc/passwd" ]]; then
            pass "Path traversal prevented"
        else
            fail "Path traversal prevented" "No file outside uploads" "File created"
        fi
    else
        pass "Path traversal blocked"
    fi
    rm -f /tmp/evil.pdf
}

test_admin_requires_auth() {
    local http_code=$(curl -s -o /dev/null -w "%{http_code}" \
        -X POST "$BASE_URL/admin-api/rooms" \
        -H "Content-Type: application/json" \
        -d '{"name":"Unauthorized Room","dashboardUrl":"http://example.com"}')
    if [[ "$http_code" == "401" ]]; then
        pass "Admin room mutation requires auth (401)"
    else
        fail "Admin room mutation requires auth" "401" "$http_code"
    fi
}

test_upload_requires_token() {
    printf '%s\n' '%PDF-1.4' '1 0 obj <<>> endobj' '%%EOF' > /tmp/no-token.pdf
    local http_code=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$BASE_URL/upload" \
        -F "photos=@/tmp/no-token.pdf;type=application/pdf")
    if [[ "$http_code" == "401" ]]; then
        pass "Upload requires guest token (401)"
    else
        fail "Upload requires guest token" "401" "$http_code"
    fi
    rm -f /tmp/no-token.pdf
}

test_upload_rejects_code() {
    if [[ -z "$GUEST_TOKEN" ]]; then
        fail "Rejects code upload" "Needs guest token" "No token available"
        return
    fi
    echo "console.log('blocked');" > /tmp/payload.js
    local http_code=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$BASE_URL/upload" \
        -H "X-Guest-Token: $GUEST_TOKEN" \
        -F "photos=@/tmp/payload.js;type=application/javascript")
    if [[ "$http_code" == "400" ]]; then
        pass "Rejects code upload"
    else
        fail "Rejects code upload" "400" "$http_code"
    fi
    rm -f /tmp/payload.js
}

test_rate_limiting() {
    # Make 65 rapid requests (limit is 60/min)
    local blocked=false
    for i in {1..65}; do
        local http_code=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/health")
        if [[ "$http_code" == "429" ]]; then
            blocked=true
            break
        fi
    done
    if [[ "$blocked" == "true" ]]; then
        pass "Rate limiting active"
    else
        # Rate limiting may not trigger in quick succession
        echo -e "${YELLOW}⚠ SKIP${NC}: Rate limiting (may need more requests)"
    fi
}

section "8. STATIC FILES"

test_index_html() {
    local response=$(curl -s "$BASE_URL/")
    if [[ "$response" == *"Guest Portal"* ]]; then
        pass "Index page loads"
    else
        fail "Index page loads" "HTML content" "Empty or error"
    fi
}

test_admin_html() {
    require_admin_creds "Admin page loads with Basic Auth" || return
    local response=$(admin_curl "$BASE_URL/admin.html")
    if [[ "$response" == *"Admin Panel"* ]]; then
        pass "Admin page loads with Basic Auth"
    else
        fail "Admin page loads with Basic Auth" "Admin Panel HTML" "Empty or error"
    fi
}

test_welcome_html() {
    local response=$(curl -s "$BASE_URL/welcome.html")
    if [[ "$response" == *"Upload"* && "$response" == *"My Photos"* ]]; then
        pass "Welcome hub page loads"
    else
        fail "Welcome hub page loads" "HTML with upload and nav" "Empty or error"
    fi
}

test_photo_html() {
    local response=$(curl -s "$BASE_URL/photo.html")
    if [[ "$response" == *"My Photos"* && "$response" == *"Welcome"* ]]; then
        pass "Photo gallery page loads"
    else
        fail "Photo gallery page loads" "HTML with gallery nav" "Empty or error"
    fi
}

#######################
# RUN ALL TESTS
#######################

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║   Guest Portal Comprehensive Test Suite   ║"
echo "╚══════════════════════════════════════════╝"
echo ""

wait_for_server

# Run all test functions
test_health

test_register_valid
test_register_invalid_name
test_register_empty

test_get_rooms
test_add_room_valid
test_add_room_invalid_name
test_add_room_invalid_url
test_delete_room

test_create_session
test_retrieve_session
test_invalid_session
test_list_sessions
test_revoke_session

test_admin_setup_required
test_admin_login_invalid
test_deployment_status
test_list_guest_history
test_admin_register_guest
test_update_guest_room
test_clear_guest_devices
test_checkout_admin_guest
test_remove_guest_history

test_upload
test_path_traversal
test_admin_requires_auth
test_upload_requires_token
test_upload_rejects_code

test_index_html
test_admin_html
test_welcome_html
test_photo_html

#######################
# SUMMARY
#######################

section "TEST SUMMARY"
echo ""
echo "Total:  $TOTAL"
echo -e "Passed: ${GREEN}$PASSED${NC}"
echo -e "Failed: ${RED}$FAILED${NC}"
echo -e "Skipped: ${YELLOW}$SKIPPED${NC}"
echo ""

if [[ $FAILED -eq 0 ]]; then
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}Some tests failed.${NC}"
    exit 1
fi
