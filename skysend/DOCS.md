# SkySend

End-to-end encrypted, self-hostable file and note sharing, served over HTTPS using **Home Assistant's own SSL certificate**.

## How the certificate sharing works

This add-on maps Home Assistant's `/ssl` folder (the same certificate directory used by the `http` integration / your Let's Encrypt or Duck DNS add-on) into the container read-only. An nginx process inside the container terminates TLS using those exact certificate/key files and reverse-proxies plaintext traffic to SkySend, which only listens on `127.0.0.1` and is never directly reachable.

Because it's the identical cert Home Assistant itself presents, browsers that already trust your HA instance will trust SkySend too - no extra warnings, no separate Let's Encrypt setup.

Requirements:
- Home Assistant must already have a certificate configured under `/ssl` (e.g. via the Let's Encrypt or Duck DNS add-on, or your own files copied into the `ssl` share).
- The `certfile` / `keyfile` options must match the actual file names in `/ssl` (defaults `fullchain.pem` / `privkey.pem`, which match Home Assistant's own `http:` integration defaults).

## Configuration

| Option | Default | Description |
| --- | --- | --- |
| `ssl` | `true` | Must stay `true`; this add-on always serves HTTPS. |
| `certfile` | `fullchain.pem` | Certificate file name inside `/ssl`. |
| `keyfile` | `privkey.pem` | Private key file name inside `/ssl`. |
| `base_url` | *(empty)* | Public URL used to generate share links, e.g. `https://homeassistant.local:3333`. **Set this** or links will be wrong. |
| `puid` / `pgid` | `1001` | UID/GID SkySend runs as (owns `/data`). |
| `tz` | `Etc/UTC` | Timezone, match your Home Assistant timezone. |
| `file_max_size` | `2GB` | Maximum upload size. |
| `enabled_services` | `file, note` | Which SkySend services are enabled. |
| `extra_env` | `[]` | Advanced: list of raw `KEY=VALUE` strings passed straight through as environment variables, for any [SkySend environment variable](https://docs.skysend.app/user-guide/configuration/environment-variables) not exposed above (e.g. `CUSTOM_TITLE=MyShare`, `OIDC_ISSUER=...`). |

## Storage

The database and uploaded files are stored under the add-on's persistent `/data` volume, so they survive add-on restarts/updates automatically. No extra volume mapping is required.

## Accessing the Web UI

Open `https://<your-home-assistant-host>:3333` (or click **Open Web UI** on the add-on's Info tab). Make sure port `3333` is reachable on your network/firewall, since this add-on does not use Home Assistant Ingress.

## Changing the port

The default port is `3333`. To change it, go to the add-on's **Info** tab in Home Assistant and edit the port mapping under **Network** (do *not* add a `port` option under Configuration - there isn't one; Home Assistant's own port remapping is what's used here).

## Troubleshooting

- **"certificate files not found"** on startup: check that Home Assistant actually has a certificate in `/ssl` and that `certfile`/`keyfile` match the real file names there.
- **Share links point to the wrong address**: set `base_url` explicitly.
