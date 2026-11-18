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
  the books as they were at any commit can be recovered, so a mistake can be audited and
  backed out.
- **Built for agents.** One call applies a whole batch of changes, hundreds of transactions
  at a time, all or nothing. A refused request says which change was wrong and why. JSON in
  and out, with exact decimal amounts.
- **Fast.** The database is local: a write is one call to localhost and a report is a SQLite
  query, with no rate limits and no network round trips.

**Status: early.** You can record and correct accounts, transactions, counterparties, metadata
and balance assertions, read the books with SQL as they are now or as they were at any earlier
commit, and export them as an SQLite file. Ledgers and currencies can't be changed or deleted
once made. Listing the history, reading a commit's message and backing a commit out are not in
the API yet. Everything here will change; [CHANGELOG.md](CHANGELOG.md) says what each release
changed.

**If you are an agent,** this file is the whole documentation. Work from its exact text, not
from a summary of the web page:

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
curl -fLO https://github.com/exobooks/exobooks/releases/download/v0.6.0/exobooks-0.6.0.jar
```

## 2. Start the server

```sh
java -jar exobooks-0.6.0.jar
```

This command does not return: the server runs until it is stopped. Start it as a background
process and leave it running while you work. It prints three lines on standard output (Java
may print notices of its own before them, on standard error):

```
exobooks 0.6.0
Created a new realm in /path/to/exobooks-data
Serving on http://127.0.0.1:8420, started in 563 ms
```

- The first line is the version of the jar, `major.minor.patch`, which is also in its file
  name.
- A *realm* is the database that holds all of your ledgers. The books are kept in a database
  in `exobooks-data`, in the directory the server was started from. Start it from the same
  directory later and it prints `Opened the realm in ..., 12 commits` instead. If it says
  `Created a new realm` when you expected existing books, it was started from the wrong
  directory.
- `--dir <directory>` keeps the books somewhere else; `--port <port>` changes the port.
- One server runs on a directory at a time. While it runs, its process id is in
  `exobooks-data/server.pid`; a second start on the same directory is refused and names that
  process.
- It listens on 127.0.0.1 only and has no authentication.
- Books made by a version with an earlier database schema are migrated when the server starts,
  while it answers. Until that is done, `realm` in the answer to `GET /` has `migrating`, and
  every other request except `POST /shutdown` is answered with status 503. Commit ids stay the
  same.
- Books made with exobooks 0.2.0 or earlier can't be opened: the server says so and exits with
  status 1. Start it on a new directory.

To check it is up:

```sh
curl -s http://127.0.0.1:8420/
```

```json
{"service":"exobooks-local","version":"0.6.0","realm":{"head":"f770c3cc-77ef-43da-93d3-653fe08a3055","depth":0},"exobooksVersion":"0.6.0"}
```

`head` is the id of the latest commit, and `depth` is the number of commits made so far. Every
JSON object the server answers carries `exobooksVersion`, the version that answered.

To stop it:

```sh
curl -s -X POST http://127.0.0.1:8420/shutdown -H 'Content-Type: application/json'
```

It answers `{"stopping":true,"exobooksVersion":"0.6.0"}` and exits. Ending the process with `kill` stops it cleanly too.

## 3. How the books are organized

- A **ledger** is one set of books: a company, a person, a household. One server holds any
  number of ledgers.
- Each ledger has a tree of **accounts** under five roots that come with it: `Assets`,
  `Liabilities`, `Equity`, `Income` and `Expenses`. An account is named by its path from the
  root, joined with colons: `Assets:Checking`, `Expenses:Software:Hosting`. A name can't
  contain a colon.
- A **currency** is named by its code, such as `USD`. It has to be created before it is used.
- A **transaction** is a memo and one or more **lines**. A line puts an amount of one
  currency into one account on one date, and may name a **counterparty** (a vendor, a customer,
  anyone on the other side). A transaction has no date of its own: each line has one.
- An account can be a *placeholder*, which holds sub-accounts but no lines, and can have an
  opening and a closing date, outside which it holds no lines.
- **Metadata** is key-value information on a row, such as the id a bank gave a transaction. A
  key is declared before it is used, and a key declared *unique* has at most one row with each
  value.
- A **balance assertion** says that an account, with its sub-accounts, held an amount of a
  currency at the end of a day. A commit that would contradict one is refused.
- **Positive is a debit, negative is a credit**, and the lines of a transaction must sum to
  zero in each currency. What the signs mean under each root:

| Root | A positive line | A negative line |
|---|---|---|
| `Assets` | money arriving (a deposit) | money leaving (a payment) |
| `Liabilities` | paying a debt down | borrowing, or charging a card |
| `Equity` | an owner taking money out | an owner putting money in |
| `Income` | giving a refund | earning income |
| `Expenses` | spending | getting a refund |

So a customer payment of 8,500.00 into checking is `+8500.00` on `Assets:Checking` and
`-8500.00` on an `Income` account, and a 312.58 hosting bill paid from checking is `-312.58`
on `Assets:Checking` and `+312.58` on an `Expenses` account. Balances of `Liabilities`,
`Equity` and `Income` accounts are therefore normally negative; a report for a person may
want to show them with the sign flipped.

## 4. Writing: `POST /commit`

Every change goes through one call. Its body is a JSON object with a list of mutations, sent
as `Content-Type: application/json`. The whole list is applied as one commit, in order, or
not at all.

| Field | |
|---|---|
| `exobooksVersion` | Required. The version of exobooks the request was written against: `"0.6.0"` for a request written from this file. |
| `mutations` | Required. The changes, a non-empty list. |
| `message` | Optional. What the commit is for and on whose authority. It is kept with the commit. |
| `dryRun` | Optional. `true` checks everything and answers as if it had committed, committing nothing. |

Put the body in a file and send the file, so the shell doesn't have to quote JSON:

```sh
curl -s -X POST http://127.0.0.1:8420/commit -H 'Content-Type: application/json' --data @request.json
```

An example `request.json` that sets up books and records two transactions:

```json
{
  "exobooksVersion": "0.6.0",
  "message": "Set up the books and record July's first two transactions",
  "mutations": [
    {"type": "create_currency", "code": "USD", "name": "US dollar"},
    {"type": "create_ledger", "id": "books", "name": "Marlow Studio LLC"},
    {"type": "create_account", "ledgerId": "books", "parentFQN": "Assets", "name": "Checking"},
    {"type": "create_account", "ledgerId": "books", "parentFQN": "Income", "name": "Consulting"},
    {"type": "create_account", "ledgerId": "books", "parentFQN": "Expenses", "name": "Software"},
    {"type": "create_account", "ledgerId": "books", "parentFQN": "Expenses:Software", "name": "Hosting"},
    {"type": "create_transaction", "memo": "ACH CREDIT NORTHWIND TRADING CO INV-1001", "lines": [
      {"ledgerId": "books", "accountFQN": "Assets:Checking", "amount": "8500.00", "currency": "USD", "date": "2026-07-14"},
      {"ledgerId": "books", "accountFQN": "Income:Consulting", "amount": "-8500.00", "currency": "USD", "date": "2026-07-14"}
    ]},
    {"type": "create_transaction", "memo": "AMAZON WEB SERVICES aws.amazon.com", "lines": [
      {"ledgerId": "books", "accountFQN": "Assets:Checking", "amount": "-312.58", "currency": "USD", "date": "2026-07-24"},
      {"ledgerId": "books", "accountFQN": "Expenses:Software:Hosting", "amount": "312.58", "currency": "USD", "date": "2026-07-24"}
    ]}
  ]
}
```

The answer:

```json
{"commit":"977d7524-daf5-4c0b-baff-e5c34291c518","depth":1,"ids":{"books":1},"skipped":[],"exobooksVersion":"0.6.0"}
```

`commit` is the new commit's id and `depth` its number in the history. `ids` and `skipped` are
explained under "Tempids" and "Sending a request again" below.

### Mutation types

A `?` marks an optional field.

| `type` | Fields |
|---|---|
| `create_currency` | `code`, `name`? |
| `create_ledger` | `name`, `metadata`?; also makes the five root accounts |
| `create_account` | `ledgerId`, `parentFQN` or `parentId`, `name`, `openedOn`?, `closedOn`?, `placeholder`?, `metadata`? |
| `update_account` | the account, and any of `name`, `parentFQN` or `parentId` (to move it), `openedOn`, `closedOn` (null clears), `placeholder` |
| `delete_account` | the account, which must have no lines, sub-accounts or balance assertions; close an account that has lines instead |
| `create_counterparty` | `name`, `metadata`? |
| `update_counterparty` | `counterpartyId`, `name` |
| `delete_counterparty` | `counterpartyId`, which no line may name |
| `create_transaction` | `lines`, `memo`?, `metadata`?; refused unless its lines sum to zero in each currency |
| `update_transaction` | `transactionId`, and `memo`, `lines`, or both |
| `update_line` | `lineId`, and any of the account, `date`, `at`, `memo`, `counterpartyId` (null clears the last three), `metadata` (sets the keys it gives; a null value deletes one) |
| `delete_transaction` | `transactionId` |
| `create_metadata_key` | `name`, `description`?, `unique`? |
| `update_metadata_key` | `name`, and `description`, `unique`, or both |
| `set_metadata` | `table` (`ledger`, `account`, `transaction`, `line`, `counterparty`, `currency` or `balanceAssertion`), `rowId`, `key`, `value` (null deletes) |
| `create_balance_assertion` | the account, `currency`, `date`, `amount`, `metadata`? |
| `delete_balance_assertion` | `balanceAssertionId` |

Any mutation that creates a row may also have `id`, a tempid, and every `create_*` mutation
takes `ifAbsent`.

An account is named by `accountId`, or by `ledgerId` and `accountFQN`, its path within the
ledger as in section 3. A parent account likewise by `parentId` or `parentFQN`. A currency is
named by its code.

A line of `create_transaction` has the account, `amount`, `currency` and `date`, and optionally
`at`, `memo`, `counterpartyId`, `metadata` and `id`. A line can't be on a placeholder, or dated
outside its account's opening and closing dates.

- **Amounts** are JSON strings holding a plain decimal, never JSON numbers: `"8500.00"`,
  `"-312.58"`.
- **`date`**, `openedOn` and `closedOn` are `YYYY-MM-DD`. **`at`**, when the exact time is
  known, is ISO 8601 with a zone: `"2026-07-14T09:30:00Z"`.
- **`currency`** is the code of a currency that exists.

`update_transaction`'s `lines` are all of the transaction's lines afterwards: an entry with
`lineId` keeps that line and changes the fields it gives, one without is a new line, and a line
of the transaction not listed is deleted. So splitting a line into several is one
`update_transaction`. `update_line` changes one line without its amount, which would unbalance
the transaction.

### Tempids

A row is referred to by its numeric id, which exobooks assigns. Inside the request that
creates it, that id isn't known yet, so a mutation that creates something may give it a
temporary id, a *tempid*: `"id": "<any string>"`. Later mutations in the same request use
the tempid where an id goes, as `"books"` does above. A transaction's lines can have tempids
too.

What tells the two apart is the JSON type. A string is always a tempid, and a real id is
always an integer: `"ledgerId": "books"` is the ledger this request is creating, and
`"ledgerId": 1` is the ledger whose id is 1.

A tempid lasts only for its request. The answer's `ids` maps each tempid to the integer id
that was assigned: in later requests, use the integer.

Because of tempids, a whole import can be one request: the currency, the ledger, every
account, then every transaction.

### Metadata

Metadata is set with `"metadata": {"key": value}` on whatever a mutation creates, each line
included, or with `set_metadata`. A key must be declared first, with `create_metadata_key`. A
value is a string, an integer, a number, a boolean (kept as 1 or 0), or an object or array
(kept as JSON).

### Sending a request again

`"ifAbsent": true` makes a create safe to send again: if the row it would create exists, it
does nothing, its tempids name the row that exists, and its position is listed in `skipped`.
The row that exists is the one its unique keys' values name, when its metadata gives a value
for a unique key. Otherwise it is the one with its natural key: a currency with its code, a
metadata key with its name, an account with its path in its ledger, a ledger or a counterparty
with its name, a balance assertion with its account, currency, date and amount. A natural key
that names more than one row is refused, and so is a metadata key that exists but differs in
being unique. A transaction has no natural key, so with `ifAbsent` it needs a value for a
unique key, in its metadata or a line's.

For a transaction, its own unique keys name the transaction and each line's name that line; a
key that names a row of another kind, or two lines that name the same line, are refused, and so
is a mix of keys of which some name rows and some don't. With `ifAbsent`, a line given a tempid
must carry a unique key, since that is what names the line when the request runs again.

This request can be sent any number of times and records the transaction once:

```json
{
  "exobooksVersion": "0.6.0",
  "message": "Import the bank's feed",
  "mutations": [
    {"type": "create_metadata_key", "name": "bank.id", "unique": true, "description": "The bank's id for a transaction", "ifAbsent": true},
    {"type": "create_counterparty", "id": "aws", "name": "Amazon Web Services", "ifAbsent": true},
    {"type": "create_transaction", "memo": "AMAZON WEB SERVICES aws.amazon.com", "ifAbsent": true, "metadata": {"bank.id": "txn_8Hq2"}, "lines": [
      {"ledgerId": 1, "accountFQN": "Assets:Checking", "amount": "-48.20", "currency": "USD", "date": "2026-07-28", "counterpartyId": "aws"},
      {"ledgerId": 1, "accountFQN": "Expenses:Software:Hosting", "amount": "48.20", "currency": "USD", "date": "2026-07-28", "counterpartyId": "aws"}
    ]}
  ]
}
```

The first time it makes a commit. The second time nothing changes, so no commit is made,
`commit` is the latest one, and the answer has `"unchanged": true`:

```json
{"commit":"25e56fe9-330b-4049-a131-e9301864bafc","depth":2,"unchanged":true,"ids":{"aws":1},"skipped":[0,1,2],"contextForAgents":["3 mutation(s) were skipped by ifAbsent, since the rows they would create exist, named by their unique metadata values or their natural keys; their tempids name those rows.","Nothing changed, so no commit was made; \"commit\" is the head."],"exobooksVersion":"0.6.0"}
```

### Balance assertions

After a commit's last mutation every balance assertion is checked: the lines of the account and
its sub-accounts dated on or before `date` must sum to `amount`. A commit that would break one
is refused, with status 400. To change the books under an assertion on purpose, delete the
assertion in the same commit.

```json
{"error":{"message":"The commit would break balance assertions","data":{"failingAssertions":[{"id":1,"account":"Assets:Checking","currency":"USD","date":"2026-07-31","amount":"8139.22","actual":"8140.22"}]}},"exobooksVersion":"0.6.0"}
```

### Errors

An error is answered with a JSON object holding `error`, an object with `message`, a sentence
saying what is wrong, and `data`, an object of the values it concerns. `data` is left out when
there are no values to give. A request that can't be applied changes nothing and is answered
with status 400:

```json
{"error":{"message":"The lines don't balance","data":{"currency":"USD","sum":"0.01","mutation":1}},"exobooksVersion":"0.6.0"}
```

`mutation` in `data` is the position in the list, counting from 0, of the one at fault, and
`line`, when it is one of a transaction's lines, is that line's position. Fix it and send the
whole request again. The fields named in this file are part of the API; the others, and the
sentences, may change. Unknown mutation types, fields and query parameters are errors, so a
misspelled one is reported instead of ignored. A body not sent as `application/json` is answered
with status 415.

A request without `exobooksVersion` is answered with status 400. One written against a version
that a later version has broken is answered with status 409 and changes nothing: read what has
changed, at the address in `data` as `changes`, and send the request again with `serverVersion`,
also in `data`, as its `exobooksVersion`.

Any answer, an error included, may carry `contextForAgents`: a list of short notes about what
the request may have got wrong, or what to know about the answer. Read them.

## 5. Reading

### The chart of accounts

```sh
curl -s http://127.0.0.1:8420/ledgers/1/accounts
```

`1` is the ledger's numeric id: from the `ids` of the request that created it, if it was
given a tempid, or from the list of ledgers:

```sh
curl -s http://127.0.0.1:8420/ledgers
```

```json
{"commit":"977d7524-daf5-4c0b-baff-e5c34291c518","ledgers":[{"id":1,"name":"Marlow Studio LLC"}],"exobooksVersion":"0.6.0"}
```

After the example request in section 4, the chart of accounts is this, shown here on several
lines:

```json
{"commit": "977d7524-daf5-4c0b-baff-e5c34291c518",
 "ledgerId": 1,
 "accounts": [
   {"fqn": "Assets", "id": 1, "parentId": null, "placeholder": false, "totals": {"USD": "8187.42"}},
   {"fqn": "Assets:Checking", "id": 6, "parentId": 1, "placeholder": false, "totals": {"USD": "8187.42"}},
   {"fqn": "Liabilities", "id": 2, "parentId": null, "placeholder": false, "totals": {}},
   {"fqn": "Equity", "id": 3, "parentId": null, "placeholder": false, "totals": {}},
   {"fqn": "Income", "id": 4, "parentId": null, "placeholder": false, "totals": {"USD": "-8500.00"}},
   {"fqn": "Income:Consulting", "id": 7, "parentId": 4, "placeholder": false, "totals": {"USD": "-8500.00"}},
   {"fqn": "Expenses", "id": 5, "parentId": null, "placeholder": false, "totals": {"USD": "312.58"}},
   {"fqn": "Expenses:Software", "id": 8, "parentId": 5, "placeholder": false, "totals": {"USD": "312.58"}},
   {"fqn": "Expenses:Software:Hosting", "id": 9, "parentId": 8, "placeholder": false, "totals": {"USD": "312.58"}}
 ],
 "exobooksVersion": "0.6.0"}
```

- It lists every account of the ledger in tree order: each root, then its sub-accounts by
  name, a parent before its children.
- An account's `totals` include its sub-accounts: `Expenses:Software` shows the 312.58 that
  was recorded on `Expenses:Software:Hosting`. There is one amount per currency, and none for
  an account with no lines under it.
- Amounts are signed as they were written: positive is a debit.
- An account with an opening or closing date also has `openedOn` or `closedOn`.
- `?asOf=YYYY-MM-DD` counts only the lines dated on or before that day:
  `/ledgers/1/accounts?asOf=2026-07-20`.
- A ledger id that doesn't exist is answered with status 404.

### Reading at an earlier commit

Every read answers with `commit`, the id of the commit it read: the latest, unless the
request names another with `?commit=<id>`. That reads the books as they were when that commit
was made, and it combines with `asOf`:

```sh
curl -s 'http://127.0.0.1:8420/ledgers?commit=f770c3cc-77ef-43da-93d3-653fe08a3055'
```

```json
{"commit":"f770c3cc-77ef-43da-93d3-653fe08a3055","ledgers":[],"exobooksVersion":"0.6.0"}
```

That is the commit the realm started at, before the example request, so it has no ledgers. A
commit id comes from the answer to `POST /commit`, from any read, or from `head` in `GET /`.
An id that isn't a commit's is answered with status 404.

### SQL: `POST /query`

Any other question is a query, in SQLite's dialect:

```sh
curl -s -X POST http://127.0.0.1:8420/query -H 'Content-Type: application/json' --data @query.json
```

```json
{"sql": "SELECT l.date, t.memo, l.amount FROM line l JOIN txn t ON t.id = l.txn_id JOIN account a ON a.id = l.account_id WHERE a.name = ? ORDER BY l.date", "params": ["Checking"]}
```

```json
{"commit":"25e56fe9-330b-4049-a131-e9301864bafc","columns":["date","memo","amount"],"rows":[["2026-07-14","ACH CREDIT NORTHWIND TRADING CO INV-1001","8500.00"],["2026-07-24","AMAZON WEB SERVICES aws.amazon.com","-312.58"],["2026-07-28","AMAZON WEB SERVICES aws.amazon.com","-48.20"]],"rowCount":3,"truncated":false,"exobooksVersion":"0.6.0"}
```

The body has `sql`, one statement that begins `SELECT`, `WITH`, `VALUES` or `EXPLAIN`, and
optionally `params`, bound to its `?` placeholders (strings, numbers, booleans as 1 or 0, null),
`commit`, to read at an earlier commit, and `exobooksVersion`, which works as it does on a
commit. Send `exobooksVersion` with a query you save, so that a later version that breaks the
query refuses it rather than answering something else.

`SELECT name, sql FROM sqlite_schema` lists the tables and their columns. No mutation writes the
tables `tag`, `tagging` and `line_conversion`, so they are empty. What to know:

- Name the columns you read. A new minor version can add columns to a table, which changes what
  `SELECT *` returns, and rows in an answer are arrays.
- A transaction's table is `txn`. A line has its own `date`; a transaction has none. Dates are
  `YYYY-MM-DD` text, so compare them with strings: `date <= '2025-12-31'`,
  `date LIKE '2025-03-%'`.
- `line.account_id` is the account itself. An account with its sub-accounts is a
  `WITH RECURSIVE` over `account.parent_id`.
- Amounts are kept in a binary form, a *bigdec*, that sorts the way the amounts do. In an answer,
  an amount column, or an unnamed `bigdec_sum(...)` and the like, comes back as decimal text
  (`"-12.50"`); an amount computed and named with `AS` comes back as a BLOB unless wrapped in
  `bigdec_text(...)`. `ORDER BY`, `min`, `max`, `=` and `GROUP BY` work on amounts as they are.
  `sum`, `total` and `avg` don't: use `bigdec_sum` and `bigdec_avg`. Compare an amount with
  another bigdec, writing a literal as `bigdec('100.00')`: `amount > 100` is always true, since
  SQLite orders every BLOB after every number. There are also `bigdec_abs`, `bigdec_neg`,
  `bigdec_add`, `bigdec_sub`, `bigdec_mul`, `bigdec_div` and `bigdec_round(x, n)`. A realm can
  hold several currencies, so sum per `currency_id`.
- Metadata is the table `metadata (table_id, row_id, key_id, value)`, with the keys in
  `metadata_key`. Table ids: 1 ledger, 2 account, 3 txn, 4 line, 5 counterparty, 7 currency,
  8 balance_assertion. Select `value` as it is, except a value written as an object or an array,
  which is kept as JSONB: select `json(value)` to read it as JSON, or `json_extract(value, '$.x')`
  for one field of it. Any other BLOB in an answer comes as `{"base64": ...}`.
- An error from SQLite is answered with status 400 and SQLite's message in `data` as `sqlite`.

The limits: the database can only be read; `ATTACH` is refused; a query running longer than 30
seconds is stopped and refused; no string or BLOB longer than 16 MiB may be made or read. An
answer holds at most 1,000,000 rows and 64 MiB of values, each value counted at the most its JSON
can take, so it may be cut somewhat early; when it is cut, `truncated` is true and a note says
what to do. At most 4 queries run at once; another waits up to 10 seconds, then is answered with
status 429.

### The export: `GET /export`

```sh
curl -s -o books.sqlite http://127.0.0.1:8420/export
```

The realm's database, at the latest commit or at `?commit=<id>`, as an SQLite file that any
SQLite opens: every table above, everything in it. Keep it as a backup, or read it with your own
tools.

Amounts in the file are bigdecs, which a plain SQLite can't do arithmetic on. To read one, decode
its bytes: the single byte `80` (hex) is zero. Any other amount is ±0.d₁d₂…dₙ × 100^E, with
base-100 digits dᵢ and the first and last not 0. Its first byte is `C0 + E` for a positive amount
and `100 − (C0 + E)` (hex) for a negative one, and a byte follows for each digit: dᵢ for a
positive amount; for a negative one, 99 − dᵢ for each digit but the last, and 100 − dₙ for the
last. So `c1 0c 32` is 12.50, `3f 57 32` is −12.50, and `c2 18` is 2400.
