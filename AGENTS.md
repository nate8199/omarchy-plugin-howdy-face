# Agent instructions — Howdy Lock

This plugin is a lock-screen replacement (`clonedFrom: omarchy.lock`). It does **not** install Howdy, write PAM, or enroll a face by itself. `omarchy plugin add` only clones and enables QML.

Work in this repo (or a copy under `~/Projects`). Do **not** edit files under `~/.config/omarchy/plugins/` while iterating — the shell hot-reloads on every save.

## Privilege

- Run `setup.sh` in a **visible terminal**. The user must be able to type a sudo password.
- Use `sudo`, never `pkexec`.
- Do not run `git config`. Do not write `/usr/share/omarchy/`.
- Do **not** add Howdy to `/etc/pam.d/system-local-login`, `/etc/pam.d/sddm`, or `/etc/pam.d/sudo` unless the user explicitly asks. This plugin only uses `/etc/pam.d/omarchy-lock-howdy`.

## Setup (do this)

1. Confirm the plugin is installed and enabled:

   ```sh
   omarchy plugin enable nate.howdy-lock
   ```

   Enabling it disables `omarchy.lock`. That is required (two lock services cannot run).

2. Run the setup script from a terminal:

   ```sh
   ~/.config/omarchy/plugins/nate.howdy-lock/setup.sh
   ```

   If you are developing from a git checkout:

   ```sh
   ./setup.sh
   ```

3. Inspect without changing anything:

   ```sh
   ./setup.sh --check
   ```

   Ready means `howdy_installed=yes`, `face_model=yes`, `ir_device` not `none`. The PAM file is optional leftover from setup and is not used to unlock.

4. If `face_model=no`, the user must look at the camera and run `sudo howdy add` in a terminal. Do not enroll for them from a non-interactive agent session.

## Do not

- Do not run `sudo howdy test`. It crashes on OpenCV 5 / NumPy 2 (`IndexError` in `cli/test.py`). Preview the IR node with `mpv <device>` or `ffplay <device>`.
- Do not use `sudo howdy test` with Qt/xcb workarounds as a success check.
- Do not install `linux-enable-ir-emitter` unless the IR LED stays off while the GREY node is open. Prefer `/dev/v4l/by-path/...` over `/dev/videoN`.
- Do not patch `/usr/lib/howdy/` (package-owned).

## What setup.sh already does

- Installs `v4l-utils` (`omarchy pkg add`) and `howdy-git` (`omarchy pkg aur add`) if missing.
- Finds a GREY IR camera, sets `device_path` / `frame_width` / `frame_height` in `/etc/howdy/config.ini` when unset.
- Disables Howdy snapshots.
- Does NOT touch PAM. A leftover `/etc/pam.d/omarchy-lock-howdy` from older versions is unused; suggest `./setup.sh --remove`.
- Enables this plugin if it is installed but not enabled.

The lock button is shown when `/usr/lib/howdy/compare.py` and `/etc/howdy/models/$USER.dat` exist, are **root-owned**, and are **not group/world-writable** — this is re-checked at every lock. Never `chown` the model to the user or make it group-writable; the button hides itself if those invariants break. Failed face scans lock out face auth after 5 attempts per lock (password still works).

Face unlock runs `python3 /usr/lib/howdy/compare.py $USER` and unlocks on exit 0. Do **not** use `pam_howdy` for the lock button: `workaround=input` also starts a password prompt, then hangs waiting for Enter (`uinput` is not available to the lock).

To test recognition (silent; check exit code):

```sh
cd /usr/lib/howdy && python3 compare.py "$USER"; echo exit:$?
```

`exit:0` is a match. `sudo howdy test` still crashes (OpenCV histogram bug).

## After setup

```sh
omarchy system lock
```

User presses **Unlock with face**. Escape or Cancel aborts the scan. Password still works. Fingerprint still works if already configured.

## Remove

```sh
omarchy plugin remove nate.howdy-lock
./setup.sh --remove
```

`--remove` only deletes the PAM file. It does not uninstall `howdy-git`.

## Hardware notes (Dell XPS and similar)

RGB webcam is usually `/dev/video0` (MJPG/YUYV). Howdy needs the GREY IR node (often `/dev/video2`), via a stable `/dev/v4l/by-path/` symlink. Wiki: https://wiki.archlinux.org/title/Howdy
