#!/bin/bash
set -euo pipefail

PLUGIN_ID="nate.howdy-lock"
PAM_FILE="/etc/pam.d/omarchy-lock-howdy"
HOWDY_INI="/etc/howdy/config.ini"
WIKI="https://wiki.archlinux.org/title/Howdy"

usage() {
  cat <<EOF
Usage: $(basename "$0") [--check] [--remove]

Prepare Howdy face unlock for this Omarchy lock plugin.

  --check   Print status only. Makes no changes.
  --remove  Delete $PAM_FILE (legacy; no longer used by the plugin).
  --help    Show this help.

Installs howdy-git from the AUR if missing, points Howdy at the IR
camera, and tells you if a face still needs enrolling. Does not touch
PAM configuration.

Must run in a terminal (sudo and enrollment prompt). Agents: read
AGENTS.md in this directory before running anything.
EOF
}

need_tty() {
  if [[ ! -t 0 || ! -t 1 ]]; then
    echo "Run this in a visible terminal so sudo can prompt." >&2
    echo "Agents: do not use pkexec. Ask the user to run: $0" >&2
    exit 1
  fi
}

as_root() {
  if (( EUID == 0 )); then
    "$@"
  else
    sudo "$@"
  fi
}

target_user() {
  echo "${SUDO_USER:-${USER:-$(id -un)}}"
}

howdy_module() {
  if [[ -e /lib/security/pam_howdy.so ]]; then
    echo /lib/security/pam_howdy.so
  elif [[ -e /usr/lib/security/pam_howdy.so ]]; then
    echo /usr/lib/security/pam_howdy.so
  fi
}

model_path() {
  echo "/etc/howdy/models/$(target_user).dat"
}

howdy_installed() {
  command -v howdy >/dev/null 2>&1 && [[ -n $(howdy_module) ]]
}

pam_ready() {
  [[ -f $PAM_FILE ]]
}

model_ready() {
  [[ -f $(model_path) ]]
}

ini_value() {
  local key=$1
  [[ -f $HOWDY_INI ]] || return 0
  awk -F ' *= *' -v key="$key" '$1 == key { print $2; exit }' "$HOWDY_INI"
}

set_ini() {
  local key=$1 val=$2
  as_root python3 - "$HOWDY_INI" "$key" "$val" <<'PY'
import pathlib, re, sys
path, key, val = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3]
text = path.read_text() if path.exists() else ""
pattern = re.compile(rf"^(#\s*)?{re.escape(key)}\s*=.*$", re.M)
line = f"{key} = {val}"
if pattern.search(text):
    text, n = pattern.subn(line, text, count=1)
    if n != 1:
        sys.exit(f"refusing to edit {path}: {key} matched more than once")
else:
    text = text.rstrip() + f"\n{line}\n"
path.write_text(text)
PY
}

ir_by_path() {
  local dev=$1
  local link
  [[ -d /dev/v4l/by-path ]] || { echo "$dev"; return; }
  for link in /dev/v4l/by-path/*; do
    if [[ $(readlink -f "$link") == "$(readlink -f "$dev")" ]]; then
      echo "$link"
      return
    fi
  done
  echo "$dev"
}

detect_ir_device() {
  local dev
  command -v v4l2-ctl >/dev/null 2>&1 || return 0
  for dev in /dev/video*; do
    [[ -e $dev ]] || continue
    if v4l2-ctl -d "$dev" --list-formats 2>/dev/null | grep -q GREY; then
      ir_by_path "$dev"
      return
    fi
  done
}

detect_ir_size() {
  local dev=$1
  v4l2-ctl -d "$dev" --get-fmt-video 2>/dev/null |
    awk -F '[:x ]+' '/Width\/Height/ { print $2, $3; exit }'
}

plugin_enabled() {
  command -v omarchy >/dev/null 2>&1 || return 1
  omarchy plugin list --json 2>/dev/null |
    jq -e --arg id "$PLUGIN_ID" 'any(.[]; .id == $id and .enabled == true)' >/dev/null
}

print_status() {
  local ir module
  ir=$(detect_ir_device || true)
  module=$(howdy_module || true)
  cat <<EOF
howdy_installed=$(howdy_installed && echo yes || echo no)
pam_module=${module:-missing}
pam_service=$(pam_ready && echo yes || echo no)
face_model=$(model_ready && echo yes || echo no)
face_model_path=$(model_path)
ir_device=${ir:-none}
howdy_device_path=$(ini_value device_path)
plugin_id=$PLUGIN_ID
plugin_enabled=$(plugin_enabled && echo yes || echo no)
EOF
}

install_deps() {
  if ! command -v v4l2-ctl >/dev/null 2>&1; then
    echo "Installing v4l-utils..."
    omarchy pkg add v4l-utils
  fi
  if ! howdy_installed; then
    echo "Installing howdy-git from the AUR..."
    omarchy pkg aur add howdy-git
  fi
  if ! howdy_installed; then
    echo "howdy-git did not install. Install it from the AUR, then re-run." >&2
    exit 1
  fi
}

configure_camera() {
  local ir size width height current
  ir=$(detect_ir_device || true)
  if [[ -z $ir ]]; then
    echo "No GREY IR camera found. Set device_path in $HOWDY_INI by hand."
    echo "Wiki: $WIKI"
    return 0
  fi

  current=$(ini_value device_path)
  if [[ -z $current || $current == null ]]; then
    echo "Setting Howdy device_path to $ir"
    set_ini device_path "$ir"
  else
    echo "Keeping existing device_path = $current"
    ir=$current
  fi

  size=$(detect_ir_size "$ir" || true)
  if [[ -n $size ]]; then
    width=${size%% *}
    height=${size##* }
    echo "Setting frame size ${width}x${height}"
    set_ini frame_width "$width"
    set_ini frame_height "$height"
  fi

  set_ini capture_failed false
  set_ini capture_successful false
}

enroll_if_needed() {
  if model_ready; then
    echo "Face model already present for $(target_user)."
    return 0
  fi
  echo
  echo "No face model for $(target_user)."
  echo "Look at the camera, then enroll with:"
  echo "  sudo howdy add"
  echo
  echo "Do not run: sudo howdy test"
  echo "That crashes on OpenCV 5 / NumPy 2. Preview the IR cam with: mpv /dev/video2"
  echo "(use the GREY node from v4l2-ctl --list-devices)."
  echo
  if [[ -t 0 ]]; then
    read -r -p "Run sudo howdy add now? [y/N] " answer
    if [[ $answer == [yY] ]]; then
      as_root howdy add
    fi
  fi
  if ! model_ready; then
    echo "Face not enrolled yet. The lock button stays hidden until $(model_path) exists."
    return 1
  fi
}

enable_plugin() {
  if plugin_enabled; then
    echo "Plugin $PLUGIN_ID is already enabled."
    return 0
  fi
  if ! command -v omarchy >/dev/null 2>&1; then
    return 0
  fi
  if omarchy plugin list --json 2>/dev/null | jq -e --arg id "$PLUGIN_ID" 'any(.[]; .id == $id)' >/dev/null; then
    echo "Enabling $PLUGIN_ID (replaces omarchy.lock)..."
    omarchy plugin enable "$PLUGIN_ID"
  else
    echo "Plugin $PLUGIN_ID is not installed in ~/.config/omarchy/plugins yet."
    echo "Install it, then: omarchy plugin enable $PLUGIN_ID"
  fi
}

remove_pam() {
  need_tty
  if [[ -f $PAM_FILE ]]; then
    as_root rm -f "$PAM_FILE"
    echo "Removed $PAM_FILE"
  else
    echo "No $PAM_FILE to remove."
  fi
}

case "${1:-}" in
  -h | --help)
    usage
    exit 0
    ;;
  --check)
    print_status
    exit 0
    ;;
  --remove)
    remove_pam
    exit 0
    ;;
  "")
    ;;
  *)
    echo "Unknown option: $1" >&2
    usage >&2
    exit 1
    ;;
esac

need_tty
echo "Setting up Howdy face unlock for Omarchy ($PLUGIN_ID)"
install_deps
configure_camera
if pam_ready; then
  echo "$PAM_FILE exists from an older version."
  echo "The plugin does not use it. Remove it with: $0 --remove"
fi
enroll_status=0
enroll_if_needed || enroll_status=$?
enable_plugin
echo
print_status
echo
if (( enroll_status != 0 )); then
  echo "Setup incomplete: enroll a face, then lock and press Unlock with face."
  exit 1
fi
echo "Ready. Lock with Super+Ctrl+L (or omarchy system lock) and press Unlock with face."
echo "If the IR LED stays dark during enrollment, install linux-enable-ir-emitter from the AUR."
echo "Wiki: $WIKI"
