## close

Prints a transaction that zeroes out one or more accounts, 
transferring their balances to some other account.

By default, it transfers revenues and expenses to `equity:retained earnings`.
This is traditionally done by businesses at the end of each accounting period.
In personal accounting and computer accounting, this is less necessary,
but it can help balance the accounting equation (A=L+E).

See also the `clopen` command.

_FLAGS

By default, this generates a transaction that zeroes out all accounts of type
Revenue (R) or Expense (X) (as declared with account directives or inferred
from account names), transferring their balances to `equity:retained earnings`.
This is called "retaining earnings" or "closing the books" in accounting.
<!--
it is typically done by businesses at the end of each accounting period,
to help satisfy the accounting equation A = L + E.
In personal accounting, many people don't bother with this.
-->

Or, you can use this command to zero out arbitrary accounts,
specified with query arguments, transferring their balances elsewhere.
You can change the destination account name with `--close-acct ACCT`.

The transaction description will be 'retain earnings' by default,
or 'transfer' if source accounts are specified.
You can change it with `--close-desc 'DESC'`.

Just one posting to the destination account will be used by default,
with an implicit amount.
With `--x/--explicit` the amount will be shown explicitly,
and if it involves multiple commodities, a separate posting
will be generated for each commodity.
With `--interleaved`, each destination posting is shown next to the 
corresponding source posting.

The default closing date is yesterday, or the journal's end date, whichever is later.
You can change this by specifying a [report end date](#report-start--end-date),
where "last day of the report period" will be the closing date.
Examples: `-e 2022` means "close on 2022-12-31".

### close and costs

With `--show-costs`, any amount costs are shown, with separate postings for each cost.
(This currently the best way to view investment assets, showing lots and cost bases.)
If you have many currency conversion or investment transactions, it can generate very large journal entries.

### close and balance assertions

Balance assertions will be generated, verifying that the source accounts have been reset to zero.
These provide useful error checking, but you can ignore them temporarily with `-I`,
or remove them if you prefer.

You probably should avoid filtering transactions by status or realness
(`-C`, `-R`, `status:`), or generating postings (`--auto`),
with this command, since the balance assertions would depend on these.

### close examples

Record 2022's revenues/expenses as retained earnings on 2022-12-31,
appending the generated transaction to the journal:
 
```shell
$ hledger close -f 2022.journal -p 2022 >> 2022.journal
```

Record retained earnings from the current year's first quarter:

```shell
$ hledger close -p Q1 >> $LEDGER_FILE
```

Now we can expect the first quarter's balance sheet to have a zero total,
indicating a balanced accounting equation
([unless](/investments.html#a-more-correct-entry) you are using @/@@ notation - in that case, try adding --infer-equity):

```shell
$ hledger bse -p Q1
...
====================++============
 Net:               ||          0 
```

To see the first quarter's income statement, we must suppress the retained earnings transaction.
(Note: filtering by transaction description here to exclude the whole transaction, not just the equity postings):

```shell
$ hledger is -p Q1 not:desc:retain
```
