# casjaysdevdocker repo template spec

This file is the **canonical spec** for what a properly-set-up `casjaysdevdocker/<repo>` container repo looks like. It is the source of truth for migrations, audits, and new repos.

- Untracked: this file lives at the repos root, not in any individual repo's git tree.
- Per-repo: each repo gets `<repo>/CLAUDE.md` (a copy of this file) and `<repo>/PLAN.md` (the concrete plan for that specific service stack), both committed to the repo.
- Authority: `~/.claude/CLAUDE.md` (52 numbered global rules) is the base. This file extends it for the docker-image work. Existing repo files are *input*, never authoritative — the repos are mostly unfinished.

---

## 1. What a repo is

Each repo builds **one self-contained Docker image** for the service named after the repo. The image:

- Targets `linux/amd64` and `linux/arm64` via `buildx`.
- Boots via `tini` → `entrypoint.sh` → init.d service scripts → long-running service.
- Stores user-modifiable config under `/config/<svc>` (volume).
- Stores runtime data, logs, DB files under `/data` (volume).
- Ships a single, **highly-optimized** config in `rootfs/tmp/etc/<svc>/` that replaces the distro defaults at build time.
- Provides sane defaults: first-run with no env vars works for the common case.

App-style repos (ampache, wordpress, navidrome, …) ship the **whole stack** the app needs: the app itself at `/usr/local/share/<app>`, a webserver (apache or nginx) to serve it, php-fpm if PHP-based, and a database (mariadb/postgres) if the app needs one. DB-server repos (mariadb, postgres, mongodb, …) ship the DB **plus** apache + php-fpm + the canonical web admin UI (phpmyadmin for mariadb/mysql; pgAdmin/phpPgAdmin for postgres; mongo-express for mongodb; etc.).

Inferred intent from repo name examples:

| Repo            | What it is                                                                                                              |
|-----------------|-------------------------------------------------------------------------------------------------------------------------|
| `nginx`         | nginx webserver; PHP-FPM upstream on `:9000`; CGI/Lua/etc via `nginx-mod-*` packages                                    |
| `apache`/`httpd`| apache2 webserver + php-fpm; mod_rewrite/proxy/ssl/etc                                                                  |
| `cherokee`      | cherokee webserver with **CGI handlers for Ruby, Perl, Python** + **full PHP support**                                  |
| `lighttpd`      | lighttpd webserver + php-fpm/cgi                                                                                        |
| `caddy`         | Caddy webserver (reverse-proxy/auto-TLS)                                                                                |
| `traefik`       | Traefik edge router                                                                                                     |
| `mariadb`       | mariadb-server + apache + php-fpm + **phpmyadmin** at `/usr/local/share/phpmyadmin`                                     |
| `mysql`         | mysql + apache + php-fpm + phpmyadmin                                                                                   |
| `postgres`      | postgresql + apache + php-fpm + **phpPgAdmin/pgAdmin** at `/usr/local/share/phppgadmin`                                 |
| `mongodb`       | mongodb + apache + php-fpm + mongo-express or comparable web UI                                                         |
| `couchdb`       | couchdb (built-in Fauxton UI)                                                                                            |
| `redis`/`valkey`| key-value store; CLI tools                                                                                              |
| `ampache`       | apache + php-fpm + mariadb + ampache app at `/usr/local/share/ampache`; serves the music UI on `:80`                    |
| `wordpress`     | apache + php-fpm + mariadb + wordpress at `/usr/local/share/wordpress`                                                  |
| `nextcloud`     | apache + php-fpm + mariadb + nextcloud at `/usr/local/share/nextcloud`                                                  |
| `gitea`/`forgejo`| the binary, sqlite by default                                                                                          |
| `bind`          | bind9 DNS server                                                                                                        |
| `tor`           | tor daemon                                                                                                              |
| `ssl-ca`        | a self-signed CA + `openssl`/`certbot` tooling                                                                          |

**Always cross-check intent and packages against:**
- **Distro docs for file paths**: Alpine docs for `/etc/<svc>` layout (and `pkgs.alpinelinux.org` for available package names); Alma/Rocky docs for `/etc/httpd` (rhel-family path).
- **Project docs for config content**: `nginx.org` for `nginx.conf` directives, `httpd.apache.org` for `httpd.conf`, `mariadb.com` for `my.cnf`, etc.
- **Upstream Docker images**: when available, `docker pull <upstream>/<image>:latest` and inspect (`docker history`, `docker run --rm -it ... sh`) to confirm canonical install paths and config locations. **Always `docker rmi` to clean up after.**

Never invent a package name or a config option. `WebFetch`/`WebSearch`/`docker pull` to verify.

---

## 2. File inventory (every repo)

```
<repo>/
├── CLAUDE.md                          # copy of TEMPLATE.md, committed; agent reads this when working in this repo
├── PLAN.md                            # this repo's concrete plan: packages, configs, init.d behavior, success criteria
├── README.md                          # user-facing install/run docs
├── LICENSE.md                         # MIT (per global rule 32) or per-repo as appropriate
├── Dockerfile                         # multi-stage, alpine-based by default (rhel for systemd-only repos)
├── .env.scripts                       # buildx wrapper config (registry, push, pull, packages list)
├── .dockerignore
├── .gitattributes
├── .gitignore
├── .gitea/workflows/docker.yaml       # gitea CI workflow
├── Jenkinsfile                        # optional, if the repo had one
└── rootfs/                            # everything under here is COPYed to / in the build
    ├── usr/local/bin/
    │   ├── entrypoint.sh              # SHARED template, only the description + CONTAINER_NAME line are repo-specific
    │   └── pkmgr                      # SHARED template (apt/dnf/apk auto-detect wrapper)
    ├── usr/local/etc/docker/
    │   ├── functions/entrypoint.sh    # framework functions sourced by entrypoint.sh and 99-<svc>.sh
    │   └── init.d/
    │       └── 99-<svc>.sh            # PER-REPO; defines SERVICE_NAME, ETC_DIR, CONF_DIR, EXEC_CMD_BIN/ARGS, hooks
    ├── usr/local/share/
    │   ├── <app>/                     # for app-style repos: the actual app code (e.g., ampache, wordpress)
    │   ├── phpmyadmin/                # for mariadb/mysql repos
    │   ├── phppgadmin/                # for postgres repos
    │   ├── httpd/default/             # default webroot (used when no app)
    │   └── template-files/
    │       ├── config/                # templates copied to /config/<svc>/ on first run by __initialize_config_dir
    │       ├── data/                  # templates copied to /data/<svc>/ on first run
    │       └── defaults/              # default fallbacks
    ├── tmp/etc/<svc>/                 # PER-REPO optimized configs; copied to /etc/<svc>/ at build time (see §4)
    ├── tmp/bin/                       # optional; auto-installed to /usr/local/bin/ at build time
    ├── tmp/var/                       # optional; auto-installed to /var/ at build time
    └── root/docker/setup/             # PER-REPO build-time scripts (see §3)
        ├── 00-init.sh
        ├── 01-system.sh
        ├── 02-packages.sh
        ├── 03-files.sh
        ├── 04-users.sh
        ├── 05-custom.sh               # ← service-specific config wipe-and-replace lives here
        ├── 06-post.sh
        └── 07-cleanup.sh
```

**SHARED vs PER-REPO** (load-bearing distinction — getting this wrong breaks repos):

- **SHARED** (safe to overwrite from the upstream template): `rootfs/usr/local/bin/entrypoint.sh` (only the description + `CONTAINER_NAME="<svc>"` change per repo), `rootfs/usr/local/bin/pkmgr`, `rootfs/usr/local/etc/docker/functions/entrypoint.sh`.
- **PER-REPO** (never overwrite from a template — read first; preserve service-specific logic): every script under `rootfs/root/docker/setup/`, `rootfs/usr/local/etc/docker/init.d/*`, everything under `rootfs/tmp/`, everything under `rootfs/usr/local/share/<app>/`.

---

## 3. Build-time setup script flow

`Dockerfile` runs `00-init.sh` → … → `07-cleanup.sh` interleaved with package install. Order and contract:

| Script           | When it runs                                  | What it does                                                                                       |
|------------------|-----------------------------------------------|----------------------------------------------------------------------------------------------------|
| `00-init.sh`     | Right after `mkdir`s before anything else      | Sanity setup; usually empty                                                                        |
| `01-system.sh`   | After apk repos are configured                 | System-level tweaks (extra repos, timezone, non-package OS config)                                 |
| `02-packages.sh` | After `pkmgr install $PACK_LIST`               | Per-service post-install tweaks (e.g., compile a module, install a pip/npm package, fetch the app) |
| `03-files.sh`    | After packages are installed                   | **Auto-installs `rootfs/tmp/{bin,var,etc,data}/*`** into `/usr/local/bin/`, `/var/`, `/etc/`, and the `template-files/` staging dirs. Most repos use the canonical version verbatim. |
| `04-users.sh`    | After files are placed                         | Create system users/groups the service needs (e.g., `nginx`, `mysql`, `apache`)                    |
| `05-custom.sh`   | After users                                    | **Service-specific config wipe-and-replace** (see §4). Also: clone wwwroot templates, fetch app source, etc. |
| `06-post.sh`     | After custom                                   | Late tweaks (permissions, symlinks)                                                                |
| `07-cleanup.sh`  | Last                                           | Per-service cache cleanup beyond the Dockerfile's generic cleanup                                  |

The Dockerfile's own RUN steps already do generic cleanup (`pkmgr clean`, `rm -Rf /usr/share/doc/*`, etc.); the per-script `07-cleanup.sh` only handles service-specific files.

---

## 4. The wipe-and-replace config flow

The most important pattern in this template. Goal: the running container's `/etc/<svc>/` contains **only** our optimized config, never distro defaults.

**Build time:**
1. Service package install (e.g., `apk add nginx`) creates distro defaults under `/etc/<svc>/` (e.g., `/etc/nginx/{nginx.conf, conf.d/, modules-enabled/, http.d/, mime.types, …}`).
2. `03-files.sh` copies `rootfs/tmp/etc/<svc>/*` → `/etc/<svc>/*` (overlay only) **and** stages a copy at `/usr/local/share/template-files/config/<svc>/` for runtime seeding.
3. `05-custom.sh` performs the **wipe-and-replace** (the canonical idiom):
   ```sh
   if [ -d "/tmp/etc/<svc>" ]; then
     # preserve distro-shipped files we need (e.g., mime.types when not in tmp/etc/)
     # then wipe defaults
     rm -Rf "/etc/<svc>"/*
     cp -Rf "/tmp/etc/<svc>/." "/etc/<svc>/"
   fi
   ```
   For services that auto-discover sub-confs, our `<svc>.conf` ends with an **optional** include like `include /config/<svc>/vhosts.d/*.conf;` (nginx) or `IncludeOptional /config/<svc>/conf.d/*.conf` (apache) so an empty include dir doesn't crash startup.

**Runtime (entrypoint + 99-<svc>.sh):**
1. `entrypoint.sh` calls `__initialize_default_templates` / `__initialize_config_dir` / `__initialize_data_dir` which copy `template-files/{defaults,config,data}/<svc>/*` → `/config/<svc>/` and `/data/<svc>/` **only when those target dirs are not already initialized** (via `/config/.docker_has_run` and `/data/.docker_has_run` markers).
2. `99-<svc>.sh` calls `__initialize_system_etc "$CONF_DIR"` which symlinks/copies the user-editable `/config/<svc>/<file>` → the service's expected runtime path (`/etc/<svc>/<file>` for system services; `/usr/local/share/<app>/config/<file>` for app-stack repos).
3. `99-<svc>.sh` also ensures runtime dirs exist: `vhosts.d/`, `conf.d/`, `ssl/`, `secure/auth/`, log dirs under `/data/logs/<svc>/`.
4. Service starts pointing at `/etc/<svc>/<svc>.conf` (or equivalent), which transitively reads from `/config/<svc>/`.

Net effect: end users edit files under `/config/<svc>/` (volume); the service picks them up; rebuilds and restarts don't trample user changes.

**Anti-patterns:**
- Letting distro defaults survive into the running image (didn't wipe `/etc/<svc>/*`).
- Hardcoding paths in our config that point inside `/etc/<svc>/` instead of `/config/<svc>/` for things users should customize.
- Copying `template-files/config/<svc>/*` into `/config/<svc>/` unconditionally on every container start (clobbers user edits) — always gate with the init markers.
- Using a non-optional `include` for `vhosts.d/` (kills the service when the dir is empty on first run).

---

## 5. Dockerfile structure

Multi-stage. Build stage installs packages and runs setup scripts; final stage is `FROM scratch` and `COPY --from=build /. /` for a minimal final image. Exception: containers needing systemd as PID 1 (e.g., blueonyx) are single-stage with `CMD ["/sbin/init"]`.

Required ARGs in the **header** (preserve per-repo values during migration):

```dockerfile
ARG IMAGE_NAME="<repo>"
ARG PHP_SERVER="<repo>"           # often same as IMAGE_NAME
ARG BUILD_DATE="<YYYYMMDDHHMM>"   # auto-bumped by gen-dockerfile / CI
ARG LANGUAGE="en_US.UTF-8"
ARG TIMEZONE="America/New_York"
ARG WWW_ROOT_DIR="/usr/local/share/httpd/default"
ARG DEFAULT_FILE_DIR="/usr/local/share/template-files"
ARG DEFAULT_DATA_DIR="/usr/local/share/template-files/data"
ARG DEFAULT_CONF_DIR="/usr/local/share/template-files/config"
ARG DEFAULT_TEMPLATE_DIR="/usr/local/share/template-files/defaults"
ARG PATH="/usr/local/etc/docker/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
ARG USER="root"
ARG SHELL_OPTS="set -e -o pipefail"
ARG SERVICE_PORT="<primary port for healthcheck/EXPOSE>"
ARG EXPOSE_PORTS="<additional space-separated ports>"
ARG PHP_VERSION="<php82|php83|php84|system|none>"
ARG NODE_VERSION="system"
ARG NODE_MANAGER="system"
ARG IMAGE_REPO="<org>/<repo>"
ARG IMAGE_VERSION="latest"
ARG CONTAINER_VERSION=""           # "USE_DATE" if buildx should auto-add a date tag
ARG PULL_URL="casjaysdev/alpine"   # or "alpine", "almalinux/10-init", etc.
ARG DISTRO_VERSION="${IMAGE_VERSION}"
ARG BUILD_VERSION="${BUILD_DATE}"
```

`PACK_LIST` lives in the build stage and is the **single most repo-specific value** — it must be complete and accurate for the service stack:

```dockerfile
ARG PACK_LIST="<all packages this stack needs, space-separated, trailing space>"
```

Build-stage RUN order (alpine):

1. `COPY ./rootfs/. /`  (early, so setup scripts and `/tmp/etc/` are available before package install)
2. `RUN pkmgr update; pkmgr install bash`
3. `RUN` install bash + symlink `/bin/sh` → `bash` (Alpine ships busybox sh)
4. `ENV SHELL="/bin/bash"; SHELL [ "/bin/bash", "-c" ]`
5. `COPY --from=gosu /usr/local/bin/gosu /usr/local/bin/gosu`
6. `RUN` initialize: `mkdir -p` template dirs + `00-init.sh`
7. `RUN` system: rewrite `/etc/apk/repositories` for the right distro version; `apk update && apk upgrade` + `01-system.sh`
8. `RUN` pre-package commands (usually empty)
9. `RUN` install packages from `${PACK_LIST}` via `pkmgr install`
10. `RUN` `02-packages.sh`
11. `COPY ./Dockerfile /root/docker/Dockerfile` (so the image carries its own build recipe)
12. `RUN` updating system files: timezone, nsswitch, php symlinks, .bashrc, `03-files.sh`
13. `RUN` Custom Settings (usually empty placeholder)
14. `RUN` users + `04-users.sh`
15. `RUN` user init (placeholder)
16. `RUN` OS Settings (placeholder)
17. `RUN` Custom Applications (placeholder)
18. `RUN` `05-custom.sh`
19. `RUN` final commands + `06-post.sh`
20. `RUN` cleanup (generic) + `07-cleanup.sh`
21. `RUN echo "Init done"`

Final stage (`FROM scratch`):

- ARGs re-declared (scratch needs them); ENVs set; standard LABEL block (URLs, vendor, revision = `${GIT_COMMIT}`); `COPY --from=build /. /`; `VOLUME [ "/config","/data" ]`; `EXPOSE ${SERVICE_PORT} ${ENV_PORTS}`; `STOPSIGNAL SIGRTMIN+3`; `ENTRYPOINT [ "tini", "-p", "SIGTERM", "--", "/usr/local/bin/entrypoint.sh" ]`; `HEALTHCHECK ... CMD [ "/usr/local/bin/entrypoint.sh", "healthcheck" ]`.

Distro variants:
- **alpine** (default for ~all repos)
- **rhel/almalinux** (for repos that need RHEL packages or systemd) — generated via `gen-dockerfile --dir <tmp> rhel`. Almost all are still single-stage with `CMD ["/sbin/init"]`.

Generic Dockerfile bug fixes to apply when migrating any repo (these are upstream gen-dockerfile bugs):
- Missing space before `]`: `[ "$SH_CMD" != "/bin/sh"]` → `[ "$SH_CMD" != "/bin/sh" ]`
- Blank line inside the "Creating and editing system files" RUN block (after `$SHELL_OPTS; \`) — remove the blank line; line continuation is broken otherwise.
- Unindented `echo ""` in the "Custom Settings" and "Custom Applications" RUN blocks — re-indent to `  echo ""`.

---

## 6. .env.scripts fields

The buildx wrapper (`/usr/local/bin/buildx`) reads `.env.scripts`. Required fields (current names — older field names are deprecated):

```sh
ENV_DOCKERFILE="Dockerfile"
ENV_REGISTRY_REPO="<repo>"                        # was ENV_IMAGE_NAME
ENV_USE_TEMPLATE="alpine"                          # or "almalinux", "debian", "ubuntu"
ENV_REGISTRY_ORG="<casjaysdevdocker | casjaysdev>" # was ENV_ORG_NAME; must match the org in ENV_REGISTRY_PUSH
ENV_VENDOR="CasjaysDev"
ENV_AUTHOR="CasjaysDev"
ENV_MAINTAINER="CasjaysDev <docker-admin@casjaysdev.pro>"
ENV_GIT_REPO_URL="https://github.com/<org>/<repo>"
ENV_REGISTRY_URL="https://docker.io"               # full URL, not bare "docker.io"
ENV_REGISTRY_PUSH="<org>/<repo>"                   # was ENV_IMAGE_PUSH
ENV_IMAGE_TAG="latest"
ENV_ADD_TAGS=""                                     # "USE_DATE" to auto-add YYMM tag
ENV_ADD_IMAGE_PUSH=""
ENV_PULL_URL="<base image>"                        # e.g. "casjaysdev/alpine", "alpine", "almalinux/10-init"
ENV_DISTRO_TAG="${IMAGE_VERSION}"
ENV_PLATFORMS="linux/amd64,linux/arm64"            # only emit when overriding the default both-archs
SERVICE_PORT="<primary>"
EXPOSE_PORTS="<extra ports space-separated>"
LANG_VERSION=""
PHP_VERSION="<system|php82|php83|php84|none>"
NODE_VERSION="system"
NODE_MANAGER="system"
WWW_ROOT_DIR="/usr/local/share/httpd/default"
DEFAULT_FILE_DIR="/usr/local/share/template-files"
DEFAULT_DATA_DIR="/usr/local/share/template-files/data"
DEFAULT_CONF_DIR="/usr/local/share/template-files/config"
DEFAULT_TEMPLATE_DIR="/usr/local/share/template-files/defaults"
ENV_PACKAGES="<single-space-separated package list — must mirror PACK_LIST in Dockerfile>"
```

`ENV_PACKAGES` and Dockerfile `PACK_LIST` must stay in sync. Single-space separation, no double spaces.

---

## 7. init.d/99-<svc>.sh contract

Each repo's primary init.d script (named `99-<svc>.sh` for late ordering, or `09-<svc>.sh`/etc. when ordering matters relative to other init.d entries — e.g., php-fpm starts before nginx) defines repo-specific state and calls framework functions defined in `rootfs/usr/local/etc/docker/functions/entrypoint.sh`. Required variable assignments at the top (use the nginx 99-nginx.sh as the reference structure):

```sh
SERVICE_NAME="<svc>"
DATA_DIR="/data/<svc>"
CONF_DIR="/config/<svc>"
ETC_DIR="/etc/<svc>"           # or /usr/local/share/<app>/config for app-stack repos
TMP_DIR="/tmp/<svc>"
RUN_DIR="/run/<svc>"
LOG_DIR="/data/logs/<svc>"
SERVICE_PORT="<primary>"
SERVICE_USER="<svc>"            # the daemon's run-as user
SERVICE_GROUP="<svc>"
EXEC_CMD_BIN='<binary>'         # e.g., 'nginx', 'mysqld', 'httpd'
EXEC_CMD_ARGS='<args>'          # e.g., '-c $ETC_DIR/nginx.conf'
IS_WEB_SERVER="yes|no"
IS_DATABASE_SERVICE="yes|no"
USES_DATABASE_SERVICE="yes|no"
DATABASE_SERVICE_TYPE="<sqlite|redis|postgres|mariadb|mysql|couchdb|mongodb|supabase|custom>"
ADDITIONAL_CONFIG_DIRS=""       # extra /config subdirs to seed/symlink
APPLICATION_FILES="..."
APPLICATION_DIRS="$ETC_DIR $CONF_DIR $LOG_DIR $TMP_DIR $RUN_DIR $VAR_DIR"
```

Repo-customizable hooks (override the `_local` variants — the framework calls them at the right time):

- `__run_precopy_local` — before any /config copy
- `__execute_prerun_local` — pre-execution setup
- `__run_pre_execute_checks_local` — final preflight checks
- `__update_conf_files_local` — token replacement in `/etc/<svc>/*` (use `__replace`/`__find_replace`)
- `__pre_execute_local` — last-mile actions
- `__post_execute_local` — actions in background after service start
- `__pre_message_local` — pre-launch banner
- `__update_ssl_conf_local` — repo-specific SSL handling

---

## 8. Per-repo CLAUDE.md and PLAN.md

When working on a repo, the agent should:

1. `cd <repo>`
2. Read `CLAUDE.md` (this file's content, copied) for the spec.
3. Read `PLAN.md` for repo-specific decisions.
4. Read every existing file in the repo before editing it (rule 8).
5. When uncertain about a package/path/option, `WebFetch` the relevant docs (distro for paths, project for content). Never invent.

`PLAN.md` template (commit this in each repo):

```markdown
# <repo> migration plan

## Service intent
<one paragraph: what this image provides, who runs it, primary user-facing port>

## Service stack
- <component 1>: <package(s)>; canonical config at <path>
- <component 2>: ...

## Packages (PACK_LIST / ENV_PACKAGES)
<list, sourced from pkgs.alpinelinux.org, with one-line justification each>

## Configs to ship in rootfs/tmp/etc/
- /etc/<svc>/<file>: <source: which project's docs>; <key tunings applied>
- ...

## /config/<svc>/ layout (user-editable)
- <file> -> symlinked to <runtime path>
- vhosts.d/ -> include /config/<svc>/vhosts.d/*.conf (optional)

## init.d/99-<svc>.sh
- SERVICE_NAME, EXEC_CMD_BIN, EXEC_CMD_ARGS
- IS_WEB_SERVER / IS_DATABASE_SERVICE / USES_DATABASE_SERVICE
- Repo-specific hooks needed: __update_conf_files_local (replace XYZ), ...

## 05-custom.sh additions
- Wipe /etc/<svc>/* and copy from /tmp/etc/<svc>/.
- Fetch <app source> if not present
- Other service-specific install steps

## Verification (success criteria)
- buildx run Dockerfile succeeds for linux/amd64 + linux/arm64
- docker run -d -p <port>:<port> ... starts cleanly; logs show no errors
- curl -fsS http://localhost:<port>/<healthpath> returns the expected response
- /config/<svc>/ is seeded on first run; editing a file there changes service behavior on restart
- (DB repos) connecting with the right CLI client succeeds
- (optional) compared against upstream image (`docker pull <upstream>:latest && docker history <upstream>:latest`); upstream image deleted (`docker rmi`) after verification
```

---

## 9. Migration workflow per repo

1. Create `<repo>/CLAUDE.md` = copy of this `TEMPLATE.md`.
2. Read existing files; assemble the PLAN.md.
3. **Read each file before changing it** (no batch templating). Apply only the changes that PLAN.md identifies.
4. `cd <repo> && rm -f .build_failed && buildx run Dockerfile` — fix any build error before moving on.
5. Smoke-test: `docker run --rm -d --name test-<svc> -p <port>:<port> <org>/<repo>:latest`; wait for healthcheck; `curl` the health/main endpoint; `docker exec` and inspect `/config/<svc>/`; stop and remove.
6. Commit `CLAUDE.md` and `PLAN.md` to the repo (do NOT commit code changes unless the user has asked — global rule about commits applies).
7. Move to next repo with **no carry-over**: spawn a fresh subagent; do not load prior repo's context.

---

## 10. Anti-patterns (never do)

- Overwriting `rootfs/root/docker/setup/*.sh` from a generic template — these are per-repo.
- Overwriting `rootfs/usr/local/etc/docker/init.d/*.sh` from a template — per-repo.
- Overwriting `rootfs/tmp/etc/<svc>/*` — per-repo.
- Overwriting `rootfs/usr/local/share/<app>/*` — per-repo (the actual application code).
- Inventing package names, config keys, or service paths — verify with distro/project docs.
- Hardcoding secrets, tokens, internal hostnames (rule 39: every repo is public).
- Skipping the wipe-and-replace step (leaves distro defaults active alongside our config).
- Using a non-optional include for vhosts.d / conf.d (empty dir crashes the service).
- Calling a repo "done" because `buildx` was green; "done" requires the smoke-test passing.
