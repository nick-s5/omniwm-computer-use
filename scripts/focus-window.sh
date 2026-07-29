#!/usr/bin/env bash
set -euo pipefail

usage() {
  printf '%s\n' \
    'Usage:' \
    '  focus-window.sh --bundle-id <id> [--title-contains <text>] [--fit-visible]' \
    '  focus-window.sh --app <name> [--title-contains <text>] [--fit-visible]'
}

bundle_id=''
app_name=''
title_contains=''
fit_visible=false

while (($#)); do
  case "$1" in
    --bundle-id)
      [[ $# -ge 2 ]] || { usage >&2; exit 64; }
      bundle_id=$2
      shift 2
      ;;
    --app)
      [[ $# -ge 2 ]] || { usage >&2; exit 64; }
      app_name=$2
      shift 2
      ;;
    --title-contains)
      [[ $# -ge 2 ]] || { usage >&2; exit 64; }
      title_contains=$2
      shift 2
      ;;
    --fit-visible)
      fit_visible=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'Unknown argument: %s\n' "$1" >&2
      usage >&2
      exit 64
      ;;
  esac
done

if [[ -n "$bundle_id" && -n "$app_name" ]] || [[ -z "$bundle_id" && -z "$app_name" ]]; then
  printf '%s\n' 'Provide exactly one of --bundle-id or --app.' >&2
  usage >&2
  exit 64
fi

command -v jq >/dev/null 2>&1 || {
  printf '%s\n' 'focus-window.sh requires jq.' >&2
  exit 69
}

if [[ -n "${OMNIWMCTL:-}" ]]; then
  ctl=$OMNIWMCTL
elif [[ -x /Applications/OmniWM.app/Contents/MacOS/omniwmctl ]]; then
  ctl=/Applications/OmniWM.app/Contents/MacOS/omniwmctl
elif command -v omniwmctl >/dev/null 2>&1; then
  ctl=$(command -v omniwmctl)
else
  printf '%s\n' 'omniwmctl not found.' >&2
  exit 69
fi

[[ -x "$ctl" ]] || {
  printf 'omniwmctl is not executable at %s\n' "$ctl" >&2
  exit 69
}

"$ctl" ping >/dev/null

if [[ -n "$bundle_id" ]]; then
  selector=(--bundle-id "$bundle_id")
else
  selector=(--app "$app_name")
fi

response=$("$ctl" query windows "${selector[@]}" --format json)

if [[ -n "$title_contains" ]]; then
  needle=$(printf '%s' "$title_contains" | tr '[:upper:]' '[:lower:]')
  candidates=$(jq -c --arg needle "$needle" \
    '[.result.payload.windows[] | select(((.title // "") | ascii_downcase | contains($needle)))]' \
    <<<"$response")
else
  candidates=$(jq -c '[.result.payload.windows[]]' <<<"$response")
fi

count=$(jq 'length' <<<"$candidates")
if [[ "$count" -ne 1 ]]; then
  jq -n \
    --arg error "Expected exactly one managed OmniWM window; found $count." \
    --argjson candidates "$candidates" \
    '{ok: false, error: $error, candidates: $candidates}' >&2
  exit 2
fi

window_id=$(jq -r '.[0].id' <<<"$candidates")

query_window() {
  "$ctl" query windows --window "$window_id" \
    --fields id,app,title,workspace,display,frame,is-focused,is-visible,hidden-reason \
    --format json
}

wait_for_stable_focus() {
  local last_signature=''
  local stable_count=0
  local sample ready signature

  for _ in {1..60}; do
    sample=$(query_window)
    state=$sample
    ready=$(jq -r \
      '(.result.payload.windows | length) == 1 and
       (.result.payload.windows[0].isFocused == true) and
       (.result.payload.windows[0].isVisible == true)' \
      <<<"$state")
    signature=$(jq -c \
      '[.result.payload.windows[0].display.id, .result.payload.windows[0].frame]' \
      <<<"$state")

    if [[ "$ready" == true && "$signature" == "$last_signature" ]]; then
      stable_count=$((stable_count + 1))
    else
      stable_count=0
    fi

    if [[ "$ready" == true && "$stable_count" -ge 4 ]]; then
      return 0
    fi

    last_signature=$signature
    sleep 0.1
  done

  return 1
}

read_geometry() {
  window=$(jq -c '.result.payload.windows[0]' <<<"$state")
  display_id=$(jq -r '.display.id' <<<"$window")
  display_state=$("$ctl" query displays --display "$display_id" --format json)
  display=$(jq -c '.result.payload.displays[0]' <<<"$display_state")
  fully_contained=$(jq -nr \
    --argjson window "$window" \
    --argjson display "$display" \
    '($window.frame.x >= ($display.visibleFrame.x - 0.5)) and
     ($window.frame.y >= ($display.visibleFrame.y - 0.5)) and
     (($window.frame.x + $window.frame.width) <=
       ($display.visibleFrame.x + $display.visibleFrame.width + 0.5)) and
     (($window.frame.y + $window.frame.height) <=
       ($display.visibleFrame.y + $display.visibleFrame.height + 0.5))')
  size_fits=$(jq -nr \
    --argjson window "$window" \
    --argjson display "$display" \
    '($window.frame.width <= ($display.visibleFrame.width + 0.5)) and
     ($window.frame.height <= ($display.visibleFrame.height + 0.5))')
}

emit_fit_error() {
  local message=$1
  jq -n \
    --arg error "$message" \
    --arg fitAction "$fit_action" \
    --argjson window "$window" \
    --argjson display "$display" \
    --argjson fullyContained "$fully_contained" \
    '{ok: false, error: $error, fitAction: $fitAction,
      fullyContained: $fullyContained, window: $window, display: $display}' >&2
}

"$ctl" window focus "$window_id" >/dev/null

if ! wait_for_stable_focus; then
  jq -n \
    --arg error 'OmniWM did not report a stable, focused, visible target within 6 seconds.' \
    --argjson state "$state" \
    '{ok: false, error: $error, state: $state}' >&2
  exit 1
fi

read_geometry
original_frame=$(jq -c '.frame' <<<"$window")
fit_applied=false
fit_action='none'

if [[ "$fit_visible" == true && "$fully_contained" != true ]]; then
  workspace_name=$(jq -r '.workspace.rawName' <<<"$window")
  workspace_state=$("$ctl" query workspaces --workspace "$workspace_name" --format json)
  layout=$(jq -r '.result.payload.workspaces[0].layout' <<<"$workspace_state")

  if [[ "$layout" != niri ]]; then
    emit_fit_error "Cannot fit a partially visible $layout workspace with Niri container commands."
    exit 1
  fi

  if [[ "$size_fits" == true ]]; then
    "$ctl" command center-column >/dev/null
    fit_action='center-column'
  else
    orientation=$(jq -r '.orientation // empty' <<<"$display")
    case "$orientation" in
      horizontal)
        secondary_fits=$(jq -nr \
          --argjson window "$window" \
          --argjson display "$display" \
          '$window.frame.height <= ($display.visibleFrame.height + 0.5)')
        ;;
      vertical)
        secondary_fits=$(jq -nr \
          --argjson window "$window" \
          --argjson display "$display" \
          '$window.frame.width <= ($display.visibleFrame.width + 0.5)')
        ;;
      *)
        emit_fit_error "Cannot fit the window because OmniWM reported an unknown display orientation: $orientation"
        exit 1
        ;;
    esac
    if [[ "$secondary_fits" != true ]]; then
      emit_fit_error 'The window exceeds the display secondary axis; automatic secondary-span fitting is not enabled.'
      exit 1
    fi
    "$ctl" command expand-container-to-available-primary-span >/dev/null
    fit_action='expand-container-to-available-primary-span'
  fi
  fit_applied=true

  if ! wait_for_stable_focus; then
    emit_fit_error 'The target frame did not settle after the fit command.'
    exit 1
  fi

  read_geometry
  if [[ "$fully_contained" != true && "$size_fits" == true ]]; then
    "$ctl" command center-column >/dev/null
    fit_action="${fit_action}+center-column"
    if ! wait_for_stable_focus; then
      emit_fit_error 'The target frame did not settle after centering.'
      exit 1
    fi
    read_geometry
  fi

  if [[ "$fully_contained" != true ]]; then
    emit_fit_error 'OmniWM could not fully contain the target in its display visible frame.'
    exit 1
  fi
fi

jq -n \
  --argjson fitRequested "$fit_visible" \
  --argjson fitApplied "$fit_applied" \
  --arg fitAction "$fit_action" \
  --argjson fullyContained "$fully_contained" \
  --argjson originalFrame "$original_frame" \
  --argjson window "$window" \
  --argjson display "$display" \
  '{ok: true, fitRequested: $fitRequested, fitApplied: $fitApplied,
    fitAction: $fitAction, fullyContained: $fullyContained,
    originalFrame: $originalFrame, window: $window, display: $display}'
