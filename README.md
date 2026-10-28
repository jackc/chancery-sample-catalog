# Chancery sample catalog

A catalog to start a new [Chancery](https://github.com/jackc/chancery)
installation with. It begins as a short tour, where each step needs one more
kind of grant than the one before, and ends with templates you can fork and
adapt.

Nothing in it changes anything outside the machine an action runs in, and no
action runs an arbitrary command.

## Using it

On a new installation, open **Administration → Catalog** and choose **Use the
sample catalog**. Or set the source yourself:

| Field | Value |
| --- | --- |
| Repository | `https://github.com/jackc/chancery-sample-catalog.git` |
| Ref | `main` |
| Directory | `actions` |
| Credential | none |

Chancery fetches the catalog and waits for an administrator to review and
activate it. Every later commit to `main` also waits for activation, so nothing
pushed here runs on your installation until you approve it.

To build your own catalog from it, fork the repository (or use it as a
template), point Chancery at your copy, and change what you need. Check your
changes before pushing:

```sh
chancery catalog check actions
```

## The tour

### Tier 0: a policy rule

| Action | What it shows |
| --- | --- |
| `hello` | Typed parameters, validation, and output streamed as it is written |
| `sandbox-info` | The machine an action runs in: a new VM for every run, a read-only root, a temporary `/work`, and no network without a grant |

Catalogs carry no policy, so nothing can run until you add a rule under
**Administration → Action settings**. Suggested rules:

| Action | Rule |
| --- | --- |
| `hello` | Any member; runs immediately |
| `sandbox-info` | Any member; runs immediately |

### Tier 1: a catalog environment and its setup destinations

| Item | What it shows |
| --- | --- |
| `_environments/net-tools` | An Ubuntu 26.04 image with curl, dig, openssl, the OpenSSH client, netcat, socat, the PostgreSQL client and jq, built once by a setup script and rebuilt weekly |
| `net-tools-info` | An action that runs in that image: it lists the tools, then shows it cannot reach the network with them |

Building the image needs the Ubuntu archive. Under **Administration →
Environments → Setup network access**, add a shared environment named
`net-tools` with these destinations, keeping the budget already shown:

| Host | Port |
| --- | --- |
| `archive.ubuntu.com` | 443 |
| `security.ubuntu.com` | 443 |

These destinations apply only while the image is built. Without them the
build has no network at all, and fails with `Temporary failure resolving
'archive.ubuntu.com'`.

Add a policy rule for `net-tools-info` like the tier 0 ones. Its first run
waits for the build, which takes a few minutes. If the build fails, the
petition says so and Chancery tries again ten minutes later while the
petition waits. The setup script's output is kept on the server, under
`/var/lib/chancery/environments/jobs/` on an installed host.

### Tier 2: actions made from templates, and their run destinations

| Template | What it shows |
| --- | --- |
| `tls-check` | The certificate a server presents; fails if it does not verify or expires within `warn_days` |
| `http-check` | One HTTPS fetch; fails unless the status is `expect_status`, and reports redirects without following them |

These are templates: neither can be requested itself, and neither names a
server. Under **Administration → Templates**, make an action from each one,
such as `tls-check-www` with `server` set to `www.example.com`. The action is
an ordinary action with its own name, policy and grants, so make one for each
server you want to check.

A new action cannot reach its server yet. Its page says so and links to
**Network access** on the action's settings page (also under
**Administration → Action settings**). There, grant each action exactly its
server and port, such as `www.example.com` port 443 for both `tls-check-www`
and `http-check-www`.

Unlike setup destinations, these apply whenever the action runs, and only to
that action. A server with a private address, such as one on your own
network, also needs a pinned IP in its grant: hostname grants connect only to
public addresses.

When a run cannot connect, its output says which side to look at. The egress
proxy answers `403 Forbidden` for a destination the action is not granted, and
`502 Bad Gateway` for a granted one that the Chancery host could not connect
to, such as a server that refuses the port or a firewall that drops it. The
run's network usage on the petition page counts these as denied and
unreachable streams. Chancery releases before the distinction answer 403 for
both.

Then add policy rules for the new actions, not the templates. Suggested
rule: any member; runs immediately. Deleting an action made from a template
also deletes its rules and grants.

### Tier 3: secrets

| Template | What it shows |
| --- | --- |
| `ssh-service-status` | `systemctl status` for one unit on a server, over SSH with a stored key and a pinned host key |
| `pg-dump` | `pg_dump` of one PostgreSQL database over TLS with a stored password, kept as an artifact |

#### `ssh-service-status`

The private key is a secret: Chancery stores it, and the catalog and the
action's settings name it but never hold it. Make a key for the server, and
an unprivileged user on the server for it to log in as. `systemctl status`
needs no privileges.

```sh
ssh-keygen -t ed25519 -N '' -C chancery -f chancery-status
```

Add `chancery-status.pub` to that user's `~/.ssh/authorized_keys` on the
server, prefixed with `restrict ` so that the key gets no terminal or
forwarding. Then, under **Administration → Secrets**, store the contents of
`chancery-status` as a secret, such as `web1-status-key`, and delete the local
copy.

Under **Administration → Templates**, make an action from
`ssh-service-status`, such as `ssh-service-status-web1`, with:

| Slot | Value |
| --- | --- |
| `server` | The server's name or address |
| `port` | Its SSH port, 22 by default |
| `user` | The user the key logs in as |
| `host_key` | The server's host key: the contents of `/etc/ssh/ssh_host_ed25519_key.pub` on the server |
| `key` | The secret, `web1-status-key` |

Copy the host key from the server itself, not from `ssh-keyscan` over the
network: the run trusts that key and no other, so a wrong key here would be
trusted on every run. The run reports a mismatch as `Host key verification
failed.`

Then grant the action the server and its SSH port under **Network access**,
as in tier 2, and add a policy rule. Requesters choose only the unit, and the
pattern on it keeps the remote command to `systemctl status` and a unit name.
The run fails when the unit is not running or does not exist, so its outcome
is the service's state.

`restrict` limits what a login can open, not what it can run. A real catalog
would also give the key a forced command on the server, so that even a
leaked key could only report status.

#### `pg-dump`

The password is a secret, delivered to the run as `PGPASSWORD`. Make a user
that can read everything and change nothing:

```sql
CREATE ROLE chancery_dump LOGIN PASSWORD '...';
GRANT pg_read_all_data TO chancery_dump;
```

Store the password under **Administration → Secrets**, such as
`app-dump-password`. Then, under **Administration → Templates**, make an
action from `pg-dump`, such as `pg-dump-app`, with:

| Slot | Value |
| --- | --- |
| `server` | The server's name or address |
| `port` | Its PostgreSQL port, 5432 by default |
| `database` | The database to dump |
| `user` | `chancery_dump` |
| `sslmode` | `verify-full`, or `require` for a server whose certificate is not from a public authority |
| `password` | The secret, `app-dump-password` |

Grant the action the server and port under **Network access**, and allow the
user in the server's `pg_hba.conf` from the host Chancery runs on, over TLS
only (`hostssl`). Requesters choose only whether to leave out the data
(`schema_only`).

The dump is pg_dump's custom format: download it from the run's artifacts and
restore it with `pg_restore`. Chancery keeps artifacts for seven days by
default and caps a run's artifacts at 1 GiB. A larger database also needs a
larger workspace than the host's default, since the dump is written there
before Chancery collects it. The client is PostgreSQL 18's, so the server must
be version 18 or older.

`verify-full` checks the server's certificate against the authorities Ubuntu
trusts and against `server`. `require` still encrypts, but cannot tell the
real server from anything else that answers at that address.

A later tier reads artifacts.

## Requirements

A Chancery build with action templates (decision 2026-10-23-004). No release
includes them yet.
