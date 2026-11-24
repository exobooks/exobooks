# exobooks

A ledger system of record for bookkeeping agents: the books live in exobooks, and the
bookkeeping intelligence is your own AI agent, working them from outside.

exobooks runs on your own machine as a small local server with an HTTP API. The books are
stored in a versioned SQLite database on local disk, and the server makes no network calls.

What makes it a good place for an agent to keep books:

- **A flexible, modern schema.** Any number of ledgers in one database, transactions that can
  span them, any mix of currencies in one account, and a date on every line of a transaction.
- **Complete history.** Every write is a *commit*: a batch of changes applied together and
  added to a history that is never overwritten. Any change can be traced to its commit, and
  the books as they were at any commit can be read, and a commit undone, so a mistake can be
  audited and backed out.
- **Built for agents.** One call applies a whole batch of changes, hundreds of transactions
  at a time, all or nothing. A refused request says which change was wrong and why. JSON in
  and out, with exact decimal amounts.
- **Fast.** The database is local: a write is one call to localhost and a report is a SQLite
  query, with no rate limits and no network round trips.

**Status: early.** You can record and correct accounts, transactions, counterparties,
metadata, and feeds and their lines; read the books with SQL as they are now or as they were
at any earlier commit; list the history and undo a commit; and export the books as an SQLite
file. Ledgers and currencies can't be changed or deleted once made. Everything here will
change; [CHANGELOG.md](CHANGELOG.md) says what each release changed.

**If you are an agent,** this file says how to install and start exobooks. The docs, which
say how to use it, are in [`docs/`](docs/): [`docs/api.md`](docs/api.md), the API, and
[`docs/guide.md`](docs/guide.md), how to keep books with it. The server also writes the docs
of its own version into its work directory each time it starts (below), so once it runs, read
them there. Work from the exact text of these files, not from a summary of the web page:

```sh
curl -fsSL https://raw.githubusercontent.com/exobooks/exobooks/main/README.md
```

## 1. Install

exobooks is one jar, run on Java 26. That is the version it is developed and tested on.

### Java 26

```sh
java -version
```

If that prints version 26, use it. Otherwise install a private copy into the current
directory. This needs no root and no package manager, and leaves any other Java alone:

```sh
os=$(uname -s | sed 's/Darwin/mac/; s/Linux/linux/')
cpu=$(uname -m | sed 's/arm64/aarch64/; s/x86_64/x64/')
release=https://github.com/adoptium/temurin26-binaries/releases/download/jdk-26.0.2.1%2B1
url="$release/OpenJDK26U-jre_${cpu}_${os}_hotspot_26.0.2.1_1.tar.gz"
mkdir -p java26 && curl -fsSL "$url" | tar -xz -C java26 --strip-components=1
```

That is Eclipse Temurin 26, an open-source build of Java, at `java26/bin/java` on Linux and
`java26/Contents/Home/bin/java` on a Mac. Use that path wherever the steps below say `java`.

### The jar

```sh
curl -fLO https://github.com/exobooks/exobooks/releases/download/v0.16.2/exobooks-0.16.2.jar
```

## 2. Start the server

```sh
java -jar exobooks-0.16.2.jar
```

This command does not return: the server runs until it is stopped. Start it as a background
process and leave it running while you work. It prints three lines on standard output (Java
may print notices of its own before them, on standard error):

```
exobooks 0.16.2
Created a new realm in /path/to/exobooks-data
Serving on http://127.0.0.1:8420, started in 628 ms
```

The books are kept in its *work directory*, `exobooks-data` in the directory the server was
started from, or the one `--dir <directory>` names. Start it on the same directory later and
it prints `Opened the realm in ..., 12 commits` instead.

To check it is up:

```sh
curl -s http://127.0.0.1:8420/
```

```json
{"service":"exobooks-local","version":"0.16.2","realm":{"head":"11509d44-71ab-4f12-9623-99f51a27792f","depth":0},"exobooksVersion":"0.16.2"}
```

To stop it:

```sh
curl -s -X POST http://127.0.0.1:8420/shutdown -H 'Content-Type: application/json'
```

It answers `{"stopping":true,"exobooksVersion":"0.16.2"}` and exits.

## 3. Read the docs

Each time it starts, the server writes the docs of its own version into `docs/` in its work
directory:

- `exobooks-data/docs/api.md`: the API, the whole of it, starting with the server's options
  and how to stop it. Read it before you use the server.
- `exobooks-data/docs/guide.md`: how to keep books with exobooks, with recipes for common work
  such as importing from a bank. Before you start a task, read the guide's part on it.
- `exobooks-data/docs/schema.sql`: the ledger schema, with comments on each table and column.
- `exobooks-data/docs/changelog.md`: what changed in each version.

They are the same as [`docs/`](docs/) here for the latest release, and are those of the jar
that runs when it is an earlier one.
