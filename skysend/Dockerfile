FROM skyfay/skysend:latest

# Add nginx (TLS termination using the Home Assistant certificate),
# jq (read /data/options.json), gettext (envsubst for templating nginx.conf).
RUN apk add --no-cache nginx jq gettext

COPY nginx.conf.template /etc/nginx/templates/default.conf.template
COPY run.sh /run.sh
RUN chmod +x /run.sh

# The Node app is only reachable via loopback; nginx is the only process
# that binds an externally reachable port, and it does so with TLS.
ENV HOST=127.0.0.1
ENV PORT=3000

EXPOSE 3333

HEALTHCHECK --interval=30s --timeout=5s --start-period=40s --retries=3 \
  CMD wget -q -O- http://127.0.0.1:3000/api/health || exit 1

ENTRYPOINT ["/run.sh"]
