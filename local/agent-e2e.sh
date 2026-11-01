#!/usr/bin/env bash
# End-to-end test of hg-gitops against the systemd Ubuntu target (local/target/up.sh + 3-ansible laptop-test).
# Needs the server installed and running. Prints PASS/FAIL per check; exit code = failures.
set -uo pipefail

on() { docker exec hg-target bash -c "$*"; }
fails=0
check() { # name command...
  local n=$1; shift
  if "$@"; then echo "PASS $n"; else echo "FAIL $n"; fails=$((fails + 1)); fi
}
# shellcheck disable=SC2016 # expanded on the target
UUID=$(on '. /etc/hg-gitops/stack.env; K=$(cat $STATE_DIR/app-key); curl -s -H "Host: $PANEL_HOST" -H "Authorization: Bearer $K" -H "Accept: application/json" $PANEL_URL/api/application/servers | jq -r ".data[0].attributes.uuid"')
VOL=/var/lib/pelican/volumes/$UUID
AGENT=/srv/heldengilde/gitops/agent/hg-gitops.sh
echo "server $UUID"

# Fresh content repo with one commit, and a clean agent state, so the test can be re-run.
on 'rm -rf /srv/test-content.git /tmp/cw /srv/heldengilde/content /srv/heldengilde/content-autosync /srv/heldengilde/state/content-deployed
  git init -q --bare -b main /srv/test-content.git && git clone -q /srv/test-content.git /tmp/cw 2>/dev/null && cd /tmp/cw
  mkdir -p BetonQuest/hub MythicMobs/Mobs MythicMobs/Skills MythicMobs/Items server-owned
  echo "# quest v1" > BetonQuest/hub/package.yml; echo "HubGuard: {Type: ZOMBIE}" > MythicMobs/Mobs/hub.yml
  touch MythicMobs/Skills/.keep MythicMobs/Items/.keep server-owned/.keep
  git add -A && git -c user.name=t -c user.email=t@t commit -qm "initial content" && git push -q origin main'
push() { on "cd /tmp/cw && git add -A && git -c user.name=t -c user.email=t@t commit -qm '$1' && git push -q origin main"; }

echo "--- deploy-content"
on "$AGENT deploy-content"
check "BetonQuest package deployed"   on "grep -q 'quest v1' $VOL/plugins/BetonQuest/QuestPackages/hub/package.yml"
check "MythicMobs mob deployed"       on "test -f $VOL/plugins/MythicMobs/Mobs/hub.yml"
check "files owned by uid 988"        on "test \"\$(stat -c %u $VOL/plugins/BetonQuest/QuestPackages/hub/package.yml)\" = 988"

echo "--- deletion propagates, server-owned files survive"
on "mkdir -p $VOL/plugins/Citizens && echo 'npc: guard' > $VOL/plugins/Citizens/saves.yml"
on "cd /tmp/cw && git rm -q MythicMobs/Mobs/hub.yml && echo '# quest v2' > BetonQuest/hub/package.yml"
push "update content"
on "$AGENT deploy-content"
check "package updated"               on "grep -q 'quest v2' $VOL/plugins/BetonQuest/QuestPackages/hub/package.yml"
check "deleted mob removed (B4)"      on "! test -e $VOL/plugins/MythicMobs/Mobs/hub.yml"
check "Citizens save untouched"       on "grep -q 'npc: guard' $VOL/plugins/Citizens/saves.yml"
check "no redeploy when unchanged"    bash -c "! docker exec hg-target $AGENT deploy-content | grep -q deployed"

echo "--- snapshot-server-content"
on "mkdir -p $VOL/plugins/MythicDungeons/maps/crypt $VOL/plugins/MythicDungeons/loottables && echo 'triggers: []' > $VOL/plugins/MythicDungeons/maps/crypt/triggers.yml && echo 'loot: x' > $VOL/plugins/MythicDungeons/loottables/a.yml && head -c 1000 /dev/urandom > $VOL/plugins/MythicDungeons/maps/crypt/region.dat"
on "HG_SAVE_WAIT=1 $AGENT snapshot-server-content"
check "autosync/server branch pushed" on "git -C /srv/test-content.git rev-parse --verify -q autosync/server >/dev/null"
# Citizens rewrites saves.yml on `citizens save`, so only check that the file made it into the snapshot.
check "saves.yml in snapshot"         on "git -C /srv/test-content.git cat-file -e autosync/server:server-owned/Citizens/saves.yml"
check "dungeon YAML in snapshot"      on "git -C /srv/test-content.git show autosync/server:server-owned/MythicDungeons/maps/crypt/triggers.yml >/dev/null"
check "world data NOT in snapshot"    on "! git -C /srv/test-content.git ls-tree -r --name-only autosync/server | grep -q region.dat"
check "main untouched by agent"       on "test \"\$(git -C /srv/test-content.git log --format=%s main | head -1)\" = 'update content'"
before=$(on "git -C /srv/test-content.git rev-parse autosync/server")
on "HG_SAVE_WAIT=1 $AGENT snapshot-server-content" >/dev/null
check "second snapshot is a no-op"    test "$before" = "$(on "git -C /srv/test-content.git rev-parse autosync/server")"

echo "--- infra sync in rsync mode"
check "sync-infra skips non-git"      on "$AGENT sync-infra | grep -q skipping"

echo "failures: $fails"
exit "$fails"
