#!/usr/bin/env bash

# Functional tests for the bootstrap script. All fixtures live in a temporary
# directory, including their simulated home directories and Git repositories.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BOOTSTRAP="${ROOT}/scripts/bootstrap.sh"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/workspace-bootstrap-test.XXXXXX")"

pass_count=0

cleanup() {
  rm -rf "${TEST_ROOT}"
}

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

pass() {
  pass_count=$((pass_count + 1))
  printf 'PASS: %s\n' "$*"
}

assert_file_contains() {
  local file="$1"
  local expected="$2"

  grep -F -- "${expected}" "${file}" >/dev/null || fail "Expected '${expected}' in ${file}."
}

assert_failure() {
  if "$@"; then
    fail "Expected command to fail: $*"
  fi
}

new_fixture() {
  local name="$1"
  local fixture="${TEST_ROOT}/${name}"

  mkdir -p "${fixture}/managed" "${fixture}/manifests" "${fixture}/scripts"
  fixture="$(cd "${fixture}" && pwd -P)"
  cp "${BOOTSTRAP}" "${fixture}/scripts/bootstrap.sh"
  chmod +x "${fixture}/scripts/bootstrap.sh"
  printf '%s\n' '# source_path_below_managed | absolute_destination_path' > "${fixture}/manifests/links.conf"
  printf '%s\n' '# kind | name | check | installation_hint' > "${fixture}/manifests/dependencies.conf"
  printf '%s\n' '# name | url | destination_relative_to_workspace' > "${fixture}/manifests/repositories.conf"
  printf '%s\n' 'fixture source' > "${fixture}/managed/source-file"
  printf '%s\n' "${fixture}"
}

trap cleanup EXIT

if [[ "$(uname -s)" != "Darwin" ]]; then
  fail "Functional tests require macOS, matching the supported bootstrap platform."
fi

bash -n "${BOOTSTRAP}"
"${BOOTSTRAP}" --help > "${TEST_ROOT}/help.out"
assert_file_contains "${TEST_ROOT}/help.out" 'manifests/links.conf'
pass 'help and shell syntax'

"${BOOTSTRAP}" --check > "${TEST_ROOT}/default-check.out"
"${BOOTSTRAP}" --link > "${TEST_ROOT}/default-link.out"
"${BOOTSTRAP}" --repos > "${TEST_ROOT}/default-repos.out"
assert_file_contains "${TEST_ROOT}/default-link.out" 'No links declared.'
assert_file_contains "${TEST_ROOT}/default-repos.out" 'No external repositories declared.'
pass 'default template validation'

link_fixture="$(new_fixture link)"
link_destination="${link_fixture}/test-home/nested/.linked-source"
printf '%s | %s\n' ' managed/source-file ' "${link_destination}" >> "${link_fixture}/manifests/links.conf"
"${link_fixture}/scripts/bootstrap.sh" --link > "${link_fixture}/first-link.out"
test -L "${link_destination}" || fail 'Expected link destination to be a symlink.'
test "$(readlink "${link_destination}")" = "${link_fixture}/managed/source-file" || fail 'Link target did not match fixture source.'
assert_file_contains "${link_fixture}/first-link.out" "Linked ${link_destination}"
"${link_fixture}/scripts/bootstrap.sh" --link > "${link_fixture}/second-link.out"
assert_file_contains "${link_fixture}/second-link.out" "Already linked ${link_destination}"
pass 'link creation and idempotency'

conflict_fixture="$(new_fixture conflict)"
conflict_destination="${conflict_fixture}/test-home/.linked-source"
printf '%s | %s\n' 'managed/source-file' "${conflict_destination}" >> "${conflict_fixture}/manifests/links.conf"
mkdir -p "${conflict_fixture}/test-home"
printf '%s\n' 'keep this file' > "${conflict_destination}"
assert_failure "${conflict_fixture}/scripts/bootstrap.sh" --link
test ! -L "${conflict_destination}" || fail 'Existing file was replaced with a link.'
assert_file_contains "${conflict_destination}" 'keep this file'
pass 'link conflict protection'

invalid_fixture="$(new_fixture invalid)"
invalid_destination="${invalid_fixture}/test-home/.missing-target"
printf '%s | %s\n' 'managed/missing-file' "${invalid_destination}" >> "${invalid_fixture}/manifests/links.conf"
assert_failure "${invalid_fixture}/scripts/bootstrap.sh" --link
test ! -e "${invalid_fixture}/test-home/.missing-target" || fail 'Missing source created a destination.'
printf '%s\n' "managed/source-file | ${invalid_fixture}/test-home/.target | unexpected" > "${invalid_fixture}/manifests/links.conf"
assert_failure "${invalid_fixture}/scripts/bootstrap.sh" --link
test ! -e "${invalid_fixture}/test-home/.target" || fail 'Malformed manifest created a destination.'
printf '%s\n' 'home/source-file | /tmp/not-allowed' > "${invalid_fixture}/manifests/links.conf"
assert_failure "${invalid_fixture}/scripts/bootstrap.sh" --link
printf '%s\n' 'managed/source-file | relative-target' > "${invalid_fixture}/manifests/links.conf"
assert_failure "${invalid_fixture}/scripts/bootstrap.sh" --link
pass 'link manifest validation'

repo_fixture="$(new_fixture repositories)"
git init --bare "${repo_fixture}/source.git" >/dev/null
printf '%s | %s | %s\n' 'fixture-repository' "${repo_fixture}/source.git" 'fixture-repository' >> "${repo_fixture}/manifests/repositories.conf"
HOME="${repo_fixture}/test-home" "${repo_fixture}/scripts/bootstrap.sh" --repos > "${repo_fixture}/first-repo.out"
test -d "${repo_fixture}/test-home/workspace/fixture-repository/.git" || fail 'Expected external repository to be cloned.'
assert_file_contains "${repo_fixture}/first-repo.out" 'Cloned fixture-repository'
assert_failure env HOME="${repo_fixture}/test-home" "${repo_fixture}/scripts/bootstrap.sh" --repos
test -d "${repo_fixture}/test-home/workspace/fixture-repository/.git" || fail 'Existing external repository was changed or removed.'
pass 'repository cloning and existing-destination protection'

printf 'All %s functional tests passed.\n' "${pass_count}"
