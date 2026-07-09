#!/usr/bin/env bats

setup() {
    export TEST_TEMP_DIR="$(mktemp -d)"
    export MOCK_REPO_DIR="${TEST_TEMP_DIR}/repos.d"
    export MOCK_LOG_FILE="${TEST_TEMP_DIR}/opsi-repo-config.log"

    export TEST_SCRIPT="${TEST_TEMP_DIR}/opsi-repo-config.sh"
    cp server-scripts/opsi-repo-config.sh "$TEST_SCRIPT"
    chmod +x "$TEST_SCRIPT"

    sed -i "s|REPO_DIR=\"/etc/opsi/package-updater.repos.d\"|REPO_DIR=\"${MOCK_REPO_DIR}\"|g" "$TEST_SCRIPT"
    sed -i "s|LOG_FILE=\"/var/log/opsi-repo-config.log\"|LOG_FILE=\"${MOCK_LOG_FILE}\"|g" "$TEST_SCRIPT"
    sed -i 's/\$EUID/$MOCK_EUID/g' "$TEST_SCRIPT"

    export MOCK_BIN_DIR="${TEST_TEMP_DIR}/bin"
    mkdir -p "$MOCK_BIN_DIR"
    export PATH="${MOCK_BIN_DIR}:$PATH"
}

teardown() {
    rm -rf "$TEST_TEMP_DIR"
}

@test "should fail if not run as root" {
    export MOCK_EUID="1000"
    run bash "$TEST_SCRIPT"
    [ "$status" -eq 1 ]
    echo "$output" | grep -q "\[ERROR\].*This script must be run as root"
}

@test "should create REPO_DIR if it doesn't exist" {
    export MOCK_EUID="0"
    run bash "$TEST_SCRIPT"
    [ "$status" -eq 0 ]
    [ -d "$MOCK_REPO_DIR" ]
}

@test "should create uib_official.repo with correct contents" {
    export MOCK_EUID="0"
    run bash "$TEST_SCRIPT"
    [ "$status" -eq 0 ]
    [ -f "$MOCK_REPO_DIR/uib_official.repo" ]
    grep -q "\[repository_uib_official\]" "$MOCK_REPO_DIR/uib_official.repo"
    grep -q "baseURL = http://opsipackages.43.opsi.org/stable" "$MOCK_REPO_DIR/uib_official.repo"
}

@test "should create opsi_packages_official.repo" {
    export MOCK_EUID="0"
    run bash "$TEST_SCRIPT"
    [ "$status" -eq 0 ]
    [ -f "$MOCK_REPO_DIR/opsi_packages_official.repo" ]
    grep -q "\[repository_opsi_packages\]" "$MOCK_REPO_DIR/opsi_packages_official.repo"
}

@test "should create o4i_public.repo" {
    export MOCK_EUID="0"
    run bash "$TEST_SCRIPT"
    [ "$status" -eq 0 ]
    [ -f "$MOCK_REPO_DIR/o4i_public.repo" ]
    grep -q "\[repository_o4i_public\]" "$MOCK_REPO_DIR/o4i_public.repo"
}

@test "should create kit_scc_repository.repo (disabled)" {
    export MOCK_EUID="0"
    run bash "$TEST_SCRIPT"
    [ "$status" -eq 0 ]
    [ -f "$MOCK_REPO_DIR/kit_scc_repository.repo" ]
    grep -q "\[repository_kit_scc\]" "$MOCK_REPO_DIR/kit_scc_repository.repo"
    grep -q "active = false" "$MOCK_REPO_DIR/kit_scc_repository.repo"
}

@test "should log actions to LOG_FILE" {
    export MOCK_EUID="0"
    run bash "$TEST_SCRIPT"
    [ "$status" -eq 0 ]
    [ -f "$MOCK_LOG_FILE" ]
    grep -q "Starting OPSI Repository Configuration" "$MOCK_LOG_FILE"
    grep -q "UIB official repository configured" "$MOCK_LOG_FILE"
}

@test "should warn if opsi-package-updater is not found" {
    export MOCK_EUID="0"
    # Ensure opsi-package-updater is not in PATH by clearing path to just standard tools
    export PATH="/usr/bin:/bin"
    run bash "$TEST_SCRIPT"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "\[WARNING\].*opsi-package-updater not found in PATH"
}

@test "should list active repos if opsi-package-updater is found" {
    export MOCK_EUID="0"
    echo "#!/bin/bash" > "$MOCK_BIN_DIR/opsi-package-updater"
    echo "if [ \"\$1\" = \"list\" ] && [ \"\$2\" = \"--active-repos\" ]; then" >> "$MOCK_BIN_DIR/opsi-package-updater"
    echo "    echo \"mocked_repo\"" >> "$MOCK_BIN_DIR/opsi-package-updater"
    echo "    exit 0" >> "$MOCK_BIN_DIR/opsi-package-updater"
    echo "fi" >> "$MOCK_BIN_DIR/opsi-package-updater"
    echo "exit 1" >> "$MOCK_BIN_DIR/opsi-package-updater"
    chmod +x "$MOCK_BIN_DIR/opsi-package-updater"

    run bash "$TEST_SCRIPT"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "opsi-package-updater found"
    echo "$output" | grep -q "mocked_repo"
}
