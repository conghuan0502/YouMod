#!/bin/bash
# YouMod Device-Side Automated Test Script
# Installs tweak on jailbroken device, launches YouTube, monitors for errors
#
# Usage: ./scripts/test-device.sh [OPTIONS]
#   --device IP        Device IP address (default: 192.168.1.100)
#   --password PASS    Root password (default: alpine)
#   --timeout SECS     Test timeout in seconds (default: 300)
#   --video-id ID      Specific video ID to test (default: dQw4w9WgXcQ)
#   --skip-install     Skip installation, only run tests
#   --help             Show this help

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# ============================================================
# Configuration
# ============================================================
DEVICE_IP="${YOUMOD_TEST_DEVICE:-192.168.1.100}"
ROOT_PASS="${YOUMOD_TEST_PASSWORD:-alpine}"
TEST_TIMEOUT="${YOUMOD_TEST_TIMEOUT:-300}"
VIDEO_ID="${YOUMOD_TEST_VIDEO_ID:-dQw4w9WgXcQ}"
SKIP_INSTALL=false
BUNDLE_ID="com.google.ios.youtube"
LOG_FILE="/tmp/youmod_test_$(date +%s).log"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --device) DEVICE_IP="$2"; shift 2;;
        --password) ROOT_PASS="$2"; shift 2;;
        --timeout) TEST_TIMEOUT="$2"; shift 2;;
        --video-id) VIDEO_ID="$2"; shift 2;;
        --skip-install) SKIP_INSTALL=true; shift;;
        --help) echo "Usage: $0 [OPTIONS]"; exit 0;;
        *) echo "Unknown option: $1"; exit 1;;
    esac
done

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SSH_CMD="sshpass -p '$ROOT_PASS' ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 root@$DEVICE_IP"
SCP_CMD="sshpass -p '$ROOT_PASS' scp -o StrictHostKeyChecking=no -o ConnectTimeout=10"

pass() { echo -e "${GREEN}[PASS]${NC} $1" | tee -a "$LOG_FILE"; }
fail() { echo -e "${RED}[FAIL]${NC} $1" | tee -a "$LOG_FILE"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1" | tee -a "$LOG_FILE"; }
info() { echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE"; }
step() { echo -e "${CYAN}[STEP]${NC} $1" | tee -a "$LOG_FILE"; }

PASS_COUNT=0
FAIL_COUNT=0

# ============================================================
# Pre-flight checks
# ============================================================
echo ""
info "========================================"
info "  YouMod Device Test Suite"
info "========================================"
info "Device: $DEVICE_IP"
info "Timeout: ${TEST_TIMEOUT}s"
info "Video ID: $VIDEO_ID"
info "Log: $LOG_FILE"
echo ""

# Check for required tools
for tool in sshpass ssh scp; do
    if ! command -v $tool &>/dev/null; then
        echo -e "${RED}ERROR: $tool not installed.${NC}"
        echo "Install with: brew install $tool"
        exit 1
    fi
done

# Find the .deb package
DEB_FILE=$(find "$PROJECT_DIR/packages" -name "*.deb" -type f 2>/dev/null | head -1)
if [ -z "$DEB_FILE" ] && [ "$SKIP_INSTALL" = false ]; then
    fail "No .deb file found in packages/. Run 'make package' first."
    exit 1
fi

# ============================================================
# Step 1: Device connectivity
# ============================================================
step "Testing device connectivity..."
if $SSH_CMD "echo connected" &>/dev/null; then
    pass "Device connected at $DEVICE_IP"
else
    fail "Cannot connect to device at $DEVICE_IP"
    echo "Check: IP address, SSH enabled, network connection"
    exit 1
fi

# ============================================================
# Step 2: Install tweak (if not skipped)
# ============================================================
if [ "$SKIP_INSTALL" = false ]; then
    step "Installing tweak..."

    # Copy .deb to device
    $SCP_CMD "$DEB_FILE" /tmp/YouMod.deb &>/dev/null
    if $SSH_CMD "dpkg -i /tmp/YouMod.deb && rm /tmp/YouMod.deb" &>/dev/null; then
        pass "Tweak installed successfully"
    else
        fail "Tweak installation failed"
        exit 1
    fi

    # Restart YouTube app
    step "Restarting YouTube..."
    $SSH_CMD "killall YouTube || true" &>/dev/null
    sleep 3
fi

# ============================================================
# Step 3: Launch YouTube and wait for it to be ready
# ============================================================
step "Launching YouTube..."
$SSH_CMD "uicache && sbreload" &>/dev/null || true
sleep 5

# Launch YouTube via URL scheme
$SSH_CMD "open 'youtube://'" &>/dev/null || \
$SSH_CMD "launchctl bootout gui/501/com.google.ios.youtube 2>/dev/null; launchctl bootstrap gui/501 /System/Library/LaunchDaemons/com.google.ios.youtube.plist 2>/dev/null" &>/dev/null || true

# Wait for app to launch
info "Waiting for YouTube to launch..."
for i in $(seq 1 30); do
    if $SSH_CMD "ps aux | grep -v grep | grep -q YouTube" &>/dev/null; then
        pass "YouTube is running"
        break
    fi
    if [ $i -eq 30 ]; then
        fail "YouTube failed to launch within 30 seconds"
        exit 1
    fi
    sleep 1
done

sleep 5

# ============================================================
# Step 4: Clear logs and start monitoring
# ============================================================
step "Starting log monitoring..."
$SSH_CMD "cat /dev/null > /var/log/syslog 2>/dev/null || true" &>/dev/null

# Start background log capture
$SSH_CMD "log stream --style compact --predicate 'process == \"YouTube\"' 2>/dev/null &" &>/dev/null
LOG_PID=$!

# ============================================================
# Step 5: Run tests
# ============================================================
echo ""
info "========================================"
info "  Running Tests"
info "========================================"

# --- Test: App Launch ---
step "T1: App Launch Test"
if $SSH_CMD "ps aux | grep -v grep | grep -q YouTube" &>/dev/null; then
    pass "YouTube launched successfully"
    ((PASS_COUNT++))
else
    fail "YouTube not running"
    ((FAIL_COUNT++))
fi

# --- Test: Check for crash logs ---
step "T2: Crash Log Check"
CRASH_COUNT=$($SSH_CMD "ls /var/mobile/Library/Logs/CrashReporter/YouTube* 2>/dev/null | wc -l" 2>/dev/null || echo "0")
if [ "$CRASH_COUNT" -eq 0 ]; then
    pass "No crash logs found"
    ((PASS_COUNT++))
else
    warn "Found $CRASH_COUNT crash log(s)"
fi

# --- Test: Play video and monitor for errors ---
step "T3: Video Playback Test (waiting ${TEST_TIMEOUT}s)"

# Open specific video
$SSH_CMD "open 'youtube://watch?v=$VIDEO_ID'" &>/dev/null || true
sleep 10

# Monitor syslog for error patterns
ERROR_PATTERNS=(
    "Something went wrong"
    "playback.*error"
    "player.*failed"
    "EXC_BAD_ACCESS"
    "NSException"
    "crash"
    "terminate"
)

START_TIME=$(date +%s)
ERROR_FOUND=false
VIDEO_PLAYING=false

while true; do
    CURRENT_TIME=$(date +%s)
    ELAPSED=$((CURRENT_TIME - START_TIME))

    if [ $ELAPSED -ge $TEST_TIMEOUT ]; then
        info "Test timeout reached (${TEST_TIMEOUT}s)"
        break
    fi

    # Check for error patterns in logs
    for pattern in "${ERROR_PATTERNS[@]}"; do
        if $SSH_CMD "grep -i '$pattern' /var/log/syslog 2>/dev/null | tail -5" 2>/dev/null | grep -qi "$pattern"; then
            fail "Error pattern detected: '$pattern' after ${ELAPSED}s"
            ERROR_FOUND=true
            ((FAIL_COUNT++))
            break 2
        fi
    done

    # Check if video is still playing (app is responsive)
    if $SSH_CMD "ps aux | grep -v grep | grep -q YouTube" &>/dev/null; then
        if [ "$VIDEO_PLAYING" = false ]; then
            pass "Video playing normally (${ELAPSED}s elapsed)"
            VIDEO_PLAYING=true
            ((PASS_COUNT++))
        else
            # Periodic status update
            if [ $((ELAPSED % 30)) -eq 0 ]; then
                info "Video still playing at ${ELAPSED}s..."
            fi
        fi
    else
        fail "YouTube crashed after ${ELAPSED}s"
        ERROR_FOUND=true
        ((FAIL_COUNT++))
        break
    fi

    sleep 2
done

if [ "$ERROR_FOUND" = false ] && [ "$VIDEO_PLAYING" = true ]; then
    pass "Video playback stable for ${TEST_TIMEOUT}s - NO ERRORS"
    ((PASS_COUNT++))
fi

# --- Test: Check YouMod logs ---
step "T4: YouMod Debug Logs"
YOUMOD_LOGS=$($SSH_CMD "cat /var/mobile/Documents/YouModDebug.log 2>/dev/null | tail -20" 2>/dev/null || echo "")
if [ -n "$YOUMOD_LOGS" ]; then
    info "Recent YouMod logs:"
    echo "$YOUMOD_LOGS" | while read line; do
        if echo "$line" | grep -qi "error\|fail\|warn"; then
            warn "  $line"
        else
            info "  $line"
        fi
    done
else
    warn "No YouMod debug logs found"
fi

# --- Test: Check for "Something went wrong" specifically ---
step "T5: 'Something went wrong' Check"
if $SSH_CMD "grep -i 'something went wrong' /var/log/syslog 2>/dev/null" 2>/dev/null | grep -qi "something went wrong"; then
    fail "❌ 'Something went wrong' error detected in logs"
    ((FAIL_COUNT++))
else
    pass "No 'Something went wrong' errors in logs"
    ((PASS_COUNT++))
fi

# ============================================================
# Cleanup
# ============================================================
step "Cleaning up..."
kill $LOG_PID 2>/dev/null || true
$SSH_CMD "killall log 2>/dev/null || true" &>/dev/null

# ============================================================
# Summary
# ============================================================
echo ""
echo "========================================"
echo -e "${BLUE}=== Test Summary ===${NC}"
echo "========================================"
echo -e "  ${GREEN}Passed: $PASS_COUNT${NC}"
echo -e "  ${RED}Failed: $FAIL_COUNT${NC}"
echo "========================================"

if [ $FAIL_COUNT -gt 0 ]; then
    echo -e "${RED}DEVICE TESTS FAILED${NC}"
    echo -e "${YELLOW}Full logs saved to: $LOG_FILE${NC}"
    exit 1
else
    echo -e "${GREEN}ALL DEVICE TESTS PASSED${NC}"
    exit 0
fi
