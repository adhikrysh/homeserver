# latency: measuring before tuning

measured march 2026 from a laptop about 13,600 km of fibre away from the server, against the photo app behind the tunnel. hostnames are replaced with `photos.example.com`.

## the measurement

`curl` can split one request into its phases. run it twice: the first run pays for a cold dns lookup, the second does not.

```bash
# each %{time_*} value is cumulative seconds since the request started
curl -o /dev/null -s -w \
  "dns %{time_namelookup}\nconnect %{time_connect}\ntls %{time_appconnect}\nfirst byte %{time_starttransfer}\ntotal %{time_total}\n" \
  https://photos.example.com
```

| phase | cumulative | this phase alone |
|---|---:|---:|
| tcp connect | 110 ms | ~107 ms of network round trip |
| tls handshake | 146 ms | ~37 ms |
| first byte | 182 ms | ~35 ms, mostly the server and proxy |
| total | 182 ms | |

## what the numbers say

- the server and proxy spend about 30 ms per request. tuning them further would save almost nothing.
- the round trip is the cost. light in fibre travels about 200,000 km/s, so crossing 13,600 km once takes about 68 ms before any equipment adds delay.
- so the job is to spend fewer round trips, not to make each one faster.

## what was applied

| change | where | why it helps on a long link |
|---|---|---|
| bbr congestion control + `fq` | [`config/sysctl/99-network-latency.conf`](../config/sysctl/99-network-latency.conf) | models bandwidth and rtt directly instead of backing off on every lost packet |
| tcp fast open (client and server) | same file | a returning client sends data in its first packet, saving one round trip |
| no slow start after idle | same file | a pause, like switching tabs, does not reset the connection to a crawl |
| shorter keepalives | same file | dead connections are noticed in about a minute instead of two hours |
| http/2 on every proxy host | nginx proxy manager, per host | many requests share one connection instead of queueing |
| gzip level 5 | [`config/nginx/custom-http.conf`](../config/nginx/custom-http.conf) | smaller responses need fewer round trips to deliver |

## what was considered and not done

- **http/3 (quic)** merges the tcp and tls handshakes into one round trip. nginx proxy manager does not serve it.
- **brotli** compresses better than gzip, but the proxy's bundled nginx lacks the module.
- **edge caching of static assets** would serve thumbnails from a nearby cloudflare location in a few milliseconds. it is the largest remaining win for a photo-heavy app.
- **a faster proxy runtime** would save one or two milliseconds per request. not worth a migration.
