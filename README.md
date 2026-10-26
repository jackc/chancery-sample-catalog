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

Later tiers add a catalog environment, actions made from templates with
their own targets and secrets, and artifacts.

## Requirements

A Chancery build with action templates (decision 2026-10-23-004). No release
includes them yet.
