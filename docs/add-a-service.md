# runbook: adding a service

every app lives in its own folder with its own compose file and its own docker network. nginx proxy manager is the only container on every network.

1. create `~/<service>/docker-compose.yml`. give the service an external network named `<service>-network`, and publish no host ports.
2. create the network: `docker network create <service>-network`.
3. add `<service>-network` to the `npm` service's `networks:` list in [`compose/npm.yml`](../compose/npm.yml), and declare it `external: true` at the bottom.
4. restart the proxy: `docker compose up -d` in its folder. the tunnel waits for the proxy's healthcheck before reconnecting.
5. start the service: `docker compose up -d` in its folder.
6. in the proxy's admin ui, add a proxy host: domain `<service>.example.com`, scheme `http`, forward host = the container name, forward port = the container's internal port.
7. if the service should be private, add a cloudflare access application for that hostname before sharing the link.
8. add an uptime kuma check that reaches the container directly, and add the kuma container to the new network.
9. if the service keeps state, add it to [`scripts/backup_configs.sh`](../scripts/backup_configs.sh).

no dns change is needed. a wildcard record already sends every subdomain down the tunnel, and the proxy decides where each hostname goes.

## two traps

- **route order.** in the tunnel's public hostnames, specific routes (like ssh) must sit above the wildcard. routes match top to bottom.
- **localhost inside a container.** a tunnel route that says `localhost` means the tunnel container itself. to reach the host, use the docker gateway address of the network the tunnel container is on.
