# UniFi Guest WiFi Deployment Guide

This app should not be the only security boundary for guests. Use UniFi and your firewall to isolate the guest VLAN, then redirect authorized guests to the portal.

## Recommended first deployment

1. Create a UniFi guest WiFi network on its own VLAN.
2. Apply firewall rules that block guest access to home LAN devices by default.
3. Allow guest clients to reach only:
   - DNS and DHCP
   - The Guest Portal reverse proxy
   - The specific Home Assistant dashboard host and port you expose for guests
4. In UniFi Hotspot Manager, enable the guest portal method you prefer, such as vouchers or a shared password.
5. Set the post-authorization redirect URL to:
   - `https://guestportal.example.com/`
6. In Home Assistant, create a dedicated guest user and dashboard with only the entities guests need.
7. In Guest Portal admin, configure each room with that limited Home Assistant dashboard URL.

With this model, UniFi decides who may join the guest network. Guest Portal then creates the room session, stores the guest token in the browser, and requires that token for uploads.

## Home Assistant isolation checklist

- Use a dedicated Home Assistant guest user.
- Hide admin, settings, automations, logs, history, and private dashboards.
- Expose only guest-safe entities such as room lights, climate, media, or locks you explicitly trust guests to control.
- Prefer HTTPS for the Home Assistant URL.
- Do not rely on the Guest Portal link as the access control layer; Home Assistant permissions must enforce the boundary.

## NAS upload checklist

- Use a dedicated NAS share for guest uploads.
- Apply a storage quota.
- Mount with `noexec,nodev,nosuid` where your NAS/client supports it.
- Back up or download photos before deleting guest folders from the admin panel.
- Treat uploads as untrusted files even though the app rejects scripts and executable file types.

## Future external portal integration

A true UniFi external portal integration would let this app receive UniFi guest parameters, call the UniFi Network Application API to authorize the client, and then redirect to registration.

Before implementing that, gather:

- UniFi Network Application URL
- Site ID, often `default`
- Preferred auth method: local admin API account, API key, or another supported integration path for your controller version
- Guest WiFi VLAN/subnet
- Portal FQDN and TLS certificate plan
- Whether authorization should be voucher-based, room-code-based, or admin-approved

The current app is ready for the safer first deployment path. External portal support should be added after those controller details are known, because UniFi API behavior differs across Network Application versions.
