## Views

### Person & Roles
Views over people and the roles they hold. No views currently live here; all person and role logic is procedural (see Procedures.md).

### Ad Lifecycle & Review
Views covering an ad from submission through review decision and expiry: the pending review queue, expiry tracking, reviewer throughput, and the breakdown of ads by the type of user who posted them.

vw_ExpiredAds
: Find all ads that are past duration.
: Columns:
  ```
  AdID
  PostDate
  Duration
  DaysOverdue
  ```

vw_ReviewQueue
: View for the review queue.
: Columns:
  ```
  QueuePosition
  AdID
  PosterName
  Title
  AdType
  AdLength
  AdWidth
  Duration
  ImageFileName
  ```

vw_ReviewCountsPerReviewer
: Display counts of ads rejected and ads approved for each reviewer. Reviews performed by a since-deleted reviewer (ReviewerID cleared to NULL by RevokeEmployeeRole) are preserved under a single 'Deleted Reviewer(s)' row rather than being dropped from the totals.
: Columns:
  ```
  PersonID
  ReviewerName
  ApprovedCount
  RejectedCount
  TotalReviews
  ```

AdsByUserType
: Classify every ad by the type of user who posted it. A poster may hold several roles at once, so the CASE is ordered by specificity: Student wins over Employee, which wins over an unspecialized College Member.
: Columns:
  ```
  AdID
  PosterID
  AdType
  UserType
  ```

vw_AdsByUserTypeAndAdType
: Pivot table of ads by user type x ad type. ROLLUP adds a grand-total row, labelled 'Total' where the grouping column comes back NULL.
: Columns:
  ```
  UserType
  Tutorship
  Rent
  Sale
  Roommate
  Event
  RowTotal
  ```

### Board & Posting
Views describing the physical boards and what is currently posted to them: the posting join itself, per-board space accounting, and the two exception lists (approved-but-unposted, and posted-but-require-removal).

Order matters here. vw_PostedAdsInfo must be created first; vw_BoardSpace and vw_PendingRemoval read from it, and vw_BoardSpaceDisplay reads from vw_BoardSpace.

vw_PostedAdsInfo
: View of all ads posted to each board, joining posting location to the full ad record. This is the base view for the rest of this category.
: Columns:
  ```
  Building
  BldgFloor
  Slot
  AdID
  Title
  AdType
  PosterID
  ReviewerID
  ReviewStatus
  ReviewDate
  PostDate
  Duration
  AdWidth
  AdLength
  IsWithdrawn
  WithdrawnDate
  ImageFileName
  ```

vw_BoardSpace
: View to list board occupancy details: number of posted ads, board size, total ad sizes, and remaining board space. RIGHT JOIN so that empty boards still appear, with zeroed ad totals.
: Columns:
  ```
  Building
  BldgFloor
  Slot
  NumAds
  BoardWidth
  BoardLength
  BoardArea
  TotalAdArea
  RemainingBoardSpace
  ```

vw_BoardSpaceDisplay
: Display view for board occupancy details. Formats the areas with thousands separators and ranks boards from fullest to emptiest.
: Columns:
  ```
  BoardID
  NumAds
  BoardWidth
  BoardLength
  BoardArea
  TotalAdArea
  AvailableSpace
  FullnessRank
  ```

vw_PendingPosting
: Show ads that are approved but not posted yet.
: Columns (SELECT * over Ad; listed per the Ad table's column order):
  ```
  AdID
  PosterID
  ReviewerID
  Title
  AdType
  AdLength
  AdWidth
  Duration
  PostDate
  ReviewStatus
  EnteredPending
  ReviewDate
  IsWithdrawn
  WithdrawnDate
  ImageFileName
  ```

vw_PendingRemoval
: Find all ads that should be removed from the board, this includes any ad that has become un-approved after being posted, ads that have been withdrawn, and expired ads in a ranked list of importance. Top priority is ads that have been withdrawn, then otherwise unapproved ads, and then expired ads by DaysOverdue. This view feeds the UnPost ad workflow.
: Columns:
  ```
  Building
  BldgFloor
  Slot
  AdID
  Title
  ReviewStatus
  IsWithdrawn
  WithdrawnDate
  PostDate
  Duration
  DaysOverdue
  ImageFileName
  RemovalPriority
  RemovalReason
  ```

### Messaging
Views aggregating the messages exchanged about ads, counted per ad and per person.

vw_NumMessagesPerAd
: Count how many messages each ad has.
: Columns:
  ```
  AdID
  Title
  NumMessages
  ```

vw_MessageCountsPerUser
: Calculate total number of messages sent and received per user. Unfolds Messages into one row per participant role so that both sides of every message can be counted in a single pass.
: Columns:
  ```
  PersonID
  UserName
  NumSent
  NumReceived
  ```