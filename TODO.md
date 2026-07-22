# Query Modernization & Fixes Checklist

## CRITICAL — files will not run until these are fixed (do first)
- [x] **MySQL Q9 — `CREATE OR RESlot VIEW`** (line 229): a `Place`→`Slot` find/replace corrupted the keyword `REPLACE` into `RESlot`. Must be `CREATE OR REPLACE VIEW`. Hard syntax error — the view never gets created, which then cascades into Q21 and PostAd both failing (they depend on `vw_ExpiredAds`).
- [x] **MSSQL Q19 — broken/incomplete test call**: the file ends the PostAd section with `BEGIN TRANSACTION;\n    EXEC PostAd()` — no arguments, no closing `ROLLBACK`, no semicolon. This is a syntax error and also leaves an unclosed transaction. Replace with the real approve-then-post test (`BEGIN TRAN; EXEC ReviewAd 16...; EXEC PostAd @_AdID=16, @_Bldg='LIB', @_Floor=1, @_Slot='A'; ROLLBACK;`).

## Cross-file divergences to reconcile (medium)
- [x] **MySQL Q9 boundary vs MSSQL**: confirm both use `>= 0` (both currently do — just verify after fixing the RESlot typo doesn't get reverted).
- [x] **MSSQL Q10 uses `COUNT(CASE...)`, MySQL uses `SUM(CASE...)`**: functionally equivalent, but pick one idiom for parity. (Note: MySQL's `SUM(CASE WHEN...THEN 1 END)` omits `ELSE 0`, so a reviewer with only approvals returns `NULL` for RejectedCount instead of 0 — worth an `ELSE 0` regardless.)
- [x] **`GetPosterInfo` column order differs** between files (MSSQL: Title/AdType before the member flags; MySQL: AdID/Title before flags, AdType last). Align for a clean side-by-side.
- [x] **MySQL still has the leftover `-- DROP PROCEDURE ReviewAd;` comment** (line 407) and a bare `SELECT * FROM Ad WHERE AdID = 16;` verification line (412) with no MSSQL equivalent. Decide whether both files carry these debug lines or neither.

## Correctness fixes (structural, medium)
- [x] **`AdsByUserType` five-category collapse** (Q14, both files): Administration/Support/Specialized all mislabeled `'Staff'`. Surface real `PositionTitle` or rename bucket. Needs a decision first.
- [x] **Q10 `INNER JOIN` → `LEFT JOIN`** (both files): reviewers with zero approvals/rejections currently vanish from the report; decide how deleted reviewers surface too.
- [x] **`PostAd` race protection** (both files): `WITH (UPDLOCK, HOLDLOCK)` / `FOR UPDATE` on the validation reads, closing the check-then-act gap. (You flagged this for the modernization pass specifically.)

## Technique modernization (the "how I'd write these now" pass)
- [x] **Q3 — sent/received counts**: two subquery joins → single-pass CTE with conditional aggregation, or `UNION ALL` + `GROUP BY`. The flagship example.
- [x] **Q7 — largest ad by area**: self-join-via-`MAX`-subquery → `RANK() OVER (ORDER BY area DESC)` in a CTE; handles ties natively.
- [x] **Q1 — messages per ad**: correlated scalar subquery → `LEFT JOIN ... GROUP BY` or windowed count.
- [x] **Q11 — approved-but-not-posted**: `NOT IN` subquery → `NOT EXISTS` or anti-join (`LEFT JOIN ... WHERE ... IS NULL`); safer against NULLs and often clearer.

## SELECT → stored-procedure conversions (judgment, larger)
- [ ] Decide which standalone queries become parameterized procedures vs. stay ad-hoc. This decision sets the views/procedures file boundary for the eventual file split.
- [x] **New: `GetReviewerInfo`** mirroring `GetPosterInfo`, surfacing `OfficeLocation`/`Extension` — the last open justification for keeping those columns.

## Consistency / docs (do last, or alongside the file split)
- [ ] Rewrite both `QUERIES` header comment blocks to be engine-perspective-specific, matching the `CREATE` files' polish (currently identical generic boilerplate).
- [ ] MSSQL cosmetic sweep: `differece` typo (line ~33 — note MySQL's copy is already correct), lowercase `Go` before Q14, missing trailing semicolons on `SELECT * FROM Board` (Q5) and the `EXEC ReviewAd`/`EXEC AssignReviewer` test lines.
- [ ] **MySQL Q2**: stray blank line inside the `SELECT` (harmless, cosmetic) — actually that's MSSQL; verify which file. MySQL Q2 is clean.