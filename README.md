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
**Administration → Policy**. Suggested rules:

| Action | Rule |
| --- | --- |
| `hello` | Any member; runs immediately |
| `sandbox-info` | Any member; runs immediately |

### Tier 1: a catalog environment and its setup destinations

| Item | What it shows |
| --- | --- |
| `_environments/net-tools` | An Ubuntu 26.04 image with curl, dig, openssl, the OpenSSH client and jq, built once by a setup script and rebuilt weekly |
| `net-tools-info` | An action that runs in that image: it lists the tools, then shows it cannot reach the network with them |

Building the image needs the Ubuntu archive. Under **Settings → Setup
destinations**, let the `net-tools` environment reach it, keeping the budget
already shown:

```json
{
  "environments": {
    "net-tools": [
      {"host": "archive.ubuntu.com", "port": 443},
      {"host": "security.ubuntu.com", "port": 443}
    ]
  },
  "actions": {},
  "budget_bytes": 2147483648
}
```

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

A new action cannot reach its server yet, and its page says so. Under
**Settings → Run destinations by action**, grant each action exactly its
server and port:

```json
{
  "tls-check-www": [{"host": "www.example.com", "port": 443}],
  "http-check-www": [{"host": "www.example.com", "port": 443}]
}
```

Unlike setup destinations, these apply whenever the action runs, and only to
that action. A server with a private address, such as one on your own
network, also needs `"ip"` in its grant: hostname grants connect only to
public addresses.

Then add policy rules for the new actions, not the templates. Suggested
rule: any member; runs immediately. Deleting an action made from a template
also deletes its rules and grants.

Later tiers add secrets and artifacts.

## Requirements

A Chancery build with action templates (decision 2026-10-23-004). No release
includes them yet.
