#!/bin/bash
# YouMod Post-Build Validation Script
# Runs after .deb is built to verify the package integrity

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0

pass() {
    echo -e "${GREEN}[PASS]${NC} $1"
    PASS_COUNT=$((PASS_COUNT + 1))
}

fail() {
    echo -e "${RED}[FAIL]${NC} $1"
    FAIL_COUNT=$((FAIL_COUNT + 1))
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
    WARN_COUNT=$((WARN_COUNT + 1))
}

info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

# ============================================================
# Find built packages
# ============================================================
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PACKAGES_DIR="$PROJECT_DIR/packages"

# If packages not found, try current directory (for CI where cwd may differ)
if [ ! -d "$PACKAGES_DIR" ]; then
    PACKAGES_DIR="$PROJECT_DIR/YouMod/packages"
    if [ ! -d "$PACKAGES_DIR" ]; then
        PACKAGES_DIR="./packages"
    fi
fi

info "Looking for .deb packages in $PACKAGES_DIR"

if [ ! -d "$PACKAGES_DIR" ]; then
    fail "Packages directory not found. Run 'make package' first."
    exit 1
fi

DEB_FILES=("$PACKAGES_DIR"/*.deb)
if [ ${#DEB_FILES[@]} -eq 0 ] || [ ! -f "${DEB_FILES[0]}" ]; then
    fail "No .deb files found in $PACKAGES_DIR"
    exit 1
fi

info "Found ${#DEB_FILES[@]} package(s):"
for deb in "${DEB_FILES[@]}"; do
    info "  - $(basename "$deb")"
done

# ============================================================
# Test 1: Package integrity
# ============================================================
echo ""
info "=== Package Integrity Tests ==="

for deb in "${DEB_FILES[@]}"; do
    deb_name=$(basename "$deb")
    info "Testing: $deb_name"

    # Check file size (> 100KB means it has content)
    file_size=$(stat -f%z "$deb" 2>/dev/null || stat -c%s "$deb" 2>/dev/null)
    if [ "$file_size" -gt 102400 ]; then
        pass "$deb_name size: $((file_size / 1024))KB"
    else
        fail "$deb_name too small: $((file_size / 1024))KB"
    fi

    # Extract and verify structure
    TEMP_DIR=$(mktemp -d)
    cd "$TEMP_DIR"
    ar x "$deb" 2>/dev/null || true

    # Extract data archive
    if [ -f "data.tar.gz" ]; then
        tar -xzf data.tar.gz 2>/dev/null || true
    elif ls data.tar.* 1>/dev/null 2>&1; then
        tar -xf data.tar.* 2>/dev/null || true
    fi

    # Extract control archive for control file
    if [ -f "control.tar.gz" ]; then
        mkdir -p control_extract && cd control_extract
        tar -xzf ../control.tar.gz 2>/dev/null || true
        cd ..
    fi

    # Check dylib exists
    DYLIB_PATH=$(find . -name "YouMod.dylib" 2>/dev/null | head -1)
    if [ -n "$DYLIB_PATH" ] && [ -f "$DYLIB_PATH" ]; then
        pass "YouMod.dylib found in $deb_name"
    else
        fail "YouMod.dylib NOT found in $deb_name"
    fi

    # Check control file - try multiple locations
    CONTROL_PATH=$(find . -name "control" 2>/dev/null | head -1)
    if [ -n "$CONTROL_PATH" ] && [ -f "$CONTROL_PATH" ]; then
        pass "control file found in $deb_name"
    else
        fail "control file NOT found in $deb_name"
    fi

    # Check Info.plist or tweak plist
    PLIST_PATH=$(find . -name "*.plist" -not -path "*/DEBIAN/*" 2>/dev/null | head -1)
    if [ -n "$PLIST_PATH" ]; then
        pass "Plist found: $(basename "$PLIST_PATH")"
    else
        warn "No plist file found in $deb_name"
    fi

    cd "$PROJECT_DIR"
    rm -rf "$TEMP_DIR"
done

# ============================================================
# Test 2: Dylib symbol verification
# ============================================================
echo ""
info "=== Dylib Symbol Tests ==="

for deb in "${DEB_FILES[@]}"; do
    TEMP_DIR=$(mktemp -d)
    cd "$TEMP_DIR"
    ar x "$deb" 2>/dev/null
    tar -xzf data.tar.gz 2>/dev/null || tar -xf data.tar.* 2>/dev/null || true

    DYLIB_PATH=$(find . -name "YouMod.dylib" 2>/dev/null | head -1)

    if [ -n "$DYLIB_PATH" ] && [ -f "$DYLIB_PATH" ]; then
        # Check for expected Objective-C classes/symbols
        if command -v nm &>/dev/null; then
            SYMBOLS=$(nm -g "$DYLIB_PATH" 2>/dev/null || true)

            # Check for key hook symbols
            for symbol in "YTPlayerViewController" "YTMainAppVideoPlayerOverlayView" "YTSingleVideoController"; do
                if echo "$SYMBOLS" | grep -q "$symbol"; then
                    pass "Symbol '$symbol' found in dylib"
                else
                    warn "Symbol '$symbol' not visible in dylib (may be stripped)"
                fi
            done
        else
            warn "nm tool not available, skipping symbol check"
        fi

        # Check architecture
        if command -v file &>/dev/null; then
            FILE_INFO=$(file "$DYLIB_PATH")
            if echo "$FILE_INFO" | grep -qi "arm64"; then
                pass "Dylib contains arm64 architecture"
            else
                warn "arm64 architecture not detected: $FILE_INFO"
            fi
        fi
    fi

    cd "$PROJECT_DIR"
    rm -rf "$TEMP_DIR"
done

# ============================================================
# Test 3: Source code validation
# ============================================================
echo ""
info "=== Source Code Validation ==="

FILES_DIR="$PROJECT_DIR/Files"

# Check that all .x files compile without unused function warnings
for xfile in "$FILES_DIR"/*.x; do
    filename=$(basename "$xfile")

    # Check for unused static functions (common cause of build failures)
    unused_funcs=$(grep -c "^static.*{" "$xfile" 2>/dev/null | tr -d '[:space:]')
    unused_funcs=${unused_funcs:-0}
    if [ "$unused_funcs" -gt 0 ] 2>/dev/null; then
        info "$filename has $unused_funcs static function(s) - verify they are used"
    fi

    # Check for balanced %hook/%end (accounting for %group blocks)
    # Strip both /* */ and // comments before counting (use perl for cross-platform compat)
    stripped=$(perl -0777 -pe 's{/\*.*?\*/}{}gs; s{//.*}{}g' "$xfile" 2>/dev/null || cat "$xfile")
    hook_count=$(echo "$stripped" | grep -c "^%hook" 2>/dev/null | tr -d '[:space:]')
    group_count=$(echo "$stripped" | grep -c "^%group" 2>/dev/null | tr -d '[:space:]')
    end_count=$(echo "$stripped" | grep -c "^%end" 2>/dev/null | tr -d '[:space:]')
    hook_count=${hook_count:-0}
    group_count=${group_count:-0}
    end_count=${end_count:-0}
    total_opens=$((hook_count + group_count))
    if [ "$total_opens" -eq "$end_count" ] 2>/dev/null; then
        pass "$filename: %hook/%group/%end balanced ($hook_count hooks, $group_count groups)"
    else
        fail "$filename: %hook ($hook_count) + %group ($group_count) != %end ($end_count)"
    fi

    # Check for balanced %{/}%
    group_start=$(grep -c "^%group" "$xfile" 2>/dev/null || echo "0")
    group_end=$(grep -c "^%end" "$xfile" 2>/dev/null || echo "0")
    # Note: %end is shared with %hook, so this is just informational
done

# ============================================================
# Test 4: Check for known problematic patterns
# ============================================================
echo ""
info "=== Known Issue Pattern Checks ==="

# Check Ads.x for the createAdsPlaybackCoordinator fix
ADS_FILE="$FILES_DIR/Ads.x"
if [ -f "$ADS_FILE" ]; then
    # Should NOT return nil for createAdsPlaybackCoordinator
    if grep -q "createAdsPlaybackCoordinator.*return nil" "$ADS_FILE"; then
        fail "Ads.x: createAdsPlaybackCoordinator returns nil (causes 'Something went wrong' error)"
    else
        pass "Ads.x: createAdsPlaybackCoordinator does not return nil"
    fi
fi

# Check for any hardcoded old version strings that might cause API issues
if grep -rq "clientVersion.*1[0-9]\." "$FILES_DIR" 2>/dev/null; then
    warn "Found old clientVersion references - verify spoof versions are current"
else
    pass "No obviously outdated clientVersion references"
fi

# ============================================================
# Test 5: Control file validation
# ============================================================
echo ""
info "=== Control File Validation ==="

CONTROL_FILE="$PROJECT_DIR/control"
if [ -f "$CONTROL_FILE" ]; then
    # Check required fields
    for field in "Package:" "Name:" "Version:" "Architecture:" "Description:"; do
        if grep -q "^$field" "$CONTROL_FILE"; then
            pass "control: $field present"
        else
            fail "control: $field missing"
        fi
    done

    # Check version format
    VERSION=$(grep "^Version:" "$CONTROL_FILE" | cut -d' ' -f2)
    if [[ "$VERSION" =~ ^[0-9]+\.[0-9]+ ]]; then
        pass "Version format valid: $VERSION"
    else
        warn "Version format unusual: $VERSION"
    fi
else
    fail "control file not found at $CONTROL_FILE"
fi

# ============================================================
# Summary
# ============================================================
echo ""
echo "========================================"
echo -e "${BLUE}=== Test Summary ===${NC}"
echo "========================================"
echo -e "  ${GREEN}Passed: $PASS_COUNT${NC}"
echo -e "  ${RED}Failed: $FAIL_COUNT${NC}"
echo -e "  ${YELLOW}Warnings: $WARN_COUNT${NC}"
echo "========================================"

if [ $FAIL_COUNT -gt 0 ]; then
    echo -e "${RED}BUILD VALIDATION FAILED${NC}"
    exit 1
else
    echo -e "${GREEN}BUILD VALIDATION PASSED${NC}"
    exit 0
fi
