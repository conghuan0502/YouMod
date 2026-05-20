#!/bin/bash
# YouMod Automated Test Runner
# Builds the project, validates the package, and optionally tests on device
#
# Usage: ./scripts/test.sh [OPTIONS]
#   --device IP        Device IP for remote testing
#   --password PASS    Device root password
#   --timeout SECS     Playback test duration (default: 300)
#   --no-build         Skip build, use existing packages
#   --device-only      Only run device tests
#   --build-only       Only run build validation
#   --video-id ID      Video ID to test
#   --all              Run all tests including device
#   --help             Show this help

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Load configuration
source "$SCRIPT_DIR/test-config.sh" 2>/dev/null || true

# Parse arguments
RUN_BUILD=true
RUN_DEVICE=false
BUILD_ONLY=false
DEVICE_ONLY=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --device) YOUMOD_TEST_DEVICE="$2"; shift 2;;
        --password) YOUMOD_TEST_PASSWORD="$2"; shift 2;;
        --timeout) YOUMOD_TEST_TIMEOUT="$2"; shift 2;;
        --video-id) YOUMOD_TEST_VIDEO_ID="$2"; shift 2;;
        --no-build) RUN_BUILD=false; shift;;
        --device-only) DEVICE_ONLY=true; RUN_BUILD=false; shift;;
        --build-only) BUILD_ONLY=true; RUN_DEVICE=false; shift;;
        --all) RUN_DEVICE=true; shift;;
        --help)
            echo -e "${BOLD}YouMod Test Runner${NC}"
            echo ""
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --device IP        Device IP for remote testing"
            echo "  --password PASS    Device root password (default: alpine)"
            echo "  --timeout SECS     Playback test duration (default: 300)"
            echo "  --video-id ID      Video ID to test (default: dQw4w9WgXcQ)"
            echo "  --no-build         Skip build, use existing packages"
            echo "  --device-only      Only run device tests"
            echo "  --build-only       Only run build validation"
            echo "  --all              Run all tests including device"
            echo "  --help             Show this help"
            exit 0
            ;;
        *) echo "Unknown option: $1"; exit 1;;
    esac
done

TOTAL_PASS=0
TOTAL_FAIL=0

echo ""
echo -e "${BOLD}╔════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║       YouMod Automated Test Suite      ║${NC}"
echo -e "${BOLD}╚════════════════════════════════════════╝${NC}"
echo ""
echo -e "  Project: $PROJECT_DIR"
echo -e "  Build:   $([ "$RUN_BUILD" = true ] && echo 'Yes' || echo 'No')"
echo -e "  Device:  $([ "$RUN_DEVICE" = true ] && echo "Yes ($YOUMOD_TEST_DEVICE)" || echo 'No')"
echo ""

# ============================================================
# Phase 1: Build
# ============================================================
if [ "$RUN_BUILD" = true ]; then
    echo -e "${CYAN}════════════════════════════════════════${NC}"
    echo -e "${BOLD}  Phase 1: Building YouMod${NC}"
    echo -e "${CYAN}════════════════════════════════════════${NC}"
    echo ""

    cd "$PROJECT_DIR"

    # Clean previous build
    info "Cleaning previous build..."
    make clean 2>/dev/null || true

    # Build packages
    info "Building packages..."
    BUILD_START=$(date +%s)

    # Build rootful
    echo -e "${BLUE}  Building rootful...${NC}"
    if make package DEBUG=0 FINALPACKAGE=1 2>&1 | tee /tmp/youmod_build.log; then
        BUILD_END=$(date +%s)
        BUILD_TIME=$((BUILD_END - BUILD_START))
        pass "Rootful build successful (${BUILD_TIME}s)"
        ((TOTAL_PASS++))
    else
        fail "Rootful build failed"
        ((TOTAL_FAIL++))
        echo ""
        echo -e "${RED}Build errors:${NC}"
        grep -i "error:" /tmp/youmod_build.log | tail -10 || true
        exit 1
    fi

    # Build rootless
    echo -e "${BLUE}  Building rootless...${NC}"
    if make package DEBUG=0 FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=rootless 2>&1 | tee -a /tmp/youmod_build.log; then
        pass "Rootless build successful"
        ((TOTAL_PASS++))
    else
        warn "Rootless build failed (non-critical)"
        ((TOTAL_FAIL++))
    fi

    # Build roothide
    echo -e "${BLUE}  Building roothide...${NC}"
    if make package DEBUG=0 FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=roothide 2>&1 | tee -a /tmp/youmod_build.log; then
        pass "Roothide build successful"
        ((TOTAL_PASS++))
    else
        warn "Roothide build failed (non-critical)"
        ((TOTAL_FAIL++))
    fi

    echo ""
fi

# ============================================================
# Phase 2: Build Validation
# ============================================================
if [ "$BUILD_ONLY" = false ]; then
    echo -e "${CYAN}════════════════════════════════════════${NC}"
    echo -e "${BOLD}  Phase 2: Build Validation${NC}"
    echo -e "${CYAN}════════════════════════════════════════${NC}"
    echo ""

    if bash "$SCRIPT_DIR/test-build.sh"; then
        ((TOTAL_PASS++))
    else
        ((TOTAL_FAIL++))
    fi

    echo ""
fi

# ============================================================
# Phase 3: Source Code Validation
# ============================================================
if [ "$BUILD_ONLY" = false ]; then
    echo -e "${CYAN}════════════════════════════════════════${NC}"
    echo -e "${BOLD}  Phase 3: Source Code Validation${NC}"
    echo -e "${CYAN}════════════════════════════════════════${NC}"
    echo ""

    FILES_DIR="$PROJECT_DIR/Files"
    SOURCE_PASS=0
    SOURCE_FAIL=0

    # Check for balanced %hook/%end in all .x files
    for xfile in "$FILES_DIR"/*.x; do
        filename=$(basename "$xfile")
        hook_count=$(grep -c "^%hook" "$xfile" 2>/dev/null || echo "0")
        end_count=$(grep -c "^%end" "$xfile" 2>/dev/null || echo "0")

        if [ "$hook_count" -eq "$end_count" ]; then
            echo -e "${GREEN}[PASS]${NC} $filename: hooks balanced ($hook_count)"
            ((SOURCE_PASS++))
        else
            echo -e "${RED}[FAIL]${NC} $filename: %hook ($hook_count) != %end ($end_count)"
            ((SOURCE_FAIL++))
        fi
    done

    # Check for known problematic patterns
    echo ""
    info "Checking for known issue patterns..."

    # Check Ads.x for createAdsPlaybackCoordinator
    ADS_FILE="$FILES_DIR/Ads.x"
    if [ -f "$ADS_FILE" ]; then
        if grep -q "createAdsPlaybackCoordinator.*return nil" "$ADS_FILE"; then
            echo -e "${RED}[FAIL]${NC} Ads.x: createAdsPlaybackCoordinator returns nil"
            ((SOURCE_FAIL++))
        else
            echo -e "${GREEN}[PASS]${NC} Ads.x: createAdsPlaybackCoordinator safe"
            ((SOURCE_PASS++))
        fi
    fi

    TOTAL_PASS=$((TOTAL_PASS + SOURCE_PASS))
    TOTAL_FAIL=$((TOTAL_FAIL + SOURCE_FAIL))
    echo ""
fi

# ============================================================
# Phase 4: Device Tests
# ============================================================
if [ "$RUN_DEVICE" = true ]; then
    echo -e "${CYAN}════════════════════════════════════════${NC}"
    echo -e "${BOLD}  Phase 4: Device Tests${NC}"
    echo -e "${CYAN}════════════════════════════════════════${NC}"
    echo ""

    if bash "$SCRIPT_DIR/test-device.sh" \
        --device "$YOUMOD_TEST_DEVICE" \
        --password "$YOUMOD_TEST_PASSWORD" \
        --timeout "$YOUMOD_TEST_TIMEOUT" \
        --video-id "$YOUMOD_TEST_VIDEO_ID"; then
        ((TOTAL_PASS++))
    else
        ((TOTAL_FAIL++))
    fi

    echo ""
fi

# ============================================================
# Final Summary
# ============================================================
echo ""
echo -e "${BOLD}╔════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║          Final Test Summary            ║${NC}"
echo -e "${BOLD}╚════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${GREEN}Passed: $TOTAL_PASS${NC}"
echo -e "  ${RED}Failed: $TOTAL_FAIL${NC}"
echo ""

if [ $TOTAL_FAIL -gt 0 ]; then
    echo -e "${RED}${BOLD}❌ SOME TESTS FAILED${NC}"
    exit 1
else
    echo -e "${GREEN}${BOLD}✅ ALL TESTS PASSED${NC}"
    exit 0
fi
