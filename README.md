# NordVPN for KOReader

This plugin connects KOReader to NordVPN. You pick a country, tap Connect, and KOReader's own network requests leave through a Nord server in that country. Wikipedia lookups and OPDS catalogs are examples.

You need a NordVPN subscription and KOReader on a device with Wi-Fi.

Status: tested in KOReader for Linux (Docker). It is not tested on a real Kindle or Kobo yet. Please open an issue if it fails on your device.

## 1. Get an access token

The plugin signs in with a Nord access token, not with your Nord email and password. You can do this on a phone or a computer.

1. Log in at https://my.nordaccount.com.
2. Open the NordVPN tab, then Advanced settings, then Get access token.
3. Enter the verification code that Nord sends to your email.
4. Choose a token type. A temporary token expires after 30 days. A non-expiring token stays valid until you revoke it. Nord asks you to turn on multi-factor authentication for the non-expiring type.
5. Copy the token. Nord shows it once. If you lose it, revoke it on the same page and generate a new one.

Nord changes its site from time to time. If these labels are different, see Nord's guide: https://support.nordvpn.com/hc/en-us/articles/20286980309265

## 2. Install the plugin

With the App Store plugin (https://github.com/omer-faruq/appstore.koplugin): open Tools, App Store, Plugins, and search for `nordvpn`. In the App Store settings you can also use Install plugin from URL with `GuitarWag/koreader-nordvpn`.

By hand: copy the `nordvpn.koplugin` folder from this repo into KOReader's `plugins` folder.

Restart KOReader after the install.

## 3. Give the plugin your token and country

Choose one way.

### Option A: config file (easier)

Use this if you have a computer. The token is long, and a keyboard is much easier than the e-reader's on-screen keyboard.

1. Connect the device to the computer with USB.
2. Open the plugin folder `nordvpn.koplugin`. On a Kindle it is `koreader/plugins/nordvpn.koplugin` inside the Kindle drive.
3. Copy `nordvpn.conf.example` to `nordvpn.conf` in the same folder.
4. Open `nordvpn.conf` in a text editor. Put the token after `token =`. Put a country name or code after `country =`, for example `Germany` or `DE`.
5. Save the file and eject the device.

### Option B: on the device, no computer

You can type the token on the e-reader. It works, but it is slow and easy to get wrong.

1. Tap the top of the screen. Open the Network tab, then NordVPN, then Access token.
2. Type the token with the on-screen keyboard. Check each character before you tap Save. The token is a long string, so a single wrong character makes Nord reject it.
3. Tap Country in the same menu and choose a country from the list.

If both a `nordvpn.conf` file and menu choices exist, the file wins.

## 4. Connect

1. Open Network, then NordVPN, then tap Connect.
2. Wait. The first connect downloads `wireproxy` (a small WireGuard client), checks its sha256, and asks Nord for a server. The connection can take up to 40 seconds.
3. The message "NordVPN on" with a server name means it works, and the box next to Connect is ticked.
4. Tap Connect again to disconnect.

## What goes through the VPN

- Included: HTTP and HTTPS requests that KOReader makes itself, such as Wikipedia lookups.
- Not included: other software on the device, such as Syncthing or SSH. KOReader's proxy setting does not reach them.

While the VPN is on, KOReader's HTTP proxy is set to `127.0.0.1:25345`. Disconnect clears it. It does not restore a proxy you set before.

## Where your token is stored

The plugin keeps your token in plain text. It does not encrypt it. KOReader has no secure storage for plugins, and other plugins work the same way. The Z-Library plugin, for example, stores your account password in plain text.

- `nordvpn.conf` in the plugin folder, if you use Option A.
- KOReader's `settings/nordvpn.lua`. It holds the token and the NordLynx key that Nord returns. The plugin needs the token to fetch a new key, so it keeps it.

Anyone who can read the device storage can read both files. This includes any computer you connect with USB and any backup or sync tool that copies the KOReader folder. Do not share or zip the plugin folder after you create `nordvpn.conf`.

To limit the risk:

- Use the 30-day token. It stops working on its own.
- Revoke the token in your Nord Account if you lose the device or share the folder by mistake.
- Do not use this plugin on a device that other people can use.

## If something fails

| Message | What to do |
|---|---|
| `NordVPN failed: token rejected` | The token is wrong, expired, or revoked. Generate a new one. |
| `NordVPN failed: no server` | The country has no WireGuard server, or the Nord API is not reachable. Pick another country. |
| `NordVPN failed: download failed` or `checksum mismatch` | GitHub is not reachable, or the download broke. Check Wi-Fi and try again. |
| `NordVPN failed: no tunnel. See bin/wireproxy.log` | The tunnel did not start in 40 seconds. Try again or pick another country. Read `bin/wireproxy.log` in the plugin folder. |
| `Country list failed` | The Nord API did not answer. Check Wi-Fi and try again. |

The device needs `tar`, `sha256sum`, and `pkill` or `killall`. Most Kindle and Kobo systems have them through busybox. Do not post `bin/wireproxy.conf` in an issue, because it holds your private key.

## Remove

Delete the `nordvpn.koplugin` folder. To remove saved data, delete `settings/nordvpn.lua` in KOReader's folder. To revoke the token, use your Nord Account.

## Test setup

`test/` has a Dockerfile that runs KOReader for Linux in a browser through noVNC. `test/tunnel_test.lua` checks that HTTPS goes through the tunnel.
