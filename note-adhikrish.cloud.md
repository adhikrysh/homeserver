# homeserver

a thinkpad t480 i set up in dec 2024. it runs my photo library, file storage, music, dns, backups, my notes, and the claude code and codex sessions i leave running for hours. it sits in singapore and i work from palo alto, so most decisions here come down to two constraints: nothing exposed to the internet, and as few round trips across the pacific as possible.

## hardware

```text
thinkpad t480        i5-8350U, 4c/8t
ram                  ~24 GB, ~3 GB in use
disk                 477 GB nvme
os                   ubuntu 24.04
battery              charge held at 75-80%
```

a laptop is a reasonable server for this load: low idle power, no fan noise, and the battery covers short power cuts. charge is capped at 80% because a cell held at 100% for years degrades and swells.

## ingress

no ports are forwarded on the router and the home ip isn't in dns. `cloudflared` keeps an outbound tunnel to cloudflare, cloudflare terminates tls and enforces access policies, and nginx proxy manager routes by hostname.

```text
cloudflare edge (tls + access) -> cloudflared -> nginx proxy manager -> one docker network per app
```

a single wildcard record points every subdomain at the tunnel, so adding a service is a compose file and a proxy host with no dns change. each app has its own docker network and the proxy is the only container attached to all of them. the tunnel container is attached only to the frontend network, so it can reach the proxy and nothing else.

details that matter:

- ssh uses the same tunnel on its own hostname. cloudflare evaluates routes in order, so the ssh route has to sit above the wildcard or ssh traffic is sent to nginx.
- the ssh route targets the docker gateway address on the frontend network, since `localhost` inside the tunnel container is the container itself.
- let's encrypt on the proxy fails behind cloudflare's proxying because the http challenge is intercepted. tls terminates at the edge instead, the tunnel encrypts the middle leg, and the last hop is plain http on a private bridge network.

humans authenticate through the browser, scripts use service tokens, and the immich ios app has its own narrowly scoped policy because it can't complete a browser login.

## tailscale

cloudflare handles everything that should have a public hostname. tailscale handles everything that shouldn't. the tailnet has three nodes (the server, my mac, my phone) with magicdns enabled, and the mac connects over a direct wireguard path rather than a relay. samba and navidrome are never published; off the home network the tailnet is the only route to them. no exit node and no subnet routing.

the two paths fail independently. a cloudflare incident doesn't cut me off, and neither does a stuck tailscale client on the laptop, because the tunnel runs as a container on the server.

## latency

before tuning anything i broke a request down by phase (measured in march, ~13,600 km of fibre):

```text
tcp connect     110 ms
tls             146 ms
first byte      182 ms
```

server time is about 30ms. the rest is distance, so the only lever is reducing round trips:

- bbr with `fq` instead of cubic, which holds throughput better on a long, lossy path
- tcp fast open on client and server, saving a round trip on repeat connections
- `tcp_slow_start_after_idle = 0`, so idle connections don't drop back to a small window
- keepalives at ~1 minute instead of 2 hours, so dead connections are detected and replaced quickly
- http/2 on every proxy host (it had been off)
- gzip at level 5

http/3 and brotli would help further, but nginx proxy manager supports neither. the largest remaining win is caching immich thumbnails at the edge. measurements and configs are in [`docs/latency.md`](docs/latency.md).

## dns

adguard home is the resolver for my devices. it blocks ad and tracker domains, and more importantly it caches: a cold lookup measured ~123ms, a cached one ~3ms. its config is root-owned, so the nightly backup reads it through `docker exec`.

## music

navidrome serves the music library over the subsonic api, so any subsonic client works. the library is mounted read-only, rescanned hourly, and sessions last 24 hours. navidrome is reachable only on the lan and the tailnet. a small shim i wrote sits beside it, talks to navidrome's api, and is the only service with write access to the library.

## reliability

the system should recover from routine failures without me:

- every container runs with `always` or `unless-stopped`, so crashes and reboots recover on their own
- the tunnel starts only after the proxy's healthcheck passes, so traffic never reaches a proxy that's still starting
- immich's postgres image is pinned by digest and initialised with data checksums, so upgrades are explicit and corruption is detected
- uptime kuma checks every app directly as well as through the proxy, which separates a proxy failure from an app failure
- beszel records cpu, memory, disk, network and temperature for the host and each container
- unattended-upgrades applies security patches

## backups

```text
01:30  backup_configs.sh -> server-configs
02:00  backrest (restic) -> backblaze b2
03:00  prune; monthly integrity check; 30 daily, 12 monthly snapshots
```

the config script handles three cases a plain copy gets wrong. root-owned `0600` configs are read through `docker exec`. beszel's sqlite database is copied with `sqlite3.backup()` so a write in progress can't produce a torn copy. and the restic repository password, which used to sit in a config that was itself backed up into that repository, is now kept outside the system, since a copy only reachable through the password can't recover the password. [`scripts/backup_configs.sh`](scripts/backup_configs.sh)

## storage

about 32 GB of original photos, mounted read-only into immich so it can index them but never modify them. about 24 GB of immich uploads and thumbnails, with face and object search running locally. filebrowser and samba expose the same share. n8n, open webui and logseq ran here earlier and have since been retired; their configs remain in the backup bundle.

## second brain

my notes are obsidian vaults stored as plain markdown on google drive, mounted on the server by an `rclone` systemd user service, so every machine and every agent reads the same files. the storage provider is incidental; the requirement is plain files i hold a copy of.

```text
obsidian/
  skills/          agent instructions and skills
  technicals/  space/  startups/
  meeting-notes/   raw transcripts, source material only
  private/         excluded from agent use
```

each vault has a `home.md` linking to folder indexes, and each index line states what its note explains, so an agent can reach any note in a couple of `rg` lookups. notes are written for a reader with no context, and corrections are kept alongside the original reasoning instead of overwriting it.

claude code and codex load the same instruction file and skills, symlinked out of `obsidian/skills/`, so one edit updates both agents on every machine. one skill converts a long technical conversation into a note, and it refuses to write unless the vault passes three checks: a `home.md` exists, the vault contains notes, and exactly one `.obsidian` directory is present.

## long-running agents

claude code and codex run on the server, not on my laptop. tmux is started at boot by a systemd user service with lingering enabled, so sessions continue regardless of whether i'm connected, and a multi-hour task keeps running with the laptop closed.

i attach from the mac over the tailnet (~190ms) or the tunnel, and cmux shows each tmux window as a tab. tmux passes clipboard and notification escape sequences through, so permission prompts and completions reach the mac. the agents, their working trees and their tools all live on the server; only terminal input crosses the pacific.

two tools came out of running many sessions in parallel: [agent-squad](https://github.com/adhikrysh/agent-squad), a read-only dashboard of every claude code and codex session ordered by which ones are waiting on me, and [ghostty-agent-workspace](https://github.com/adhikrysh/ghostty-agent-workspace), a scripted terminal layout for working alongside them.

the agents' standing instructions: push me to reason instead of reasoning for me, separate what was verified from what was assumed, prefer cli over api over mcp over a browser, and delegate simple work to smaller models but verify the result.

configs and scripts are in this repo with secrets removed.
