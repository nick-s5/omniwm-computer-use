#!/usr/bin/env bash
set -euo pipefail

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
skill_dir=$(CDPATH= cd -- "$script_dir/.." && pwd -P)
test_root=$(mktemp -d "${TMPDIR:-/tmp}/omniwm-verify-test.XXXXXX")
test_root=$(CDPATH= cd -- "$test_root" && pwd -P)
trap 'rm -R "$test_root"' EXIT

export CODEX_HOME="$test_root/codex"
export OMNIWM_APP_PATH="$test_root/OmniWM.app"
export OMNIWM_SETTINGS="$test_root/settings.toml"
export FAKE_CTL_LOG="$test_root/ctl.log"
export TMPDIR="$test_root/tmp"
mkdir -p "$CODEX_HOME/skills" "$OMNIWM_APP_PATH/Contents/MacOS" "$TMPDIR"
ln -s "$skill_dir" "$CODEX_HOME/skills/omniwm-computer-use"
printf '%s\n' '<!-- omniwm-computer-use:begin -->' \
  "$CODEX_HOME/skills/omniwm-computer-use/SKILL.md" \
  '<!-- omniwm-computer-use:end -->' >"$CODEX_HOME/AGENTS.md"
printf '[general]\nipcEnabled = true\n' >"$OMNIWM_SETTINGS"

fake_ctl="$OMNIWM_APP_PATH/Contents/MacOS/omniwmctl"
cat >"$fake_ctl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$FAKE_CTL_LOG"
case "${1:-}" in
  ping) printf '%s\n' pong ;;
  version)
    jq -n --argjson protocol "$FAKE_PROTOCOL" \
      '{ok:true,result:{kind:"version",payload:{appVersion:"test",protocolVersion:$protocol}}}'
    ;;
  query)
    case "${2:-}" in
      capabilities)
        jq -n --argjson protocol "$FAKE_PROTOCOL" --arg schema "${FAKE_SCHEMA:-valid}" '
          {ok:true,result:{kind:"capabilities",payload:{protocolVersion:$protocol,
            commands:[
              {name:"resize",path:"command resize <horizontal|vertical> <grow|shrink>"},
              {name:"resize-focused",path:"command resize-focused <grow|shrink>"}],
            queries:[{name:"focused-window"},{name:"windows"}],
            subscriptions:(if $schema == "valid" then
              [{channel:"focus",resultKind:"focused-window"}] else [] end),
            windowActions:[{name:"focus",path:"window focus <opaque-id>"}]}}}'
        ;;
      focused-window)
        jq -n '{ok:true,result:{kind:"focused-window",payload:{window:
          {id:"protected",app:{bundleId:"com.test.Protected",name:"Protected"}}}}}'
        ;;
      windows)
        jq -n '{ok:true,result:{kind:"windows",payload:{windows:[
          {id:"protected",app:{bundleId:"com.test.Protected",name:"Protected"}}]}}}'
        ;;
      *) exit 64 ;;
    esac
    ;;
  window)
    [[ "${2:-}" == focus && "${3:-}" == protected ]] || exit 64
    ;;
  *) exit 64 ;;
esac
EOF
chmod +x "$fake_ctl"

for protocol in 10 19; do
  export FAKE_PROTOCOL=$protocol
  : >"$FAKE_CTL_LOG"
  "$skill_dir/scripts/verify-setup.sh" >"$test_root/output"
  rg -q 'verified \(read-only\)' "$test_root/output"
  if rg -q '^(window|watch) ' "$FAKE_CTL_LOG"; then
    printf 'FAIL: default verification ran a focus/watch command for protocol %s.\n' "$protocol" >&2
    exit 1
  fi
done

export FAKE_PROTOCOL=20
if "$skill_dir/scripts/verify-setup.sh" >"$test_root/output" 2>&1; then
  printf '%s\n' 'FAIL: unknown protocol was accepted.' >&2
  exit 1
fi
rg -q 'protocol 20 is unsupported' "$test_root/output"

export FAKE_PROTOCOL=19 FAKE_SCHEMA=bad
if "$skill_dir/scripts/verify-setup.sh" >"$test_root/output" 2>&1; then
  printf '%s\n' 'FAIL: incompatible guard capabilities were accepted.' >&2
  exit 1
fi
rg -q 'incompatible capabilities response' "$test_root/output"

unset FAKE_SCHEMA
: >"$FAKE_CTL_LOG"
"$skill_dir/scripts/verify-setup.sh" --check-restore >"$test_root/output"
rg -q 'verified \(restore check\)' "$test_root/output"
rg -q '^window focus protected$' "$FAKE_CTL_LOG"

printf '%s\n' 'PASS: read-only default, supported protocols, schema rejection, and explicit restore.'
