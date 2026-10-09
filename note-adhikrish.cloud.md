# homeserver

somewhere across the pacific from me, a 2018 thinkpad is running my life. it was designed to open spreadsheets for a regional sales manager. today it serves every photo i have taken, keeps my files, backs itself up to another continent every night, and hosts the second brain that my ai agents read before they write a single line of code.

it has no open ports. nobody on the internet can knock on its door. it dug a tunnel outward and lets the world in only through that tunnel, one checked visitor at a time.

this is the story of how an old laptop became infrastructure, and what it taught me about owning things.

## the rent problem

most of us rent our digital lives without noticing the lease.

your photos live in a company's basement, billed by the gigabyte, searchable on their terms. your files are scattered across three clouds and a usb stick called `final_final_2`. your notes live in four apps, none of which talk to the others. and your ai assistant, the smartest tool you own, has the long-term memory of a goldfish on a subscription plan. every conversation starts at zero.

so you try to self-host, and you immediately meet the three horsemen:

- **port forwarding**, which turns your home router into a welcome mat for every scanner on the internet;
- **certificates**, which expire at the worst possible moment and never at a convenient one;
- **backups**, which everyone has and almost nobody has thought about past the first copy.

i wanted to own three things: my memories, my files, and my thinking. this repo is the field journal of doing that with one laptop and a stubborn refusal to open a port.

## the machine

```text
lenovo thinkpad t480
  intel core i5-8350U   4 cores / 8 threads
  ~24 GB ram            usually ~3 GB in use
  477 GB nvme           ext4 on lvm, ~19% used
  ubuntu 24.04 lts
  battery               charge held between 75% and 80%
```

a laptop is a quietly excellent server. it sips power, it is silent, and it ships with a built-in ups: the battery. holding the charge between 75 and 80 percent keeps the cell from cooking itself on a desk for years while still giving the machine room to ride out a short outage.

about a dozen containers run on it. the cpu is mostly asleep.

## the front door that does not exist

the usual way to expose a home server is to open a port on the router and point the internet at your house. i wanted the opposite: a server that cannot be reached at all, except through a door it opened from the inside.

```text
your browser
    |  https
    v
cloudflare edge          tls ends here; access policy checked here
    |  encrypted tunnel (opened outward by the server)
    v
cloudflared container    lives on one network: frontend
    |  http
    v
nginx proxy manager      routes by hostname
    |
    +--> immich network       (photos)
    +--> files network        (file browser)
    +--> backrest network     (backups)
    +--> kuma network         (uptime)
    +--> beszel network       (metrics)
```

**the tunnel.** `cloudflared` runs in a container and dials out to cloudflare, then keeps that connection open. inbound requests ride back down it. the home ip never appears in dns, and the router forwards nothing. a scanner hitting my house finds a residential connection with nothing listening.

**one wildcard, zero dns chores.** a single wildcard record points every subdomain at the tunnel. adding a service never touches dns; the proxy decides where a hostname goes.

**hub and spoke, not a flat network.** every app gets its own docker network. nginx proxy manager is the only container that joins all of them, and the tunnel container joins only the frontend network. so the photo app cannot talk to the backup app, and the tunnel cannot reach any app directly. if one service is compromised, it is alone in a small room.

two lessons this layer taught me the hard way:

- **route order is load-bearing.** ssh rides the same tunnel on its own hostname, and cloudflare matches routes top to bottom. put the wildcard first and every ssh connection gets politely forwarded to an http proxy that has no idea what ssh is.
- **localhost is a lie inside a container.** the ssh route cannot say `localhost:22`, because inside the tunnel container, localhost is the tunnel container. it points at the docker host's gateway address on the frontend network instead.

and one fight i chose not to win: let's encrypt on the proxy. its domain challenge gets intercepted by cloudflare's proxying, so it fails. the honest fix was to stop fighting. cloudflare's edge certificate covers the browser leg, the tunnel encrypts the middle, and the last hop is plain http on a private docker network.

## zero trust, for real

"zero trust" gets slapped on everything, so here is what it means on this box: being on the right network earns you nothing. every request to a protected hostname proves who it is before it reaches the server.

```text
request for a protected hostname
    |
    v
cloudflare access
    |-- a human? -> browser login with an allowed identity
    |-- a machine? -> service token in request headers
    |-- neither -> redirected to a login page, never reaches the tunnel
    v
tunnel -> proxy -> app
```

humans log in through the browser. machines, which cannot click a login button, carry service tokens. the photo app's phone client is the awkward one: it cannot complete a browser login, so it gets a narrowly scoped policy of its own. that is a deliberate tradeoff, written down where future me will find it.

even my terminal uses the tunnel. my laptop runs `cloudflared access tcp` as a login agent, so ssh and a finder mount of the server work from any network, with no vpn client to forget to start. tailscale is installed as a second road for direct, lan-like access between my own devices. two independent paths in means one bad day on either does not lock me out.

## fighting physics

for a while i lived about 13,600 km of fibre away from this laptop. every page felt like it was being mailed to me.

so i measured before touching anything:

```text
phase            cumulative
tcp connect          110 ms    <- the network round trip, ~107 ms
tls handshake        146 ms
first byte           182 ms    <- the server itself spends ~30 ms
```

the server was fast: about 30 ms of work per request. everything else was distance and handshakes. light in glass needs about 68 ms just to cross 13,600 km once, and no config file argues with that. the only thing i could do was stop wasting round trips.

- **bbr instead of cubic.** cubic treats packet loss as congestion and backs off. on a long, fat pipe that is the wrong instinct. bbr models the path's bandwidth and round-trip time directly. it pairs with the `fq` packet scheduler, so that changed too.
- **tcp fast open on both sides.** a returning client can send data in its very first packet, which saves one full round trip on every new connection.
- **no slow start after idle.** switching browser tabs should not drop a connection back to a crawl.
- **http/2 was off.** every proxy host had it disabled. turning it on let a page's dozens of requests share one connection instead of queueing.
- **gzip at level 5.** most of the compression of level 9 for far less cpu. smaller responses fit in fewer round trips.

the sysctl file, the gzip snippet, and the reasoning are in [`config/`](config/) and [`docs/latency.md`](docs/latency.md). the lesson i keep: measure the phases first. without that table i would have spent a weekend tuning a server that was already fast.

## reliability, or: designing for the 3am version of me

i designed this box assuming that the version of me who has to fix it is half asleep at 3am. so the system has to heal the boring failures without him.

- **everything restarts itself.** every container runs with `always` or `unless-stopped`.
- **startup order is enforced by health, not hope.** the tunnel waits until the proxy reports healthy, so the internet never gets routed into a proxy that is still booting.
- **pinned databases.** immich's postgres image is pinned by digest and initialised with data checksums, so silent corruption becomes a loud error.
- **monitoring that tests the app, not the proxy.** uptime kuma joins each app's network, so it can check the app directly as well as through the proxy. "the proxy is up" and "the photos load" are different claims, and only one of them matters.
- **metrics with a memory.** beszel records cpu, memory, disk, network, temperature and per-container usage, and holds the alert rules. its agent reads docker through a read-only socket.
- **the os patches itself.** unattended-upgrades applies security updates.

## backups that respect the restore

a backup you cannot restore is a very expensive placebo. the pipeline runs every night as three steps, each feeding the next:

```text
01:30  backup_configs.sh
         pg_dumpall of the photo database
         proxy, monitoring, and file-browser config
         root-only configs read through docker exec
         beszel's sqlite db via an online snapshot
         every compose file and env file
                 |
                 v
       one folder on the data share
                 |
02:00  backrest (restic) -> backblaze b2, encrypted
03:00  prune; integrity check monthly
       keep 30 daily and 12 monthly snapshots
```

three bugs shaped that script, and each one taught something:

- **permissions.** some apps write their config as root-only files, so a plain copy as my user died with "permission denied". the script now reads them through `docker exec`, which runs as root inside the container.
- **live databases.** copying a sqlite file while it is being written can capture a torn page. the script uses python's `sqlite3` online backup api, which takes a consistent snapshot while the app keeps running.
- **the circular password.** the backup tool's config contains the repository password, and that config is itself backed up into the encrypted repository. a copy that only exists inside the vault it unlocks is no recovery path. the password is escrowed outside the system entirely.

the script is in [`scripts/backup_configs.sh`](scripts/backup_configs.sh).

## what lives here

```text
/srv/sambashare/data
  photos/           ~32 GB   originals, organised by shoot
  library/          ~24 GB   the photo app's upload store and thumbnails
  server-configs/            the nightly config bundle
  archives/                  long-term keepsakes
```

| app | what it does | how it is reached |
|---|---|---|
| immich | photo library with machine-learning search for faces and objects, run on the server itself | tunnel + access |
| filebrowser | web file manager over the data share | tunnel + access |
| samba | the same share in finder and explorer | lan and tailnet only |
| backrest | restic ui and scheduler, data mounted read-only | proxy only |
| uptime kuma | uptime checks, direct and through the proxy | proxy only |
| beszel | host and container metrics | proxy and lan |
| nginx proxy manager | hostname routing | the hub |
| cloudflared | the outbound tunnel | the only door |

the photo app mounts my archive read-only. it can index every photo i own and cannot delete a single one.

there is also a small graveyard. n8n, open webui and logseq each ran here for a while. their configs are still in the backup bundle, but they did not earn their ram, so they are off. turning things off is part of running things.

## the second brain

the most important thing on this machine is a folder of markdown.

i was tired of learning the same thing twice. the fix was a second brain my agents and i both read and write, built on obsidian and stored on google drive. yes, after a whole section about renting, my thinking lives on google drive. ownership here means plain markdown files i hold a copy of, in a format that will outlive any app. the server mounts the folder with an `rclone` systemd user service, so every machine, human or agent, sees the same files.

```text
obsidian/
  skills/          shared agent instructions and skills
  technicals/      concepts, systems, project notes, practice
  space/           space technology research
  startups/        startup lessons
  meeting-notes/   raw transcripts, used only as source material
  private/         never used in public or work contexts
```

the design rules are small and strict:

- **separate vaults by audience.** a vault is a boundary. private reflections live in a vault agents are told never to use in public or work contexts.
- **navigation is a tree you can walk.** each vault has a `home.md` that points to folder indexes, and each index lists its notes with one line on what each explains. an agent can find anything with `rg` in a few hops.
- **notes are written for a stranger.** every note assumes the reader has no context: first principles, causal order, one concrete example, the misconceptions that were corrected, and the questions still open.
- **search before writing.** update the note that owns an idea instead of creating a near-duplicate.
- **archive, never delete.** superseded thinking moves to an archive. how i used to be wrong is useful data.

the quiet trick is that the agents' instructions live inside the second brain. claude code and codex both read the same instruction file and the same skills, symlinked out of `obsidian/skills/`. i edit one file and both agents change their behaviour on every machine.

one skill turns a technical conversation into a durable note. it does not save a transcript. it reconstructs the learning arc: the first question, the model i started with, where that model broke, and what replaced it. before it writes, it runs three separate checks: the vault root has a home note, the vault really contains notes, and exactly one vault root exists. a path can resolve and still be wrong: an empty mount, an unreadable folder, a vault nested inside another vault. if any check fails, the skill changes nothing and says so. an agent that writes confidently into the wrong place is worse than one that stops.

## working with agents

the server is also where my agents live. a systemd user service starts a tmux session at boot, so sessions survive me closing my laptop. my terminal app shows each tmux window as a tab, and tmux passes the agents' notifications and clipboard straight through to my mac.

two tools grew out of running many agents at once, and both are public:

- [agent-squad](https://github.com/adhikrysh/agent-squad): a read-only terminal dashboard of every claude code and codex session, sorted so the ones waiting on me float to the top.
- [ghostty-agent-workspace](https://github.com/adhikrysh/ghostty-agent-workspace): a one-command terminal layout for working alongside agents.

the philosophy behind how they are instructed is simple. an agent should make me think harder, not think for me. it should show its reasoning, separate what it verified from what it assumed, and never dress a guess up as a fact. it should reach for a command-line tool before an api, an api before an mcp server, and a browser only as a last resort. it should hand cheap, independent work to cheaper models and then check their work, because delegation without verification is just hope with extra steps.

## what an old laptop taught me

- **reduce the attack surface to one door, then guard that door.** no open ports beats a clever firewall.
- **measure the phases before you optimise.** most of my latency was physics, and the table proved it in one command.
- **health beats existence.** a running container is not a working service.
- **backups are a restore plan with a schedule attached.** design for the night you need them, including where the password lives.
- **knowledge compounds only if it is written for a stranger.** the stranger is usually me, six months later.

the configs, scripts and runbooks are in this repository, with secrets removed. the laptop is still on a desk somewhere across the pacific, doing its job.
