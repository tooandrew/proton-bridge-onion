# proton-bridge-onion

Run [Proton Mail Bridge](https://github.com/ProtonMail/proton-bridge) entirely over Tor, talking to
Proton's **onion service** instead of the clearnet API, and use it from Thunderbird with all of
Thunderbird's own traffic forced through Tor as well.

```
Thunderbird ──IMAP/SMTP (127.0.0.1)──▶ Bridge ──SOCKS5──▶ Tor ──▶ mail.<proton onion>/api
     │
     └──every other connection (updates, remote content, DNS)──▶ Tor
```

## Why a patch is needed

Official Bridge builds hard-code the API host (`https://mail-api.proton.me`); only Proton's internal
QA builds read an override. The patch changes that one constant:

```diff
-const APIHost = "https://mail-api.proton.me"
+const APIHost = "https://mail.protonmailrmez3lotccipshtkleegetolb73fuirgj7r4o4vfu7ozyd.onion/api"
```

**Use the `mail.` subdomain.** Proton serves each subdomain on its own onion host (advertised in the
`Onion-Location` headers of `mail.proton.me` and `account.proton.me`). The bare onion address only
serves the marketing site: its `/api` answers `401` to reads and `405 Method Not Allowed` to Bridge's
login. `mail.<onion>/api/core/v4/tests/ping` returns `{"Code":1000}`, the real API.

Bridge honours `HTTPS_PROXY` (its transport uses Go's `http.ProxyFromEnvironment`). With a `socks5://`
proxy, Go connects through Tor, lets Tor resolve the hostname (no local DNS), and validates TLS against
the system roots. Proton's onion certificate is publicly trusted, so this works without extra setup.

## Requirements (macOS)

- Xcode Command Line Tools, Homebrew
- `brew install go tor tmux pkgconf libfido2` (`libfido2`/`pkgconf` are only needed to satisfy the
  build; upstream's Makefile builds its own static copy via vcpkg)
- `brew install --cask thunderbird`
- `brew install nss`, optional, for `certutil` to trust Bridge's certificate in Thunderbird

## Setup

1. **Tor** as a background service: `brew services start tor` (SOCKS on `127.0.0.1:9050`).
2. **Build**: `./build.sh` (or `./build.sh v3.27.1` to pin a release). Produces `proton-bridge/bridge`.
   Run `bridge`, not the `proton-bridge` launcher; the launcher is the self-updater.
3. **First run and login**, in tmux so it keeps running:
   ```sh
   tmux new -s bridge "HTTPS_PROXY=socks5://127.0.0.1:9050 HTTP_PROXY=socks5://127.0.0.1:9050 NO_PROXY=localhost,127.0.0.1 ./proton-bridge/bridge --cli"
   ```
   In the Bridge shell:
   - `updates autoupdates disable`: **required**, otherwise an update replaces the onion build
   - `proxy disallow`: no third-party "alternative routing"
   - `telemetry disable`
   - `login`, then `info 0` for the local IMAP/SMTP settings and Bridge password

   macOS will ask for Keychain access the first time (Bridge keeps its vault key there).
4. **Thunderbird through Tor**:
   `sudo defaults import /Library/Preferences/org.mozilla.thunderbird macos/org.mozilla.thunderbird.plist`
   This locked policy proxies everything except `localhost`/`127.0.0.1`.
5. **Thunderbird account**: IMAP `127.0.0.1:1143` STARTTLS, SMTP `127.0.0.1:1025` STARTTLS, normal
   password, with the Bridge password from `info`. To avoid the self-signed certificate warning,
   export it with `cert export` in Bridge, then with Thunderbird closed:
   `certutil -A -d sql:<thunderbird-profile> -n "Proton Mail Bridge (local)" -t "P,," -i cert.pem`
   (delete the exported `key.pem`; Thunderbird does not need it).
6. **Optional: start at login.** Fill in `macos/proton-bridge-onion.plist.template` and load it with
   `launchctl` (instructions inside). Stop the tmux copy first; only one Bridge can run.

## Updating

Auto-updates are off by design. To update, rerun `./build.sh <new-tag>` and restart Bridge.
Settings, login, and cached mail live in Bridge's data directory and carry over.

## Notes

- New mail arrives in roughly 20–40 seconds: Bridge polls Proton every 20 s (plus jitter) over Tor,
  then pushes to Thunderbird instantly over IMAP IDLE.
- A few rarely used endpoints stay on clearnet hostnames but still go through Tor: login captcha
  (`verify.proton.me`), TLS failure reports, and the (disabled) update check.
- Expect onion round trips of several seconds; the first sync is slow.

## License

The patch and scripts here modify Proton Mail Bridge and are released under the
[GNU GPL v3](LICENSE), the same license as Bridge. Not affiliated with or endorsed by Proton AG.
