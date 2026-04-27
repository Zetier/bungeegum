#!/usr/bin/env bash

#
# Run Bungeegum integration tests on a connected Android device
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
readonly PKG_NAME="com.zetier.bungeegum"


log_error() {
  echo "$*" >&2
}


detect_abi() {
  local device_abi

  device_abi="$(adb shell getprop ro.product.cpu.abi)" || {
    log_error "A single supported ARM or AArch64 device must be attached via adb to run tests"
    exit 1
  }
  device_abi="${device_abi%"${device_abi##*[![:space:]]}"}"

  case "${device_abi}" in
    arm64-v8a)
      echo "arm64-v8a"
      ;;
    armeabi-v7a | armeabi)
      echo "armeabi-v7a"
      ;;
    *)
      log_error "Unsupported device ABI: ${device_abi}"
      log_error "Supported ABIs: arm64-v8a, armeabi-v7a"
      exit 1
      ;;
  esac
}


uninstall_app_if_present() {
  if adb shell pm list packages "${PKG_NAME}" | grep -q "${PKG_NAME}"; then
    adb uninstall "${PKG_NAME}"
  fi
}


run_test_command() {
  local cmd="$1"
  local expected_status="$2"
  local ret

  set +e
  eval "${cmd}"
  ret=$?
  set -e

  if [[ "${ret}" -ne "${expected_status}" ]]; then
    log_error "${cmd} returned ${ret}"
    exit 1
  fi
}


run_exit42_tests() {
  local expected_status=42
  local test_abi="$1"
  local exit42_release_local_dir="${SCRIPT_DIR}/exit42/build/release/local"
  local test_elf
  local test_shellcode

  if [[ ! -d "${exit42_release_local_dir}" ]]; then
    log_error "Missing test artifact directory: ${exit42_release_local_dir}"
    log_error "Build the test binaries before running this script"
    exit 1
  fi

  test_elf="${exit42_release_local_dir}/${test_abi}/exit42"
  test_shellcode="${exit42_release_local_dir}/${test_abi}/exit42.bin"

  run_test_command "bungeegum --shellcode ${test_shellcode}" "${expected_status}"
  run_test_command "bungeegum --elf ${test_elf}" "${expected_status}"
  run_test_command \
    "bungeegum --remote --elf /system/bin/sh --args -c 'return 42;'" \
    "${expected_status}"
}


main() {
  local abi

  abi="$(detect_abi)"
  uninstall_app_if_present
  run_exit42_tests "${abi}"
}


main
