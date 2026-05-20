# YouMod Test Suite

Automated testing scripts for YouMod YouTube tweak.

## Quick Start

### In-App Tests (After Sideload)
Open YouTube → Settings → YouMod → Miscellaneous → **Run Diagnostics**

This runs 12 automated tests directly on your device:
- Core class existence checks
- Hook verification (player load, ad coordinator, playability)
- Configuration validation (spoof version, bundle, UserDefaults)
- Network connectivity test
- Crash log detection
- Dylib load status

### CLI Tests (Build Machine)
```bash
# Run all local tests (build + validation)
./scripts/test.sh

# Run only build validation (no rebuild)
./scripts/test.sh --no-build

# Run only device tests
./scripts/test.sh --device-only --device 192.168.1.100 --password alpine

# Run everything including device tests
./scripts/test.sh --all --device 192.168.1.100

# Run with custom video and longer timeout
./scripts/test.sh --all --device 192.168.1.100 --video-id abc123 --timeout 600
```

## Scripts Overview

| Script | Purpose |
|--------|---------|
| `test.sh` | Main test runner - orchestrates all tests |
| `test-build.sh` | Post-build validation (package integrity, symbols, patterns) |
| `test-device.sh` | Device-side testing (install, launch, monitor playback) |
| `test-config.sh` | Configuration file for test parameters |

## Test Phases

### Phase 1: Build
- Builds rootful, rootless, and roothide packages
- Captures build output for error analysis

### Phase 2: Build Validation (`test-build.sh`)
- ✅ Package file size check
- ✅ Dylib exists in package
- ✅ DEBIAN/control file present
- ✅ Architecture verification (arm64)
- ✅ Symbol verification
- ✅ Known issue pattern detection
- ✅ Source code validation (balanced %hook/%end)

### Phase 3: Source Code Validation
- ✅ Balanced %hook/%end in all .x files
- ✅ Checks for `createAdsPlaybackCoordinator` returning nil
- ✅ Checks for empty ad arrays (may cause playback issues)

### Phase 4: Device Tests (`test-device.sh`)
Requires a jailbroken iOS device accessible via SSH.

- ✅ Device connectivity
- ✅ Tweak installation
- ✅ YouTube launch
- ✅ Video playback monitoring (default 5 minutes)
- ✅ Error pattern detection in logs
- ✅ "Something went wrong" detection
- ✅ Crash log check

## Configuration

Edit `test-config.sh` or use environment variables:

```bash
# Device settings
export YOUMOD_TEST_DEVICE="192.168.1.100"
export YOUMOD_TEST_PASSWORD="alpine"

# Test settings
export YOUMOD_TEST_TIMEOUT=300        # 5 minutes
export YOUMOD_TEST_VIDEO_ID="dQw4w9WgXcQ"

# Enable/disable test phases
export YOUMOD_TEST_BUILD=true
export YOUMOD_TEST_DEVICE_ENABLED=false
export YOUMOD_TEST_SOURCE=true
```

## Error Patterns Monitored

The following patterns in logs indicate test failure:
- `Something went wrong`
- `Tap to retry`
- `playback.*error`
- `player.*failed`
- `EXC_BAD_ACCESS`
- `NSException`
- `crash`

## CI Integration

Build validation runs automatically in GitHub Actions after each build.
See `.github/workflows/build.yml` for the workflow configuration.

## Requirements

### Local Tests
- macOS or Linux with Theos installed
- `make`, `ldid`, `ar`, `nm`, `file`

### Device Tests
- Jailbroken iOS device
- `sshpass` installed (`brew install sshpass`)
- Device on same network with SSH enabled
- YouTube app installed

## Troubleshooting

### "Cannot connect to device"
- Verify device IP address
- Ensure SSH is enabled on device (Settings → OpenSSH)
- Check network connectivity
- Verify root password (default: `alpine`)

### "No .deb files found"
- Run `make package` first
- Check that build completed successfully

### Device tests timeout
- Increase timeout: `--timeout 600`
- Check device logs: `ssh root@DEVICE_IP "log stream --style compact"`
