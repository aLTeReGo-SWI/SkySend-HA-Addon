# Home Assistant Add-on: SkySend

[SkySend](https://github.com/Skyfay/SkySend) is a minimalist, self-hostable, end-to-end encrypted file and note sharing service.

This add-on runs SkySend behind a local nginx TLS terminator that reuses **the same SSL certificate Home Assistant uses** (from `/ssl`), so the web UI is served over HTTPS with the same trusted cert/chain your browser already trusts for Home Assistant - no separate certificate management needed.

See the **Documentation** tab for configuration details.
