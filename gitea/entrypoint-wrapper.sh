#!/bin/sh
set -e
# Install mkcert root CA from /etc/mkcert-ca (host dir ssl/) so outbound HTTPS works (e.g. Actions artifact upload).
# Put rootCA.pem in ssl/ on the host (e.g. cp "$(mkcert -CAROOT)/rootCA.pem" ssl/), then recreate the container.
mkdir -p /usr/local/share/ca-certificates
installed=
for f in /etc/mkcert-ca/rootCA.pem /etc/mkcert-ca/*.pem; do
  [ -f "$f" ] || continue
  case "$f" in *-key.pem) continue ;; esac
  cp "$f" /usr/local/share/ca-certificates/mkcert-rootCA.crt
  installed=1
  break
done
if [ -n "$installed" ]; then
  update-ca-certificates
fi
exec /usr/bin/entrypoint "$@"
