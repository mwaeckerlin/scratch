#!/usr/bin/env bash
# Config contract: the definitions every derived image relies on are in place.
#
# The image has no shell, so nothing is asked inside a running container: the
# environment and the user come from `docker image inspect`, the user and
# group files are copied out of a created (never started) container, and the
# build argument `lang` is checked on a child image built FROM this one.
#
# Usage: tests/config-contract.sh IMAGE

set -uo pipefail

IMAGE="${1:?usage: tests/config-contract.sh IMAGE}"

PASS=0
FAIL=0
declare -a FAILED_NAMES

_pass() { PASS=$((PASS + 1)); echo "  PASS  $1"; }
_fail() { FAIL=$((FAIL + 1)); FAILED_NAMES+=("$1"); echo "  FAIL  $1: $2"; }

_env_is() {
    local name="$1" expected="$2"
    local value
    value=$(docker image inspect --format '{{range .Config.Env}}{{println .}}{{end}}' "${IMAGE}" | sed -n "s/^${name}=//p")
    if [[ "${value}" == "${expected}" ]]; then
        _pass "env_${name}"
    else
        _fail "env_${name}" "expected '${expected}', got '${value}'"
    fi
}

echo "==> Config contract: definitions for derived images"

if ! docker image inspect "${IMAGE}" > /dev/null 2>&1; then
    _fail "${IMAGE}_image_exists" "image not built — run 'npm run build' first"
else
    _env_is RUN_USER somebody
    _env_is RUN_GROUP somebody
    _env_is RUN_HOME /home/somebody
    _env_is BUILD_USER coder
    _env_is BUILD_GROUP coder
    _env_is BUILD_HOME /home/coder
    _env_is SHARED_GROUP_NAME shared-access
    _env_is SHARED_GROUP_ID 500
    _env_is LANG en_US.UTF-8
    _env_is PKG_INSTALL "apk add --no-cache --clean-protected -u"
    _env_is PKG_REMOVE "apk del --no-cache --purge"
    _env_is PKG_SEARCH "apk search --no-cache"
    _env_is ALLOW_USER "chown -R somebody:somebody"
    _env_is ALLOW_BUILD "chown -R coder:coder"

    PS1_VALUE=$(docker image inspect --format '{{range .Config.Env}}{{println .}}{{end}}' "${IMAGE}" | sed -n 's/^PS1=//p')
    if [[ "${PS1_VALUE}" == *'${CONTAINERNAME}'* ]]; then
        _pass "env_PS1_shows_container"
    else
        _fail "env_PS1_shows_container" "prompt does not show the container name: '${PS1_VALUE}'"
    fi

    USER_VALUE=$(docker image inspect --format '{{.Config.User}}' "${IMAGE}")
    if [[ "${USER_VALUE}" == "somebody" ]]; then
        _pass "runs_as_somebody"
    else
        _fail "runs_as_somebody" "image user is '${USER_VALUE}'"
    fi

    CONTAINER=$(docker create --pull=never "${IMAGE}" /none)
    PASSWD=$(docker cp "${CONTAINER}:/etc/passwd" - | tar -xO)
    GROUP=$(docker cp "${CONTAINER}:/etc/group" - | tar -xO)
    HOMES=$(docker cp "${CONTAINER}:/home" - | tar -t)
    docker rm "${CONTAINER}" > /dev/null

    for user in somebody coder; do
        if echo "${PASSWD}" | grep -q "^${user}:"; then
            _pass "passwd_${user}"
        else
            _fail "passwd_${user}" "user missing in /etc/passwd"
        fi
        if echo "${HOMES}" | grep -qx "home/${user}/"; then
            _pass "home_${user}"
        else
            _fail "home_${user}" "home directory missing"
        fi
    done
    if echo "${GROUP}" | grep -q '^shared-access:x:500:.*somebody'; then
        _pass "shared_group_500_with_somebody"
    else
        _fail "shared_group_500_with_somebody" "group shared-access:500 missing or somebody not a member"
    fi

    CHILD="${IMAGE%%:*}-config-contract-child"
    if printf 'FROM %s\n' "${IMAGE}" | docker build --quiet --build-arg lang=de_CH.UTF-8 -t "${CHILD}" - > /dev/null 2>&1; then
        CHILD_LANG=$(docker image inspect --format '{{range .Config.Env}}{{println .}}{{end}}' "${CHILD}" | sed -n 's/^LANG=//p')
        docker image rm "${CHILD}" > /dev/null
        if [[ "${CHILD_LANG}" == "de_CH.UTF-8" ]]; then
            _pass "child_lang_build_arg"
        else
            _fail "child_lang_build_arg" "child LANG is '${CHILD_LANG}'"
        fi
    else
        _fail "child_lang_build_arg" "child image does not build"
    fi
fi

echo ""
echo "==> Config contract results: ${PASS} passed, ${FAIL} failed"
if [[ ${FAIL} -gt 0 ]]; then
    echo "==> Failed contracts: ${FAILED_NAMES[*]}"
    exit 1
fi
