# Backup and Restore Guide

Back up app configuration separately from guest uploads. Guest uploads may live on a NAS share, while app state lives in `/etc/guest-portal` inside the LXC.

## What to back up

Inside the Guest Portal container:

- `/etc/guest-portal/config.json`
- `/etc/guest-portal/storage.json`
- `/etc/guest-portal/sessions.json`
- `/etc/guest-portal/guest-tokens.json`
- `/etc/guest-portal/.smbcredentials`, if SMB mounting is configured inside the container

Upload storage:

- Default local uploads: `/opt/guest-portal/uploads/`
- NAS uploads: your configured upload mount path

## Recommended backup command

From the Proxmox host, replace `<ctid>` and choose a destination outside the container:

```bash
pct exec <ctid> -- tar -czf /tmp/guest-portal-config-backup.tgz -C / etc/guest-portal
pct pull <ctid> /tmp/guest-portal-config-backup.tgz ./guest-portal-config-backup.tgz
```

If uploads are stored locally rather than on a NAS:

```bash
pct exec <ctid> -- tar -czf /tmp/guest-portal-uploads-backup.tgz -C /opt/guest-portal uploads
pct pull <ctid> /tmp/guest-portal-uploads-backup.tgz ./guest-portal-uploads-backup.tgz
```

If uploads are on a NAS, use the NAS backup tooling or snapshots for that share.

## Restore

1. Stop the service:
   ```bash
   pct exec <ctid> -- systemctl stop guest-portal
   ```
2. Push and extract the config backup:
   ```bash
   pct push <ctid> ./guest-portal-config-backup.tgz /tmp/guest-portal-config-backup.tgz
   pct exec <ctid> -- tar -xzf /tmp/guest-portal-config-backup.tgz -C /
   ```
3. Restore ownership:
   ```bash
   pct exec <ctid> -- chown -R guestportal:guestportal /etc/guest-portal
   ```
4. Restore local uploads if needed:
   ```bash
   pct push <ctid> ./guest-portal-uploads-backup.tgz /tmp/guest-portal-uploads-backup.tgz
   pct exec <ctid> -- tar -xzf /tmp/guest-portal-uploads-backup.tgz -C /opt/guest-portal
   pct exec <ctid> -- chown -R guestportal:guestportal /opt/guest-portal/uploads
   ```
5. Start the service:
   ```bash
   pct exec <ctid> -- systemctl start guest-portal
   ```
6. Log into `/admin.html` and verify **Deployment Status**:
   - App status is OK.
   - Upload storage exists and is writable.
   - Room/dashboard counts look correct.
   - Dashboard URL reachability passes after selecting **Check Dashboard URLs**.

## NAS permission checklist

- Use a dedicated NAS share for guest uploads.
- Apply a quota that matches your comfort level for guest photos and videos.
- Use a dedicated NAS user with access only to the guest upload share.
- Prefer host-managed mounts plus LXC bind mounts for unprivileged containers.
- If the container mounts SMB directly, use `uid` and `gid` for the `guestportal` service user.
- Mount with restrictive options such as `nosuid,nodev,noexec` where supported.
- Confirm the container service user can write:
  ```bash
  pct exec <ctid> -- su -s /bin/sh -c 'test -w /mnt/nas/guest-photos' guestportal
  ```
