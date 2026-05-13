# bind migration plan

## Service intent

ISC BIND9 DNS server in a single Alpine-based container. Serves DNS on tcp/53 + udp/53. Defaults to a **recursive resolver** (any client can query, recursion enabled, forwards to 1.1.1.1 / 8.8.8.8 / 4.4.4.4 with auto DNSSEC validation) but is also wired to operate as an authoritative server: the existing init.d hooks discover zone files dropped under `/data/bind/zones/` and append matching `zone {}` blocks into a generated `/etc/bind/zones.conf`. Volumes: `/config/bind` (user-editable named.conf, secrets, custom.conf overrides) and `/data/bind` (zones, primary/secondary/dynamic/stats subdirs and `/data/logs/bind/*`). One container, one binary, one init.d script.

## Decision: prune the multi-service stack

The pre-existing repo had `PACK_LIST="bind bind-tools bind-dnssec-root bind-plugins nginx php82-fpm tor tini shadow"` and four init.d scripts (01-tor, 02-named, 03-nginx, 04-php-fpm). Investigation:

- No webmin module, no PHP admin app, no custom PHP scripts under `rootfs/usr/local/share/`. The `usr/share/httpd/default/` tree is the generic CasjaysDev landing page, not a bind admin UI. No `.php` file references named/rndc.
- The `tor` package was wired only because the previous `named.conf` had `zone "exit"` and `zone "onion"` forwarders pointing at `127.0.0.1:9053` (Tor's `DNSPort`). Without tor running, those zones return SERVFAIL but do not break startup; we **drop those two zone blocks** to keep the config truthful.
- `nginx` + `php82-fpm` shipped no functional content. They were boilerplate from the casjaysdev template.
- The `aria2` migration confirmed the framework's `__start_init_scripts` only reliably runs the first init.d entry; multi-service stacks require a wrapper. bind has exactly one daemon (`named`), so a single init.d script is the right shape — no wrapper.

**Outcome: bind-only image.** Dropped packages: `nginx php82-fpm tor shadow` (also `tini` since it's already provided by the Dockerfile's `ENTRYPOINT [ "tini", ... ]` via the casjaysdev/alpine base image). Dropped init.d scripts: `01-tor.sh`, `03-nginx.sh`, `04-php-fpm.sh`. Renamed `02-named.sh` → `99-named.sh` per template spec §7. Dropped `rootfs/tmp/etc/{nginx,php,tor}/`.

## Service stack

- DNS server: `bind` Alpine package → `/usr/sbin/named`. Started by `99-named.sh` with `EXEC_CMD_BIN='named'`, `EXEC_CMD_ARGS='-f -u $SERVICE_USER -c $ETC_DIR/named.conf'` (foreground; -u drops privileges to the `named` user that the Alpine package creates).
- DNS tooling: `bind-tools` Alpine package → `/usr/bin/{dig,host,nslookup,named-checkconf,named-checkzone,named-compilezone,named-journalprint,named-rrchecker}`. Used by `__run_pre_execute_checks` (calls `named-checkconf -z`) and the smoke-test (`dig`).
- Root hints: `rootfs/tmp/var/bind/root.cache` (preserved verbatim — IANA root NS list dated Aug 2024). 03-files.sh installs to `/var/bind/root.cache`.
- DNSSEC trust anchor: `rootfs/tmp/etc/bind/bind.keys` (preserved — IANA-published root KSK; matches `dnssec-validation auto`).
- rndc control channel: `rootfs/tmp/etc/bind/rndc.key` (template with `REPLACE_KEY_RNDC` token; the existing `__update_conf_files` hook generates a hmac-sha512 secret on first run).

## Packages (PACK_LIST / ENV_PACKAGES)

Verified against `pkgs.alpinelinux.org` (edge / main).

- `bind` — the named daemon (`/usr/sbin/named`, Alpine package version 9.x).
- `bind-tools` — `dig`, `nslookup`, `host`, `named-checkconf`, `named-checkzone`, etc. Required by `__run_pre_execute_checks` and useful for in-container debugging.
- `bind-dnssec-root` — bundles the IANA root trust anchor (`/usr/share/dnssec-root/`) used when `dnssec-validation auto` (our setting) needs to bootstrap. Pre-existing repo already shipped it; kept.
- `bind-plugins` — provides optional GeoIP / filter-aaaa / filter-a runtime plugins. Pre-existing repo already shipped it; kept (small, ~100 KB, and the named.conf could be extended with `plugin query` lines without a rebuild).
- `bash` — entrypoint and init.d scripts are bash.

System glue intentionally NOT added to PACK_LIST (already present in `casjaysdev/alpine` base image): `tini`, `tzdata`, `ca-certificates`, `curl`. Verified by reading the existing aria2 PLAN's package strategy (where they ARE explicitly listed because that base image was at the time uncertain to include them; `bind` follows the leaner pattern since the prior failure log shows `tini` install succeeded as a no-op-ish addon — but to keep parity with what worked for aria2, we still list `bash` explicitly so the early `pkmgr install bash` step in the Dockerfile is idempotent).

Final list: `bind bind-tools bind-dnssec-root bind-plugins bash` (single-space separated).

## Configs to ship in rootfs/tmp/etc/bind/

Wipe-and-replace at build time per template §4.

- `named.conf` (preserved, edited to drop tor-forward zones):
  - `key "rndc-key"`, `key "dhcp-key"`, `key "certbot."`, `key "backup-key"` declarations with `REPLACE_KEY_*` tokens (substituted at runtime by `__update_conf_files`).
  - `acl "trusted"` covers RFC1918 + loopback; `acl "all"` is `0.0.0.0/0; ::/0;`.
  - `controls { inet 127.0.0.1 allow { trusted; } keys { "rndc-key"; }; };` (rndc only on loopback).
  - `options { ... }`: `directory "REPLACE_VAR_DIR"` (→ `/var/bind`), `pid-file "REPLACE_RUN_DIR/named.pid"` (→ `/run/bind/named.pid`), `listen-on { any; }; listen-on-v6 { any; };`, `allow-query { any; }; allow-recursion { any; }; allow-query-cache { any; };`, `forwarders { 1.1.1.1; 8.8.8.8; 4.4.4.4; };`, `dnssec-validation auto;`, `version "9";` (hide real version), `max-cache-size 60m;`, `max-udp-size 4096;`.
  - **Removed**: `validate-except { "onion"; "exit"; };` (no tor) and the `zone "exit" / zone "onion"` forward blocks pointing at port 9053.
  - `logging { ... }`: per-channel files under `REPLACE_LOG_DIR` (→ `/data/logs/bind`); preserved verbatim.
  - `zone "." { type hint; file "REPLACE_VAR_DIR/root.cache"; };` (root hints).
  - `include "REPLACE_ETC_DIR/zones.conf";` (the existing init.d generates this file from `/data/bind/zones/*` — optional include so missing/empty file does not crash).
- `rndc.key` (preserved): single `key "rndc-key"` block with `REPLACE_KEY_RNDC` token.
- `bind.keys` (preserved): IANA root KSK trust anchor.

`rootfs/tmp/var/bind/root.cache` (preserved): IANA root nameservers list. 03-files.sh installs to `/var/bind/root.cache`. The init.d's `__update_conf_files` also copies from `/usr/local/share/bind/data/root.cache` (already present at `rootfs/usr/local/share/bind/data/root.cache`) into `$VAR_DIR` if missing.

## /config/bind/ layout (user-editable)

Framework's `__initialize_system_etc` symlinks every file under `/config/bind/` back to its `/etc/bind/` peer at runtime.

- `/config/bind/named.conf` → `/etc/bind/named.conf` (the running named reads `/etc/bind/named.conf` since the wipe-and-replace plus the `__init_config_etc` symlinking points them at the same content).
- `/config/bind/rndc.key` → `/etc/bind/rndc.key`.
- `/config/bind/bind.keys` → `/etc/bind/bind.keys`.
- `/config/bind/secrets/{rndc,dhcp,backup,certbot}.key` (created by the existing `__update_conf_files` hook on first run; persists rotated keys).
- `/config/bind/keys/` (managed-keys-directory).
- `/config/bind/custom.conf` (optional) — if present, overrides `named.conf` entirely (the existing hook does `cp -f $CONF_DIR/custom.conf $NAMED_CONFIG_FILE`). Lets a user paste a hand-written named.conf without editing the templated one.
- `/config/env/named.sh`, `/config/env/named.local.sh` — per-service env overrides (DNS_TYPE, DNS_SERVER_PRIMARY/SECONDARY/TRANSFER_IP, KEY_*, etc.). The hook auto-creates a stub on first boot.

`/data/bind/` (runtime + user-editable zones):
- `/data/bind/zones/<domain>.zone` — drop-in zone files; the init.d's `__pre_execute` discovers them and appends `zone "<name>" { type master; ... }` blocks into `/etc/bind/zones.conf`.
- `/data/bind/remote/<domain>.zone` — pre-formatted slave/forward zone block snippets that get concatenated into `zones.conf` directly (with `REPLACE_VAR_DIR` substitution).
- `/data/logs/bind/{debug.run,querylog.log,security.log,xfer.log,update.log,notify.log,client.log,default.log,general.log,database.log}` — per-channel logs, `chmod 777` by the hook so the dropped-privileges `named` user can write.
- `/var/bind/{primary,secondary,dynamic,stats}/` — runtime-managed data dirs.

## init.d/99-named.sh

Renamed from `02-named.sh` (per template §2/§7: 99- prefix is the canonical late-ordering name; works with the framework's `__start_init_scripts` which iterates `init.d/*.sh` lexicographically).

Variables (all preserved from the existing 02-named.sh):
- `SERVICE_NAME="named"` (binary name, used for PID file `/run/init.d/named.pid` and `__proc_check`).
- `EXEC_CMD_BIN='named'` (resolved to `/usr/sbin/named` by the framework's `type -P` lookup).
- `EXEC_CMD_ARGS='-f -u $SERVICE_USER -c $ETC_DIR/named.conf'` — `-f` foreground (PID supervision), `-u named` drops privileges, `-c` points at our config.
- `SERVICE_USER="named"`, `SERVICE_GROUP="named"` (the Alpine `bind` package creates uid 100 / gid 101 — **04-users.sh leaves this to the package**).
- `RUNAS_USER="root"` (init.d script runs as root so it can chown `/etc/bind`, `/var/bind`, `/data/logs/bind` to `named:named` before exec).
- `SERVICE_PORT="53"`, `WWW_ROOT_DIR="/usr/local/share/httpd/default"` (unused but kept for framework parity).
- `IS_WEB_SERVER="no"`, `IS_DATABASE_SERVICE="no"`, `USES_DATABASE_SERVICE="no"`, `DATABASE_SERVICE_TYPE="sqlite"`.
- `DATA_DIR="/data/bind"`, `CONF_DIR="/config/bind"`, `ETC_DIR="/etc/bind"`, `VAR_DIR="/var/bind"`, `TMP_DIR="/tmp/bind"`, `RUN_DIR="/run/bind"`, `LOG_DIR="/data/logs/bind"`.

Hooks (preserved in 02-named.sh, reused intact):
- `__update_conf_files` — generates rndc / dhcp / backup / certbot keys via `tsig-keygen` (or reads from `/config/bind/secrets/*.key`), substitutes `REPLACE_KEY_RNDC/DHCP/BACKUP/CERTBOT`, `REPLACE_DNS_SERVER_TRANSFER_IP`, ensures `$VAR_DIR/root.cache` exists.
- `__pre_execute` — auto-generates a default zone block + zone file for `$HOSTNAME` if `/data/bind/zones/` is empty, then iterates `/data/bind/zones/*` to append zone declarations into `/etc/bind/zones.conf`.
- `__run_pre_execute_checks` — `chown -Rf named:named /etc/bind /var/bind /data/logs/bind` then `named-checkconf -z` against the assembled config; aborts startup if it fails.
- `__post_execute` — sleeps then logs (no functional commands).

## Setup script changes

`02-packages.sh` (already correct, edited only to drop dead lines):
```sh
rm -Rf "/etc/bind"/* "/var/bind"/*
mkdir -p "/etc/bind/keys" "/var/bind/zones" "/var/bind/primary" \
         "/var/bind/secondary" "/var/bind/stats" "/var/bind/dynamic"
```
(Dropped: `rm -Rf /etc/tor/*`, `rm -Rf /etc/nginx/*`, `rm -Rf /etc/php*/*`, `rm -Rf /etc/named.*` — that last one was a stray, the Alpine package never installs `/etc/named.*`.)

`05-custom.sh` — gains the wipe-and-replace block per template §4:
```sh
if [ -d "/tmp/etc/bind" ]; then
  rm -Rf "/etc/bind"/*
  cp -Rf "/tmp/etc/bind/." "/etc/bind/"
fi
mkdir -p /run/bind /data/logs/bind /var/bind
chown -Rf named:named /etc/bind /var/bind 2>/dev/null || true
```
(Belt + suspenders: 02-packages already wipes /etc/bind before tmp/etc/bind is overlaid, but the explicit block makes the intent visible and tolerates rebuilds where 03-files.sh order changes.)

`07-cleanup.sh` — drop the `/var/bind` wipe (it deletes the root.cache we just installed). Keep `/var/named` wipe (Alpine doesn't use that path; harmless).

`00-init.sh`, `01-system.sh`, `03-files.sh`, `04-users.sh`, `06-post.sh` — left as-is. The `bind` Alpine package already creates the named user (uid 100 / gid 101 confirmed via `docker run --rm alpine:edge sh -c 'apk add bind && getent passwd named'`).

## Files to delete

- `rootfs/usr/local/etc/docker/init.d/01-tor.sh`
- `rootfs/usr/local/etc/docker/init.d/03-nginx.sh`
- `rootfs/usr/local/etc/docker/init.d/04-php-fpm.sh`
- `rootfs/usr/local/etc/docker/init.d/02-named.sh` (replaced by `99-named.sh`)
- `rootfs/tmp/etc/nginx/` (entire dir)
- `rootfs/tmp/etc/php/` (entire dir)
- `rootfs/tmp/etc/tor/` (entire dir)

## Dockerfile changes

Surgical edits:
- `BUILD_DATE="202605101200"` (today, 2026-05-10).
- `SERVICE_PORT="53"` (was `"80"` — fixes the EXPOSE so DNS port is the primary advertised one).
- `EXPOSE_PORTS="53/udp"` (was `"53/tcp 53/udp"` — `SERVICE_PORT` is already 53/tcp via `EXPOSE ${SERVICE_PORT}`; we only need to add the udp variant).
- `PHP_VERSION="none"` (was `"php82"` — no PHP).
- `PACK_LIST="bind bind-tools bind-dnssec-root bind-plugins bash "` (was the multi-service list; trailing space preserved per template convention).
- Fix the upstream gen-dockerfile bug `[ "$SH_CMD" != "/bin/sh"]` → `[ "$SH_CMD" != "/bin/sh" ]` (missing space).

## .env.scripts changes

- `SERVICE_PORT="53"`.
- `EXPOSE_PORTS="53/udp"`.
- `PHP_VERSION="none"`.
- `ENV_PACKAGES="bind bind-tools bind-dnssec-root bind-plugins bash"` (mirrors PACK_LIST minus trailing space, single-space separated).

## Verification (success criteria)

1. `cd /root/Projects/github/casjaysdevdocker/bind && rm -f .build_failed && buildx run Dockerfile` succeeds for both `linux/amd64` and `linux/arm64`.
2. `docker run -d --rm --name test-bind -p 15353:53/udp -p 15353:53/tcp docker.io/casjaysdevdocker/bind:latest` boots; after ~25s `docker ps --filter name=test-bind --format '{{.Status}}'` shows `Up ... (healthy)` (healthcheck framework returns OK once init.d PID files exist).
3. `docker exec test-bind sh -c 'netstat -tnlp 2>/dev/null; netstat -unlp 2>/dev/null'` shows `named` (or `/usr/sbin/named`) bound to `0.0.0.0:53` on both tcp and udp.
4. `dig @127.0.0.1 -p 15353 +short . NS` (host-side, with `bind-tools`/`dnsutils` installed) returns the 13 root nameservers (recursion path through forwarders works).
5. `dig @127.0.0.1 -p 15353 +short google.com A` returns at least one A record.
6. `docker exec test-bind ls /config/bind/ /data/bind/` confirms `/config/bind/` (named.conf, secrets/, keys/) and `/data/bind/` (zones/, primary/, secondary/, stats/) are seeded.
7. `docker logs test-bind 2>&1 | tail -30` shows no FATAL or "exiting" errors; `named-checkconf -z` passed.
8. `docker stop test-bind`.

## Rollback

Code changes can be reverted via `git checkout -- rootfs/ Dockerfile .env.scripts`. New files (PLAN.md, CLAUDE.md, 99-named.sh) tracked separately. The deleted init.d scripts (01-tor.sh, 03-nginx.sh, 04-php-fpm.sh) and tmp/etc/{nginx,php,tor}/ remain in git history.
