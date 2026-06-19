# Reverse Proxy and HTTPS Guide

Use a reverse proxy in front of the Guest Portal container. The app should stay on an internal HTTP listener, and the proxy should terminate HTTPS.

## Nginx Proxy Manager

Create a Proxy Host with these generic settings:

### Details

- Domain Names: `guestportal.example.com`
- Scheme: `http`
- Forward Hostname / IP: the Guest Portal LXC IP
- Forward Port: `3000`
- Cache Assets: off
- Block Common Exploits: on
- Websockets Support: on

### SSL

- Request a new SSL certificate.
- Enable Force SSL.
- Enable HTTP/2.
- Enable HSTS after the hostname is stable.
- For internal-only hostnames, use a DNS challenge provider rather than exposing the portal publicly.
- Store DNS provider API tokens in Nginx Proxy Manager only. Do not commit them to this repository.

### Advanced

Use generic hardening headers and an upload body size that matches your guest policy:

```nginx
client_max_body_size 50M;
add_header X-Content-Type-Options nosniff always;
add_header X-Frame-Options DENY always;
add_header Referrer-Policy strict-origin-when-cross-origin always;
add_header Permissions-Policy "camera=(), microphone=(), geolocation=()" always;
```

If your Home Assistant dashboard must frame the portal or the portal must frame another service, revisit `X-Frame-Options` and any Content Security Policy together. Do not loosen framing globally without a specific need.

## Internal DNS

For home deployments, prefer split DNS or an internal DNS override so guest devices resolve the portal hostname to the internal reverse proxy address.

Recommended flow:

1. Public DNS provider proves domain ownership for certificates with DNS challenge.
2. Internal DNS resolves `guestportal.example.com` to the NPM LXC address.
3. NPM forwards to the Guest Portal LXC on port `3000`.
4. UniFi guest VLAN firewall allows guests to reach only DNS/DHCP, NPM, and the limited Home Assistant endpoint.

## Safety checklist

- Keep the Guest Portal LXC off the public internet unless you explicitly need remote access.
- Use HTTPS even for internal guest networks.
- Keep Cloudflare or DNS provider API tokens in NPM secrets/config only.
- Do not store real domains, tokens, or internal IPs in repository files.
- Test `/health`, `/admin.html`, `/photo.html`, and a PDF upload after proxy changes.
