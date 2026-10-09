# homeserver

bought a thinkpad t480 in dec 2024 and it somehow ended up running my whole life: photos, files, notes, and whatever my agents read before they touch anything. it's in singapore and i'm in palo alto, so every request swims the pacific.

nothing is port-forwarded. the box tunnels out to cloudflare and everything comes in through that, so there's no door for anyone to knock on.

## the box

```text
thinkpad t480        i5-8350U, 4c/8t
ram                  ~24 GB, ~3 used
disk                 477 GB nvme
os                   ubuntu 24.04
battery              held at 75-80%
```

laptops make great servers. quiet, sips power, and the battery is a free ups. charge is capped so it doesn't turn into a spicy pillow.

## getting in

`cloudflared` holds the tunnel, cloudflare does tls and access, nginx proxy manager routes by hostname. one wildcard dns record, so a new app is a compose file and a proxy host. every app gets its own docker network and only the proxy joins all of them, so the tunnel can't reach anything but the proxy.

```text
edge (tls + access) -> cloudflared -> nginx proxy manager -> one network per app
```

things that each ate an evening:

- ssh shares the tunnel and routes match top-down, so with the wildcard first, ssh gets sent to nginx. nginx was confused.
- the ssh route can't be `localhost:22` because that's the tunnel container. it points at the docker gateway.
- let's encrypt never works behind cloudflare's proxy, so i stopped trying. edge cert outside, tunnel in the middle, plain http on a private bridge.

i log in through the browser, scripts use service tokens, and the immich ios app gets its own narrow policy because it can't do the browser login.

## tailscale

cloudflare is the front door, tailscale is the side door. three nodes (thinkpad, mac, phone), magicdns on, and the mac gets a direct wireguard path. samba and raw ports like beszel's dashboard only exist on the tailnet when i'm away from home. no exit node, no subnet routes, just a lan that follows me around.

having both means one of them can have a bad day and i'm still in.

## latency

timed a request before touching anything (march, ~13,600 km):

```text
tcp connect     110 ms
tls             146 ms
first byte      182 ms
```

the server takes ~30ms. the pacific takes the rest and refuses to negotiate. so i cut round trips instead: bbr + `fq`, tcp fast open, no slow start after idle, shorter keepalives, gzip at 5, and http/2, which was somehow off on every proxy host. details in [`docs/latency.md`](docs/latency.md).

## keeping it up

assume 3am me is asleep and not coming. containers restart themselves, the tunnel waits for the proxy's healthcheck, immich's postgres is pinned by digest with checksums on, and unattended-upgrades does patches. uptime kuma checks each app directly and through the proxy, because a green proxy in front of a dead app is just lying to you. beszel watches cpu, memory, disk and temps per container.

## backups

```text
01:30  backup_configs.sh -> server-configs
02:00  backrest (restic) -> backblaze b2
03:00  prune, monthly check, 30 daily + 12 monthly
```

that script exists because of three bugs. root-only configs failed with permission denied, so they're read through `docker exec`. live sqlite can tear mid-copy, so beszel goes through `sqlite3.backup()`. and the restic password was living in a config that got backed up into the repo that needs the password to open. very secure, very useless. it lives outside the system now. [`scripts/backup_configs.sh`](scripts/backup_configs.sh)

## what's on it

~32 GB of photos that immich mounts read-only (it can index everything and delete nothing), ~24 GB of immich uploads and thumbnails with face search running locally, filebrowser and samba over the same share, plus backrest, uptime kuma and beszel. n8n, open webui and logseq lived here for a bit, didn't earn their ram, got evicted.

## second brain

obsidian, plain markdown on google drive, mounted on the box with an `rclone` user service so every machine and agent reads the same files. yes it's google drive. i own the files, not the disk.

```text
obsidian/
  skills/  technicals/  space/  startups/
  meeting-notes/   raw transcripts, source only
  private/         agents stay out
```

`home.md` links to folder indexes, indexes say what each note explains, and an agent finds anything in two `rg` hops. notes assume zero context because the reader is usually me in six months, and wrong answers stay next to the right ones because that's the useful part.

claude code and codex read the same instruction file and skills, symlinked out of `obsidian/skills/`, so one edit changes both agents everywhere. one skill turns a long technical convo into a note and refuses to write unless the vault actually checks out (home note exists, notes exist, exactly one `.obsidian`).

## agents

tmux starts at boot so sessions outlive my laptop lid. two tools came out of running too many agents at once: [agent-squad](https://github.com/adhikrysh/agent-squad), a dashboard of every claude code and codex session sorted by who's waiting on me, and [ghostty-agent-workspace](https://github.com/adhikrysh/ghostty-agent-workspace), a one-command terminal layout.

the rules i give them: make me think, say what you checked versus assumed, cli before api before mcp before browser, and give cheap work to cheap models but check it.

configs and scripts are in this repo, secrets removed.
