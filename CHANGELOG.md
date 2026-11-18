# Changelog

Every release of exobooks, newest first. Versions are `major.minor.patch`
([semantic versioning](https://semver.org)). While the major version is 0, any release may
change the API, and this file says how. A release's jar is named `exobooks-<version>.jar`,
and a running server gives its version as the first line it prints and as `version` in the
answer to `GET /`.

## 0.6.0 (2026-11-18)

The jar is `exobooks-0.6.0.jar`. The numbers 0.3.0 to 0.5.1 have no jar: they went to the hosted
service at exobooks.ai, which shares this numbering.

Books made with 0.2.0 or earlier can't be opened: start this version on a new data directory.
From this version on, a newer version migrates the books it finds.

### Breaking

- `POST /commit` requires `exobooksVersion`, the version of exobooks the request was written
  against. Without it the request is answered 400. A request written against a version that a
  later one has broken is answered 409 and changes nothing, and the error's `data` gives
  `changes`, where to read what has changed, and `serverVersion`.
- `error` in an error's answer is an object, not a sentence: `message` is the sentence, and
  `data` an object of the values the error concerns, which are no longer written into the
  sentence. A refused commit's `mutation` and `failingAssertions` are in `error`'s `data`, not
  beside `error`. A refused mutation's sentence no longer begins with its type, and one about a
  transaction's line gives the line's position in `data` as `line`. An error from SQLite gives
  SQLite's message in `data` as `sqlite`.

### Added

- `POST /query` answers read-only SQL on the books, at the latest commit or an earlier one.
  It takes `exobooksVersion`, and refuses as `POST /commit` does.
- `GET /export`, optionally `?commit=<id>`, gives the books as an SQLite file.
- `POST /commit` takes `message`, kept with the commit, and `dryRun`, which checks everything
  and commits nothing.
- Mutations that change and delete: `update_account`, `delete_account`, `update_transaction`,
  `update_line` and `delete_transaction`.
- Counterparties: `create_counterparty`, `update_counterparty` and `delete_counterparty`, and
  `counterpartyId` on a line.
- Metadata: `create_metadata_key`, `update_metadata_key` and `set_metadata`, and `metadata` on
  what a mutation creates. A key declared `unique` has at most one row with each value.
- Balance assertions: `create_balance_assertion` and `delete_balance_assertion`. A commit that
  would break an assertion is refused, with `failingAssertions` in the error's `data`.
- `create_account` takes `parentId`, `openedOn`, `closedOn` and `placeholder`. A line can't be
  on a placeholder, or dated outside its account's opening and closing dates.
- A transaction's lines can have tempids.
- `GET /ledgers/<id>/accounts` gives each account's `id`, `parentId` and `placeholder`, and
  `openedOn` and `closedOn` if it has them.
- `exobooksVersion` in every JSON object answered, saying which version answered.
- `contextForAgents` on any answer: short notes about what the request may have got wrong, or
  what to know about the answer.
- The start line `Serving on http://127.0.0.1:<port>` adds how long the server took to start,
  `, started in <n> ms`.
- Migrations. A version of exobooks whose database schema is newer than the books' migrates
  them when it starts, while the server answers. Until it's done, `realm` in the answer to
  `GET /` has `"migrating": {"from": <n>, "to": <n>}`, the schema versions, the start line
  `Opened the realm in <path>, <n> commits` adds `; migrating it from schema version <n> to
  <n>, and until that's done its API answers 503`, and every request other than `GET /` and
  `POST /shutdown` is answered 503 with `migrating` in the error's `data`. Commit ids stay the
  same, so a read at a commit made before the migration still works. The books in the earlier
  schema are left on disk as they were. If the migration fails, `realm` in the answer to
  `GET /` has `error`, and the other requests are answered 500 with it.
- The data directory has a `README.md`, which the server writes each time it starts. It says
  that the books are read and changed through the API and not through the files there, gives
  the version and address of the server that last started on the directory, and says what
  each file is. No file in the directory opens with `sqlite3` or another tool.
- `"ifAbsent": true` on any `create_*` mutation makes it safe to send again: if the row it
  would create exists, the mutation does nothing, its tempid names the row that exists, and
  `skipped` in the answer lists its position; if nothing changed at all, no commit is made
  and the answer has `"unchanged": true`. The row that exists is the one the create's
  unique metadata values name, when it gives a value for a unique key, or else the one with
  its natural key: a currency with its code, a metadata key with its name, an account with
  its path in its ledger, a ledger or a counterparty with its name, a balance assertion with
  its account, currency, date and amount. A natural key that names more than one row is
  refused, as is a metadata key that exists but differs in being unique, and a transaction
  with `ifAbsent` but no value for a unique key, in its metadata or a line's.

### Changed

- The books are stored in a new form, so that commits keep their ids through migrations.
  This version can't open books made with 0.2.0 or 0.1.0: it says so and exits with status 1,
  and the fix is a new data directory. Books whose schema is newer than this version's, or
  not one of its versions at all, are refused the same way. Before, a database of another
  schema was refused with a list of the tables and indexes that differ.

### Fixed

- `POST /commit` answers a request with a query parameter 400, naming the parameter. Before,
  the parameter was ignored, so `POST /commit?dryRun=true` committed.

## 0.2.0 (2026-11-04)

The jar is `exobooks-0.2.0.jar`. Books made with 0.1.0 open as they are.

### Added

- Reads at an earlier commit. `GET /ledgers` and `GET /ledgers/<id>/accounts` take
  `?commit=<id>` and answer from the books as they were when that commit was made; on the
  chart of accounts it combines with `asOf`. A commit id that isn't a UUID is refused (400),
  and one that names no commit is answered 404.
- `POST /shutdown`, sent as `Content-Type: application/json` like any `POST`, answers
  `{"stopping": true}` and then stops the server, which exits with status 0. Without that
  content type it is refused (415), so a web page open in a browser can't stop the server.
- While a server runs, its process id is in `server.pid` in the data directory. The file is
  deleted when the server stops, by `POST /shutdown` or by a signal such as `kill`.

### Changed

- The answers to `GET /ledgers` and `GET /ledgers/<id>/accounts` now begin with `commit`, the
  id of the commit that was read, so the same state can be read again later. The rest of each
  answer is as before.
- `GET /ledgers` refuses a query parameter other than `commit` (400).
- One server runs on a data directory at a time. Before, a second server started on the same
  directory would open the same books, and two could write to them at once. Now the second
  start is refused, says which process has the directory, and exits with status 1. This is
  an operating system lock, not the presence of `server.pid`, so a file left behind by a
  server that was killed doesn't block the next start.
- A port that is already in use is refused with a message that says so and suggests
  `--port`, and status 1. Before, it was a Java stack trace.

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
