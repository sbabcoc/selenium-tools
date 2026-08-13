# selenium-tools

Cross-project utility scripts for coordinating releases and builds across
[`selenium-bom`](https://github.com/sbabcoc/selenium-bom),
[`Selenium-Foundation`](https://github.com/sbabcoc/Selenium-Foundation), and
[`selenium-grid-manager`](https://github.com/sbabcoc/selenium-grid-manager).

This repo exists because `selenium-tasks.sh` is a peer to all three projects
rather than subordinate to any one of them — it doesn't belong inside any
single project's own repo.

## Requirements

- Bash
- Git
- The three project repos cloned as siblings under `~/code`:
  - `~/code/selenium-bom`
  - `~/code/Selenium-Foundation`
  - `~/code/selenium-grid-manager`
- A JRE/JDK on `PATH` (only needed for `sandbox`)

## Installation

Clone this repo and add `selenium-tasks.sh` to your `PATH`, or invoke it
directly:

```bash
git clone https://github.com/sbabcoc/selenium-tools.git
```

The script uses paths relative to `HOME` to locate the three project
checkouts, so its own location doesn't matter — it also gets synced to a
Termux environment for use there.

## Usage

```
selenium-tasks.sh <command> [options]
```

## Commands

### `release <version>`

Tags, publishes, and prepares the next dev cycle for all three projects, in
dependency order (`selenium-bom` → `Selenium-Foundation` →
`selenium-grid-manager`). For each project, in order:

1. Runs pre-flight checks (see [Pre-flight checks](#pre-flight-checks))
2. Updates the README and resolves `[next-major]` placeholders for the given
   version (`updateReadme`, `updateSinceAnnotations`, `checkSincePlaceholders`)
3. Commits and pushes any resulting changes
4. Tags the release (`v<version>`) and pushes the tag
5. Installs and publishes (`Selenium-Foundation` and
   `selenium-grid-manager` publish both the `selenium3` and `selenium4`
   profiles, with tests skipped)

After all three projects are released, runs `install` to install the
newly-released versions locally, then reports current versions via
`versions`.

### `install`

Installs all three projects to local Maven, in dependency order:

1. `selenium-bom`
2. `Selenium-Foundation` — both `selenium3` and `selenium4` profiles, tests
   skipped
3. `selenium-grid-manager` — both `selenium3` and `selenium4` profiles, tests
   skipped

### `versions`

Reports the current base version of each project, and checks for a version
mismatch across them (comparing each project's base version, ignoring
`-SNAPSHOT`, against the highest one found). If any project is lagging behind
the others, prints the `git commit --allow-empty` / `git push` commands
needed to advance it to the current dev cycle.

### `branch <name>`

Runs pre-flight checks, then creates and pushes a branch named `<name>` in
all three projects.

### `sync`

For each project: checks out `main`, pulls, force-fetches tags, and deletes
any local branches already merged into `main`.

### `sandbox`

Wipes and repopulates a standalone `selenium-grid-manager` runtime sandbox at
`~/code/sandbox`:

1. Resolves the current `selenium-grid-manager` base version and locates the
   corresponding `selenium3`/`selenium4` artifacts (`-s3`/`-s4`) in the local
   Maven repo — run `install` first if they're not there yet
2. Deletes and recreates `~/code/sandbox`, then copies both jars into it
3. Bootstraps the runtime by running `java -jar` on the `selenium4` jar

## Pre-flight checks

`release` and `branch` both require, for every project, before doing
anything:

- Currently checked out on `main`
- No uncommitted changes (staged or unstaged)
- Up to date with `origin/main` — neither ahead nor behind

If any project fails a check, the script aborts before making any changes.

## Notes

- `selenium-bom`, `Selenium-Foundation`, and `selenium-grid-manager` are
  always released as a set — there's never a point where only one or two of
  the three are published on their own.
- `release` intentionally does **not** create an automatic "start new dev
  cycle" empty commit after every release. A new dev cycle only starts when
  real work naturally lands — `versions` will flag the mismatch and hand you
  the commands to advance manually when that time comes.
