#!/usr/bin/env bash
#
# Open a URL in the browser, reusing an existing tab when the same base URL
# is already open (refresh + focus instead of spawning another tab).

open_or_refresh_browser_url() {
  local url="$1"
  if [[ -z "$url" ]]; then
    return 1
  fi

  local match_prefix="${url%%\?*}"

  case "$(uname -s)" in
    Darwin)
      if _open_or_refresh_macos "$url" "$match_prefix"; then
        return 0
      fi
      ;;
  esac

  if command -v xdg-open >/dev/null 2>&1; then
    xdg-open "$url" >/dev/null 2>&1 &
    return 0
  fi
  if command -v open >/dev/null 2>&1; then
    open "$url" >/dev/null 2>&1
    return 0
  fi

  echo "Open $url in your browser." >&2
  return 1
}

_browser_is_running() {
  local app_name="$1"
  osascript -e "tell application \"System Events\" to (name of processes) contains \"$app_name\"" 2>/dev/null \
    | grep -q true
}

_open_or_refresh_macos() {
  local url="$1"
  local match_prefix="$2"
  local browser=""

  local -a browsers=(
    "Google Chrome"
    "Chromium"
    "Brave Browser"
    "Microsoft Edge"
    "Arc"
    "Vivaldi"
    "Safari"
  )

  for browser in "${browsers[@]}"; do
    if _browser_is_running "$browser" &&
      _refresh_existing_tab_in_browser "$browser" "$url" "$match_prefix"; then
      return 0
    fi
  done

  if command -v open >/dev/null 2>&1; then
    open "$url" >/dev/null 2>&1
    return 0
  fi

  return 1
}

_refresh_existing_tab_in_browser() {
  local app_name="$1"
  local url="$2"
  local match_prefix="$3"
  local result=""

  result="$(
    osascript - "$app_name" "$url" "$match_prefix" <<'APPLESCRIPT' 2>/dev/null
on run argv
  set appName to item 1 of argv
  set targetURL to item 2 of argv
  set matchPrefix to item 3 of argv

  if appName is "Safari" then
    tell application "Safari"
      repeat with w in windows
        repeat with t in tabs of w
          if (URL of t) starts with matchPrefix then
            set URL of t to targetURL
            set current tab of w to t
            set index of w to 1
            activate
            return "true"
          end if
        end repeat
      end repeat
    end tell
  else
    tell application appName
      repeat with w in windows
        set tabIndex to 1
        repeat with t in tabs of w
          if (URL of t) starts with matchPrefix then
            set URL of t to targetURL
            set active tab index of w to tabIndex
            set index of w to 1
            activate
            return "true"
          end if
          set tabIndex to tabIndex + 1
        end repeat
      end repeat
    end tell
  end if

  return "false"
end run
APPLESCRIPT
  )"

  [[ "$result" == "true" ]]
}
