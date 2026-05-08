#!/usr/bin/env bash
# ============================================================
# Unit tests for acfs capacity report
# ============================================================

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CAPACITY_SH="$REPO_ROOT/scripts/lib/capacity.sh"

TESTS_PASSED=0
TESTS_FAILED=0

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

test_high_capacity_json() {
    local output
    output="$(run_capacity_json 64 268435456 314572800 true true --profile 25-agents --recommend-ntm)"

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
    ' <<<"$output" >/dev/null

    pass "high_capacity_json"
}

test_profile_warns_above_recommended() {
    local output
    output="$(run_capacity_json 64 268435456 314572800 true true --profile 50)"

    jq -e '.profile_check.status == "warn" and .profile_check.requested_agents == 50' <<<"$output" >/dev/null

    pass "profile_warns_above_recommended"
}

test_small_host_fails_oversized_profile() {
    local output
    output="$(run_capacity_json 2 4194304 15728640 false false --profile 10)"

    jq -e '
      .status == "warn" and
      .tools.rch.available == false and
      .capacity.safe_agent_count == 1 and
      .profile_check.status == "fail"
    ' <<<"$output" >/dev/null

    pass "small_host_fails_oversized_profile"
}

test_human_output() {
    local output
    output="$(
        ACFS_CAPACITY_CPU_COUNT=8 \
        ACFS_CAPACITY_MEM_TOTAL_KB=33554432 \
        ACFS_CAPACITY_DISK_AVAILABLE_KB=104857600 \
        ACFS_CAPACITY_RCH_AVAILABLE=true \
        ACFS_CAPACITY_NTM_AVAILABLE=false \
        bash "$CAPACITY_SH" --workload standard --profile 5
    )"

    grep -Fq "ACFS Capacity Report" <<<"$output"
    grep -Fq "Recommended agents:" <<<"$output"
    grep -Fq "Profile Check" <<<"$output"
    grep -Fq "Launch Profiles" <<<"$output"
    grep -Fq "25 agents:" <<<"$output"
    grep -Fq "Agent Mail:" <<<"$output"

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
    run_test test_human_output

    echo "Results: $TESTS_PASSED passed, $TESTS_FAILED failed"
    [[ $TESTS_FAILED -eq 0 ]]
}

main "$@"
