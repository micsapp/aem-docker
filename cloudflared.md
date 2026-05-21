# Cloudflare Tunnel Guide

How to expose this machine's services (e.g. AEM Author on `:4502`, Publish on `:4503`) over HTTPS via Cloudflare Tunnel — no port forwarding, no firewall rules.

## Current state on this host

| Item | Value |
|---|---|
| `cloudflared` binary | `/usr/local/bin/cloudflared` (v2026.2.0) |
| Config dir | `~/.cloudflared/` |
| Login cert | `~/.cloudflared/cert.pem` (already authenticated) |
| Active tunnel | `mytunnel` (UUID `<TUNNEL_UUID>`) |
| Active config | `~/.cloudflared/config.yml` |
| Runner | tmux session `cloudflared` → `cloudflared tunnel run mytunnel` |
| Log | `~/micsapp-webterminal/cloudflared.log` |

Existing ingress in `~/.cloudflared/config.yml`:

```yaml
tunnel: mytunnel
credentials-file: /home/mli/.cloudflared/<TUNNEL_UUID>.json

ingress:
  - hostname: mytunnel.example.com
    service: http://localhost:7680
  - hostname: md-docs.example.com
    service: http://localhost:80
  - hostname: ssh-mytunnel.example.com
    service: ssh://localhost:22
  - service: http_status:404
```

Because a tunnel and login cert already exist, the easiest path is to **add a new hostname to the existing `mytunnel` tunnel** rather than creating a brand-new one.

---

## Option A — Add AEM to the existing `mytunnel` tunnel (recommended)

### 1. Edit ingress rules

Add entries **above** the catch-all `http_status:404` rule.

```yaml
tunnel: mytunnel
credentials-file: /home/mli/.cloudflared/<TUNNEL_UUID>.json

ingress:
  - hostname: mytunnel.example.com
    service: http://localhost:7680
  - hostname: md-docs.example.com
    service: http://localhost:80
  - hostname: ssh-mytunnel.example.com
    service: ssh://localhost:22

  # AEM Author + Publish
  - hostname: aem-author.example.com
    service: http://localhost:4502
  - hostname: aem-publish.example.com
    service: http://localhost:4503

  - service: http_status:404
```

Ingress matches **top-down**; the `http_status:404` line must stay last.

### 2. Create the DNS CNAMEs

Run once per hostname — this writes a `*.cfargotunnel.com` CNAME into your Cloudflare zone:

```bash
cloudflared tunnel route dns mytunnel aem-author.example.com
cloudflared tunnel route dns mytunnel aem-publish.example.com
```

### 3. Restart the tunnel to pick up the new config

The tunnel is running in a tmux session, so restart by killing the process inside it (tmux re-runs nothing on its own — the `tee` pipeline exits and the session ends, which is fine because we'll relaunch).

```bash
tmux kill-session -t cloudflared 2>/dev/null
tmux new-session -d -s cloudflared \
  'cloudflared tunnel run mytunnel 2>&1 | tee -a /home/mli/micsapp-webterminal/cloudflared.log'
```

Verify:

```bash
tmux ls                         # cloudflared session should be listed
cloudflared tunnel info mytunnel # should show active connections
curl -I https://aem-author.example.com/
```

> First request after DNS creation can take up to a minute to propagate.

### 4. (Optional) Protect with Cloudflare Access

AEM ships with `admin/admin`. Before pointing a public hostname at it, add a Cloudflare Access policy (Zero Trust dashboard → Access → Applications) so only your email/identity can reach `aem-author.example.com`.

---

## Option B — Create a new dedicated tunnel

Use this if you want AEM isolated from the `mytunnel` tunnel.

### 1. Authenticate (only if `~/.cloudflared/cert.pem` is missing)

```bash
cloudflared tunnel login
```

Opens a URL — sign in and pick the `example.com` zone. Already done on this host.

### 2. Create the tunnel

```bash
cloudflared tunnel create aem
```

Writes a `~/.cloudflared/<UUID>.json` credentials file. Note the UUID.

### 3. Write config

`~/.cloudflared/aem.yml`:

```yaml
tunnel: aem
credentials-file: /home/mli/.cloudflared/<UUID>.json

ingress:
  - hostname: aem-author.example.com
    service: http://localhost:4502
  - hostname: aem-publish.example.com
    service: http://localhost:4503
  - service: http_status:404
```

### 4. Route DNS and run

```bash
cloudflared tunnel route dns aem aem-author.example.com
cloudflared tunnel route dns aem aem-publish.example.com

# Foreground test
cloudflared --config ~/.cloudflared/aem.yml tunnel run aem

# Persistent (tmux)
tmux new-session -d -s aem-tunnel \
  'cloudflared --config ~/.cloudflared/aem.yml tunnel run aem 2>&1 | tee -a ~/aem-docker/aem-tunnel.log'
```

### 5. Or install as a systemd service

```bash
sudo cloudflared --config ~/.cloudflared/aem.yml service install
sudo systemctl status cloudflared
```

---

## Option C — Fully automated via `cf_tunnel_install.sh`

`~/micsapp-webterminal/cf_tunnel_install.sh` is a standalone installer that creates the tunnel, writes config, sets up DNS, and (optionally) installs a systemd service in one shot.

```bash
~/micsapp-webterminal/cf_tunnel_install.sh \
  --name aem-author \
  --hostname aem-author.example.com \
  --service http://localhost:4502 \
  --install-service
```

See `--help` for all flags (web-terminal mode, replace-config, etc.).

---

## Useful commands

```bash
cloudflared tunnel list                 # list all tunnels in this account
cloudflared tunnel info mytunnel         # connections + edge POPs for one tunnel
cloudflared tunnel ingress validate     # check the active config.yml
cloudflared tunnel ingress rule https://aem-author.example.com/
                                        # which rule matches this URL?
tail -f ~/micsapp-webterminal/cloudflared.log
```

## Troubleshooting

- **`error="connection refused"` in logs** — AEM isn't listening yet (first boot takes 5–10 min) or the port is wrong.
- **DNS resolves but request hangs** — config wasn't reloaded after editing; restart the tunnel process.
- **`This site can't provide a secure connection`** — Cloudflare SSL mode must be **Full** (not Flexible) so the edge knows the origin is HTTP behind the tunnel.
- **`cloudflared` version warning** — current host runs 2026.2.0; latest is 2026.5.0. Upgrade with the official Cloudflare apt repo if you hit a bug.

## Related docs

- `~/micsapp-webterminal/README.md` — end-to-end web terminal setup (auth, nginx, tunnel)
- `~/micsapp-webterminal/web_terminal_wiki.md` — architecture diagrams + flow
- `~/micsapp-webterminal/cf_tunnel_install.sh --help` — installer reference
