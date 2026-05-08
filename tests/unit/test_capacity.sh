#!/usr/bin/env bash
# ============================================================
# Unit tests for acfs capacity report
# ============================================================

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CAPACITY_SH="$REPO_ROOT/scripts/lib/capacity.sh"

TESTS_PASSED=0
TESTS_FAILED=0
ARTIFACT_DIR="${ACFS_CAPACITY_TEST_ARTIFACTS_DIR:-${TMPDIR:-/tmp}/acfs-capacity-test-artifacts-$(date +%Y%m%d-%H%M%S)-$$}"

mkdir -p "$ARTIFACT_DIR"

pass() {
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo "PASS: $1"
}

fail() {
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "FAIL: $1"
    [[ -n "${2:-}" ]] && echo "  Reason: $2"
}

run_capacity_json() {
    ACFS_CAPACITY_CPU_COUNT="$1" \
    ACFS_CAPACITY_MEM_TOTAL_KB="$2" \
    ACFS_CAPACITY_DISK_AVAILABLE_KB="$3" \
    ACFS_CAPACITY_RCH_AVAILABLE="$4" \
    ACFS_CAPACITY_NTM_AVAILABLE="$5" \
    bash "$CAPACITY_SH" --json "${@:6}"
}

write_fixture_artifact() {
    local name="$1"
    local cpu_count="$2"
    local mem_total_kb="$3"
    local disk_available_kb="$4"
    local rch_available="$5"
    local ntm_available="$6"
    shift 6

    {
        echo "test=$name"
        echo "cpu_count=$cpu_count"
        echo "mem_total_kb=$mem_total_kb"
        echo "disk_available_kb=$disk_available_kb"
        echo "rch_available=$rch_available"
        echo "ntm_available=$ntm_available"
        printf 'args='
        printf ' %q' "$@"
        printf '\n'
    } > "$ARTIFACT_DIR/${name}.fixture"
}

write_output_artifact() {
    local name="$1"
    local extension="$2"
    local content="$3"

    printf '%s\n' "$content" > "$ARTIFACT_DIR/${name}.${extension}"
}

run_capacity_json_fixture() {
    local name="$1"
    local cpu_count="$2"
    local mem_total_kb="$3"
    local disk_available_kb="$4"
    local rch_available="$5"
    local ntm_available="$6"
    shift 6

    write_fixture_artifact "$name" "$cpu_count" "$mem_total_kb" "$disk_available_kb" "$rch_available" "$ntm_available" "$@"

    local output
    output="$(run_capacity_json "$cpu_count" "$mem_total_kb" "$disk_available_kb" "$rch_available" "$ntm_available" "$@")"
    write_output_artifact "$name" "json" "$output"
    printf '%s\n' "$output"
}

test_high_capacity_json() {
    local output
    output="$(run_capacity_json_fixture high_capacity_json 64 268435456 314572800 true true --profile 25-agents --recommend-ntm)"

    jq -e '
      .schema_version == 1 and
      .host.cpu_count == 64 and
      .host.mem_total_mib == 262144 and
      .tools.rch.available == true and
      .capacity.safe_agent_count == 64 and
      .capacity.recommended_agent_count == 44 and
      .profile_check.status == "pass" and
      .ntm.agent_count == 44 and
      (.ntm.profiles | length) == 4 and
      (.ntm.profiles[] | select(.agents == 25 and .status == "pass" and (.command | contains("ntm spawn myproject --label swarm-25")))) and
      (.ntm.profiles[] | select(.agents == 50 and .status == "warn" and (.rch_policy | contains("rch exec --"))))
    ' <<<"$output" >/dev/null || return 1

    pass "high_capacity_json"
}

test_profile_warns_above_recommended() {
    local output
    output="$(run_capacity_json_fixture profile_warns_above_recommended 64 268435456 314572800 true true --profile 50)"

    jq -e '.profile_check.status == "warn" and .profile_check.requested_agents == 50' <<<"$output" >/dev/null || return 1

    pass "profile_warns_above_recommended"
}

test_small_host_fails_oversized_profile() {
    local output
    output="$(run_capacity_json_fixture small_host_fails_oversized_profile 2 4194304 15728640 false false --profile 10)"

    jq -e '
      .status == "fail" and
      .tools.rch.available == false and
      .capacity.safe_agent_count == 0 and
      .profile_check.status == "fail"
    ' <<<"$output" >/dev/null || return 1

    pass "small_host_fails_oversized_profile"
}

test_heavy_workload_capacity() {
    local output
    output="$(run_capacity_json_fixture heavy_workload_capacity 16 67108864 209715200 true true --workload heavy --profile 8)"

    jq -e '
      .assumptions.workload == "heavy" and
      .assumptions.per_agent_mib == 4096 and
      .assumptions.cpu_milli_per_agent == 2000 and
      .capacity.cpu_limited_agents == 8 and
      .capacity.safe_agent_count == 8 and
      .profile_check.status == "warn"
    ' <<<"$output" >/dev/null || return 1

    pass "heavy_workload_capacity"
}

test_low_disk_fails_capacity() {
    local output
    output="$(run_capacity_json_fixture low_disk_fails_capacity 16 67108864 4096 true true --profile 1)"

    jq -e '
      .status == "fail" and
      .capacity.disk_limited_agents == 0 and
      .capacity.safe_agent_count == 0 and
      .profile_check.status == "fail"
    ' <<<"$output" >/dev/null || return 1

    pass "low_disk_fails_capacity"
}

test_invalid_workload_exits_2() {
    local output status

    set +e
    output="$(bash "$CAPACITY_SH" --workload impossible 2>&1)"
    status=$?
    set -e
    write_output_artifact "invalid_workload_exits_2" "stderr" "$output"

    [[ "$status" -eq 2 ]] || return 1
    grep -Fq "unsupported workload" <<<"$output" || return 1

    pass "invalid_workload_exits_2"
}

test_human_output() {
    local output
    output="$(
        ACFS_CAPACITY_CPU_COUNT=8 \
        ACFS_CAPACITY_MEM_TOTAL_KB=33554432 \
        ACFS_CAPACITY_DISK_AVAILABLE_KB=104857600 \
        ACFS_CAPACITY_RCH_AVAILABLE=true \
        ACFS_CAPACITY_NTM_AVAILABLE=false \
        bash "$CAPACITY_SH" --workload standard --profile 5 --recommend-ntm
    )"
    write_fixture_artifact human_output 8 33554432 104857600 true false --workload standard --profile 5 --recommend-ntm
    write_output_artifact "human_output" "txt" "$output"

    grep -Fq "ACFS Capacity Report" <<<"$output" || return 1
    grep -Fq "Recommended agents:" <<<"$output" || return 1
    grep -Fq "Profile Check" <<<"$output" || return 1
    grep -Fq "Launch Profiles" <<<"$output" || return 1
    grep -Fq "25 agents:" <<<"$output" || return 1
    grep -Fq "Agent Mail:" <<<"$output" || return 1

    pass "human_output"
}

run_test() {
    local name="$1"
    if "$name"; then
        return 0
    fi
    fail "$name"
}

main() {
    command -v jq >/dev/null 2>&1 || {
        echo "jq is required for capacity tests" >&2
        exit 1
    }

    run_test test_high_capacity_json
    run_test test_profile_warns_above_recommended
    run_test test_small_host_fails_oversized_profile
    run_test test_heavy_workload_capacity
    run_test test_low_disk_fails_capacity
    run_test test_invalid_workload_exits_2
    run_test test_human_output

    echo "Results: $TESTS_PASSED passed, $TESTS_FAILED failed"
    echo "Artifacts: $ARTIFACT_DIR"
    [[ $TESTS_FAILED -eq 0 ]]
}

main "$@"
