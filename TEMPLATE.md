# bind — Per-Repo Spec (AI.md)

## What this image is
A full DNS/web stack on Alpine:
- **named** (BIND 9) — authoritative + recursive DNS on port 53 TCP/UDP
- **tor** — Tor relay/proxy
- **nginx** — web front-end (stats/admin UI)
- **php-fpm** — PHP support for web UI

## Services and init.d scripts
One script per service — **never merge or remove them**:

| Script | Service | Binary | Port |
|--------|---------|--------|------|
| `init.d/01-tor.sh` | Tor relay | `tor` | 9050/9051 |
| `init.d/02-named.sh` | BIND named | `named` | 53 TCP+UDP |
| `init.d/03-nginx.sh` | nginx web | `nginx` | 80/443 |
| `init.d/04-php-fpm.sh` | PHP-FPM | `php-fpm` | 9000 (unix) |

## Migration task (current)
UPDATE each of the 4 init.d scripts to the canonical pattern from
`/.github/example/rootfs/usr/local/etc/docker/init.d/04-example.sh`.

Key fixes needed in each script:
- PID sentinel path: `/run/.start_init_scripts.pid` (dot prefix)
- All required hook functions present
- Correct `EXEC_CMD_BIN`, `SERVICE_USES_PID`, `SERVICE_PORT` values
- Functions file sourced before framework calls

## Config files (rootfs/tmp/etc/)
- `rootfs/tmp/etc/nginx/` — nginx.conf, mime.types
- `rootfs/tmp/etc/php/` — php.ini, php-fpm.conf, php-fpm.d/www.conf
- `rootfs/tmp/etc/tor/` — torrc, torsocks.conf

These are copied into the image at build time by `03-files.sh`.

## Dockerfile
Standard alpine template. `PACK_LIST` includes bind, bind-tools, tor, nginx, php-fpm.
`SERVICE_PORT="53"`, `EXPOSE_PORTS="53/udp"`.

## Special notes
- `SERVICE_USER="named"` for the named service (runs as named user)
- Custom helpers in 02-named.sh: `__rndc_key`, `__dhcp_key` for TSIG key generation
- Tor and nginx run as their own users; PHP-FPM runs as www-data or nginx
