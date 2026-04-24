#!/usr/bin/env bats

load '../test_helper'

setup() {
    common_setup
    source_lib "logging"
    source_lib "state"
    
    # Setup a temp state file
    export ACFS_HOME=$(create_temp_dir)
    export ACFS_STATE_FILE="$ACFS_HOME/state.json"
}

teardown() {
    common_teardown
}

@test "state: init creates valid json" {
    run state_init
    assert_success
    
    run cat "$ACFS_STATE_FILE"
    assert_output --partial '"version":'
    assert_output --partial '"completed_phases": []'
}

@test "state: init tolerates missing ACFS_VERSION under nounset" {
    local state_root
    state_root=$(create_temp_dir)

    run env -i PATH="$PATH" HOME="$state_root/home" ACFS_HOME="$state_root/acfs" ACFS_STATE_FILE="$state_root/acfs/state.json" bash -u -c '
        mkdir -p "$HOME" "$ACFS_HOME"
        source "$1"
        state_init
        jq -r .version "$ACFS_STATE_FILE"
    ' _ "$PROJECT_ROOT/scripts/lib/state.sh"
    assert_success
    assert_output "unknown"
}

@test "state: save and load round trip" {
    state_init
    
    local content='{"test": "value"}'
    run state_save "$content"
    assert_success
    
    run state_load
    assert_success
    assert_output --partial '"test": "value"'
}

@test "state: phase lifecycle" {
    state_init
    
    # Start
    run state_phase_start "phase1" "step1"
    assert_success
    
    run state_get ".current_phase"
    assert_output "phase1"
    
    # Complete
    run state_phase_complete "phase1"
    assert_success
    
    run state_is_phase_completed "phase1"
    assert_success # Returns 0 (true in bash)
    
    run state_get ".current_phase"
    assert_output ""
}

@test "state: fail records error" {
    state_init
    state_phase_start "phase1"
    
    run state_phase_fail "phase1" "stepX" "Something blew up"
    assert_success
    
    run state_get ".failed_phase"
    assert_output "phase1"
    
    run state_get ".failed_error"
    assert_output "Something blew up"
}

@test "state: skip logic" {
    state_init
    
    run state_phase_skip "skipped_phase"
    assert_success
    
    run state_should_skip_phase "skipped_phase"
    assert_success # Returns 0 (true)
    
    run state_should_skip_phase "other_phase"
    assert_failure # Returns 1 (false)
}

@test "state: update atomic" {
    state_init
    
    run state_update '.new_field = "exists"'
    assert_success
    
    run state_get ".new_field"
    assert_output "exists"
}

@test "state: nested state_save keeps outer lock held" {
    state_init

    _state_acquire_lock
    state_save '{"nested": "value"}'

    [[ "${_ACFS_STATE_LOCKED:-}" == "true" ]]
    [[ "${_ACFS_STATE_LOCK_DEPTH:-0}" -eq 1 ]]

    _state_release_lock
    [[ "${_ACFS_STATE_LOCKED:-}" == "false" ]]
    [[ "${_ACFS_STATE_LOCK_DEPTH:-0}" -eq 0 ]]

    run state_get ".nested"
    assert_output "value"
}

@test "state: ubuntu upgrade helpers escape dynamic values" {
    state_init

    run state_upgrade_init '24.04"; halt' '25.10"; halt' '["25.04","25.10"]'
    assert_success

    run state_upgrade_start '24.04"; from' '25.04"; to'
    assert_success

    run state_upgrade_complete '25.04"; done'
    assert_success

    run state_get ".ubuntu_upgrade.original_version"
    assert_output '24.04"; halt'

    run state_get ".ubuntu_upgrade.target_version"
    assert_output '25.10"; halt'

    run state_get ".ubuntu_upgrade.completed_upgrades[0].from"
    assert_output '24.04"; from'

    run state_get ".ubuntu_upgrade.completed_upgrades[0].to"
    assert_output '25.04"; done'

    run state_upgrade_set_error 'failed "quoted" upgrade'
    assert_success

    run state_get ".ubuntu_upgrade.last_error"
    assert_output 'failed "quoted" upgrade'

    run state_upgrade_mark_complete
    assert_success

    run state_get ".ubuntu_upgrade.current_stage"
    assert_output "completed"
}

@test "state: get file prefers passwd-resolved target home when ACFS_HOME unset" {
    local stub_home
    stub_home=$(create_temp_dir)

    unset ACFS_HOME
    unset ACFS_STATE_FILE
    export TARGET_USER="dummy"
    export TARGET_HOME=""
    export HOME="/tmp/not-the-target-home"

    state_getent_passwd_entry() {
        if [[ "${1:-}" == "dummy" ]]; then
            printf "dummy:x:1000:1000::%s:/bin/bash\n" "$stub_home"
            return 0
        fi
        return 1
    }

    run state_get_file
    assert_success
    assert_output "$stub_home/.acfs/state.json"
}

@test "state: init uses passwd-resolved target home when ACFS_HOME unset" {
    local stub_home
    stub_home=$(create_temp_dir)

    unset ACFS_HOME
    unset ACFS_STATE_FILE
    export TARGET_USER="dummy"
    export TARGET_HOME=""
    export HOME="/tmp/not-the-target-home"

    state_getent_passwd_entry() {
        if [[ "${1:-}" == "dummy" ]]; then
            printf "dummy:x:1000:1000::%s:/bin/bash\n" "$stub_home"
            return 0
        fi
        return 1
    }

    run state_init
    assert_success

    run test -f "$stub_home/.acfs/state.json"
    assert_success
}

@test "state: init persists resolved target home when TARGET_HOME unset" {
    local stub_home
    stub_home=$(create_temp_dir)

    unset ACFS_HOME
    unset ACFS_STATE_FILE
    export TARGET_USER="dummy"
    export TARGET_HOME=""
    export HOME="/tmp/not-the-target-home"

    state_getent_passwd_entry() {
        if [[ "${1:-}" == "dummy" ]]; then
            printf "dummy:x:1000:1000::%s:/bin/bash\n" "$stub_home"
            return 0
        fi
        return 1
    }

    run state_init
    assert_success

    run state_get ".target_home"
    assert_success
    assert_output "$stub_home"
}

@test "state: backup and remove accepts passwd-resolved user state path" {
    local stub_home
    stub_home=$(create_temp_dir)

    unset ACFS_HOME
    unset ACFS_STATE_FILE
    export TARGET_USER="dummy"
    export TARGET_HOME=""
    export HOME="/tmp/not-the-target-home"

    state_getent_passwd_entry() {
        if [[ "${1:-}" == "dummy" ]]; then
            printf "dummy:x:1000:1000::%s:/bin/bash\n" "$stub_home"
            return 0
        fi
        return 1
    }

    mkdir -p "$stub_home/.acfs"
    printf '{"schema_version":3}\n' > "$stub_home/.acfs/state.json"

    run state_backup_and_remove
    assert_success

    run test ! -f "$stub_home/.acfs/state.json"
    assert_success

    run bash -lc "shopt -s nullglob; files=(\"$stub_home/.acfs/state.json.backup.\"*); [[ \${#files[@]} -eq 1 ]]"
    assert_success
}

@test "state: resolve target home rejects invalid fallback usernames" {
    unset ACFS_HOME
    unset ACFS_STATE_FILE
    export TARGET_HOME=""
    export TARGET_USER="../bad-user"
    export HOME="/"

    getent() {
        return 2
    }

    run state_resolve_target_home
    assert_failure
}

@test "state: resolve target home accepts dotted usernames but fails closed when unresolved" {
    unset ACFS_HOME
    unset ACFS_STATE_FILE
    export TARGET_HOME=""
    export TARGET_USER="john.doe"
    export HOME="/"

    getent() {
        return 2
    }

    run state_resolve_target_home
    assert_failure
}

@test "state: resolve target home prefers target user passwd home over stale TARGET_HOME" {
    local stale_home
    local passwd_home
    stale_home="$(create_temp_dir)"
    passwd_home="$(create_temp_dir)"

    unset ACFS_HOME
    unset ACFS_STATE_FILE
    export TARGET_HOME="$stale_home"
    export TARGET_USER="targetuser"
    export HOME="$stale_home"

    state_resolve_current_user() {
        printf 'calleruser\n'
    }

    state_getent_passwd_entry() {
        if [[ "${1:-}" == "targetuser" ]]; then
            printf 'targetuser:x:1000:1000::%s:/bin/bash\n' "$passwd_home"
            return 0
        fi
        return 1
    }

    run state_resolve_target_home
    assert_success
    assert_output "$passwd_home"
}

@test "state: resolve target home rejects invalid TARGET_USER before TARGET_HOME" {
    local target_home
    target_home="$(create_temp_dir)"

    unset ACFS_HOME
    unset ACFS_STATE_FILE
    export TARGET_HOME="$target_home"
    export TARGET_USER="../bad-user"
    export HOME="$target_home"

    run state_resolve_target_home
    assert_failure
}

@test "state: resolve target home fails closed for unresolved target with stale TARGET_HOME" {
    local stale_home
    stale_home="$(create_temp_dir)"

    unset ACFS_HOME
    unset ACFS_STATE_FILE
    export TARGET_HOME="$stale_home"
    export TARGET_USER="missinguser"
    export HOME="$stale_home"

    state_resolve_current_user() {
        printf 'calleruser\n'
    }

    state_getent_passwd_entry() {
        return 1
    }

    run state_resolve_target_home
    assert_failure
}

@test "state.sh: ownership target-home probes are best-effort under set -e" {
    run grep -n 'target_home="$(state_resolve_target_home)"' "$PROJECT_ROOT/scripts/lib/state.sh"
    assert_failure
}
