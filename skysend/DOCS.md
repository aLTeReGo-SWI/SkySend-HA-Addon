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
| `oidc_enabled` | `false` | Enable OIDC/SSO login. See **OIDC / SSO (Entra ID)** below. |
| `oidc_provider` | `generic` | Provider preset (`generic`, `pocketid`, `authentik`, `keycloak`). Use `generic` for Microsoft Entra ID. |
| `oidc_issuer` | *(empty)* | OIDC issuer URL, e.g. `https://login.microsoftonline.com/<tenant-id>/v2.0` for Entra ID. |
| `oidc_client_id` | *(empty)* | Application (client) ID from the Entra ID app registration. |
| `oidc_client_secret` | *(empty)* | Client secret **value** from the Entra ID app registration. |
| `oidc_protect_files` | `true` | Require OIDC login to upload files. |
| `oidc_protect_notes` | `true` | Require OIDC login to create notes. |
| `oidc_redirect_uri` | *(empty)* | Override the default `{base_url}/auth/callback` redirect URI. |
| `oidc_session_secret` | *(empty)* | Fixed secret (32+ chars) to sign session cookies; auto-generated per restart if left blank. |
| `oidc_scopes` | `openid profile email` | Space-separated OIDC scopes to request. |
| `oidc_session_duration` | `86400` | Session cookie lifetime in seconds. |

## OIDC / SSO (Entra ID)

SkySend can require sign-in (via any OIDC-compliant provider) before allowing uploads, while keeping downloads/views always public. This section walks through Microsoft Entra ID (Azure AD), since it has no built-in preset - use `oidc_provider: generic`.

### 1. Create the Enterprise App / App registration in Entra ID

1. Go to [entra.microsoft.com](https://entra.microsoft.com) (or Azure Portal → **Microsoft Entra ID**) → **App registrations** → **New registration**.
2. **Name**: `SkySend` (or anything you like).
3. **Supported account types**: "Accounts in this organizational directory only" (single tenant), unless you need multi-tenant.
4. **Redirect URI**: platform `Web`, value `https://<your-skysend-base_url>/auth/callback` - this must exactly match this add-on's `base_url` option plus `/auth/callback` (e.g. `https://homeassistant.local:3333/auth/callback`), unless you override it with `oidc_redirect_uri`.
5. Click **Register**.

### 2. Collect the values SkySend needs

| Entra ID location | Value | Add-on option |
| --- | --- | --- |
| App registration → Overview → "Application (client) ID" | GUID | `oidc_client_id` |
| App registration → Overview → "Directory (tenant) ID" | GUID | Used to build `oidc_issuer` |
| App registration → Certificates & secrets → New client secret → **Value** (not Secret ID, shown once) | secret string | `oidc_client_secret` |

Build the issuer URL as:
```
https://login.microsoftonline.com/<Directory (tenant) ID>/v2.0
```
All other endpoints (authorize, token, JWKS) are auto-discovered from this URL via `/.well-known/openid-configuration` - nothing else needs to be entered.

### 3. (Optional) Grant admin consent

Under **API permissions**, click **Grant admin consent for `<tenant>`** so users aren't individually prompted to consent to the basic `openid`/`profile`/`email` scopes.

### 4. Configure the add-on

| Add-on option | Value |
| --- | --- |
| `oidc_enabled` | `true` |
| `oidc_provider` | `generic` |
| `oidc_issuer` | `https://login.microsoftonline.com/<tenant-id>/v2.0` |
| `oidc_client_id` | Application (client) ID |
| `oidc_client_secret` | Client secret value |
| `oidc_scopes` | `openid profile email` (default) |
| `oidc_session_secret` | A fixed random string, e.g. generate with `openssl rand -base64 48`, so sessions survive add-on restarts |

`oidc_issuer`, `oidc_client_id`, and `oidc_client_secret` must all be set together - the add-on refuses to start with a clear error if only some of them are filled in.

## Storage

The database and uploaded files are stored under the add-on's persistent `/data` volume, so they survive add-on restarts/updates automatically. No extra volume mapping is required.

## Accessing the Web UI

Open `https://<your-home-assistant-host>:3333` (or click **Open Web UI** on the add-on's Info tab). Make sure port `3333` is reachable on your network/firewall, since this add-on does not use Home Assistant Ingress.

## Changing the port

The default port is `3333`. To change it, go to the add-on's **Info** tab in Home Assistant and edit the port mapping under **Network** (do *not* add a `port` option under Configuration - there isn't one; Home Assistant's own port remapping is what's used here).

## Troubleshooting

- **"certificate files not found"** on startup: check that Home Assistant actually has a certificate in `/ssl` and that `certfile`/`keyfile` match the real file names there.
- **Share links point to the wrong address**: set `base_url` explicitly.
