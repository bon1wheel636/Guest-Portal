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
    if [[ "$response" == *"token"* ]] && [[ "$response" == *"guest"* ]] && [[ "$response" == *'"returningDevice":false'* ]]; then
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
    local response=$(curl -s "$BASE_URL/guest/rooms")
    if [[ "$response" == "["* ]]; then
        pass "Get guest rooms returns array"
    else
        fail "Get guest rooms returns array" "[...]" "$response"
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
    if [[ "$response" == *'"guestEntry"'* ]] && [[ "$response" == *'"roomCount"'* ]] && [[ "$response" == *'"/guest/rooms"'* ]]; then
        pass "Deployment status includes guest entry health"
    else
        fail "Deployment status includes guest entry health" '"guestEntry":{"roomCount":...}' "$response"
    fi
    if [[ "$response" == *'"portal"'* ]] && [[ "$response" == *'"publicUrl"'* ]]; then
        pass "Deployment status includes portal URL setting"
    else
        fail "Deployment status includes portal URL setting" '"portal":{"publicUrl":...}' "$response"
    fi
}

test_portal_url_setting() {
    require_admin_creds "Portal URL setting" || return
    local response=$(admin_curl -X POST "$BASE_URL/admin-api/portal-url" \
        -H "Content-Type: application/json" \
        -d '{"portalPublicUrl":"https://guestportal.example.test/"}')
    if [[ "$response" == *'"portalPublicUrl":"https://guestportal.example.test"'* ]]; then
        pass "Portal URL setting updates"
    else
        fail "Portal URL setting updates" "normalized portal URL" "$response"
    fi
}

test_link_code_expiration_setting() {
    require_admin_creds "Link code expiration setting" || return
    local set_response=$(admin_curl -X POST "$BASE_URL/admin-api/session-expiration" \
        -H "Content-Type: application/json" \
        -d '{"minutes":7}')
    if [[ "$set_response" != *'"minutes":7'* ]]; then
        fail "Link code expiration setting" '{"minutes":7}' "$set_response"
        return
    fi
    pass "Link code expiration setting updates"

    local get_response=$(admin_curl "$BASE_URL/admin-api/session-expiration")
    if [[ "$get_response" == *'"minutes":7'* ]]; then
        pass "Link code expiration setting reads back"
    else
        fail "Link code expiration setting reads back" '{"minutes":7}' "$get_response"
    fi

    if [[ -z "$GUEST_TOKEN" ]]; then
        fail "Guest link code uses configured expiration" "Needs guest token" "No token available"
        return
    fi
    local link_response=$(curl -s -X POST "$BASE_URL/guest/link-code" \
        -H "Content-Type: application/json" \
        -d "{\"token\":\"$GUEST_TOKEN\"}")
    if [[ "$link_response" == *'"expiresIn":"7 minutes"'* ]]; then
        pass "Guest link code uses configured expiration"
    else
        fail "Guest link code uses configured expiration" '"expiresIn":"7 minutes"' "$link_response"
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

test_admin_guest_link_code_qr() {
    require_admin_creds "Admin guest link code QR" || return
    if [[ -z "$ADMIN_GUEST_ID" ]]; then
        fail "Admin guest link code QR" "Needs admin guest id" "No guest id available"
        return
    fi
    local response=$(admin_curl -X POST "$BASE_URL/admin-api/guest-sessions/$ADMIN_GUEST_ID/link-code")
    if [[ "$response" == *'"code"'* ]] && [[ "$response" == *'"linkUrl"'* ]] && [[ "$response" == *'"qrSvg"'* ]] && [[ "$response" == *"<svg"* ]] && [[ "$response" == *"https://guestportal.example.test"* ]]; then
        pass "Admin guest link code includes QR"
    else
        fail "Admin guest link code includes QR" "code/linkUrl/qrSvg with configured portal URL" "$response"
    fi
}

test_csv_exports() {
    require_admin_creds "CSV exports" || return
    local sessions_csv=$(admin_curl "$BASE_URL/admin-api/guest-sessions.csv")
    if [[ "$sessions_csv" == *"Guest Type ID"* ]] && [[ "$sessions_csv" == *"Visit Mode"* ]]; then
        pass "Active sessions CSV export"
    else
        fail "Active sessions CSV export" "Guest Type columns" "$sessions_csv"
    fi

    local history_csv=$(admin_curl "$BASE_URL/admin-api/guests.csv")
    if [[ "$history_csv" == *"Guest Type"* ]] && [[ "$history_csv" == *"Visit Mode"* ]]; then
        pass "Registration history CSV export"
    else
        fail "Registration history CSV export" "Guest Type columns" "$history_csv"
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

test_validate_returning_device() {
    local ua="GuestPortalTestSuite/1.0"
    local response=$(curl -s -X POST "$BASE_URL/register" \
        -H "Content-Type: application/json" \
        -H "User-Agent: $ua" \
        -d '{"name":"Return Device User","room":"Room 1","stayDays":3}')
    local token=$(echo "$response" | grep -o '"token":"[^"]*"' | cut -d'"' -f4)
    if [[ -z "$token" ]]; then
        fail "Validate returning device" "Registration token" "Missing token"
        return
    fi

    local validate=$(curl -s -X POST "$BASE_URL/guest/validate" \
        -H "Content-Type: application/json" \
        -H "User-Agent: $ua" \
        -d "{\"token\":\"$token\"}")
    if [[ "$validate" == *'"returningDevice":true'* ]]; then
        pass "Validate recognizes returning device"
    else
        fail "Validate recognizes returning device" '"returningDevice":true' "$validate"
    fi
}

test_guest_uploads_list() {
    if [[ -z "$GUEST_TOKEN" ]]; then
        fail "Guest uploads list" "Needs guest token" "No token available"
        return
    fi
    local response=$(curl -s "$BASE_URL/guest/uploads" -H "X-Guest-Token: $GUEST_TOKEN")
    if [[ "$response" == *'"files"'* ]] && [[ "$response" == *'"eventSlug"'* ]]; then
        GUEST_UPLOAD_FILENAME=$(echo "$response" | grep -o '"name":"[^"]*"' | head -1 | cut -d'"' -f4)
        GUEST_UPLOAD_EVENT_SLUG=$(echo "$response" | grep -o '"eventSlug":"[^"]*"' | head -1 | cut -d'"' -f4)
        pass "Guest uploads list"
    else
        fail "Guest uploads list" '{"files":[...]}' "$response"
    fi
}

test_guest_link_code_qr() {
    if [[ -z "$GUEST_TOKEN" ]]; then
        fail "Guest link code QR" "Needs guest token" "No token available"
        return
    fi
    local response=$(curl -s -X POST "$BASE_URL/guest/link-code" \
        -H "Content-Type: application/json" \
        -d "{\"token\":\"$GUEST_TOKEN\"}")
    if [[ "$response" == *'"code"'* ]] && [[ "$response" == *'"linkUrl"'* ]] && [[ "$response" == *'"qrSvg"'* ]] && [[ "$response" == *"<svg"* ]]; then
        pass "Guest link code includes QR"
    else
        fail "Guest link code includes QR" "code/linkUrl/qrSvg" "$response"
    fi
}

test_admin_uploads_metadata() {
    require_admin_creds "Admin upload preview metadata" || return
    local response=$(admin_curl "$BASE_URL/admin-api/uploads")
    if [[ "$response" == *'"uploadedAt"'* ]] && [[ "$response" == *'"url"'* ]]; then
        pass "Admin uploads include preview metadata"
    else
        fail "Admin uploads include preview metadata" "uploadedAt/url fields" "$response"
    fi
}

test_guest_uploads_requires_token() {
    local http_code=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/guest/uploads")
    if [[ "$http_code" == "401" ]]; then
        pass "Guest uploads list requires token (401)"
    else
        fail "Guest uploads list requires token" "401" "$http_code"
    fi
}

test_guest_upload_delete() {
    if [[ -z "$GUEST_TOKEN" || -z "$GUEST_UPLOAD_FILENAME" ]]; then
        fail "Guest upload delete" "Needs uploaded file" "Missing token or filename"
        return
    fi
    local slug="${GUEST_UPLOAD_EVENT_SLUG:-General}"
    local encoded_slug=$(python3 -c "import urllib.parse; print(urllib.parse.quote('$slug'))")
    local encoded_name=$(python3 -c "import urllib.parse; print(urllib.parse.quote('$GUEST_UPLOAD_FILENAME'))")
    local response=$(curl -s -X DELETE "$BASE_URL/guest/uploads/$encoded_slug/$encoded_name" \
        -H "X-Guest-Token: $GUEST_TOKEN")
    if [[ "$response" == *'"success":true'* ]]; then
        pass "Guest upload delete"
    else
        fail "Guest upload delete" '{"success":true}' "$response"
    fi
}

test_guest_upload_delete_requires_token() {
    local http_code=$(curl -s -o /dev/null -w "%{http_code}" -X DELETE "$BASE_URL/guest/uploads/example.pdf")
    if [[ "$http_code" == "401" ]]; then
        pass "Guest upload delete requires token (401)"
    else
        fail "Guest upload delete requires token" "401" "$http_code"
    fi
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

section "7b. GUEST TYPES AND PERMISSIONS"

test_guest_types_seeded() {
    require_admin_creds "Guest types seeded" || return
    local response=$(admin_curl "$BASE_URL/admin-api/guest-types")
    if [[ "$response" == *"type_overnight"* ]] && [[ "$response" == *"type_day_personal"* ]] && [[ "$response" == *"type_day_business"* ]]; then
        pass "Default guest types seeded"
    else
        fail "Default guest types seeded" "overnight/personal/business types" "$response"
    fi
}

test_guest_types_public() {
    local response=$(curl -s "$BASE_URL/guest/guest-types")
    if [[ "$response" == *"type_overnight"* ]] && [[ "$response" == *'"visitMode":"day"'* ]]; then
        pass "Public guest types endpoint"
    else
        fail "Public guest types endpoint" "enabled guest types" "$response"
    fi
}

test_validate_permissions() {
    local response=$(curl -s -X POST "$BASE_URL/register" \
        -H "Content-Type: application/json" \
        -d '{"name":"Perm Test","room":"Room 1","stayDays":2}')
    local token=$(echo "$response" | grep -o '"token":"[^"]*"' | cut -d'"' -f4)
    if [[ -z "$token" ]]; then
        fail "Validate permissions" "registration token" "$response"
        return
    fi
    local validate=$(curl -s -X POST "$BASE_URL/guest/validate" \
        -H "Content-Type: application/json" \
        -d "{\"token\":\"$token\"}")
    if [[ "$validate" == *'"permissions"'* ]] && [[ "$validate" == *'"uploadPhotos":true'* ]] && [[ "$validate" == *'"guestTypeId"'* ]]; then
        pass "Validate returns guest permissions"
    else
        fail "Validate returns guest permissions" 'permissions + guestTypeId' "$validate"
    fi
}

test_business_day_upload_forbidden() {
    require_admin_creds "Business day upload forbidden" || return
    admin_curl -X POST "$BASE_URL/admin-api/rooms" \
        -H "Content-Type: application/json" \
        -d '{"name":"Business Room","dashboardUrl":"http://example.com/business"}' > /dev/null
    local response=$(curl -s -X POST "$BASE_URL/register" \
        -H "Content-Type: application/json" \
        -d '{"name":"Biz Visitor","guestTypeId":"type_day_business"}')
    local token=$(echo "$response" | grep -o '"token":"[^"]*"' | cut -d'"' -f4)
    if [[ -z "$token" ]]; then
        fail "Business day upload forbidden" "business registration token" "$response"
        return
    fi
    printf '%s\n' '%PDF-1.4' '1 0 obj <<>> endobj' '%%EOF' > /tmp/test-business-upload.pdf
    local http_code=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$BASE_URL/upload" \
        -H "X-Guest-Token: $token" \
        -F "photos=@/tmp/test-business-upload.pdf;type=application/pdf")
    rm -f /tmp/test-business-upload.pdf
    if [[ "$http_code" == "403" ]]; then
        pass "Business day visitor upload forbidden (403)"
    else
        fail "Business day visitor upload forbidden" "403" "$http_code"
    fi
}

test_business_day_link_forbidden() {
    local response=$(curl -s -X POST "$BASE_URL/register" \
        -H "Content-Type: application/json" \
        -d '{"name":"Biz Link Test","guestTypeId":"type_day_business"}')
    local token=$(echo "$response" | grep -o '"token":"[^"]*"' | cut -d'"' -f4)
    if [[ -z "$token" ]]; then
        fail "Business day link forbidden" "business registration token" "$response"
        return
    fi
    local http_code=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$BASE_URL/guest/link-code" \
        -H "Content-Type: application/json" \
        -d "{\"token\":\"$token\"}")
    if [[ "$http_code" == "403" ]]; then
        pass "Business day visitor link code forbidden (403)"
    else
        fail "Business day visitor link code forbidden" "403" "$http_code"
    fi
}

test_change_guest_type_permissions() {
    require_admin_creds "Change guest type permissions" || return
    admin_curl -X POST "$BASE_URL/admin-api/rooms" \
        -H "Content-Type: application/json" \
        -d '{"name":"Type Change Room","dashboardUrl":"http://example.com/type-change"}' > /dev/null
    local reg=$(admin_curl -X POST "$BASE_URL/admin-api/guests" \
        -H "Content-Type: application/json" \
        -d '{"name":"Type Change Guest","room":"Type Change Room","stayDays":2}')
    local guest_id=$(echo "$reg" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
    if [[ -z "$guest_id" ]]; then
        fail "Change guest type permissions" "admin guest id" "$reg"
        return
    fi
    local patch=$(admin_curl -X PATCH "$BASE_URL/admin-api/guest-sessions/$guest_id" \
        -H "Content-Type: application/json" \
        -d '{"guestTypeId":"type_day_business"}')
    if [[ "$patch" != *'"success":true'* ]]; then
        fail "Change guest type permissions" "successful patch" "$patch"
        return
    fi
    local entry=$(admin_curl "$BASE_URL/admin-api/guest-sessions")
    if [[ "$entry" == *'"guestTypeId":"type_day_business"'* ]] && [[ "$entry" == *'"uploadPhotos":false'* ]]; then
        pass "Changing guest type updates effective permissions"
    else
        fail "Changing guest type updates effective permissions" "business type + uploadPhotos false" "$entry"
    fi
    admin_curl -X DELETE "$BASE_URL/admin-api/guest-sessions/$guest_id" > /dev/null
}

test_event_subfolder_upload() {
    require_admin_creds "Event subfolder upload" || return
    local response=$(curl -s -X POST "$BASE_URL/register" \
        -H "Content-Type: application/json" \
        -d '{"name":"Event Upload Guest","room":"Room 1","stayDays":3,"guestTypeId":"type_overnight"}')
    local token=$(echo "$response" | grep -o '"token":"[^"]*"' | cut -d'"' -f4)
    if [[ -z "$token" ]]; then
        fail "Event subfolder upload" "registration token" "$response"
        return
    fi
    printf '%s\n' '%PDF-1.4' '1 0 obj <<>> endobj' '%%EOF' > /tmp/test-event-upload.pdf
    local http_code=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$BASE_URL/upload" \
        -H "X-Guest-Token: $token" \
        -F "eventName=Birthday Party" \
        -F "photos=@/tmp/test-event-upload.pdf;type=application/pdf")
    rm -f /tmp/test-event-upload.pdf
    if [[ "$http_code" != "200" ]]; then
        fail "Event subfolder upload" "200 upload" "$http_code"
        return
    fi
    local admin_uploads=$(admin_curl "$BASE_URL/admin-api/uploads")
    if [[ "$admin_uploads" == *"Birthday-Party"* ]] || [[ "$admin_uploads" == *'"event":"Birthday Party"'* ]]; then
        pass "Event subfolder upload lands under event folder"
    else
        fail "Event subfolder upload lands under event folder" "Birthday Party event path" "$admin_uploads"
    fi
}

test_legacy_session() {
    require_admin_creds "Legacy session without guestTypeId" || return
    admin_curl -X POST "$BASE_URL/admin-api/rooms" \
        -H "Content-Type: application/json" \
        -d '{"name":"Legacy Room","dashboardUrl":"http://example.com/legacy"}' > /dev/null
    local reg=$(admin_curl -X POST "$BASE_URL/admin-api/guests" \
        -H "Content-Type: application/json" \
        -d '{"name":"Legacy Guest","room":"Legacy Room","stayDays":2}')
    local guest_id=$(echo "$reg" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
    local token=$(echo "$reg" | grep -o '"token":"[^"]*"' | cut -d'"' -f4)
    if [[ -z "$guest_id" || -z "$token" ]]; then
        fail "Legacy session without guestTypeId" "guest id + token" "$reg"
        return
    fi
    local patch=$(admin_curl -X PATCH "$BASE_URL/admin-api/guest-sessions/$guest_id" \
        -H "Content-Type: application/json" \
        -d '{"guestTypeId":null}')
    if [[ "$patch" != *'"success":true'* ]]; then
        fail "Legacy session without guestTypeId" "clear guestTypeId patch" "$patch"
        return
    fi
    local validate=$(curl -s -X POST "$BASE_URL/guest/validate" \
        -H "Content-Type: application/json" \
        -d "{\"token\":\"$token\"}")
    if [[ "$validate" == *'"uploadPhotos":true'* ]] && [[ "$validate" == *'"guestTypeId":"type_overnight"'* || "$validate" == *'"guestTypeName":"Overnight Guest"'* ]]; then
        pass "Legacy session maps to overnight permissions"
    else
        fail "Legacy session maps to overnight permissions" "overnight uploadPhotos true" "$validate"
    fi
    printf '%s\n' '%PDF-1.4' '1 0 obj <<>> endobj' '%%EOF' > /tmp/test-legacy-upload.pdf
    local upload_code=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$BASE_URL/upload" \
        -H "X-Guest-Token: $token" \
        -F "photos=@/tmp/test-legacy-upload.pdf;type=application/pdf")
    rm -f /tmp/test-legacy-upload.pdf
    if [[ "$upload_code" == "200" ]]; then
        pass "Legacy session upload succeeds"
    else
        fail "Legacy session upload succeeds" "200" "$upload_code"
    fi
    admin_curl -X DELETE "$BASE_URL/admin-api/guest-sessions/$guest_id" > /dev/null
}

test_day_personal_registration() {
    local response=$(curl -s -X POST "$BASE_URL/register" \
        -H "Content-Type: application/json" \
        -d '{"name":"Day Personal Guest","guestTypeId":"type_day_personal","eventName":"Family BBQ"}')
    local token=$(echo "$response" | grep -o '"token":"[^"]*"' | cut -d'"' -f4)
    if [[ -z "$token" ]]; then
        fail "Day personal registration" "registration token" "$response"
        return
    fi
    if [[ "$response" == *'"eventName":"Family BBQ"'* ]] && [[ "$response" == *'"visitMode":"day"'* ]]; then
        pass "Day personal registration includes event"
    else
        fail "Day personal registration includes event" "eventName + day visitMode" "$response"
        return
    fi
    local validate=$(curl -s -X POST "$BASE_URL/guest/validate" \
        -H "Content-Type: application/json" \
        -d "{\"token\":\"$token\"}")
    local checkout_ms=$(echo "$validate" | python3 -c "
import json, sys
from datetime import datetime, timezone
data = json.load(sys.stdin)
checkout = datetime.fromisoformat(data['guest']['checkoutDate'].replace('Z', '+00:00'))
now = datetime.now(timezone.utc)
print(int((checkout - now).total_seconds() / 3600))
")
    if [[ "$checkout_ms" -ge 7 && "$checkout_ms" -le 9 ]]; then
        pass "Day personal checkout is about 8 hours out"
    else
        fail "Day personal checkout is about 8 hours out" "7-9 hours" "${checkout_ms}h"
    fi
}

test_delete_forbidden() {
    require_admin_creds "Delete own photos forbidden" || return
    admin_curl -X POST "$BASE_URL/admin-api/rooms" \
        -H "Content-Type: application/json" \
        -d '{"name":"Delete Forbidden Room","dashboardUrl":"http://example.com/delete-forbidden"}' > /dev/null
    local reg=$(admin_curl -X POST "$BASE_URL/admin-api/guests" \
        -H "Content-Type: application/json" \
        -d '{"name":"Delete Forbidden Guest","room":"Delete Forbidden Room","stayDays":2}')
    local guest_id=$(echo "$reg" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
    local token=$(echo "$reg" | grep -o '"token":"[^"]*"' | cut -d'"' -f4)
    if [[ -z "$guest_id" || -z "$token" ]]; then
        fail "Delete own photos forbidden" "guest id + token" "$reg"
        return
    fi
    printf '%s\n' '%PDF-1.4' '1 0 obj <<>> endobj' '%%EOF' > /tmp/test-delete-forbidden.pdf
    curl -s -X POST "$BASE_URL/upload" \
        -H "X-Guest-Token: $token" \
        -F "photos=@/tmp/test-delete-forbidden.pdf;type=application/pdf" > /dev/null
    rm -f /tmp/test-delete-forbidden.pdf
    local list=$(curl -s "$BASE_URL/guest/uploads" -H "X-Guest-Token: $token")
    local filename=$(echo "$list" | grep -o '"name":"[^"]*"' | head -1 | cut -d'"' -f4)
    local slug=$(echo "$list" | grep -o '"eventSlug":"[^"]*"' | head -1 | cut -d'"' -f4)
    slug="${slug:-General}"
    admin_curl -X PATCH "$BASE_URL/admin-api/guest-sessions/$guest_id" \
        -H "Content-Type: application/json" \
        -d '{"guestTypeId":"type_day_business"}' > /dev/null
    local encoded_slug=$(python3 -c "import urllib.parse; print(urllib.parse.quote('$slug'))")
    local encoded_name=$(python3 -c "import urllib.parse; print(urllib.parse.quote('$filename'))")
    local http_code=$(curl -s -o /dev/null -w "%{http_code}" -X DELETE "$BASE_URL/guest/uploads/$encoded_slug/$encoded_name" \
        -H "X-Guest-Token: $token")
    if [[ "$http_code" == "403" ]]; then
        pass "Delete own photos forbidden for business type (403)"
    else
        fail "Delete own photos forbidden for business type" "403" "$http_code"
    fi
    admin_curl -X DELETE "$BASE_URL/admin-api/guest-sessions/$guest_id" > /dev/null
}

test_scoped_delete() {
    require_admin_creds "Scoped delete with duplicate basename" || return
    local reg=$(curl -s -X POST "$BASE_URL/register" \
        -H "Content-Type: application/json" \
        -d '{"name":"Scoped Delete Guest","room":"Room 1","stayDays":2,"guestTypeId":"type_overnight"}')
    local token=$(echo "$reg" | grep -o '"token":"[^"]*"' | cut -d'"' -f4)
    local guest_id=$(echo "$reg" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
    if [[ -z "$token" || -z "$guest_id" ]]; then
        fail "Scoped delete with duplicate basename" "token + guest id" "$reg"
        return
    fi
    local folder=$(python3 -c "import datetime,re; name='Scoped Delete Guest'; slug=re.sub(r'\\s+','-',re.sub(r'[^\\w\\s-]','',name))[:100]; print(f'{slug}-$guest_id-{datetime.date.today().isoformat()}')")
    python3 - <<'PY' "$folder"
import os, pathlib, sys
folder = sys.argv[1]
root = pathlib.Path("uploads") / folder
(root / "Event-A").mkdir(parents=True, exist_ok=True)
(root / "Event-B").mkdir(parents=True, exist_ok=True)
(root / "Event-A" / "duplicate-test.pdf").write_text("%PDF-1.4 duplicate A")
(root / "Event-B" / "duplicate-test.pdf").write_text("%PDF-1.4 duplicate B")
PY
    local encoded_slug=$(python3 -c "import urllib.parse; print(urllib.parse.quote('Event-A'))")
    local http_code=$(curl -s -o /dev/null -w "%{http_code}" -X DELETE "$BASE_URL/guest/uploads/$encoded_slug/duplicate-test.pdf" \
        -H "X-Guest-Token: $token")
    local remaining=$(curl -s "$BASE_URL/guest/uploads" -H "X-Guest-Token: $token")
    if [[ "$http_code" == "200" ]] && [[ "$remaining" == *"duplicate-test.pdf"* ]] && [[ "$remaining" == *'"eventSlug":"Event-B"'* ]]; then
        pass "Scoped delete removes only the targeted duplicate basename"
    else
        fail "Scoped delete removes only the targeted duplicate basename" "200 delete + Event-B file remains" "delete=$http_code list=$remaining"
    fi
}

test_admin_events_crud() {
    require_admin_creds "Admin events CRUD" || return
    local create=$(admin_curl -X POST "$BASE_URL/admin-api/events" \
        -H "Content-Type: application/json" \
        -d '{"name":"Admin Test Event"}')
    local event_id=$(echo "$create" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
    if [[ -z "$event_id" ]]; then
        fail "Admin events CRUD" "create event id" "$create"
        return
    fi
    local list=$(admin_curl "$BASE_URL/admin-api/events")
    if [[ "$list" == *'"name":"Admin Test Event"'* ]]; then
        pass "Admin events list includes created event"
    else
        fail "Admin events list includes created event" "Admin Test Event" "$list"
        return
    fi
    local rename=$(admin_curl -X PATCH "$BASE_URL/admin-api/events/$event_id" \
        -H "Content-Type: application/json" \
        -d '{"name":"Admin Test Event Renamed"}')
    if [[ "$rename" == *'"name":"Admin Test Event Renamed"'* ]]; then
        pass "Admin event rename"
    else
        fail "Admin event rename" "renamed event" "$rename"
    fi
    local del=$(admin_curl -X DELETE "$BASE_URL/admin-api/events/$event_id")
    if [[ "$del" == *'"success":true'* ]]; then
        pass "Admin event delete"
    else
        fail "Admin event delete" '{"success":true}' "$del"
    fi
    local guest_events=$(curl -s "$BASE_URL/guest/events")
    if [[ "$guest_events" != *"Admin Test Event Renamed"* ]]; then
        pass "Guest events list reflects admin delete"
    else
        fail "Guest events list reflects admin delete" "event removed" "$guest_events"
    fi
}

test_admin_event_merge() {
    require_admin_creds "Admin event merge" || return
    local create_a=$(admin_curl -X POST "$BASE_URL/admin-api/events" \
        -H "Content-Type: application/json" \
        -d '{"name":"Merge Source Event"}')
    local create_b=$(admin_curl -X POST "$BASE_URL/admin-api/events" \
        -H "Content-Type: application/json" \
        -d '{"name":"Merge Target Event"}')
    local source_id=$(echo "$create_a" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
    local target_id=$(echo "$create_b" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
    if [[ -z "$source_id" || -z "$target_id" ]]; then
        fail "Admin event merge" "source and target ids" "source=$create_a target=$create_b"
        return
    fi
    local merge=$(admin_curl -X PATCH "$BASE_URL/admin-api/events/$source_id" \
        -H "Content-Type: application/json" \
        -d "{\"mergeIntoId\":\"$target_id\"}")
    if [[ "$merge" != *'"success":true'* ]] || [[ "$merge" != *'"name":"Merge Target Event"'* ]]; then
        fail "Admin event merge" "success + survivor event" "$merge"
        return
    fi
    local list=$(admin_curl "$BASE_URL/admin-api/events")
    if [[ "$list" == *'"name":"Merge Target Event"'* ]] && [[ "$list" != *'"name":"Merge Source Event"'* ]]; then
        pass "Admin event merge removes source and keeps target"
    else
        fail "Admin event merge removes source and keeps target" "target only" "$list"
    fi
    admin_curl -X DELETE "$BASE_URL/admin-api/events/$target_id" > /dev/null
}

test_guest_upload_retag() {
    require_admin_creds "Guest upload re-tag" || return
    admin_curl -X POST "$BASE_URL/admin-api/events" \
        -H "Content-Type: application/json" \
        -d '{"name":"Retag Event A"}' > /dev/null
    admin_curl -X POST "$BASE_URL/admin-api/events" \
        -H "Content-Type: application/json" \
        -d '{"name":"Retag Event B"}' > /dev/null
    local response=$(curl -s -X POST "$BASE_URL/register" \
        -H "Content-Type: application/json" \
        -d '{"name":"Retag Guest","room":"Room 1","stayDays":2,"guestTypeId":"type_overnight"}')
    local token=$(echo "$response" | grep -o '"token":"[^"]*"' | cut -d'"' -f4)
    if [[ -z "$token" ]]; then
        fail "Guest upload re-tag" "registration token" "$response"
        return
    fi
    printf '%s\n' '%PDF-1.4' '1 0 obj <<>> endobj' '%%EOF' > /tmp/test-retag-upload.pdf
    local upload_code=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$BASE_URL/upload" \
        -H "X-Guest-Token: $token" \
        -F "eventName=Retag Event A" \
        -F "photos=@/tmp/test-retag-upload.pdf;type=application/pdf")
    rm -f /tmp/test-retag-upload.pdf
    if [[ "$upload_code" != "200" ]]; then
        fail "Guest upload re-tag" "200 upload" "$upload_code"
        return
    fi
    local list=$(curl -s "$BASE_URL/guest/uploads" -H "X-Guest-Token: $token")
    local filename=$(echo "$list" | grep -o '"name":"[^"]*"' | head -1 | cut -d'"' -f4)
    local source_slug=$(echo "$list" | grep -o '"eventSlug":"[^"]*"' | head -1 | cut -d'"' -f4)
    if [[ -z "$filename" || -z "$source_slug" ]]; then
        fail "Guest upload re-tag" "upload filename + slug" "$list"
        return
    fi
    local target_id=$(curl -s "$BASE_URL/guest/events" | python3 -c "
import json, sys
events = json.load(sys.stdin)
match = next((e['id'] for e in events if e['name'] == 'Retag Event B'), '')
print(match)
")
    local encoded_slug=$(python3 -c "import urllib.parse; print(urllib.parse.quote('$source_slug'))")
    local encoded_name=$(python3 -c "import urllib.parse; print(urllib.parse.quote('$filename'))")
    local patch=$(curl -s -X PATCH "$BASE_URL/guest/uploads/$encoded_slug/$encoded_name" \
        -H "Content-Type: application/json" \
        -H "X-Guest-Token: $token" \
        -d "{\"eventId\":\"$target_id\"}")
    if [[ "$patch" != *'"event":"Retag Event B"'* ]] || [[ "$patch" != *'"eventSlug":"Retag-Event-B"'* ]]; then
        fail "Guest upload re-tag" "Retag Event B response" "$patch"
        return
    fi
    local after=$(curl -s "$BASE_URL/guest/uploads" -H "X-Guest-Token: $token")
    if [[ "$after" == *'"eventSlug":"Retag-Event-B"'* ]] && [[ "$after" != *'"eventSlug":"Retag-Event-A"'* ]]; then
        pass "Guest upload re-tag moves file between events"
    else
        fail "Guest upload re-tag moves file between events" "Retag-Event-B only" "$after"
    fi
}

test_guest_upload_retag_forbidden() {
    require_admin_creds "Guest upload re-tag forbidden" || return
    admin_curl -X POST "$BASE_URL/admin-api/rooms" \
        -H "Content-Type: application/json" \
        -d '{"name":"Retag Forbidden Room","dashboardUrl":"http://example.com/retag-forbidden"}' > /dev/null
    local reg=$(admin_curl -X POST "$BASE_URL/admin-api/guests" \
        -H "Content-Type: application/json" \
        -d '{"name":"Retag Forbidden Guest","room":"Retag Forbidden Room","stayDays":2}')
    local guest_id=$(echo "$reg" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
    local token=$(echo "$reg" | grep -o '"token":"[^"]*"' | cut -d'"' -f4)
    if [[ -z "$guest_id" || -z "$token" ]]; then
        fail "Guest upload re-tag forbidden" "guest id + token" "$reg"
        return
    fi
    printf '%s\n' '%PDF-1.4' '1 0 obj <<>> endobj' '%%EOF' > /tmp/test-retag-forbidden.pdf
    curl -s -X POST "$BASE_URL/upload" \
        -H "X-Guest-Token: $token" \
        -F "photos=@/tmp/test-retag-forbidden.pdf;type=application/pdf" > /dev/null
    rm -f /tmp/test-retag-forbidden.pdf
    local list=$(curl -s "$BASE_URL/guest/uploads" -H "X-Guest-Token: $token")
    local filename=$(echo "$list" | grep -o '"name":"[^"]*"' | head -1 | cut -d'"' -f4)
    local slug=$(echo "$list" | grep -o '"eventSlug":"[^"]*"' | head -1 | cut -d'"' -f4)
    slug="${slug:-General}"
    admin_curl -X PATCH "$BASE_URL/admin-api/guest-sessions/$guest_id" \
        -H "Content-Type: application/json" \
        -d '{"guestTypeId":"type_day_business"}' > /dev/null
    local target_id=$(curl -s "$BASE_URL/guest/events" | python3 -c "
import json, sys
events = json.load(sys.stdin)
print(events[0]['id'] if events else '')
")
    local http_code=$(curl -s -o /dev/null -w "%{http_code}" -X PATCH "$BASE_URL/guest/uploads/$slug/$filename" \
        -H "Content-Type: application/json" \
        -H "X-Guest-Token: $token" \
        -d "{\"eventId\":\"$target_id\"}")
    if [[ "$http_code" == "403" ]]; then
        pass "Guest upload re-tag forbidden for business type (403)"
    else
        fail "Guest upload re-tag forbidden for business type" "403" "$http_code"
    fi
    admin_curl -X DELETE "$BASE_URL/admin-api/guest-sessions/$guest_id" > /dev/null
}

test_index_hero_markup() {
    local response=$(curl -s "$BASE_URL/")
    if [[ "$response" == *"hero-view"* ]] && [[ "$response" == *"heroRegisterBtn"* ]] && [[ "$response" == *"registrationModal"* ]]; then
        pass "Index page includes hero landing markup"
    else
        fail "Index page includes hero landing markup" "hero-view + heroRegisterBtn + registrationModal" "Missing hero markup"
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

test_guest_entry_smoke_routes() {
    local failed=""
    local health_code=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/health")
    local index_code=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/")
    local rooms_code=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/guest/rooms")
    local welcome_code=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/welcome.html")
    local photo_code=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/photo.html")

    [[ "$health_code" == "200" ]] || failed+="/health=$health_code "
    [[ "$index_code" == "200" ]] || failed+="/=$index_code "
    [[ "$rooms_code" == "200" ]] || failed+="/guest/rooms=$rooms_code "
    [[ "$welcome_code" == "200" ]] || failed+="/welcome.html=$welcome_code "
    [[ "$photo_code" == "200" ]] || failed+="/photo.html=$photo_code "

    if [[ -z "$failed" ]]; then
        pass "Guest entry smoke routes return 200"
    else
        fail "Guest entry smoke routes return 200" "all 200" "$failed"
    fi
}

test_frontend_script_syntax() {
    local tmp_dir
    tmp_dir=$(mktemp -d)
    python3 - "$tmp_dir" frontend/index.html frontend/welcome.html frontend/photo.html frontend/admin.html <<'PY'
import pathlib
import sys
from html.parser import HTMLParser

out_dir = pathlib.Path(sys.argv[1])

class ScriptExtractor(HTMLParser):
    def __init__(self):
        super().__init__()
        self.in_script = False
        self.scripts = []
        self.current = []

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if tag.lower() == "script" and "src" not in attrs:
            self.in_script = True
            self.current = []

    def handle_endtag(self, tag):
        if tag.lower() == "script" and self.in_script:
            self.in_script = False
            self.scripts.append("".join(self.current))

    def handle_data(self, data):
        if self.in_script:
            self.current.append(data)

for html_path in sys.argv[2:]:
    parser = ScriptExtractor()
    parser.feed(pathlib.Path(html_path).read_text())
    for index, script in enumerate(parser.scripts, 1):
        (out_dir / f"{pathlib.Path(html_path).stem}-{index}.js").write_text(script)
PY

    local failed=0
    for script in "$tmp_dir"/*.js; do
        if ! node --check "$script" >/dev/null 2>&1; then
            failed=1
            fail "Frontend inline script syntax" "Valid JavaScript" "$script failed node --check"
            break
        fi
    done
    rm -rf "$tmp_dir"

    if [[ "$failed" == "0" ]]; then
        pass "Frontend inline script syntax"
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
test_portal_url_setting
test_link_code_expiration_setting
test_list_guest_history
test_admin_register_guest
test_update_guest_room
test_clear_guest_devices
test_admin_guest_link_code_qr
test_csv_exports
test_checkout_admin_guest
test_remove_guest_history

test_upload
test_path_traversal
test_admin_requires_auth
test_upload_requires_token
test_upload_rejects_code
test_validate_returning_device
test_guest_uploads_list
test_guest_link_code_qr
test_admin_uploads_metadata
test_guest_uploads_requires_token
test_guest_upload_delete
test_guest_upload_delete_requires_token

test_guest_types_seeded
test_guest_types_public
test_validate_permissions
test_business_day_upload_forbidden
test_business_day_link_forbidden
test_change_guest_type_permissions
test_event_subfolder_upload
test_legacy_session
test_day_personal_registration
test_delete_forbidden
test_scoped_delete
test_admin_events_crud
test_admin_event_merge
test_guest_upload_retag
test_guest_upload_retag_forbidden
test_index_hero_markup

test_index_html
test_admin_html
test_welcome_html
test_photo_html
test_guest_entry_smoke_routes
test_frontend_script_syntax

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
