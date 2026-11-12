# NordVPN for KOReader

Runs wireproxy with a NordLynx config and sets KOReader's HTTP proxy.

## Setup

1. Copy `nordvpn.koplugin` into KOReader's `plugins` folder. Restart KOReader.
2. Create a Nord access token: Nord Account, NordVPN, Manual setup, Access token.
3. Copy `nordvpn.koplugin/nordvpn.conf.example` to `nordvpn.koplugin/nordvpn.conf`. Fill in `token` and `country` (name or code).
4. In KOReader, tap Network, NordVPN, Connect.

Without `nordvpn.conf`, Network, NordVPN has an Access token dialog and a Country list. The conf file wins over the menu when both exist.

On first connect the plugin downloads wireproxy, checks its sha256, asks Nord for a server in the country, and starts it. Only traffic that uses KOReader's HTTP proxy goes through Nord. Logs are in `bin/wireproxy.log`. `nordvpn.conf` holds your token, so git ignores it.
