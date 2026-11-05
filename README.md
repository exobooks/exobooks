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

**Status: early.** You can create ledgers, accounts and transactions, and read back the chart
of accounts. History is recorded with every commit, but reading it and backing changes out
are not in the API yet. Everything here will change; [CHANGELOG.md](CHANGELOG.md) says what
each release changed.

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
curl -fLO https://github.com/exobooks/exobooks/releases/download/v0.1.0/exobooks-0.1.0.jar
```

## 2. Start the server

```sh
java -jar exobooks-0.1.0.jar
```

This command does not return: the server runs until it is stopped. Start it as a background
process and leave it running while you work. It prints three lines:

```
exobooks 0.1.0
Created a new realm in /path/to/exobooks-data
Serving on http://127.0.0.1:8420
```

- The first line is the version of the jar, `major.minor.patch`, which is also in its file
  name.
- A *realm* is the database that holds all of your ledgers. The books are kept in a database
  in `exobooks-data`, in the directory the server was started from. Start it from the same
  directory later and it prints `Opened the realm in ..., 12 commits` instead. If it says
  `Created a new realm` when you expected existing books, it was started from the wrong
  directory.
- `--dir <directory>` keeps the books somewhere else; `--port <port>` changes the port.
- It listens on 127.0.0.1 only and has no authentication.

To check it is up:

```sh
curl -s http://127.0.0.1:8420/
```

```json
{"service":"exobooks-local","version":"0.1.0","realm":{"head":"20767cad-905f-4042-bd48-89cefd489560","depth":0}}
```

`depth` is the number of commits made so far.

## 3. How the books are organized

- A **ledger** is one set of books: a company, a person, a household. One server holds any
  number of ledgers.
- Each ledger has a tree of **accounts** under five roots that come with it: `Assets`,
  `Liabilities`, `Equity`, `Income` and `Expenses`. An account is named by its path from the
  root, joined with colons: `Assets:Checking`, `Expenses:Software:Hosting`. A name can't
  contain a colon.
- A **currency** is named by its code, such as `USD`. It has to be created before it is used.
- A **transaction** is a memo and two or more **lines**. A line puts an amount of one
  currency into one account on one date.
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

Put the body in a file and send the file, so the shell doesn't have to quote JSON:

```sh
curl -s -X POST http://127.0.0.1:8420/commit -H 'Content-Type: application/json' --data @request.json
```

An example `request.json` that sets up books and records two transactions:

```json
{
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
{"commit":"f147e20f-6f64-4a8e-9419-a50bcbfaa7a7","depth":1,"ids":{"books":1}}
```

### Mutation types

| `type` | Fields | What it does |
|---|---|---|
| `create_currency` | `code`; optionally `name` | Adds a currency. Refused if the code exists. |
| `create_ledger` | `name` | Adds a ledger and its five root accounts. |
| `create_account` | `ledgerId`, `parentFQN`, `name` | Adds an account under an existing one. Create a parent before its children. |
| `create_transaction` | `lines`; optionally `memo` | Adds a transaction. Refused unless its lines sum to zero in each currency. |

A line has `ledgerId`, `accountFQN`, `amount`, `currency` and `date`, and optionally `at` and
`memo`.

- **Amounts** are JSON strings holding a plain decimal, never JSON numbers: `"8500.00"`,
  `"-312.58"`.
- **`date`** is `YYYY-MM-DD`. **`at`**, when the exact time is known, is ISO 8601 with a
  zone: `"2026-07-14T09:30:00Z"`.
- **`currency`** is the code of a currency that exists.
- **`accountFQN`** and **`parentFQN`** are account paths within the ledger, as in section 3.
  The account has to exist.

### Tempids

A ledger is referred to by its numeric id, which exobooks assigns. Inside the request that
creates it, that id isn't known yet, so a mutation that creates something may give it a
temporary id, a *tempid*: `"id": "<any string>"`. Later mutations in the same request use
the tempid where an id goes, as `"books"` does above.

What tells the two apart is the JSON type. A string is always a tempid, and a real id is
always an integer: `"ledgerId": "books"` is the ledger this request is creating, and
`"ledgerId": 1` is the ledger whose id is 1.

A tempid lasts only for its request. The answer's `ids` maps each tempid to the integer id
that was assigned: in later requests, use the integer.

Because of tempids, a whole import can be one request: the currency, the ledger, every
account, then every transaction.

### Errors

A request that can't be applied changes nothing and is answered with status 400:

```json
{"error":"The lines don't balance: USD sums to 0.01","mutation":1}
```

`mutation` is the position in the list, counting from 0, of the one at fault. Fix it and send
the whole request again. Unknown mutation types and unknown fields are errors, so a
misspelled field is reported instead of ignored. A body not sent as `application/json` is
answered with status 415.

## 5. Reading: the chart of accounts

```sh
curl -s http://127.0.0.1:8420/ledgers/1/accounts
```

`1` is the ledger's numeric id: from the `ids` of the request that created it, if it was
given a tempid, or from the list of ledgers:

```sh
curl -s http://127.0.0.1:8420/ledgers
```

```json
{"ledgers":[{"id":1,"name":"Marlow Studio LLC"}]}
```

After the example request in section 4, the chart of accounts is this, shown here on several
lines:

```json
{"ledgerId": 1,
 "accounts": [
   {"fqn": "Assets", "totals": {"USD": "8187.42"}},
   {"fqn": "Assets:Checking", "totals": {"USD": "8187.42"}},
   {"fqn": "Liabilities", "totals": {}},
   {"fqn": "Equity", "totals": {}},
   {"fqn": "Income", "totals": {"USD": "-8500.00"}},
   {"fqn": "Income:Consulting", "totals": {"USD": "-8500.00"}},
   {"fqn": "Expenses", "totals": {"USD": "312.58"}},
   {"fqn": "Expenses:Software", "totals": {"USD": "312.58"}},
   {"fqn": "Expenses:Software:Hosting", "totals": {"USD": "312.58"}}
 ]}
```

- It lists every account of the ledger in tree order: each root, then its sub-accounts by
  name, a parent before its children.
- An account's `totals` include its sub-accounts: `Expenses:Software` shows the 312.58 that
  was recorded on `Expenses:Software:Hosting`. There is one amount per currency, and none for
  an account with no lines under it.
- Amounts are signed as they were written: positive is a debit.
- `?asOf=YYYY-MM-DD` counts only the lines dated on or before that day:
  `/ledgers/1/accounts?asOf=2026-07-20`.
- A ledger id that doesn't exist is answered with status 404.
