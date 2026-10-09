# homeserver

i bought a thinkpad t480 in december 2024. it now holds every photo i've taken, my files, my notes, and the instructions my coding agents read at the start of every session. nothing on it has ever been port-forwarded.

## why

photos in someone else's cloud. documents spread across accounts. notes in whichever app was exciting that quarter. agents that forget everything the moment the tab closes.

none of that is a crisis. it's rent, paid monthly, on things worth keeping for forty years.

## the box

```text
thinkpad t480        i5-8350U, 4c/8t
ram                  ~24 GB, ~3 in use on a busy day
disk                 477 GB nvme, ext4 on lvm
os                   ubuntu 24.04
battery              held at 75-80%
```

the battery is the ups. capping the charge is what keeps a laptop that never leaves the desk from swelling up in year two.

## ingress

no port forwarding, no public ip in dns. `cloudflared` dials out, the edge terminates tls, cloudflare access decides who gets in, and nginx proxy manager routes by hostname.

```text
edge (tls + access)
  -> cloudflared         frontend-network only
  -> nginx proxy manager on every app network
       -> immich | filebrowser | backrest | uptime-kuma | beszel
```

one wildcard record points every subdomain at the tunnel, so a new app is a compose file and a proxy host. every app gets its own docker network and the proxy is the only thing on all of them. the tunnel can reach the proxy and nothing else.

things that cost me an evening each:

- ssh shares the tunnel. routes match top-down, so the ssh hostname has to sit above the wildcard or ssh gets handed to nginx.
- the ssh route can't say `localhost:22`. that's the tunnel container. it points at the docker gateway on frontend-network.
- let's encrypt on the proxy never worked behind cloudflare's proxying. i stopped trying. edge cert outside, tunnel in the middle, plain http on a private bridge for the last hop.

humans authenticate in the browser, scripts carry service tokens, and immich's ios app has its own narrow policy because it can't do the browser flow. from my mac, ssh and a finder mount go through `cloudflared access tcp` on a launch agent. tailscale is the second way in when i want the lan.

## latency

for a while i lived roughly 13,600 km of fibre from this desk. so before changing anything i split a request into phases:

```text
tcp connect     110 ms
tls             146 ms
first byte      182 ms
```

the server spends ~30 ms. the rest is the pacific. so the work was cutting round trips:

- bbr + `fq` instead of cubic
- tcp fast open, both directions
- `tcp_slow_start_after_idle = 0`
- keepalive down from 2 hours to about a minute
- http/2, which turned out to be off on every proxy host
- gzip at level 5

http/3 and brotli would help and nginx proxy manager supports neither. edge-caching immich thumbnails is the biggest win left. numbers and configs are in [`docs/latency.md`](docs/latency.md) and [`config/`](config/).

## keeping it up

i built this for the 3am version of me, who is asleep and not getting up.

- every container restarts on its own
- the tunnel waits on the proxy's healthcheck, so traffic never lands on a half-booted nginx
- immich's postgres is pinned by digest with `--data-checksums`
- uptime kuma sits on each app's network and checks the app directly as well as through the proxy, because a green proxy in front of a dead app is the classic lie
- beszel tracks host and per-container cpu, memory, disk, network and temps, through a read-only docker socket
- unattended-upgrades handles security patches

## backups

```text
01:30  backup_configs.sh -> /srv/sambashare/data/server-configs
02:00  backrest (restic) -> backblaze b2
03:00  prune · monthly check · 30 daily, 12 monthly
```

the config script exists because of three bugs, in order:

- root-owned `0600` configs made the copy die with permission denied. now read through `docker exec`.
- copying a live sqlite file can tear a page. beszel's db goes through `sqlite3.backup()`.
- the restic password sat in backrest's config, which got backed up into the restic repo it unlocks. the password now lives outside the system.

script: [`scripts/backup_configs.sh`](scripts/backup_configs.sh).

## what's on it

| | |
|---|---|
| photos | ~32 GB of originals. immich mounts them read-only, so it can index everything and delete nothing |
| immich library | ~24 GB of uploads and thumbnails, with face and object search running locally |
| server-configs | the nightly bundle |
| filebrowser · samba | the same share, in a browser or in finder |
| backrest · uptime kuma · beszel | backups, uptime, metrics |

n8n, open webui and logseq each lived here for a while. none of them earned the ram. their configs are still in the bundle in case i'm wrong.

## second brain

obsidian, plain markdown on google drive, mounted on the server by an `rclone` user service so every machine and every agent reads the same files. yes, it's on google drive. i own the files, not the disk.

```text
obsidian/
  skills/          agent instructions + skills
  technicals/
  space/
  startups/
  meeting-notes/   raw transcripts, source material only
  private/         agents never use this outside private work
```

each vault has a `home.md` that points at folder indexes, and every index line says what the note explains. an agent gets anywhere in a couple of `rg` hops. notes are written for someone with zero context, which is usually me in six months. they keep the wrong model next to the right one, because how i was wrong is the useful part. nothing gets deleted. it gets archived.

claude code and codex read the same instruction file and the same skills, symlinked out of `obsidian/skills/`. one edit changes both agents on every machine.

one skill turns a long technical conversation into a note. it keeps the argument, meaning the question, the model i started with, where it broke and what replaced it, and drops the chat. before writing it checks three things separately: the vault has a `home.md`, it actually contains notes, and there's exactly one `.obsidian` under it. any failure and it writes nothing.

## agents

a user service starts tmux at boot, so sessions outlive my laptop lid. each window shows up as a tab in my terminal, and notifications and clipboard pass through to the mac.

two tools came out of running too many agents at once:

- [agent-squad](https://github.com/adhikrysh/agent-squad), a read-only dashboard of every claude code and codex session, with the ones waiting on me at the top
- [ghostty-agent-workspace](https://github.com/adhikrysh/ghostty-agent-workspace), a one-command terminal layout for working next to them

the rules i give them are short. make me think instead of thinking for me. say what you checked and what you assumed. cli before api, api before mcp, browser last. hand the cheap work to cheaper models, then check it.

configs, scripts and runbooks are in this repo with the secrets taken out. the thinkpad is still on the desk.
