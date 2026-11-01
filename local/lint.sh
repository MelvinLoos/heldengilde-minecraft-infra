#!/usr/bin/env bash
# Repo checks shared by CI and local runs. Exits non-zero if any check fails.
set -uo pipefail

cd "$(dirname "$0")/.." || exit 1
fails=0
check() { # name command...
  local n=$1; shift
  if out=$("$@" 2>&1); then echo "PASS $n"; else echo "FAIL $n"; echo "$out" | head -20; fails=$((fails + 1)); fi
}

mapfile -t shell_files < <(git ls-files '*.sh')
mapfile -t json_files < <(git ls-files '*.json')

check "yamllint"                  yamllint -c .yamllint .
check "shellcheck"                shellcheck "${shell_files[@]}"
check "json files are valid"      jq empty "${json_files[@]}"
check "no jars tracked by git"    test -z "$(git ls-files "*.jar")"
check "egg.yaml is in sync"       bash -c 'diff <(4-server/build-egg.sh) 4-server/egg.yaml'
check "ansible-lint"              ansible-lint 3-ansible 1-host-bootstrap
check "ansible syntax"            bash -c 'cd 3-ansible && ANSIBLE_CONFIG=ansible.cfg ansible-playbook --syntax-check -i inventory/laptop-test.yml site.yml && cd ../1-host-bootstrap && ansible-playbook --syntax-check -i ../3-ansible/inventory/laptop-test.yml playbook.yml'
check "jar lock is well formed"   jq -e '
  .jars | length > 0 and all(.[];
    (.name | test("^[A-Za-z0-9._-]+\\.jar$")) and
    (.sha256 | test("^[0-9a-f]{64}$")) and
    (.source | test("^https://") or test("^local:[A-Za-z0-9._-]+\\.jar$")))' 4-server/custom-jars.lock.json
check "plugin pins are versioned" bash -c '! grep -vE "^(#|$)" 4-server/plugins.txt 4-server/plugins-26.3.txt | grep -vE ":[A-Za-z0-9]{8}$"'
# shellcheck disable=SC2016 # single quotes are intentional: the inner bash expands
check "dungeon safety gamerules" bash -c 'f=4-server/config/plugins/MythicDungeons/config.yml; grep -q "keepInventory: true" $f && grep -q "mobGriefing: false" $f && grep -q "doDaylightCycle: false" $f && grep -q "doWeatherCycle: false" $f'
# shellcheck disable=SC2016
check "CFG_ placeholders are egg variables" bash -c 'for v in $(grep -rhoE "\$\{CFG_[A-Z0-9_]+\}" 4-server/config | sort -u | tr -d "\${}"); do grep -q "env_variable: $v\$" 4-server/egg.yaml || { echo "missing $v"; exit 1; }; done'
check "env has no secrets"        bash -c '! grep -E "^CFG_|TOKEN|PASSWORD|SECRET" 4-server/env/server.env'

echo "failures: $fails"
exit "$fails"
