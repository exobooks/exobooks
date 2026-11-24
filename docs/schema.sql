-- exobooks ledger schema: the tables a realm's books are in, and what each
-- table and column means.
--
-- Written for exobase. Invariants the DDL does not state are in comments here,
-- enforced by the server.
-- Loads unchanged into plain sqlite3; run with PRAGMA foreign_keys = ON.
--
-- Conventions
--   ids        INTEGER PRIMARY KEY AUTOINCREMENT, unique per table, assigned
--              by the write path. A row named from another table is
--              (table_id, row_id), table ids below. Global ids rejected.
--              exobooks generates them; the user and agents never choose one.
--   name       a column named name is an identifier that the user or an agent
--              gives a row, always unique, so that a create with ifAbsent can
--              find the row it made by it. A hierarchical name is unique as a
--              path: an account's within its ledger (Assets:Checking), a tag's
--              within the realm. currency.code is such an identifier too.
--              Text that only labels or describes a row, and need not be
--              unique, is display_name or description.
--   booleans   INTEGER 0 or 1, column name prefixed is_.
--   instants   columns suffixed _at: INTEGER seconds since 1970-01-01T00:00:00Z,
--              no sub-second part, no zone (a point in time, like
--              java.time.Instant truncated to seconds). Convert with
--              unixepoch('2026-11-03T14:02:11-05:00') and
--              datetime(x, 'unixepoch').
--   dates      columns named date or suffixed _on: TEXT 'YYYY-MM-DD', a
--              calendar day with no time of day and no zone, four digits of
--              year so dates sort and compare as text. A prefix picks out a
--              month or a year: date LIKE '2024-03-%'. A report "as of" a date
--              D includes every line dated D: date <= D.
--   decimals   BLOB: a bigdec, a decimal of arbitrary precision and scale in
--              a binary encoding, never text. Columns: line.amount,
--              line_conversion.amount, feed_line.amount. Its bytes
--              sort the way the values do, so ORDER BY, min, max, =, GROUP BY
--              and indexes work on them as they are. The SQLite that exobase
--              bundles has bigdec_ functions for the rest: bigdec('-12.50')
--              for a literal, bigdec_text(x) to read one, bigdec_sum(x) for an
--              exact sum. A decimal column has CHECK (bigdec_valid(...)),
--              which marks it as one, and refuses anything else.
--              Sign: positive is a debit (beancount). Assets and expenses
--              increase with positive amounts; liabilities, equity and income
--              increase with negative amounts.
--   currency   a row of the currency table, by id, so the line table stays
--              small. Currencies and commodities are one thing.
--   memo       free text on a transaction and on a line; the same word for both.
--   metadata   not a column: the metadata table, indexed by key
--              and value; structured values are JSONB.
--   names      "ledger", not "entity", for a set of books. Table names
--              are singular.
--   foreign keys are declared.
--
-- Table ids, used wherever a row names a row of another table
-- (metadata.table_id, tagging.table_id), small integers because they are in
-- every row of those tables:
--   1 ledger   2 account   3 txn   4 line   5 counterparty   6 tag   7 currency
--   9 feed   10 feed_line
--   (line_conversion and line_feed_line rows are addressed through their line.)

-- A set of books: a company, a person, a household, a fund. The industry says
-- "entity"; we say ledger. One database, a realm, holds many
-- ledgers. No home currency: reports take their target currency as a
-- parameter, and an import keeps the source's home currency in metadata.
CREATE TABLE ledger (
  id   INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL
) STRICT;
CREATE UNIQUE INDEX ledger_name ON ledger (name);

-- Currencies and commodities: USD, EUR, NVDA, a kind of tire. A line
-- holds an amount of one of these; accounts hold any mix. Cost basis and lots
-- (beancount's {cost}) are not here yet.
CREATE TABLE currency (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  code        TEXT NOT NULL,                  -- 'USD', 'NVDA'; beancount's commodity name
  description TEXT                            -- 'US dollar', 'NVIDIA common stock'
) STRICT;
CREATE UNIQUE INDEX currency_code ON currency (code);

-- Chart of accounts. A tree per ledger: the five roots have parent_id NULL
-- and names Assets, Liabilities, Equity, Income, Expenses; everything else has
-- a parent in the same ledger. No account type: no field is privileged until
-- a feature needs it. No currency. Deleting an account that has lines
-- is an application error; it is closed instead, with a close date.
--   is_placeholder: may hold sub-accounts, never lines (GnuCash's word).
--   opened_on / closed_on: optional dates; the account's life runs from
--              opened_on through closed_on, both days included, unbounded on
--              a NULL side. A line is inside it by its date: a line dated on
--              the opening day or the closing day is inside.
CREATE TABLE account (
  id             INTEGER PRIMARY KEY AUTOINCREMENT,
  ledger_id      INTEGER NOT NULL REFERENCES ledger (id),
  parent_id      INTEGER REFERENCES account (id),   -- NULL only for the five roots
  name           TEXT NOT NULL,               -- one path segment; the path is derived
  is_placeholder INTEGER NOT NULL DEFAULT 0,
  opened_on      TEXT,
  closed_on      TEXT
) STRICT;
CREATE INDEX account_parent ON account (parent_id);
CREATE INDEX account_ledger ON account (ledger_id);
-- Sibling names unique; the same name may recur elsewhere in the tree.
-- NULL parent_id (roots) is not covered by a UNIQUE index in SQLite; the
-- application keeps the five roots unique per ledger.
CREATE UNIQUE INDEX account_sibling_name ON account (ledger_id, parent_id, name);

-- Vendors, customers, employees, banks: anyone on the other side of a line.
-- One record whichever direction the money goes. Shared across a
-- database's ledgers so a household and its companies can share one vendor.
-- Kind, address, etc. are metadata until a feature needs them; name is
-- privileged so the UI has something to show. Two counterparties with the
-- same everyday name are told apart in their names.
CREATE TABLE counterparty (
  id   INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL
) STRICT;
CREATE UNIQUE INDEX counterparty_name ON counterparty (name);

-- A transaction: the thing that ties lines together. Named txn
-- because TRANSACTION is an SQLite keyword. No date: every line has its own,
-- so a transfer settling on two days, or a depreciation schedule, is one
-- transaction. No ledger_id: a transaction belongs to the ledgers of its
-- lines' accounts, and may span two. No type: inferred
-- from the lines, or metadata.
-- Invariant (beancount's): the lines' weights sum to zero per currency, where
-- a line's weight is its amount in its currency, or its line_conversion
-- amount in that currency when it has one.
CREATE TABLE txn (
  id   INTEGER PRIMARY KEY AUTOINCREMENT,
  memo TEXT
) STRICT;

-- A line: one posting (beancount "posting", QuickBooks "split").
--   date:  the accounting date, always present, and the authority: reports,
--          balances and queries read it.
--   at:    the instant, when the source knew it (Mercury, Stripe, some Plaid
--          items). The date is never derived from it.
--   amount, currency_id: how much, of which currency or commodity. What
--          that was worth in another currency, when that matters, is
--          line_conversion.
--   counterparty_id: on the line, not the transaction, because QuickBooks puts
--          customers on lines, and vendors go there the same way.
CREATE TABLE line (
  id                INTEGER PRIMARY KEY AUTOINCREMENT,
  txn_id            INTEGER NOT NULL REFERENCES txn (id),
  account_id        INTEGER NOT NULL REFERENCES account (id),
  amount            BLOB NOT NULL CHECK (bigdec_valid(amount)),
  currency_id       INTEGER NOT NULL REFERENCES currency (id),
  date              TEXT NOT NULL,
  at                INTEGER,
  counterparty_id   INTEGER REFERENCES counterparty (id),
  memo              TEXT
) STRICT;
CREATE INDEX line_txn ON line (txn_id);
CREATE INDEX line_account_date ON line (account_id, date);
CREATE INDEX line_date ON line (date);
CREATE INDEX line_counterparty ON line (counterparty_id);

-- A line's value in another currency: the converted total, not a
-- per-unit rate, so it is exact ("these 3 EUR were 3.25 USD") and the balance
-- invariant is a plain sum. Beancount's "@" on a posting, stored as the total;
-- QuickBooks' home amount. One row per line that needs it,
-- in a side table so the line table stays compact and so cost basis (lot
-- date, label, cost versus price: beancount's "{...}") can join it later
-- without widening line.
--   amount: the same sign as the line's amount.
--   currency_id: the currency the line is being valued in.
CREATE TABLE line_conversion (
  line_id     INTEGER PRIMARY KEY REFERENCES line (id),
  amount      BLOB NOT NULL CHECK (bigdec_valid(amount)),
  currency_id INTEGER NOT NULL REFERENCES currency (id)
) STRICT;

-- Hierarchical tags: the one dimension mechanism. Replaces QuickBooks
-- class, department, location. Whether dimensions are separate roots of one
-- tree or a forest is data, not schema: the import makes 'Class' and
-- 'Department' two roots, is_placeholder set, their values beneath them. A
-- row may carry any number of tags for now.
CREATE TABLE tag (
  id             INTEGER PRIMARY KEY AUTOINCREMENT,
  parent_id      INTEGER REFERENCES tag (id),
  name           TEXT NOT NULL,
  is_placeholder INTEGER NOT NULL DEFAULT 0   -- groups tags, is never applied
) STRICT;
CREATE INDEX tag_parent ON tag (parent_id);
CREATE UNIQUE INDEX tag_sibling_name ON tag (parent_id, name);

-- A tag on anything: table_id is a table id (above), row_id the row.
CREATE TABLE tagging (
  tag_id   INTEGER NOT NULL REFERENCES tag (id),
  table_id INTEGER NOT NULL,
  row_id   INTEGER NOT NULL,
  PRIMARY KEY (tag_id, table_id, row_id)
) STRICT, WITHOUT ROWID;
CREATE INDEX tagging_row ON tagging (table_id, row_id);

-- Metadata keys: every user-defined key is declared once, so metadata
-- rows carry a small integer instead of the string, and agents can list what
-- keys exist and what they mean.
--   name:  the key as users and agents write it, e.g. 'qbo.id', 'plaid.pending'.
--          Dotted prefixes by convention name the module that owns the key.
-- No value type per key for now (values are any type); an exobooks notion of
-- value types, including values that name a row of a table, is not designed.
--   is_unique: no two rows have the same value for this key, so a value
--          names one row: an external id such as 'qbo.id' or 'mercury.id'.
--          Enforced by the write path.
CREATE TABLE metadata_key (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  name        TEXT NOT NULL,
  description TEXT,
  is_unique   INTEGER NOT NULL DEFAULT 0
) STRICT;
CREATE UNIQUE INDEX metadata_key_name ON metadata_key (name);

-- Metadata values: one value per key per row of any table,
-- single-valued by the primary key for now. A lookup by key and value
-- is an index probe, not a scan: "the line whose qbo.id is Purchase/42",
-- "lines where plaid.pending".
--   table_id / row_id: the row, by table id (above) and the row's id. Named
--          row_id, not rowid: the bare word is SQLite's implicit key.
--   value: ANY, so integers, reals and text are stored natively and compare
--          and sort as such in the index; booleans as 0 / 1 (SQLite has no
--          boolean); objects and arrays as JSONB (write with jsonb(?), read
--          with json() or json_extract()). Never NULL: absence is no row.
-- Where a row's whole source record goes: the import stores a QuickBooks
-- entity's JSON once, as 'qbo.record' on the txn, and its id as 'qbo.id' on
-- the txn and on each line ('Purchase/42', 'Purchase/42/Line/1'); that is
-- the idempotence key for re-import and for sync modules. A key declared
-- is_unique has one row per value, which the write path enforces.
CREATE TABLE metadata (
  table_id INTEGER NOT NULL,
  row_id   INTEGER NOT NULL,
  key_id   INTEGER NOT NULL REFERENCES metadata_key (id),
  value    ANY NOT NULL,
  PRIMARY KEY (table_id, row_id, key_id)
) STRICT, WITHOUT ROWID;
CREATE INDEX metadata_key_value ON metadata (key_id, value);

-- A feed: a source of transaction data for one account at a bank, a card or
-- anywhere else, whether it is fed continually (a Plaid connection) or once (a
-- CSV). Its records are feed lines, which an agent imports into the ledger as
-- lines of transactions.
--   display_name: what the feed is called, such as 'Checking CSV'; not unique,
--          so a unique metadata key names a feed, such as the source's id for it.
--   account_id: the ledger account the feed's lines are imported to, and so its
--          ledger; NULL until an agent associates one.
CREATE TABLE feed (
  id           INTEGER PRIMARY KEY AUTOINCREMENT,
  display_name TEXT NOT NULL,
  account_id   INTEGER REFERENCES account (id)
) STRICT;
CREATE INDEX feed_account ON feed (account_id);

-- One record from a feed, as its source gave it: what a bank calls a
-- transaction. Feed lines can be changed after they are written, as when a
-- pending charge posts, independently of the ledger lines imported from them.
--   amount: in the books' sign for the feed's account: positive is money into
--          a bank account, or a payment or refund onto a card.
--   record: the source's record, whole, as JSON text; a CSV's row as an object.
--   is_excluded: the agent decided not to import it, such as a duplicate or a
--          personal charge on a company card; note says why.
-- A feed line is imported while a line_feed_line row names it.
CREATE TABLE feed_line (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  feed_id     INTEGER NOT NULL REFERENCES feed (id),
  date        TEXT NOT NULL,
  amount      BLOB NOT NULL CHECK (bigdec_valid(amount)),
  currency_id INTEGER NOT NULL REFERENCES currency (id),
  memo        TEXT,
  record      TEXT CHECK (json_valid(record)),
  is_excluded INTEGER NOT NULL DEFAULT 0,
  note        TEXT
) STRICT;
CREATE INDEX feed_line_feed_date ON feed_line (feed_id, date);

-- Which ledger lines were imported from which feed lines. A feed line a ledger
-- line names can't be deleted; deleting the ledger line, or this row, makes
-- the feed line unimported again.
CREATE TABLE line_feed_line (
  line_id      INTEGER NOT NULL REFERENCES line (id),
  feed_line_id INTEGER NOT NULL REFERENCES feed_line (id),
  PRIMARY KEY (line_id, feed_line_id)
) STRICT, WITHOUT ROWID;
CREATE INDEX line_feed_line_feed_line ON line_feed_line (feed_line_id);
