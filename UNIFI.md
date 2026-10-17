# UniFi Guest WiFi Deployment Guide

This app should not be the only security boundary for guests. Use UniFi to admit guests, then send the browser to the portal. Validated against UniFi OS 5.1 with Network 10.6 on a UDM Pro, and Home Assistant OS with Core 2026.10.

Live hostnames, VLAN IDs, and subnets stay in the gitignored site note from [AGENTS.md](AGENTS.md). Do not commit them.

## Recommended first deployment

UniFi sends the phone to Guest Portal before it authorizes the client. The phone's temporary captive-portal browser stays open while the client is unauthorized, which is the only way a guest reaches registration without typing the address. Guest Portal creates the room session and the upload token in that window. Other websites stay blocked until the later Integration API step authorizes the client.

1. In **Settings > Networks**, create the guest VLAN and turn on **Network Isolation**. That blocks the guest network from every other VLAN, including the home LAN where the portal, Nginx Proxy Manager, and Home Assistant live.
2. In **Settings > WiFi**, create the SSID, assign that VLAN, turn on **Hotspot Portal > Captive Portal**, and turn on **Client Device Isolation**. On the switch, turn on **Device Isolation (ACL)** for that network.
3. In **Settings > Security > Firewall**, add one exception. Network 10 uses zone-based firewalls. Allow the guest network to reach DNS and DHCP on its gateway, and TCP 443 plus TCP 80 on the Nginx Proxy Manager address. Leave the portal LXC, Home Assistant port 8123, and the rest of the home LAN closed to guests.
4. On **Clients > Hotspot > Landing Page**, enable **External Portal Server** and aim it at the internal Guest Portal hostname (`guestportal.example.com`). Leave hotspot **Password** and **Vouchers** off. Those methods authorize the phone and then open the success **Custom URL**, and iOS and Android close the temporary browser as soon as the connectivity check succeeds. A Wi-Fi passphrase on the SSID can stay. That passphrase is not the hotspot password. Leave **HTTPS Redirection Support** off so the UDM does not intercept TLS. UniFi redirects to `http://<portal-host>/guest/s/<site>/` with `ap`, `id`, `t`, `url`, and `ssid`. Guest Portal answers that path with the registration page. If the external-portal field accepts only an IPv4 address, enter the Nginx Proxy Manager address and set the landing-page **Domain** to the portal hostname. The address in the temporary browser has to be that hostname so the proxy certificate matches. Turn **Secure Portal** on only when the redirect would otherwise stay on the raw proxy IP. The certificate the phone sees is the proxy certificate, not a certificate on the UDM.
5. On that same Landing Page, add the portal hostname and the Nginx Proxy Manager address to **Pre-Authorization Allowances** (some builds label this **Pre-Authorization Access**). Unauthorized phones can open only those hosts. That allowance is what lets the registration page load while the temporary browser stays open. The firewall exception in step 3 is still required.
6. On that same Landing Page, check **Post-Authorization Restrictions**. A private-range block drops traffic to the home LAN even after a later authorization. Exempt the Nginx Proxy Manager address.
7. Add a Host (A) record so guests resolve the portal hostname to the Nginx Proxy Manager address. On Network 10.6 this is **Settings > Policy Table > Create New Policy > DNS**. Guest DHCP already uses the UDM as DNS. Issue the certificate in Nginx Proxy Manager with a DNS challenge. A public A record is not required for an internal name.
8. Publish Home Assistant through the same proxy under one local hostname, then set each room's dashboard URL to a path on that host. See the Home Assistant section below.
9. In Guest Portal admin, store that room dashboard URL. The Welcome hub opens it in the guest's browser. The guest still signs in to Home Assistant. The portal does not sign them in.

A phone that already passed the hotspot password is still authorized, so UniFi will not open the temporary browser again. Forget that Wi-Fi network on the phone, or unauthorize the client in UniFi, then join again.

Use [PROXY.md](PROXY.md) for the Nginx Proxy Manager host, forwarded headers, and upload size. Use [BACKUP.md](BACKUP.md) for NAS backup and permission checks.

Home Assistant dashboard DNS waits until that one hostname exists. One record covers every room. Paths such as `/guest-room/home` are not separate DNS names.

## Home Assistant

Guest dashboard links stay on the local hostname. A Nabu Casa remote URL is a public address, so it is not the room dashboard URL. Nabu Casa cloud backups can stay enabled. Turn remote control off when the instance itself should stay off the internet.

The proxy target is Home Assistant on port 8123. Trust the proxy in `configuration.yaml`, using the proxy's home-LAN address:

```yaml
http:
  use_x_forwarded_for: true
  trusted_proxies:
    - 192.168.0.10
```

Create the guest login under **Settings > People > Users**. Leave **Administrator** off, and do not attach the login to a Person. A non-administrator cannot open Settings.

Household dashboards stay available to the family. Do not mark them admin-only when other non-administrator accounts need them.

Install the HACS Kiosk Mode integration and scope it to the guest display name (the name shown in Home Assistant, not the login username):

```yaml
kiosk_mode:
  user_settings:
    - users:
        - "Guest display name"
      kiosk: true
      ignore_mobile_settings: true
```

`non_admin_settings` would hide the sidebar for every non-administrator, including the household. Do not use it for this.

In the guest user's profile, set the default dashboard to the guest dashboard. In Guest Portal, set the room URL to that dashboard's path. Kiosk mode hides the header and sidebar for that login, so the guest sees that dashboard and no menu of the others.

Kiosk mode hides navigation. A guest who types another Home Assistant path can still open it. Stock Home Assistant Core 2026.10 also leaves History, Activity, Energy, and Map reachable by address, and a non-administrator can control entities that are not on the guest dashboard. Keep locks and cameras off the guest dashboard.

## NAS upload checklist

- Use a dedicated NAS share for guest uploads.
- Apply a storage quota.
- Mount with `noexec,nodev,nosuid` where your NAS/client supports it.
- Back up or download photos before deleting guest folders from the admin panel.
- Treat uploads as untrusted files even though the app rejects scripts and executable file types.

## Future external portal integration

Guest Portal already accepts the external-portal redirect and shows registration while the phone is unauthorized. Calling the Network Integration API to authorize the client, which is what opens the rest of the internet and lets the temporary browser close, is still a later step. Do not turn hotspot Password or Vouchers back on to grant that internet access. That closes the temporary browser before the guest can use the page.

On UniFi OS 5.1 and Network 10.6 the Integration API is the supported path. Create the key on the console under **Settings > Control Plane > Integrations**. A key created at unifi.ui.com is a cloud key and is rejected by the gateway's local API. Read the site id from `GET /v1/sites`. A UDM returns one site. The legacy redirect path still uses `/guest/s/default/`. The Integration API id can differ from that slug.

The external portal redirect looks like `/guest/s/<site>/` with query parameters `ap`, `id` (client MAC), `t`, `url`, and `ssid`. Authorization is `POST /v1/sites/{siteId}/clients/{clientId}/actions` with `action` set to `AUTHORIZE_GUEST_ACCESS`. Pre-authorization allowances apply to this mode, because guests must reach the external portal before UniFi authorizes them.

The guest VLAN and the portal hostname are already decided. They stay in the gitignored site note. Hotspot Password and Voucher admission is not the landing path, because it authorizes the phone before the page loads. Still ask only for these, and keep the answers out of git:

- Console URL
- Site id returned by `GET /v1/sites`
- API key created on the console
- Nginx Proxy Manager, Home Assistant, and portal addresses on the home LAN
- Local Home Assistant hostname and the guest user's display name
