#!/usr/bin/env bats

setup() {
    # Create a temporary directory for tests
    export TEST_TEMP_DIR="$(mktemp -d)"
    export REPO_DIR="${TEST_TEMP_DIR}/repos.d"
    export LOG_FILE="${TEST_TEMP_DIR}/opsi-repo-config.log"
    export SKIP_ROOT_CHECK=1

    # Store original PATH to restore it later if needed
    export ORIGINAL_PATH="$PATH"

    # Target script path
    export SCRIPT_PATH="$(dirname "$BATS_TEST_DIRNAME")/opsi-repo-config.sh"
}

teardown() {
    # Clean up temporary directory
    rm -rf "$TEST_TEMP_DIR"
    export PATH="$ORIGINAL_PATH"
}

@test "fails when not run as root and SKIP_ROOT_CHECK is not set" {
    unset SKIP_ROOT_CHECK

    run bash "$SCRIPT_PATH"

    [ "$status" -eq 1 ]
    [[ "$output" == *"This script must be run as root"* ]]
}

@test "creates the repository directory if it doesn't exist" {
    # Provide an empty PATH so opsi-package-updater is not found, but keep minimal core utilities
    PATH="/bin:/usr/bin" run bash "$SCRIPT_PATH"

    [ -d "$REPO_DIR" ]
    [[ "$output" == *"Creating repository configuration directory"* ]]
}

@test "creates uib_official.repo correctly" {
    PATH="/bin:/usr/bin" run bash "$SCRIPT_PATH"

    [ -f "$REPO_DIR/uib_official.repo" ]
    grep -q "\[repository_uib_official\]" "$REPO_DIR/uib_official.repo"
    grep -q "baseURL = http://opsipackages.43.opsi.org/stable" "$REPO_DIR/uib_official.repo"
}

@test "creates opsi_packages_official.repo correctly" {
    PATH="/bin:/usr/bin" run bash "$SCRIPT_PATH"

    [ -f "$REPO_DIR/opsi_packages_official.repo" ]
    grep -q "\[repository_opsi_packages\]" "$REPO_DIR/opsi_packages_official.repo"
    grep -q "baseURL = http://opsipackages.43.opsi.org/stable" "$REPO_DIR/opsi_packages_official.repo"
}

@test "creates o4i_public.repo correctly" {
    PATH="/bin:/usr/bin" run bash "$SCRIPT_PATH"

    [ -f "$REPO_DIR/o4i_public.repo" ]
    grep -q "\[repository_o4i_public\]" "$REPO_DIR/o4i_public.repo"
    grep -q "baseURL = https://repo.o4i.org/public" "$REPO_DIR/o4i_public.repo"
}

@test "creates kit_scc_repository.repo correctly (disabled by default)" {
    PATH="/bin:/usr/bin" run bash "$SCRIPT_PATH"

    [ -f "$REPO_DIR/kit_scc_repository.repo" ]
    grep -q "\[repository_kit_scc\]" "$REPO_DIR/kit_scc_repository.repo"
    grep -q "active = false" "$REPO_DIR/kit_scc_repository.repo"
}

@test "handles missing opsi-package-updater gracefully" {
    # Ensure opsi-package-updater is not in PATH
    MOCK_BIN="${TEST_TEMP_DIR}/bin"
    mkdir -p "$MOCK_BIN"
    export PATH="${MOCK_BIN}:/bin:/usr/bin"

    run bash "$SCRIPT_PATH"

    [[ "$output" == *"opsi-package-updater not found in PATH"* ]]
}

@test "validates configuration using opsi-package-updater if available" {
    MOCK_BIN="${TEST_TEMP_DIR}/bin"
    mkdir -p "$MOCK_BIN"

    # Create mock opsi-package-updater
    cat > "${MOCK_BIN}/opsi-package-updater" << 'EOF'
#!/bin/bash
if [[ "$1" == "list" && "$2" == "--active-repos" ]]; then
    echo "Mock active repos list"
    exit 0
fi
echo "Unexpected mock arguments: $@" >&2
exit 1
EOF
    chmod +x "${MOCK_BIN}/opsi-package-updater"

    export PATH="${MOCK_BIN}:$PATH"

    run bash "$SCRIPT_PATH"

    [[ "$output" == *"opsi-package-updater found"* ]]
    [[ "$output" == *"Mock active repos list"* ]]
}
