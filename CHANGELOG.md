# Changelog

Every release of exobooks, newest first. Versions are `major.minor.patch`
([semantic versioning](https://semver.org)). While the major version is 0, any release may
change the API, and this file says how. A release's jar is named `exobooks-<version>.jar`,
and a running server gives its version as the first line it prints and as `version` in the
answer to `GET /`.

## 0.1.0 (2026-11-04)

The first release of the local server: `java -jar exobooks-0.1.0.jar` starts it and keeps
running. Before this there was only `exobooks.jar`, a compatibility check that printed
`hello world` and exited (release `hello-0.1.0`); that check is gone.

### The server

- Runs on Java 26 and serves an HTTP API on `127.0.0.1`, port 8420. `--port <port>` changes
  the port. There is no authentication.
- Keeps the books in a versioned SQLite database in `exobooks-data`, in the directory it was
  started from. `--dir <directory>` puts them somewhere else. The directory is created if it
  doesn't exist. The server makes no network calls.
- Prints three lines on start: `exobooks 0.1.0`; then `Created a new realm in <path>` or
  `Opened the realm in <path>, <n> commits`, with the absolute path; then
  `Serving on http://127.0.0.1:<port>`.
- Refuses to start on a directory whose database was made with a different schema, and says
  which tables and indexes differ. There are no migrations yet: the fix is a new directory.
- Refuses a request whose `Host` isn't localhost or a loopback address (403), and a `POST`
  whose body isn't sent as `application/json` (415), so a web page open in a browser can't
  use the server.
- Any other path is answered 404, `{"error": ...}`.

### Writing

- `POST /commit` with `{"mutations": [...]}` applies the whole list as one commit, in order.
  The answer is `{"commit": <id>, "depth": <n>, "ids": {<tempid>: <id>}}`. A commit id is a
  UUID; `depth` counts the commits made so far.
- Mutation types: `create_currency` (`code`, optional `name`), `create_ledger` (`name`; also
  makes the root accounts `Assets`, `Liabilities`, `Equity`, `Income` and `Expenses`),
  `create_account` (`ledgerId`, `parentFQN`, `name`), and `create_transaction` (optional
  `memo`, and `lines`).
- A line has `ledgerId`, `accountFQN`, `amount`, `currency` and `date`, and optionally `at`
  and `memo`. The lines of a transaction must sum to zero in each currency. They may be in
  different ledgers.
- Accounts are named by path from a root, joined with colons (`Expenses:Software:Hosting`).
  A name can't contain a colon, and two accounts under one parent can't share a name.
- Amounts are JSON strings holding a plain decimal, positive a debit, with up to 64 digits on
  each side of the point. They are exact: nothing is rounded.
- `date` is `YYYY-MM-DD`. `at` is ISO 8601 with a zone.
- Tempids: a mutation that creates something may carry `"id": "<string>"`, and later
  mutations in the same request may use that string where an id goes. A string is always a
  tempid and a real id is always an integer. `ids` in the answer maps each tempid to the id
  assigned.
- A request that can't be applied changes nothing and is answered 400 with `error` and
  `mutation`, the position (from 0) of the mutation at fault. Unknown mutation types and
  unknown fields are refused.

### Reading

- `GET /` answers `{"service": "exobooks-local", "version": ..., "realm": {"head": <commit
  id>, "depth": <n>}}`.
- `GET /ledgers` lists every ledger, `{"ledgers": [{"id": ..., "name": ...}]}`, in id order.
- `GET /ledgers/<id>/accounts` is the chart of accounts: every account of the ledger in tree
  order as `{"fqn": ..., "totals": {<currency code>: <amount>}}`. An account's totals include
  its sub-accounts. Amounts come back as strings with at least two decimal places.
  `?asOf=YYYY-MM-DD` counts only lines dated on or before that day. Any other query parameter
  is refused (400), and a ledger that doesn't exist is answered 404.

### Not there yet

- Nothing can be changed or deleted once written: every mutation creates.
- History is recorded with every commit, but there is no call to read it, to read the books
  as of an earlier commit, or to back a commit out.
- No reads other than the two above: no list of transactions or lines.
- No conversions between currencies, counterparties, tags or metadata.
