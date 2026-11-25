# exobooks API: the local server

> **Version 0.18.0** · [changelog](changelog.md)

exobooks is a ledger system of record for bookkeeping agents: the books live in exobooks, a double-entry ledger with any number of ledgers and currencies and a history of every change, and the bookkeeping intelligence is your own AI agent, working the books from outside through this HTTP API. This server runs on the user's own machine and keeps the books on its disk. It makes no network calls.

This is the whole documentation of exobooks 0.18.0, the version of the server that wrote it. The server writes its docs into the `docs/` directory of its work directory each time it starts, so they always describe the server that last ran there:

| File | What it is |
|---|---|
| `api.md` | This documentation: what each call does. |
| `guide.md` | How to keep books with exobooks: how it is meant to be used, recipes for common work, and how to work with particular banks. |
| `schema.sql` | The ledger schema, with comments on what each table and column means. |
| `changelog.md` | What changed in each version. |

**Read the guide's part on a task before you start it**, such as importing transactions from a user's bank. The guide is advice, and this documentation is what you can rely on.

**Status: early.** You can record and correct accounts, transactions, counterparties, metadata, and feeds and their lines; read the books with SQL as they are now or as they were at any earlier commit; list the history and undo a commit; and export the books as an SQLite file. Ledgers and currencies can't be changed or deleted once made. Everything here will change; the changelog says how.

## Starting and stopping the server

```sh
java -jar exobooks-0.18.0.jar [--dir <work directory>] [--port <port>]
```

This command does not return: the server runs until it is stopped. Start it as a background process and leave it running while you work. It prints three lines on standard output (Java may print notices of its own before them, on standard error):

```
exobooks 0.18.0
Created a new realm in /path/to/exobooks-data
Serving on http://127.0.0.1:8420, started in 563 ms
```

- The first line is the version of the jar, which is also in its file name.
- A **realm** holds all of the books, in the **work directory**: `--dir`, or `exobooks-data` in the directory the server was started from, created if missing. Started on a directory that has books, the server prints `Opened the realm in ..., 12 commits` instead. If it says `Created a new realm` when you expected existing books, it was started on the wrong directory.
- `--port` changes the port, 8420 by default.
- One server runs on a work directory at a time. It holds a lock on `server.pid` there, which has its process id while it runs and is deleted when it stops. A second start on the directory is refused and names that process. A `server.pid` left by a server that was killed doesn't block the next start.
- A start is refused, too, if the port is taken. A refused start says why and exits with status 1.
- Books made by a version with an earlier schema are migrated when the server starts, while it answers. Until that is done, `realm` in the answer to `GET /api/status` has `"migrating": {"from": <n>, "to": <n>}`, the schema versions, and every other request except `POST /api/shutdown` is answered 503. Commit ids stay the same.
- Books this version can't open, made by a later version or by exobooks 0.2.0 or earlier, make the server say so and exit with status 1. Start it on a new directory, or, for a later version's books, use that version.

`GET /api/status` says the server is up, its version, and the realm's latest commit (`head`) and the number of commits made so far (`depth`):

```sh
curl -s http://127.0.0.1:8420/api/status
```

```json
{"service": "exobooks-local", "version": "0.18.0", "realm": {"head": "f770c3cc-77ef-43da-93d3-653fe08a3055", "depth": 0}, "exobooksVersion": "0.18.0"}
```

To stop it:

```sh
curl -s -X POST http://127.0.0.1:8420/api/shutdown -H 'Content-Type: application/json'
```

It answers `{"stopping": true}` and exits. Ending the process with `kill` stops it cleanly too.

## The realm's address

The server has one realm, and the realm's API, which the rest of this document describes, is under `/api` at the server's address, `http://127.0.0.1:8420/api` (with the port it was started on). Its paths are under that address: `POST /commit` is `POST http://127.0.0.1:8420/api/commit`.

The server listens on 127.0.0.1 only and has no authentication. So that a web page open in a browser on the same machine can't use it, a request whose `Host` header isn't `localhost` or a loopback address is answered 403, and a `POST` whose body isn't sent as `Content-Type: application/json` is answered 415, `POST /api/shutdown` included. A path the server doesn't have is answered 404.

Put a request's body in a file and send the file, so the shell doesn't have to quote JSON:

```sh
curl -s -X POST http://127.0.0.1:8420/api/commit -H 'Content-Type: application/json' --data @request.json
```

## Versions, and what has changed

exobooks has a version number, `major.minor.patch`, for everything you can depend on: the API's paths, fields, status codes and mutations, the ledger schema and its SQL functions, the rules a request is checked against, and whether existing books still open. The wording of errors and the notes in `contextForAgents` can change in any version.

A new major version may break what came before, a minor version adds to it, and a patch fixes a bug. While the major version is 0, a minor version may also break what came before, and its entry in the changelog says so under `### Breaking`.

The server gives its version as the first line it prints, as `version` in the answer to `GET /api/status`, and as `exobooksVersion` in every JSON object it answers. Say which version you wrote a request against by sending `exobooksVersion` in its body: `POST /commit` requires it, and `POST /query` takes it. A request written against a version that a later one has broken is answered 409 and changes nothing.

`changelog.md`, beside this file, says what changed in each version up to this one, newest first. If you keep notes between sessions, record the version you last read, and when the server gives a newer one, read what changed: a workaround in your notes may no longer be needed. New versions are released at https://github.com/exobooks/exobooks/releases.

## The books

A **realm** holds books: any number of ledgers, and the history of every change to them.

- A **ledger** is one set of books: a company, a person, a household. Its name is unique in the realm.
- Each ledger has a tree of **accounts** under five roots that come with it: `Assets`, `Liabilities`, `Equity`, `Income` and `Expenses`. An account is named by its path from the root, joined with colons (`Assets:Checking`, `Expenses:Software:Hosting`), or by its numeric id. A name can't contain a colon. An account can be a *placeholder*, which holds sub-accounts but no lines, and can have an opening and a closing date, outside which it holds no lines.
- A **currency** is named by its code, such as `USD`, and may have a description, such as `US dollar`. It has to be created before it is used.
- A **transaction** is a memo and one or more **lines**. A line puts an amount of one currency into one account on one date, and may name a **counterparty** (a vendor, a customer, anyone on the other side, its name unique in the realm) and carry a memo of its own. A transaction has no date of its own: each line has one.
- **Metadata** is key-value information on any row: an external id, the record a bank gave for a transaction. A key is declared before it is used, and a key declared *unique* has at most one row with each value.
- A **feed** is a source of transaction data for one account, such as a bank account or a card, and its **feed lines** are the records it gives, which are imported into the books as lines of transactions (below, under "Feeds, and importing from them").
- Every change is a **commit**: a batch of changes applied together and added to a history that is never overwritten. The books can be read as they were at any commit.

**Positive is a debit, negative is a credit**, and the lines of a transaction sum to zero in each currency. What the signs mean under each root:

| Root | A positive line | A negative line |
|---|---|---|
| `Assets` | money arriving (a deposit) | money leaving (a payment) |
| `Liabilities` | paying a debt down | borrowing, or charging a card |
| `Equity` | an owner taking money out | an owner putting money in |
| `Income` | giving a refund | earning income |
| `Expenses` | spending | getting a refund |

So a customer payment of 8,500.00 into checking is `+8500.00` on `Assets:Checking` and `-8500.00` on an `Income` account. Balances of `Liabilities`, `Equity` and `Income` accounts are normally negative.

Amounts are JSON strings holding a plain decimal, never JSON numbers: `"8500.00"`, `"-312.58"`. They are exact, with as many decimal places as they need. An answer gives an amount in its shortest form, with no trailing zeros: `"8500"`, `"-312.5"`, `"0.125"`. Formatting it for display, such as to two decimal places, is up to the client. Dates are `YYYY-MM-DD`. A line's `at`, when the exact time is known, is ISO 8601 with a zone: `"2026-07-14T09:30:00Z"`.

## Calling the realm's API

The paths below are relative to the realm's own address. Bodies are JSON, sent as `Content-Type: application/json`; a body sent otherwise is answered 415. Unknown fields and query parameters are errors, so a misspelled one is reported rather than ignored.

An error is answered with a JSON object holding `error`, an object with `message`, a sentence saying what is wrong, and `data`, an object of the values it concerns, such as the field, the value sent, or the row at fault. As with Clojure's `ex-info`, the values are in `data` and not in the sentence, so read them from there:

```json
{"error": {"message": "Unknown query parameter", "data": {"parameter": "dryRun", "parameters": []}}}
```

`data` is left out when there are no values to give. Which fields it has depends on the error; those this document names, such as `mutation` on a refused commit, are part of the API, and the others are there to help and may change, as the sentences may.

Every JSON object answered carries `exobooksVersion`, the version of exobooks that answered.

Any answer, an error included, may carry `contextForAgents`: a list of short notes about what the request may have got wrong, or what to know about the answer, each saying what to do instead. Read them. They are how the server points out a query that runs but means something other than what was probably intended.

## Writing: `POST /commit`

```json
{"exobooksVersion": "0.18.0", "mutations": [...], "message": "Categorized October's card charges, as approved", "dryRun": false}
```

`exobooksVersion` is required: the version of exobooks the request was written against, the one this document describes. If a later version has broken what that version did, the request is answered 409 and changes nothing: read what has changed, at the address in the error's `data` as `changes`, and send the request again with `serverVersion`, also in `data`, as its `exobooksVersion`.

The mutations are applied in order as one commit, or not at all. `message` (optional) says what the commit is for and on whose authority; it is kept with the commit. `dryRun: true` checks everything and answers as if it had committed, committing nothing.

The answer:

```json
{"commit": "413917e9-7ec9-404a-8f07-d3ea80447a0d", "depth": 12, "ids": {"books": 1}, "skipped": []}
```

`commit` is the new commit's id and `depth` its number in the history. `ids` maps each tempid (below) to the id it named. `skipped` lists the positions of mutations that `ifAbsent` (below) found already applied; if nothing changed at all, no commit is made, `commit` is the latest one, and the answer has `"unchanged": true`.

A request that can't be applied changes nothing and is answered 400, with `mutation` in the error's `data`, the position of the one at fault counting from 0, and `line`, when it is one of a transaction's lines, counting from 0:

```json
{"error": {"message": "The lines don't balance", "data": {"mutation": 1, "currency": "USD", "sum": "0.01"}}}
```

### Naming rows, and tempids

A row is named by its numeric id. Inside the request that creates it, that id isn't known yet, so a mutation that creates a row may give it a temporary id, a **tempid**: `"id": "<any string>"`. Later mutations in the same request use the tempid where an id goes. A string is always a tempid and an integer always a real id: `"ledgerId": "books"` is the ledger this request creates, `"ledgerId": 1` the ledger whose id is 1. A tempid names one row of its request, and lasts only for that request; the answer's `ids` gives the real ids to use afterwards. A transaction's lines can have tempids too.

An account is named by `accountId`, or by `ledgerId` and `accountFQN` (its path, `"Expenses:Repairs"`). A parent account likewise by `parentId` or `parentFQN`. A currency by its code. Other rows by `ledgerId`, `transactionId`, `lineId`, `counterpartyId`, `feedId` and `feedLineId`.

### The mutations

A `?` marks an optional field.

| `type` | Fields |
|---|---|
| `create_currency` | `code`, `description`? |
| `create_ledger` | `name`, `metadata`?; also makes the five root accounts |
| `create_account` | `ledgerId`, `parentFQN` or `parentId`, `name`, `openedOn`?, `closedOn`?, `placeholder`?, `metadata`? |
| `update_account` | the account, and any of `name`, `parentFQN` or `parentId` (to move it), `openedOn`, `closedOn` (null clears), `placeholder` |
| `delete_account` | the account, which must have no lines, sub-accounts or feeds (move a feed with `update_feed`); close an account that has lines instead |
| `create_counterparty` | `name`, `metadata`? |
| `update_counterparty` | `counterpartyId`, `name` |
| `delete_counterparty` | `counterpartyId`, which no line may name |
| `create_transaction` | `lines`, `memo`?, `metadata`? |
| `update_transaction` | `transactionId`, and `memo`, `lines`, or both |
| `update_line` | `lineId`, and any of the account, `date`, `at`, `memo`, `counterpartyId` (null clears the last three), `metadata` (sets the keys it gives; a null value deletes one) |
| `delete_transaction` | `transactionId` |
| `create_metadata_key` | `name`, `description`?, `unique`? |
| `update_metadata_key` | `name`, and `description`, `unique`, or both |
| `set_metadata` | `table` (`ledger`, `account`, `transaction`, `line`, `counterparty`, `currency`, `feed` or `feedLine`), `rowId`, `key`, `value` (null deletes) |
| `create_feed` | `displayName`, the account?, `metadata`? |
| `update_feed` | `feedId`, and `displayName`, the account (`accountId` null clears it), or both |
| `delete_feed` | `feedId`; its feed lines are deleted with it, and none may be imported |
| `create_feed_line` | `feedId`, `date`, `amount`, `currency`, `memo`?, `record`?, `excluded`?, `note`?, `metadata`? |
| `update_feed_line` | `feedLineId`, and any of `date`, `amount`, `currency`, `memo`, `record`, `excluded`, `note` (null clears the memo, record and note), `metadata` (sets the keys it gives) |
| `delete_feed_line` | `feedLineId`, which must not be imported |
| `link_feed_line` | `lineId`, `feedLineId`: the line was imported from the feed line |
| `unlink_feed_line` | `lineId`, `feedLineId` |

Any mutation that creates a row may also have `id`, a tempid, and every `create_*` mutation takes `ifAbsent` (below, under "Metadata, and importing safely").

A line of `create_transaction` has the account, `amount`, `currency` and `date`, and optionally `at`, `memo`, `counterpartyId`, `metadata` and `id`. A line isn't on a placeholder or dated outside its account's opening and closing dates.

`update_transaction`'s `lines` are all of the transaction's lines afterwards: an entry with `lineId` keeps that line and changes the fields it gives, one without is a new line, and a line of the transaction not listed is deleted. So splitting a line into several is one `update_transaction`. `update_line` changes one line without its amount, which would unbalance the transaction.

An example that sets up books and records a transaction from a bank's feed, which can be sent again without recording anything twice, since every create has `ifAbsent` and the transaction carries the bank's id under a unique key:

```json
{"exobooksVersion": "0.18.0", "mutations": [
  {"type": "create_currency", "code": "USD", "description": "US dollar", "ifAbsent": true},
  {"type": "create_metadata_key", "name": "bank.id", "unique": true, "description": "The bank's id for a transaction", "ifAbsent": true},
  {"type": "create_ledger", "id": "books", "name": "Marlow Studio LLC", "ifAbsent": true},
  {"type": "create_account", "ledgerId": "books", "parentFQN": "Assets", "name": "Checking", "ifAbsent": true},
  {"type": "create_account", "ledgerId": "books", "parentFQN": "Expenses", "name": "Hosting", "ifAbsent": true},
  {"type": "create_counterparty", "id": "aws", "name": "Amazon Web Services", "ifAbsent": true},
  {"type": "create_transaction", "memo": "AMAZON WEB SERVICES aws.amazon.com", "ifAbsent": true, "metadata": {"bank.id": "txn_8Hq2"}, "lines": [
    {"ledgerId": "books", "accountFQN": "Assets:Checking", "amount": "-312.58", "currency": "USD", "date": "2026-07-24", "counterpartyId": "aws"},
    {"ledgerId": "books", "accountFQN": "Expenses:Hosting", "amount": "312.58", "currency": "USD", "date": "2026-07-24", "counterpartyId": "aws"}
  ]}
]}
```

### Metadata, and importing safely

Metadata is set with `"metadata": {"key": value}` on whatever a mutation creates, each line included, or with `set_metadata`. A key must be declared first, with `create_metadata_key`. A value is a string, an integer, a number, a boolean (kept as 1 or 0), or an object or array (kept as JSON). A key declared `"unique": true` has at most one row with each value, which the server enforces.

`"ifAbsent": true` makes a create safe to send again: if the row it would create exists, it does nothing, its tempids name the row that exists, and its position is listed in `skipped`. The row that exists is the one its unique keys' values identify, when its metadata gives a value for a unique key. Otherwise it is the one its natural key identifies, if its kind of row has one:

| Kind of row | Natural key |
|---|---|
| A currency | its `code` |
| A ledger | its `name` |
| An account | its path in its ledger, from its parent and its `name` |
| A counterparty | its `name` |
| A metadata key | its `name` |
| A transaction | none: with `ifAbsent` it needs a value for a unique key, in its metadata or a line's, and is refused without one |
| A feed | none, since its `displayName` need not be unique: with `ifAbsent` and no value for a unique key, a feed is always created |
| A feed line | none: with `ifAbsent` it needs a value for a unique key in its metadata, and is refused without one |

The codes, names and paths in the table are unique, so a create without `ifAbsent` that gives one already taken is refused. A `create_metadata_key` with `ifAbsent` is refused when a key of that name exists and its `unique` is not the request's, which is false if left out.

Unique keys are what make an import safe to run again. Declare one for each source's ids, such as `bank.id`, and put the source's id on each row as you create it. For a transaction, its own unique keys name the transaction and each line's name that line; a key that names a row of another kind, or two lines that name the same line, are refused, and so is a mix of keys of which some name rows and some don't. With `ifAbsent`, a line given a tempid must carry a unique key, since that is what names the line when the request runs again.

So a rerun of the same import, or a request retried after a timeout, changes nothing it already did.

### Feeds, and importing from them

A **feed** is a source of transaction data for one account at a bank, a card issuer or anywhere else: a bank account connected through an aggregator, a card's statements downloaded as CSV, a spreadsheet someone sends now and then. A source used once, such as a CSV loaded once, is a feed too. A feed names the ledger account its lines belong to, once that is known. Its `displayName` is for people and need not be unique, so to find a feed again, such as to create it with `ifAbsent` when an import runs again, give it a unique key's value for the source's id for it, such as an aggregator's account id.

Each record a feed gives, what a bank calls a transaction, is a **feed line**: a `date`, an `amount` and `currency`, a `memo`, and `record`, the source's record whole as a JSON object (for a CSV, its row, with the columns as keys). A feed line's amount is in the books' sign for the feed's account, as a line on that account would be: positive for money into a bank account, negative for a charge on a card. Feed lines can be changed after they are written, as when a pending charge posts. To write feed lines that can be sent again safely, declare a unique key for the source's ids, and give each feed line its id with `ifAbsent`: since a feed line has no natural key, `ifAbsent` needs one.

**Importing** is turning feed lines into the books: a transaction whose line on the feed's account is the feed line, with the other side categorized, or two feed lines on different accounts matched as the two sides of a transfer; then `link_feed_line` records which ledger line came from which feed line. A feed line is imported while a ledger line is linked to it. Deleting the ledger line, or `unlink_feed_line`, makes it unimported again, and a feed line that is imported can't be deleted. Once imported, the feed line and the ledger line can each be changed without the other, so give the ledger line the feed line's date and amount when you import it.

A feed line that the books shouldn't have, such as a duplicate or a personal charge on a company card, is marked `"excluded": true`, with `note` saying why. An import looks only at the feed lines that are neither imported nor excluded:

```sql
SELECT f.id, f.date, f.amount, f.memo FROM feed_line f
WHERE f.feed_id = ? AND f.is_excluded = 0
  AND NOT EXISTS (SELECT 1 FROM line_feed_line x WHERE x.feed_line_id = f.id)
ORDER BY f.date
```

Feeds can overlap, and a feed can repeat itself: the same charge may come from a CSV and from a connection to the bank, or twice from a connection made again. Look for duplicates among the feeds of one ledger account by date and amount, and against the lines already in the books, such as those an earlier import from another system made.

Importing feed line 41, a hosting charge on checking:

```json
{"exobooksVersion": "0.18.0", "mutations": [
  {"type": "create_transaction", "memo": "AMAZON WEB SERVICES aws.amazon.com", "lines": [
    {"id": "bank", "ledgerId": 1, "accountFQN": "Assets:Checking", "amount": "-312.58", "currency": "USD", "date": "2026-07-24"},
    {"ledgerId": 1, "accountFQN": "Expenses:Hosting", "amount": "312.58", "currency": "USD", "date": "2026-07-24"}
  ]},
  {"type": "link_feed_line", "lineId": "bank", "feedLineId": 41}
]}
```

## Reading

Every read answers with `commit`, the id of the commit it read: the latest, unless the request names an earlier one with `?commit=<id>`, which reads the books as they were then.

- `GET /ledgers`: the realm's ledgers, `{"commit", "ledgers": [{"id", "name"}, ...]}`.
- `GET /ledgers/<id>/accounts`, optionally `?asOf=YYYY-MM-DD`: the ledger's chart of accounts in tree order (each root, then its sub-accounts by name), each account with its `fqn`, `id`, `parentId`, `placeholder`, `openedOn` and `closedOn` if set, and `totals`, one amount per currency, sub-accounts included. `asOf` counts only lines dated on or before that day.
- `POST /query`: any other question, in SQL (below).
- `GET /export`, optionally `?commit=<id>`: the realm's whole database as an SQLite file (below).
- `GET /commits` and `GET /commits/<id>`: the history, and what one commit changed (below, under "History, and undoing a commit").

### SQL: `POST /query`

```json
{"exobooksVersion": "0.18.0", "sql": "SELECT date, memo FROM line WHERE account_id = ? ORDER BY date", "params": [6], "commit": "<id>"}
```

`exobooksVersion` is optional here, and works as it does on a commit. Send it with a query you save, so that a later version that breaks the query refuses it rather than answering something else.

One statement, in SQLite's dialect, that begins `SELECT`, `WITH`, `VALUES` or `EXPLAIN`, with `?` placeholders bound from `params` (strings, numbers, booleans as 1 or 0, null), on the realm's database at the latest commit or at `commit`. The answer is `{"commit", "columns": [...], "rows": [[...], ...], "rowCount", "truncated"}`.

The tables are the ledger schema's: [`schema.sql`](schema.sql), in the docs beside this document, gives it, with comments on what each table and column means, and `SELECT name, sql FROM sqlite_schema` lists them from the realm itself. No mutation writes the tables `tag`, `tagging` and `line_conversion`, so they are empty. What to know:

- Name the columns you read. A new minor version of exobooks can add columns to a table, which changes what `SELECT *` returns and moves the columns after them in a join, and rows in an answer are arrays.
- A transaction's table is `txn`. A line has its own `date`; a transaction has none. Dates are `YYYY-MM-DD` text, so compare them with strings: `date <= '2025-12-31'`, `date LIKE '2025-03-%'`.
- `line.account_id` is the account itself. An account with its sub-accounts is a `WITH RECURSIVE` over `account.parent_id`.
- Amounts are *bigdecs*, exact decimal numbers, and work as numbers in a query: `sum(amount)`, `amount * 1.1`, `amount > 100.50`, `abs`, `round`, `min`, `max`, `ORDER BY` and the rest give what they would on numbers, with no floating point. In an answer every amount is decimal text in its shortest form (`"-12.5"`, `"7500"`), named with `AS` or not; to show two places, use `printf('%.2f', amount)` or `bigdec_text(amount, 2)`, which round half away from zero. The server rewrites the query to calls of `bigdec_` functions; `EXPLAIN` and `EXPLAIN QUERY PLAN` give the statement it ran as `rewritten`. What to know about bigdecs in a query:
  - A whole number, or a column or expression of whole numbers, can be used with a bigdec as it is: `amount + 1`, `coalesce(sum(amount), 0)`.
  - A number with a decimal point is exact when it is directly beside a bigdec: in a comparison, in `BETWEEN` or `IN`, in arithmetic with it, or among the values of `coalesce`, `CASE`, `max` and the like. Anywhere else it is SQLite's floating point, and using that with a bigdec is an error: `amount < 0.1 + 0.2` is refused, and `amount < bigdec('0.3')` is what to write.
  - Text is never a bigdec, so a string or a `?` beside a bigdec is an error. `bigdec('12.50')` and `bigdec(?)` make a bigdec from text or an integer, with `params` holding the amount as a string, as everywhere in this API. A JSON number with a decimal point or an exponent, such as `5.5` or `5.0`, is floating point, so `bigdec(?)` refuses it.
  - `||`, `LIKE`, `CAST(amount AS TEXT)` and text functions such as `upper` and `substr` take a bigdec's text. `printf` and `format` take a bigdec with `%s` or `%.Nf`. A function that does neither, such as `date` or `json_object`, refuses a bigdec: give it `bigdec_text(amount)`.
  - Integer division is SQLite's: if `n` and `m` are integer columns, `amount * (n / m)` multiplies by `n / m` truncated toward zero. Write `amount * bigdec(n) / m` for the exact quotient.
  - A compound `SELECT`, such as a `UNION`, whose parts put a whole number and a bigdec in one column makes the column a bigdec in every part. When the server rewrites a compound's result column, as it does for arithmetic or an aggregate on a bigdec or for that whole number, order the compound by a result column's alias or number, `ORDER BY 1`: an expression such as `ORDER BY x + 1` is refused, since SQLite matches it to a result column as written.
  - `metadata.value` and `json_extract(...)` can hold anything, so an amount stored there is made a bigdec with `bigdec(...)`: `bigdec(json_extract(value, '$.total'))`.
  - The `bigdec_` functions can be called too: `bigdec_sum`, `bigdec_avg`, `bigdec_abs`, `bigdec_neg`, `bigdec_add`, `bigdec_sub`, `bigdec_mul`, `bigdec_div`, `bigdec_round(x, n)`, `bigdec_text(x)` and `bigdec_text(x, n)`.

  A realm can hold several currencies, so sum per `currency_id`.
- Metadata is the table `metadata (table_id, row_id, key_id, value)`, with the keys in `metadata_key`. Table ids: 1 ledger, 2 account, 3 txn, 4 line, 5 counterparty, 7 currency, 9 feed, 10 feed_line. Select `value` as it is: a value written as a string, a number or a boolean comes back as one. Each transaction's `bank.id`, for example:

  ```sql
  SELECT t.id, t.memo, m.value FROM txn t
  JOIN metadata m ON m.table_id = 3 AND m.row_id = t.id
  WHERE m.key_id = (SELECT id FROM metadata_key WHERE name = 'bank.id')
  ```

  Only a value written as an object or an array is different: it is kept as JSONB, a BLOB, so select `json(value)` to read it as JSON, or `json_extract(value, '$.x')` for one field of it. Don't wrap other values in `json()`, which refuses a plain string. Any other BLOB in an answer comes as `{"base64": ...}`.
- A query that doesn't parse, or that uses something as an amount that can't be one, is answered 400 with what to write instead, and its position in the query in the error's `data` as `line` and `column`. An error from SQLite is answered 400 with SQLite's message in the error's `data` as `sqlite`, often with a hint in `contextForAgents`.

The limits: the database can only be read; `ATTACH` is refused; one statement per request; a query running longer than 30 seconds is stopped and refused; no string or BLOB longer than 16 MiB may be made or read. An answer holds at most 1,000,000 rows and 64 MiB of values, each value counted at the most its JSON can take, so it may be cut somewhat early; when it is cut, before the row that would pass the limit, `truncated` is true and a note says what to do. At most 4 queries run on a realm at once; another waits up to 10 seconds, then is answered 429.

### History, and undoing a commit

`GET /commits` lists the realm's commits, latest first, up to 100 to an answer, and fewer when their messages come to more than 16 MiB:

```json
{"commit": "413917e9-7ec9-404a-8f07-d3ea80447a0d", "commits": [
  {"commit": "413917e9-7ec9-404a-8f07-d3ea80447a0d", "depth": 12, "at": "2026-11-18T15:02:11.204Z", "message": "Categorized October's card charges, as approved", "author": "ada@example.com"}
], "nextBefore": 12}
```

The `commit` outside the list is the latest one. In the list, `message`, `author` and `undoes` (the commit this one undid) appear when the commit has them. A server that has users records the one who made a commit as its `author`; the local server records none. `nextBefore`, present when there are earlier commits, goes in `?before=<depth>` to get the next page, which lists the commits numbered below it.

`GET /commits/<id>` says what one commit changed, row by row, in the tables of the ledger schema:

```json
{"commit": "413917e9-7ec9-404a-8f07-d3ea80447a0d", "depth": 12, "parent": "0c9f4a52-6f0e-4a8e-9d55-0f1f7ad1a0c3",
 "at": "2026-11-18T15:02:11.204Z", "message": "Recategorized the hosting charge",
 "changeCount": 1, "summary": {"line": {"update": 1}},
 "changes": [{"table": "line", "op": "update", "key": {"id": 41}, "old": {"account_id": 6}, "new": {"account_id": 9}}]}
```

`op` is `insert`, with the row as `new`; `delete`, with the row as `old`; or `update`, with the columns it changed as `old` and `new`. `key` is the row's primary key. Values are as `POST /query` gives them, except that a metadata value that is an object or an array is given as JSON. `parent` is the commit before it, to read the books just before this one with `?commit=`. `summary` counts the rows of each table the commit inserted, updated and deleted, and `changeCount` is their total. An answer holds up to 1,000 changes, and fewer when they come to more than 16 MiB; `nextAfter`, present when there are more, goes in `?after=<position>` to get the next ones.

### Undoing a commit: `POST /commits/<id>/undo`

```json
{"exobooksVersion": "0.18.0", "message": "Entered twice, as Ada pointed out", "dryRun": false}
```

Undoing a commit writes the inverse of its changes as a new commit, so nothing leaves the history, and an undo can itself be undone. `exobooksVersion`, `message` and `dryRun` work as they do on `POST /commit`, and the answer is a commit's, with `undid` the commit undone. A commit that changed nothing has nothing to undo: no commit is made and the answer has `"unchanged": true`.

An undo applies only if it can be done cleanly. Later commits may have changed other columns of a row this commit changed, but a row whose changed columns hold something else is a conflict, and so is any change that leaves the books breaking one of their rules. A conflict changes nothing and is answered 409, with up to 100 of them as `conflicts` in the error's `data`:

```json
{"error": {"message": "The commit can't be undone: what it changed has changed since", "data": {"conflicts": [
  {"table": "line", "key": {"id": 41}, "op": "update", "reason": "row-changed", "columns": ["account_id"]}
]}}}
```

`reason` says what stands in the way:

| `reason` | What it means |
|---|---|
| `row-changed` | The row's `columns` hold something other than what this commit wrote. |
| `row-gone` | A row this commit wrote no longer exists. |
| `row-exists` | A row now has the key of one this commit deleted. |
| `constraint` | The schema refuses the row, as `sqlite` says: a name that is taken now, for example. |
| `row-referenced` | The row in `table`, `rowid`, names a row of `references` that the undo would remove. |
| `line-on-placeholder`, `line-outside-account-dates` | A line would be on a placeholder account, or dated outside its account's opening and closing dates. |
| `account-under-itself` | An account would end up beneath itself. |
| `unique-value-shared` | Two rows would have the same value for the unique metadata key in `key`. |
| `transaction-without-lines` | A transaction would have no lines left. |
| `transaction-out-of-balance` | A transaction's lines would no longer sum to zero in each currency. |
| `account-closed-before-opened` | An account's closing date would come before its opening date. |
| `metadata-on-missing-row`, `tagging-on-missing-row` | Metadata or a tag remains on the row in `table` and `key`, which the undo would remove. |

To undo such a commit, first undo or change what stands in the way, usually the later commits, latest first.

### The export: `GET /export`

The realm's database, at the latest commit or at `?commit=<id>`, as an SQLite file (`application/vnd.sqlite3`) that any SQLite opens: every table above, everything in it. Keep it as a backup, or read it with your own tools.

Amounts in the file are bigdecs, which a plain SQLite can't do arithmetic on. To read one, decode its bytes: the single byte `80` (hex) is zero. Any other amount is ±0.d₁d₂…dₙ × 100^E, with base-100 digits dᵢ and the first and last not 0. Its first byte is `C0 + E` for a positive amount and `100 − (C0 + E)` (hex) for a negative one, and a byte follows for each digit: dᵢ for a positive amount; for a negative one, 99 − dᵢ for each digit but the last, and 100 − dₙ for the last. So `c1 0c 32` is 12.50, `3f 57 32` is −12.50, and `c2 18` is 2400.

## Links to the UI

exobooks has a UI in which a person reads the books, and you can link your user to a view of their books in it: the lines you aren't sure of, what your last commits changed, a statement for the quarter. Give a link where it saves your user reading a table you would otherwise paste. The guide says when.

`POST /ui`, with `{}`, gives the address to put a page's path after, `url`, and from a server whose UI asks your user to sign in, `signinUrl`, the same signed in, and `expiresAt`. The free local server's UI answers only its own machine and asks nobody to sign in:

```json
{"url": "http://127.0.0.1:8420/ui"}
```

A server that asks your user to sign in answers with all three:

```json
{"url": "https://books.example/ui/realms/<id>", "signinUrl": "https://books.example/ui/s/k3J9xQ2mP7aZ", "expiresAt": "..."}
```

A link is a page's path, from the table below, after `signinUrl` when the answer has one, and after `url` when it doesn't: `http://127.0.0.1:8420/ui/accounts/42/2026-10`, or `https://books.example/ui/s/k3J9xQ2mP7aZ/accounts/42/2026-10`. `signinUrl` signs your user's browser in, to read only, for about an hour after it was made, and any number of times in that hour, so make one link after another from it, but call `POST /ui` again for each reply of yours that has links, and never reuse an older one. The UI can't change the books: changes go through you.

Write a link from the paths below and nothing else: they are part of this API, and they go on working. Rows are named by their ids, never their names.

| Path | What it shows |
|---|---|
| `/commits/<n>` | What commit number `n` changed, `depth` in `GET /commits` and in a commit's answer. |
| `/changes/<n>..<m>` | What commits `n` to `m` changed, both included: what you did in a session, for your user to review. |
| `/transactions/<id>` | One transaction: its lines, its metadata, and the feed lines it was imported from. |
| `/accounts/<id>`, `/counterparties/<id>`, `/transactions/<id>,<id>,...`, `/ledgers/<id>/lines` | A list of lines: an account's (its sub-accounts' included), a counterparty's, some transactions', or a ledger's, followed by any of the filters below. |
| `/ledgers/<id>/accounts`, `/ledgers/<id>/income`, `/ledgers/<id>/balances` | The chart of accounts, the income statement and the balance sheet, followed by dates, then `months`, `quarters` or `years`, either or both: `/ledgers/1/income/2026/quarters`. |
| `/feeds/<id>` | A feed's lines, and with `/unimported`, `/imported` or `/excluded` after it, those alone. |

The filters of a list of lines follow its path, in any number, each once: dates as they are, `2026`, `2026-10`, `2026-10-05` or a range with both ends included, `2026-01..2026-03`, either end left out to leave it open; `over/<amount>` and `under/<amount>`, which compare a line's amount whatever its sign; `account/<id>` (its sub-accounts' included), `counterparty/<id>`, `tag/<name>` and `text/<words>`, which looks in memos, counterparties' names and accounts' paths; and `marked/<transaction id>,...`, which marks those transactions' lines among the rest. Percent-encode text: `text/web%20hosting`. So `/accounts/42/2026-10/over/1000/marked/317,318` is account 42's lines in October 2026 over 1,000, with transactions 317 and 318 marked.

Any of the paths after `/at/<n>`, `/at/12/ledgers/1/balances`, shows the books as they were at commit number `n`. Without it, a page shows the books as they are when your user opens it: what a list of lines still to categorize wants, while a review of a change wants the commit.
