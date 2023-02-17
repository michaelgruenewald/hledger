## tags

List the tags used in the journal, or their values.

<!-- same section name as Journal > Tags, if reordering these update all #tags[-1] links -->

_FLAGS

This command lists the tag names used in the journal,
whether on transactions, postings, or account declarations.

With a TAGREGEX argument, only tag names matching this regular expression
(case insensitive, infix matched) are shown.

With QUERY arguments, only transactions and accounts matching this query are considered.
If the query involves transaction fields (date:, desc:, amt:, ...),
the search is restricted to the matched transactions and their accounts.

With the --values flag, the tags' unique non-empty values are listed instead.
With -E/--empty, blank/empty values are also shown.

With --parsed, tags or values are shown in the order they were parsed, with duplicates included.
(Except, tags from account declarations are always shown first.)

Tip: remember,
accounts also acquire tags from their parents,
postings also acquire tags from their account and transaction,
transactions also acquire tags from their postings.
