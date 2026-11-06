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

run_interactive_link() {
  local input="$1"
  local bootstrap_script="$2"

  WORKFRAME_TEST_INPUT="${input}" WORKFRAME_TEST_SCRIPT="${bootstrap_script}" expect -c '
    set timeout 5
    spawn $env(WORKFRAME_TEST_SCRIPT) --link
    expect -re {override and link\? }
    send -- "$env(WORKFRAME_TEST_INPUT)\r"
    expect eof
    lassign [wait] _ _ _ exit_status
    exit $exit_status
  '
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
mkdir -p "${link_fixture}/managed/source-directory"
printf '%s\n' 'directory source' > "${link_fixture}/managed/source-directory/settings"
directory_destination="${link_fixture}/test-home/.linked-directory"
printf '%s | %s\n' 'managed/source-directory' "${directory_destination}" >> "${link_fixture}/manifests/links.conf"
"${link_fixture}/scripts/bootstrap.sh" --link > "${link_fixture}/first-link.out"
test -L "${link_destination}" || fail 'Expected link destination to be a symlink.'
test "$(readlink "${link_destination}")" = "${link_fixture}/managed/source-file" || fail 'Link target did not match fixture source.'
test -L "${directory_destination}" || fail 'Expected directory destination to be a symlink.'
test "$(readlink "${directory_destination}")" = "${link_fixture}/managed/source-directory" || fail 'Directory link target did not match fixture source.'
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

backup_fixture="$(new_fixture backup)"
backup_destination="${backup_fixture}/test-home/.linked-source"
printf '%s | %s\n' 'managed/source-file' "${backup_destination}" >> "${backup_fixture}/manifests/links.conf"
mkdir -p "${backup_fixture}/test-home"
printf '%s\n' 'back me up' > "${backup_destination}"
run_interactive_link 'b' "${backup_fixture}/scripts/bootstrap.sh" > "${backup_fixture}/backup-link.out"
test -L "${backup_destination}" || fail 'Backup choice did not create a symlink.'
backup_file="$(find "${backup_fixture}/test-home" -name '.linked-source.*.bak' -type f -print -quit)"
test -n "${backup_file}" || fail 'Backup choice did not create an adjacent backup.'
assert_file_contains "${backup_file}" 'back me up'
pass 'interactive backup conflict resolution'

override_fixture="$(new_fixture override)"
override_destination="${override_fixture}/test-home/.linked-source"
printf '%s | %s\n' 'managed/source-file' "${override_destination}" >> "${override_fixture}/manifests/links.conf"
mkdir -p "${override_destination}"
printf '%s\n' 'replace me' > "${override_destination}/nested-file"
run_interactive_link 'o' "${override_fixture}/scripts/bootstrap.sh" > "${override_fixture}/override-link.out"
test -L "${override_destination}" || fail 'Override choice did not replace the directory with a symlink.'
test ! -e "${override_destination}/nested-file" || fail 'Override retained the replaced directory contents.'
pass 'interactive override conflict resolution'

abort_fixture="$(new_fixture abort)"
abort_destination="${abort_fixture}/test-home/.linked-source"
printf '%s | %s\n' 'managed/source-file' "${abort_destination}" >> "${abort_fixture}/manifests/links.conf"
mkdir -p "${abort_fixture}/test-home"
printf '%s\n' 'keep me' > "${abort_destination}"
assert_failure run_interactive_link 'a' "${abort_fixture}/scripts/bootstrap.sh"
test ! -L "${abort_destination}" || fail 'Abort choice created a symlink.'
assert_file_contains "${abort_destination}" 'keep me'
pass 'interactive abort conflict resolution'

atomic_abort_fixture="$(new_fixture atomic-abort)"
atomic_free_destination="${atomic_abort_fixture}/test-home/.new-link"
atomic_conflict_destination="${atomic_abort_fixture}/test-home/.existing-link"
printf '%s | %s\n' 'managed/source-file' "${atomic_free_destination}" >> "${atomic_abort_fixture}/manifests/links.conf"
printf '%s | %s\n' 'managed/source-file' "${atomic_conflict_destination}" >> "${atomic_abort_fixture}/manifests/links.conf"
mkdir -p "${atomic_abort_fixture}/test-home"
printf '%s\n' 'keep me too' > "${atomic_conflict_destination}"
assert_failure run_interactive_link 'a' "${atomic_abort_fixture}/scripts/bootstrap.sh"
test ! -e "${atomic_free_destination}" && test ! -L "${atomic_free_destination}" || fail 'Abort changed a non-conflicting destination.'
assert_file_contains "${atomic_conflict_destination}" 'keep me too'
pass 'interactive abort has no partial changes'

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
printf '%s | %s\n%s | %s\n' 'managed/source-file' "${invalid_fixture}/test-home/.duplicate" 'managed/source-file' "${invalid_fixture}/test-home/.duplicate" > "${invalid_fixture}/manifests/links.conf"
assert_failure "${invalid_fixture}/scripts/bootstrap.sh" --link
test ! -e "${invalid_fixture}/test-home/.duplicate" || fail 'Duplicate destinations created a link.'
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
