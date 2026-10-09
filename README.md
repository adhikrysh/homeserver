# homeserver

a 2018 thinkpad that serves my photos, files, backups, and the second brain my ai agents read before they act. it has no open ports: it dials out through a tunnel, and every visitor proves who they are before reaching it.

**read the story:** [adhikrish.cloud/src/homeserver](https://adhikrish.cloud/src/homeserver) (the same text is in [`note-adhikrish.cloud.md`](note-adhikrish.cloud.md)).

```text
browser
  -> cloudflare edge          tls + access policy (humans: login, machines: service tokens)
  -> outbound tunnel          the server opened it; no inbound ports, no port forwarding
  -> nginx proxy manager      routes by hostname
  -> one docker network per app
       immich · filebrowser · backrest · uptime kuma · beszel

nightly
  01:30  config bundle (pg_dumpall, root-only configs via docker exec, sqlite online backup)
  02:00  restic via backrest -> backblaze b2, encrypted
  03:00  prune; monthly integrity check
```

## what is in this repo

| path | what it is |
|---|---|
| [`note-adhikrish.cloud.md`](note-adhikrish.cloud.md) | the full write-up: why, how, and what it taught me |
| [`compose/`](compose/) | the real compose files for every running service, secrets moved to `.env` |
| [`scripts/backup_configs.sh`](scripts/backup_configs.sh) | the nightly config backup that feeds restic |
| [`scripts/apply-tcp-tuning.sh`](scripts/apply-tcp-tuning.sh) | installs the tcp tuning for a long, high-latency link |
| [`config/`](config/) | sysctl, nginx gzip snippet, tmux, and the systemd user units (tmux at boot, the second-brain mount) |
| [`docs/latency.md`](docs/latency.md) | measuring each request phase before tuning anything |
| [`docs/add-a-service.md`](docs/add-a-service.md) | the runbook for adding an app behind the tunnel |

## the stack

- **host:** thinkpad t480, i5-8350U, ~24 GB ram, 477 GB nvme, ubuntu 24.04 lts. battery held at 75-80% as a small built-in ups.
- **ingress:** cloudflare tunnel (`cloudflared`) + cloudflare access (zero trust) + nginx proxy manager. a wildcard dns record sends every subdomain to the tunnel.
- **private access:** ssh and a finder mount over the same tunnel with `cloudflared access tcp`; tailscale as a second, independent path.
- **apps:** immich (photos with machine-learning search), filebrowser, samba, backrest, uptime kuma, beszel.
- **backups:** a nightly config bundle, then restic to backblaze b2 through backrest.
- **second brain:** obsidian vaults on google drive, mounted by an `rclone` systemd user service; claude code and codex share one instruction file and one set of skills from inside it.

## what is deliberately not here

secrets, hostnames, addresses, account and tunnel identifiers, and anything personal stored on the server. the compose files reference a `.env` that is not, and will not be, in this repository.
