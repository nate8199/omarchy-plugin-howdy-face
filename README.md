# Howdy Lock

Omarchy lock screen with a button to unlock using [Howdy](https://github.com/boltgolt/howdy) face recognition. Password and fingerprint still work as before. Face unlock only runs when you press **Unlock with face**.

This plugin replaces `omarchy.lock`. Installing the plugin does **not** install Howdy or change PAM; run `setup.sh` after.

## Requires

- Omarchy 4.x (Quattro)
- An IR camera (Windows Hello / GREY V4L node)

`setup.sh` will install [howdy-git](https://aur.archlinux.org/packages/howdy-git/) from the AUR if needed.

## Install

```sh
omarchy plugin add https://github.com/nate8199/omarchy-plugin-howdy-face.git --enable
~/.config/omarchy/plugins/nate.howdy-lock/setup.sh
```

Run `setup.sh` in a terminal (sudo password, and optional `howdy add`). Agents helping with setup should read `AGENTS.md`.

The face button appears after `/usr/lib/howdy/compare.py` and `/etc/howdy/models/$USER.dat` are present.

Then lock with Super+Ctrl+L (or `omarchy system lock`) and press **Unlock with face**. Escape or **Cancel** stops a scan and lets you type a password. Face unlock runs `compare.py` directly (not `pam_howdy`, which waits for a password/Enter).

## Security notes

- Face unlock runs `compare.py` as your user — no root Python on the lock path — and unlocks only on exit status `0`. Before the face button appears, the lock screen verifies `/usr/lib/howdy/compare.py` and `/etc/howdy/models/<user>.dat` are **root-owned and not group/world-writable**; any session code able to rewrite them could otherwise enroll a face everyone matches.
- Face scans are limited to 5 failed attempts per lock; after that only password works until the next lock.
- Camera snapshots are disabled by `setup.sh` (`capture_failed=false`, `capture_successful=false`); Howdy never stores images.
- The camera is only opened when you press **Unlock with face**; there is no always-on scanning. Escape or **Cancel** kills the scan immediately.
- Password unlocking keeps PAM faillock rate limiting. Face attempts are deliberately button-triggered rather than continuously retried.
- No PAM configuration is created or required. `/etc/pam.d/omarchy-lock-howdy` is legacy from older versions and safe to delete (`./setup.sh --remove`).

## Remove

```sh
omarchy plugin remove nate.howdy-lock
~/.config/omarchy/plugins/nate.howdy-lock/setup.sh --remove
```

If you already removed the plugin:

```sh
sudo rm -f /etc/pam.d/omarchy-lock-howdy
```

Removing the plugin restores `omarchy.lock`. Howdy itself is left installed.

## License

MIT. Lock screen code is derived from Omarchy's `omarchy.lock`.
