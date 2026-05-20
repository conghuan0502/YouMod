#!/bin/bash
# YouMod Test Configuration
# Edit these values or set environment variables to override

# ============================================================
# Device Configuration
# ============================================================
# IP address of jailbroken iOS device
export YOUMOD_TEST_DEVICE="${YOUMOD_TEST_DEVICE:-192.168.1.100}"

# Root password for SSH access
export YOUMOD_TEST_PASSWORD="${YOUMOD_TEST_PASSWORD:-alpine}"

# ============================================================
# Test Configuration
# ============================================================
# How long to monitor video playback (seconds)
export YOUMOD_TEST_TIMEOUT="${YOUMOD_TEST_TIMEOUT:-300}"

# Video ID to test with (use a video that's known to have ads)
export YOUMOD_TEST_VIDEO_ID="${YOUMOD_TEST_VIDEO_ID:-dQw4w9WgXcQ}"

# ============================================================
# Test Matrix (set to true/false to enable/disable)
# ============================================================
# Run post-build validation
export YOUMOD_TEST_BUILD="${YOUMOD_TEST_BUILD:-true}"

# Run device-side tests
export YOUMOD_TEST_DEVICE_ENABLED="${YOUMOD_TEST_DEVICE_ENABLED:-false}"

# Run source code validation
export YOUMOD_TEST_SOURCE="${YOUMOD_TEST_SOURCE:-true}"

# ============================================================
# Known Issues to Check
# ============================================================
# These patterns in logs indicate test failure
export YOUMOD_ERROR_PATTERNS=(
    "Something went wrong"
    "Tap to retry"
    "playback.*error"
    "player.*failed"
    "EXC_BAD_ACCESS"
    "NSException"
    "crash"
)

# ============================================================
# Build Configuration
# ============================================================
# Build types to test
export YOUMOD_BUILD_TYPES="${YOUMOD_BUILD_TYPES:-rootful rootless roothide}"

# Build flags
export YOUMOD_DEBUG="${YOUMOD_DEBUG:-0}"
export YOUMOD_FINAL="${YOUMOD_FINAL:-1}"
