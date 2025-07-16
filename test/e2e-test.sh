#!/usr/bin/env bash

set -euo pipefail

# E2E test script for ft_otp
# Compares ft_otp output with oathtool reference implementation

echo "=== ft_otp E2E Test ==="

# Check if required tools are available
if ! command -v ft_otp &> /dev/null; then
    echo "Error: ft_otp not found in PATH"
    exit 1
fi

if ! command -v oathtool &> /dev/null; then
    echo "Error: oathtool not found in PATH"
    exit 1
fi

# Get the script directory to resolve relative paths correctly
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Test setup
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

cd "$TEST_DIR"

###############################################################
# Determine key files to test
# If the caller passed one or more arguments, use those.
# Otherwise, default to every *.hex file in the test directory.
###############################################################

# Build the list of key files to test.
# 1. Any files supplied as CLI arguments
# 2. All *.hex files found in the test directory
# Use an associative array to de-duplicate paths.
declare -A seen=()

# Add CLI-provided files first (may be empty)
for arg in "$@"; do
  seen["$arg"]=1
done

# Add *.hex files from the test directory
for f in "$PROJECT_ROOT"/test/*.hex; do
  seen["$f"]=1
done

# Populate KEY_FILES array from the associative keys (order doesn't matter)
KEY_FILES=("${!seen[@]}")

# -------------------------------------------------------------
# Append RANDOM_COUNT randomly generated keys (default 20)
# to exercise property-based style testing.
# -------------------------------------------------------------

# Function to generate 64-char hex (32 random bytes)
if command -v openssl >/dev/null 2>&1; then
  rand_hex() { openssl rand -hex 32; }
else
  # POSIX fallback using /dev/urandom + hexdump (util-linux)
  rand_hex() { hexdump -v -n32 -e '/1 "%02x"' /dev/urandom; }
fi

RANDOM_COUNT="${RANDOM_COUNT:-20}"

for ((i=0; i<RANDOM_COUNT; i++)); do
  hex=$(rand_hex)
  tmp_file="$TEST_DIR/random_${i}.hex"
  echo "$hex" > "$tmp_file"
  KEY_FILES+=("$tmp_file")
done

# Ensure at least one key file exists
if [ "${#KEY_FILES[@]}" -eq 0 ]; then
  echo "Error: No .hex key files found to test"
  exit 1
fi

echo "Test directory: $TEST_DIR"
echo "Key files to test: ${KEY_FILES[*]}"

# Helper: Execute TOTP comparison logic up to 3 retries to avoid
# boundary-window mismatches.
test_single_key() {
  local key_path="$1"
  echo "\n=== Testing key: $key_path ==="

  # Copy the key into the temp dir with canonical name expected by scripts
  cp "$key_path" key.hex

  echo "Generating ft_otp.key via 'ft_otp -g key.hex'..."
  ft_otp -g key.hex

  # Inner retry loop
  local success=0
  for attempt in 1 2 3; do
    echo "--- Attempt $attempt for key $(basename "$key_path") ---"

    # Generate TOTP from both implementations as close in time as possible
    local ft_otp_output oathtool_output
    ft_otp_output=$(ft_otp -k ft_otp.key)
    oathtool_output=$(oathtool --totp "$(cat key.hex)")

    echo "ft_otp output   : $ft_otp_output"
    echo "oathtool output : $oathtool_output"

    if [ "$ft_otp_output" = "$oathtool_output" ]; then
      echo "✓ Outputs match for key $(basename "$key_path")"
      success=1
      break
    else
      echo "✗ Outputs differ on attempt $attempt (possible time boundary)"
      # Wait 2 seconds before retry unless last attempt
      if [ $attempt -lt 3 ]; then
        sleep 2
      fi
    fi
  done

  if [ $success -ne 1 ]; then
    echo "✗ E2E test failed for key $(basename "$key_path") after 3 attempts"
    return 1
  fi
}

# Iterate over all key files and run the comparison logic.
overall_success=0
for key_file in "${KEY_FILES[@]}"; do
  if ! test_single_key "$key_file"; then
    overall_success=1
    break
  fi
done

if [ $overall_success -eq 0 ]; then
  echo "\n✓ All E2E tests passed: ft_otp and oathtool outputs match for all keys"
  exit 0
else
  echo "\n✗ Some E2E tests failed. See output above for details."
  exit 1
fi