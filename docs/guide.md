# Keeping books with exobooks

How to do bookkeeping well with exobooks: how it is meant to be used, recipes for common work, and how to work with particular banks. The API documentation says what each call does, and you can rely on it. This guide is advice: how to use the calls well. When you have a good reason to work differently, do. Before you start a task this guide has a part on, such as importing from a user's bank, read that part.

## Showing your user the books

You can link your user to pages of exobooks' UI (the API documentation, under "Links to the UI"). Link where your user would otherwise read a table you pasted, or take your word for what you did:

- After commits your user should check, link to what they changed, `/changes/<n>..<m>`, rather than describing each change.
- When you ask your user about some transactions, link to them, `/transactions/<id>,<id>`, or mark them among their account's lines, `/accounts/<id>/<dates>/marked/<id>,<id>`, so that your user sees them beside what came before and after.
- When you report a figure, link to the lines or the statement behind it, so that your user can check it.

## Banks

### Mercury

What this part says of Mercury's API was last checked against Mercury on 2026-11-24.

**If your user banks at Mercury, read Mercury's own API, not Mercury through Plaid.** Mercury's API has everything Plaid gives for a Mercury account except Plaid's categories, and much that Plaid's format drops:

- **Who made each card charge.** Each card transaction has the `cardId` of the card it was made on, and `GET /cards` gives each card's holder (`nameOnCard`). Plaid gives one account for all of a company's cards, and no card or cardholder on any transaction. Mercury's statements show only each card's last four digits, so the API is the only place the cardholder's name appears.
- **Failed payments.** A payment that posted and was then returned is one transaction in Mercury's API, with `status` `failed` and both `postedAt` and `failedAt`. Through Plaid, such a payment has been seen to arrive as its return alone, without the debit it reverses. That is income that never happened, and an account that won't reconcile to its statement.
- **The kind of each transaction.** `kind` says whether it was a card charge, an ACH, a wire, a check or a transfer between the user's own accounts.
- **Mercury's ids.** A transaction's `id` is Mercury's own. Plaid's ids are Plaid's, and change when the user's login is connected to Plaid again.
- **The user's notes and receipts.** These are `note`, `externalMemo` and `attachments`.
- **Statements that say which transactions they cover.** Each statement gives its period, its ending balance, and the ids of the transactions on it (below, under "Statements").

Plaid's copy of a Mercury account keeps the dates and the times to the second, and the description and counterparty, so a Plaid feed is usable when there's nothing better. But it can't be imported blindly.

#### Getting access

Mercury's API is reached with a token that the user creates in Mercury's dashboard, one for each Mercury organization, since each organization is a separate login. Ask the user to create one:

1. Log in to Mercury as the organization.
2. Go to Settings, then API Tokens, and choose "Create an API token". Only an admin of the organization sees this option.
3. Choose **Read Only**. A read-only token can read everything an import needs, and can't move money. Never ask for a read-and-write token for bookkeeping.
4. Copy the token at once: Mercury shows it only once.

Keep the token where the user wants their secrets kept, such as a file only they can read, and never write it into the books or a log. Send it as `Authorization: Bearer <token>` to `https://api.mercury.com/api/v1/...`. A read-only token needs no IP allowlist. Mercury deletes a token that hasn't been used in 45 days, after emailing the organization's admins a week before. Books kept up monthly use it often enough. If one has been deleted, ask for a new one.

Mercury's MCP server (`https://mcp.mercury.com/mcp`) is another way in, if your environment can connect to it, with its `read` scope. It suits looking things up. For importing hundreds of transactions, the REST API is better: what it returns goes straight into your requests to exobooks, not through your context.

#### Accounts and feeds

Mercury lists an organization's accounts at three addresses, each with its own transactions:

| Accounts | List | Transactions |
|---|---|---|
| Checking and savings | `GET /accounts` | `GET /account/{id}/transactions` |
| The IO card account (all of the company's cards) | `GET /credit` | `GET /account/{id}/transactions` |
| Treasury | `GET /treasury` | `GET /treasury/{id}/transactions`, in a shape of its own |

Make one feed for each Mercury account, with Mercury's account id under a unique key, so that the next import finds it again with `ifAbsent`. Associate the feed with its ledger account with `update_feed`, once you know which account it is:

```json
{"exobooksVersion": "0.18.0", "mutations": [
  {"type": "create_currency", "code": "USD", "description": "US dollar", "ifAbsent": true},
  {"type": "create_metadata_key", "name": "mercury.accountId", "unique": true, "description": "Mercury's id for the account a feed is of", "ifAbsent": true},
  {"type": "create_metadata_key", "name": "mercury.transactionId", "unique": true, "description": "Mercury's id for the transaction a feed line is, or for its return", "ifAbsent": true},
  {"type": "create_metadata_key", "name": "mercury.cardholder", "description": "Who holds the Mercury card a charge was made on", "ifAbsent": true},
  {"type": "create_feed", "id": "checking", "displayName": "Mercury Checking ••4417", "ifAbsent": true,
   "metadata": {"mercury.accountId": "5b3e1f2a-0000-4c1d-9e8f-123456789abc"}}
]}
```

#### Importing transactions as feed lines

Read each account's transactions with `GET /account/{id}/transactions?start=YYYY-MM-DD&limit=500&offset=<n>`, and page with `offset` until a page has fewer than 500. Always give `start`: without it, Mercury gives only the last 30 days. For a first import, give the first day of the period the books are to cover. Write each transaction Mercury has posted as a feed line:

- **`date`** is the date of `postedAt`, in UTC. Mercury's statements run from midnight to midnight UTC, so a line dated this way falls in the statement that lists it.
- **`amount`** is Mercury's `amount` as it is. Mercury's sign is already the books' sign, for the card account as for checking: positive for money into a bank account, negative for a charge on a card, and positive for a payment to the card.
- **`memo`** is `counterpartyName`, with `bankDescription` after it if it says more.
- **`record`** is Mercury's transaction whole.
- **`metadata`** has `mercury.transactionId`, the transaction's `id`, so that the import can be run again safely with `ifAbsent`. For a card charge, also give `mercury.cardholder`, the `nameOnCard` of the card whose `id` is the transaction's `cardId`, from `GET /cards`.

Which transactions become feed lines, by `status`:

| `status` | What to write |
|---|---|
| `sent` | One feed line. |
| `pending` | Nothing yet: its amount can change before it posts. The import after it posts writes it. |
| `failed`, with a `postedAt` | Two feed lines, since the bank's statement has both: the debit, dated at `postedAt`, with the transaction's `id`; and its return, dated at `failedAt`, with the opposite amount and `<id>:return` as its `mercury.transactionId`. They sum to zero. |
| `failed` with no `postedAt`, `cancelled`, `blocked` | Nothing: the money never moved. A declined card charge is one of these. |
| `reversed` | Not yet seen. Check the statement before writing it. |

When you import a feed line into the books, give the ledger line `at`, the time the line is dated by, as well as the date: Mercury's `postedAt`, or `failedAt` for a return.

To bring an account up to date later, read again from a week before the start of the first statement period you haven't reconciled, and write with `ifAbsent`, so that what's already there is skipped. The week is there because Mercury doesn't say which of a transaction's dates `start` filters on, and a charge made at the end of one period can post in the next. A payment can fail weeks after it posted, when it is out of that range, so also read `GET /account/{id}/transactions?status=failed&start=<the first day of the books>`, and write the return of each one that has a `postedAt`, with `ifAbsent`: a return already written is skipped.

The treasury account's transactions have `id`, `amount`, `balance`, `description`, `type` and `canonicalDay`. Use `canonicalDay` as the date. Before relying on the sign of its amounts, check it against the account's balance.

#### Statements

`GET /account/{id}/statements?start=YYYY-MM-DD&end=YYYY-MM-DD` gives a checking or savings account's monthly statements, for at most three months a call:

- `startDate` and `endDate`, in UTC.
- `endingBalance`.
- `transactions`, the ids of the transactions the statement covers.
- `downloadUrl` (or `GET /statements/{id}/pdf`), the PDF, which is the document the bank issued.

So which feed lines a statement covers is not a guess: they are the lines dated within its period, and the ids it lists let you check them, transaction by transaction. A failed payment's debit belongs to the statement whose period has its `postedAt`, and its return to the one whose period has its `failedAt`. Usually that is one statement, which lists the payment once and counts both lines. When the return falls in the next period, the debit counts in one statement and the return in the next, and Mercury doesn't say whether the next lists the payment's id too. The amounts of the lines a statement covers, added to the previous statement's ending balance, give this one's.

The card account's statements are at `GET /credit/{id}/statements`, with the same fields, its starting balance as well (`details.accountDetails.startingBalance`), and what is owed as a negative balance. It gives at most 100 statements a call (`limit`), newest first, and `page.nextPage` leads to the next page. If it doesn't answer for the user's token, ask the user for the card's statements from Mercury's dashboard. The treasury account's statements are on neither endpoint.

#### If the user also has a Plaid connection to Mercury

This applies to any feed of a Mercury account that came from Plaid, whoever wrote it. Don't import both: the same transactions would come twice, with different ids. If a Plaid feed of a Mercury account already has imported lines, match them to Mercury's transactions by amount and Plaid's `datetime`, which equals Mercury's `postedAt` to the second. If the user wants to stay on Plaid, look for credits that reverse a debit the feed doesn't have, and check each feed's lines against the balance Plaid reports.
