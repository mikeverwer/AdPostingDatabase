# AdPostingDB

A relational database managing advertisement postings on physical campus boards, implemented in parallel for **MS SQL Server** and **MySQL**. The system models a branching person specialization hierarchy (Person → CollegeMember → Student/Employee), an ad review workflow with reviewer eligibility rules, board capacity accounting based on physical dimensions, and per-ad messaging between posters and interested parties.

A full design writeup, covering the EER model, the supertype/subtype mapping decision, BCNF verification, cross-platform implementation notes, and description of views, procedures, and workflows, is available on my site: *mikeverwer.github.io/projects/ad_posting_db.html*.

This project originated as the final project of a database systems course in my Data Analytics diploma at Douglas College but has since greatly expanded. The modeling, both implementations, and all queries are my own work.

## Repository layout

```
mssql/
  MSSQL_CREATE.sql      Schema DDL (T-SQL), including the INSTEAD OF DELETE trigger
  MSSQL_DROP.sql        Teardown script (T-SQL)
  MSSQL_VIEWS.sql       Views (T-SQL)
  MSSQL_PROCEDURES.sql  Stored procedures (T-SQL)
  MSSQL_TESTS.sql       Procedure and constraint tests (T-SQL)
  MSSQL_INSERT.sql      Seed data (T-SQL)
mysql/
  MySQL_CREATE.sql      Schema DDL (MySQL), using native ON DELETE actions
  MySQL_DROP.sql        Teardown script (MySQL)
  MySQL_VIEWS.sql       Views (MySQL)
  MySQL_PROCEDURES.sql  Stored procedures (MySQL)
  MySQL_TESTS.sql       Procedure and constraint tests (MySQL)
  MySQL_INSERT.sql      Seed data (MySQL)
docs/
  eer-diagram.png             EER model
  ad-posting-db-eer.drawio    EER model (draw.io blueprint)
  Procedures.md               A list of all procedures with explanatory comments and signatures
  Views.md                    A list of all views with displayed column names
shift_seed_dates.py     Normalizes seed data dates to the current day (or a supplied date)
README.md
```

Both engines share five categories, in the same fixed order, across the VIEWS, PROCEDURES, and TESTS files: Person & Roles, Ad Lifecycle & Review, Board & Posting, Messaging, Lookups & Search. A category with nothing to add still carries a stub header, so the files stay positionally parallel across engines and across the view/procedure/test split.

## Setup

Run the scripts in order for your platform: `CREATE`, then `INSERT`, then `VIEWS`, then `PROCEDURES`. `TESTS` is optional and exercises the procedures and constraints directly against the loaded schema. `DROP` tears the tables and database back down.

The seed data carries an anchor date and is meant to sit near the present. Before loading `INSERT`, run `scripts/shift_seed_dates.py` to slide every date and timestamp in the seed files forward or back to the current date (or a date supplied with `--to`). The shift is uniform across all dates in a file, so the relative spacing between them, and the invariants the seed data was built around (review dates preceding post dates, a mix of expired and active postings, message chronology within a conversation) all hold after the shift. The script updates both engines' seed files together and compares them, since letting the two drift apart is the main way this kind of shared fixture breaks.

## Design highlights

**Supertype/subtype person hierarchy.** People are modeled as a `Person` supertype with `CollegeMember`, `Student`, and `Employee` subtypes keyed on a shared `PersonID`. Dual Student/Employee status is left unconstrained, since a person can hold both roles at once (a graduate teaching assistant, for instance). The employee position hierarchy collapses into a single `Employee` table with a CHECK-constrained `PositionTitle` discriminator, since the position types don't carry enough distinct attributes to justify separate tables.

**History preservation is default.** Most date fields on `Ad` record when something happened and stay put: `EnteredPending` never clears, `ReviewDate` stamps once per review decision and is retained through later status changes, and `ReviewerID` survives a reviewer's later removal from the `Employee` table. The one exception is `PostDate`, which is a live invariant enforced by a CHECK constraint (`PostDate IS NULL OR ReviewStatus = 'Approved'`) rather than a historical record: it marks when the current posting period began, and an unpost/repost resets it.

**Paired CHECK constraints for trustworthy nullable dates.** `ReviewDate` and `WithdrawnDate` are each governed by two symmetric CHECK constraints tying the date's nullability to a corresponding status column, so the column is null if and only if the record is in the corresponding state. `PostDate`'s constraint is deliberately one-directional, since an approved ad isn't necessarily posted.

**Withdrawal as an orthogonal flag rather than a status overwrite.** `IsWithdrawn` sits alongside `ReviewStatus` rather than being folded in. Review status, physical board posting, and withdrawal all vary independently, so an ad can be approved, withdrawn, and still occupying a board slot at the same time. Folding withdrawal into `ReviewStatus` would erase a reviewer's original decision and let a poster's rejected ad disappear from reporting that depends on that history.

**Three distinct deletion operations for ads.** `WithdrawAd` sets a flag and purges messages but leaves the ad's record and review history intact. `UnpostAd` is a physical removal from a board, independent of review status or withdrawal. `DeleteAd` is a permanent, reviewer-authorized removal, distinct from anything a poster can trigger. Ads are retained indefinitely by default; the reporting procedures and views that track rejection and withdrawal history depend on that persistence. `WithdrawAd` is a user request for an ad to be taken down while `UnpostAd` and `DeleteAd` are designed to be admin operations, although currently only `DeleteAd` has structured authorization.

**Locking scoped to genuine races, not merely to error conditions.** `PostAd`, `ReviewAd`, `WithdrawAd`, and `RetireBoard` take explicit row locks; each guards a race where two individually valid operations combine into a corrupted state, not merely a race that would surface as an error. `RetireBoard` is the clearest case: `ON DELETE CASCADE` on a board's removal would silently delete a newly posted ad if the two operations interleaved without a lock, with no constraint anywhere to catch it.

**Images stored as a path, not a blob.** `Ad.ImageFileName` records a filename rather than binary image data, which is standard practice for a web front end backed by this schema and avoids the backup and buffer-pool costs of storing images in the database itself.

**A documented engine divergence.** SQL Server disallows cascading delete actions on multiple foreign keys into the same table, which the `Messages` table (sender and recipient both referencing `Person`) and the `Ad` table (poster and reviewer both referencing `Person`) both require. The MySQL implementation uses ordinary `ON DELETE CASCADE`; the SQL Server implementation resolves the limitation with an `INSTEAD OF DELETE` trigger on `Person` that scripts the cascade manually in dependency order. The header comments in each CREATE script catalogue this and the other cross-platform incompatibilities (batch separators, procedure syntax, error signaling, date function semantics). A related asymmetry appears in indexing: MySQL indexes foreign key columns automatically, while SQL Server does not, so the MSSQL script adds explicit indexes covering every foreign key column not already covered by a primary key or unique constraint.

**Operational query layer.** Views and procedures cover the ad lifecycle end to end: board occupancy and remaining-space accounting (`vw_BoardSpace`, `CheckAdFit`), the review workflow (`ReviewAd`, `PostAd`, `UnpostAd`), derived-at-query-time expiry and takedown worklists (`vw_ExpiredAds`, `vw_PendingPosting`, `vw_PendingRemoval`), and reporting on messages, reviewer throughput, and poster demographics.

**Deliberate delete restriction on messages.** `Messages.AdID` references `Ad` with no cascading action in either engine, so an ad can't be deleted while messages still reference it. `WithdrawAd` and `DeleteAd` each purge an ad's messages explicitly before the ad itself is removed, keeping message deletion a deliberate step rather than a side effect of deleting the ad.

## Testing

Every stored procedure has a pass case and a fail case exercised in the TESTS file for its engine. Mutating tests run inside a transaction with a rollback at the end, with a select statement placed inside the transaction so the change is visible before it's undone. A test expecting failure treats the raised error as the pass condition. All tests have been run and verified directly against both SQL Server and MySQL.

## Known limitations

- Ad content can't be edited after submission; the workaround is to withdraw and resubmit.
- `Board`'s primary key is its physical location (building, floor, slot), which is mutable. A surrogate key would remove this, but the change touches enough other objects that it hasn't been made.
- `SearchAdsByTitle` treats a literal `%` or `_` in the search term as a wildcard, since it performs a partial free-text match.