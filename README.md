# AdPostingDB

A relational database managing advertisement postings on physical campus boards, implemented in parallel for **MS SQL Server** and **MySQL**. The system models a branching person specialization hierarchy (Person → CollegeMember → Student/Employee), an ad review workflow with reviewer eligibility rules, board capacity accounting based on physical dimensions, and per-ad messaging between posters and interested parties.

A full design writeup, covering the EER model, the supertype/subtype mapping decision, BCNF verification, and the cross-platform implementation notes, is available on my site: *mikeverwer.github.io/projects/ad_posting_db.html*.

This project originated as the final project of a database systems course in my Data Analytics diploma at Douglas College. The modeling, both implementations, and all queries are my own work.

## Repository layout

```
mssql/
  MSSQL_CREATE.sql    Schema DDL (T-SQL), including the INSTEAD OF DELETE trigger
  MSSQL_DROP.sql      Teardown script (T-SQL)
  MSSQL_INSERT.sql    Seed data (T-SQL, 25 people, 20+ ads, boards, postings, messages)
  MSSQL_QUERIES.sql   21 queries, views, and stored procedures (T-SQL)
mysql/
  MySQL_CREATE.sql    Schema DDL (MySQL), using native ON DELETE actions
  MySQL_DROP.sql      Teardown script (MySQL)
  MySQL_INSERT.sql    Seed data (MySQL, 25 people, 20+ ads, boards, postings, messages)
  MySQL_QUERIES.sql   The same 21 queries in MySQL dialect
docs/
  eer-diagram.png             EER model
  ad-posting-db-eer.drawio    EER model (draw.io blueprint)
README.md
```

## Setup

Run the scripts in order for your platform: `CREATE` first, then `INSERT`, then the queries file. `DROP` tears the tables back down.

The seed data in each `INSERT` file is the same between platforms.

## Design highlights

**Supertype/subtype person hierarchy.** People are modeled as a `Person` supertype with `CollegeMember`, `Student`, and `Employee` subtypes keyed on a shared `PersonID`. The employee type distinction is collapsed into `Employee` via a CHECK-constrained `PositionTitle` discriminator, since none of the subtypes carry enough distinct attributes to justify thier own tables.

**Integrity in the schema.** Enumerated CHECK constraints on ad type, ad status, and position title; positive-dimension checks; unique email and college ID; and a one-line constraint preventing anyone from reviewing their own ad. `Ad.ReviewerID` references `Employee` directly, so reviewer eligibility is structural. A paired CHECK constraint on `Ad` enforces that `PostDate` is set if and only if `AdStatus = 'Approved'`, closing a rule that was previously only guaranteed by application logic. `Employee.Extension` is similarly tied to `OfficeLocation` — an extension can't exist without a desk to attach it to.

**A documented engine divergence.** SQL Server disallows cascading delete actions on multiple foreign keys into the same table, which the `Messages` table (sender and recipient both referencing `Person`) requires. The MySQL implementation uses ordinary `ON DELETE CASCADE`; the SQL Server implementation resolves the limitation with an `INSTEAD OF DELETE` trigger on `Person` that scripts the cascade manually in dependency order. The header comments in each CREATE script catalogue this and the other cross-platform incompatibilities (batch separators, procedure syntax, error signaling, date function semantics). A related asymmetry appears in indexing: MySQL indexes foreign key columns automatically, while SQL Server does not, so the MSSQL script adds five explicit indexes covering every foreign key column not already covered by a primary key.

**Operational query layer.** Views and procedures cover the ad lifecycle end to end: board occupancy and remaining-space accounting (`BoardSpace`, `CheckAdFit`), the review workflow with validation and error signaling (`ReviewAd`, `AssignReviewer`, `PostAd`), derived-at-query-time expiry (`vw_ExpiredAds` plus cleanup), and reporting on messages, reviewer throughput, and poster demographics.

**Deliberate delete restrictions.** `Messages.AdID` → Ad uses `ON DELETE RESTRICT` in both engines, not `CASCADE`, so an ad can't be deleted while an active conversation still references it — preserving message history independent of the ad's own lifecycle.
