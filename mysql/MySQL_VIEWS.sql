--    Created by Mike Verwer | mikeverwer.github.io
-- ** ALL QUERIES IN THIS FILE WORK IN MySQL **
--
-- LOAD ORDER: 1 of 3
--   MySQL_VIEWS.sql  ->  MySQL_PROCEDURES.sql  ->  MySQL_TESTS.sql
-- Views must be created before procedures, since several procedures read from
-- them (PostAd reads vw_ExpiredAds, GetAdPostings reads vw_PostedAdsInfo). Tests
-- run last and depend on both.
--
-- Within this file, Board & Posting is order-sensitive: vw_PostedAdsInfo feeds
-- vw_BoardSpace and vw_PendingRemoval (along with vw_ExpiredAds), and 
-- vw_BoardSpace feeds vw_BoardSpaceDisplay. The categories themselves are 
-- independent.

USE AdPostingDB;

-- =============================================================================
-- Person & Roles
-- Views over people and the roles they hold. No views currently live here;
-- all person and role logic is procedural (see MySQL_PROCEDURES.sql).
-- =============================================================================

-- =============================================================================
-- Ad Lifecycle & Review
-- Views covering an ad from submission through review decision and expiry:
-- the pending review queue, expiry tracking, reviewer throughput, and the
-- breakdown of ads by the type of user who posted them.
-- =============================================================================

-- -------------------------------------------------------------------------------

-- Find all ads that are past duration
CREATE OR REPLACE VIEW vw_ExpiredAds AS
SELECT 
    AdID, 
    PostDate, 
    Duration, 
    DATEDIFF(CURRENT_DATE(), PostDate) - Duration AS DaysOverdue
FROM Ad
WHERE 
    DATEDIFF(CURRENT_DATE(), PostDate) - Duration >= 0;

-- -------------------------------------------------------------------------------

-- Create a view for the review queue
CREATE OR REPLACE VIEW vw_ReviewQueue AS
SELECT
    ROW_NUMBER() OVER (ORDER BY A.EnteredPending, A.AdID) AS QueuePosition
    A.AdID,
    CONCAT(P.FirstName, ' ', P.LastName) AS PosterName,
    A.Title,
    A.AdType,
    A.AdLength,
    A.AdWidth,
    A.Duration,
    A.ImageFileName
FROM
    Ad AS A
    INNER JOIN Person AS P ON A.PosterID = P.PersonID
WHERE A.ReviewStatus = 'Pending' AND A.IsWithdrawn = 0;

-- -------------------------------------------------------------------------------

-- Display counts of ads rejected and ads approved for each reviewer.
-- Reviews performed by a since-deleted reviewer (ReviewerID cleared to NULL by
-- RevokeEmployeeRole) are preserved under a single 'Deleted Reviewer(s)' row
-- rather than being dropped from the totals.
CREATE OR REPLACE VIEW vw_ReviewCountsPerReviewer AS
SELECT 
    R.PersonID,
    CONCAT(P.FirstName, ' ', P.LastName) AS ReviewerName,
    SUM(CASE WHEN A.ReviewStatus = 'Approved' THEN 1 ELSE 0 END) AS ApprovedCount,
    SUM(CASE WHEN A.ReviewStatus = 'Rejected' THEN 1 ELSE 0 END) AS RejectedCount,
    SUM(CASE WHEN A.ReviewStatus IN ('Approved', 'Rejected') THEN 1 ELSE 0 END) AS TotalReviews
FROM 
    Employee AS R
    LEFT JOIN Person AS P ON R.PersonID = P.PersonID
    LEFT JOIN Ad AS A ON R.PersonID = A.ReviewerID
WHERE R.IsReviewer = 1
GROUP BY
    R.PersonID,
    P.FirstName,
    P.LastName

UNION ALL

SELECT 
    NULL AS PersonID,
    'Deleted Reviewer(s)' AS ReviewerName,
    SUM(CASE WHEN ReviewStatus = 'Approved' THEN 1 ELSE 0 END) AS ApprovedCount,
    SUM(CASE WHEN ReviewStatus = 'Rejected' THEN 1 ELSE 0 END) AS RejectedCount,
    COUNT(*) AS TotalReviews
FROM Ad
WHERE ReviewerID IS NULL AND ReviewStatus IN ('Approved', 'Rejected')
HAVING COUNT(*) > 0;

-- -------------------------------------------------------------------------------

-- Classify every ad by the type of user who posted it. A poster may hold
-- several roles at once, so the CASE is ordered by specificity: Student wins
-- over Employee, which wins over an unspecialized College Member.
CREATE OR REPLACE VIEW AdsByUserType AS
SELECT 
    A.AdID,
    A.PosterID,
    A.AdType,
    CASE 
        WHEN S.PersonID IS NOT NULL THEN 'Student'
        WHEN E.PersonID IS NOT NULL THEN E.PositionTitle
        WHEN CM.PersonID IS NOT NULL THEN 'College Member (Unspecialized)'
        ELSE 'Non-Member'
    END AS UserType
FROM 
    Ad AS A
    LEFT JOIN CollegeMember AS CM ON A.PosterID = CM.PersonID
    LEFT JOIN Employee AS E ON A.PosterID = E.PersonID
    LEFT JOIN Student AS S ON A.PosterID = S.PersonID;

-- -------------------------------------------------------------------------------

-- Pivot table of ads by user type x ad type. WITH ROLLUP adds a grand-total
-- row, labelled 'Total' where the grouping column comes back NULL.
CREATE OR REPLACE VIEW vw_AdsByUserTypeAndAdType AS
SELECT
    IFNULL(UserType, 'Total') AS UserType,
    SUM(CASE WHEN AdType = 'Tutorship' THEN 1 ELSE 0 END) AS Tutorship,
    SUM(CASE WHEN AdType = 'Rent'      THEN 1 ELSE 0 END) AS Rent,
    SUM(CASE WHEN AdType = 'Sale'      THEN 1 ELSE 0 END) AS Sale,
    SUM(CASE WHEN AdType = 'Roommate'  THEN 1 ELSE 0 END) AS Roommate,
    SUM(CASE WHEN AdType = 'Event'     THEN 1 ELSE 0 END) AS Event,
    SUM(CASE WHEN AdType = 'Service'   THEN 1 ELSE 0 END) AS Service,
    SUM(CASE WHEN AdType = 'Other'     THEN 1 ELSE 0 END) AS Other,
    COUNT(*) AS RowTotal
FROM AdsByUserType
GROUP BY UserType WITH ROLLUP;

-- =============================================================================
-- Board & Posting
-- Views describing the physical boards and what is currently posted to them:
-- the posting join itself, per-board space accounting, and the two exception
-- lists (approved-but-unposted, and posted-but-require-removal).
--
-- Order matters here. vw_PostedAdsInfo must be created first; vw_BoardSpace and
-- vw_PendingRemoval read from it, and vw_BoardSpaceDisplay reads from
-- vw_BoardSpace.
-- =============================================================================

-- -------------------------------------------------------------------------------

-- Create a view of all ads posted to each board, joining posting location to
-- the full ad record. This is the base view for the rest of this category.
CREATE OR REPLACE VIEW vw_PostedAdsInfo AS
SELECT 
	APB.Building,
    APB.BldgFloor,
    APB.Slot,
    Ad.AdID,
    Ad.Title,
	Ad.AdType,
	Ad.PosterID,
	Ad.ReviewerID,    
    Ad.ReviewStatus,
    Ad.ReviewDate,
    Ad.PostDate,
    Ad.Duration,
    Ad.AdWidth,
    Ad.AdLength,
    Ad.IsWithdrawn,
    Ad.WithdrawnDate,
    Ad.ImageFileName
FROM 
    Ad_Posted_Board AS APB 
    INNER JOIN Ad ON APB.AdID = Ad.AdID;

-- -------------------------------------------------------------------------------

-- Create view to list board occupancy details: number of posted ads, board
--  size, total ad sizes, and remaining board space.
--  RIGHT JOIN so that empty boards still appear, with zeroed ad totals.
CREATE OR REPLACE VIEW vw_BoardSpace AS
SELECT
    B.Building,
    B.BldgFloor,
    B.Slot,
    COUNT(DISTINCT A.AdID) AS NumAds,
    B.BoardWidth,
    B.BoardLength,
    B.BoardWidth * B.BoardLength AS BoardArea,
    COALESCE(SUM(A.AdWidth * A.AdLength), 0) AS TotalAdArea,
    (B.BoardWidth * B.BoardLength) - COALESCE(SUM(A.AdWidth * A.AdLength), 0) 
        AS RemainingBoardSpace
FROM 
    vw_PostedAdsInfo AS A
    RIGHT JOIN Board AS B ON 
		A.Building = B.Building 
        AND A.BldgFloor = B.BldgFloor 
        AND A.Slot = B.Slot
GROUP BY 
    B.Building, 
    B.BldgFloor, 
    B.Slot,
    B.BoardWidth,
    B.BoardLength;

-- -------------------------------------------------------------------------------

-- Create a display view for board occupancy details. Formats the areas with
-- thousands separators and ranks boards from fullest to emptiest.
CREATE OR REPLACE VIEW vw_BoardSpaceDisplay AS
SELECT
    CONCAT(Building, '-', BldgFloor, '-', Slot) AS BoardID,
    NumAds,
    BoardWidth,
    BoardLength,
    FORMAT(BoardArea, 0) AS BoardArea,
    FORMAT(TotalAdArea, 0) AS TotalAdArea,
    FORMAT(RemainingBoardSpace, 0) AS AvailableSpace,
    RANK() OVER (ORDER BY RemainingBoardSpace ASC) AS FullnessRank
FROM vw_BoardSpace;

-- -------------------------------------------------------------------------------

-- Show ads that are approved but not posted yet
CREATE OR REPLACE VIEW vw_PendingPosting AS
SELECT * 
FROM Ad AS A
WHERE 
    A.ReviewStatus = 'Approved' 
    AND A.IsWithdrawn = 0
    AND NOT EXISTS (
        SELECT 1 
        FROM Ad_Posted_Board AS APB 
        WHERE APB.AdID = A.AdID
    );

-- -------------------------------------------------------------------------------

-- Find all ads that should be removed from the board, this includes any ad that
--  has become un-approved after being posted, ads that have been withdrawn, and 
--  expired ads in a ranked list of importance. Top priority is ads that have been 
--  withdrawn, then otherwise unapproved ads, and then expired ads by DaysOverdue.
--  This view feeds the UnPost ad workflow.
CREATE OR REPLACE VIEW vw_PendingRemoval AS
SELECT
    P.Building,
    P.BldgFloor,
    P.Slot,
    P.AdID,
    P.Title,
    P.ReviewStatus,
    P.IsWithdrawn,
    P.WithdrawnDate,
    P.PostDate,
    P.Duration,
    EA.DaysOverdue,
    P.ImageFileName
    CASE
        WHEN IsWithdrawn = 1 THEN 1
        WHEN ReviewStatus <> 'Approved' THEN 2
        ELSE 3
    END AS RemovalPriority,
    CASE
        WHEN IsWithdrawn = 1 THEN 'Withdrawn'
        WHEN ReviewStatus <> 'Approved' THEN CONCAT('Unapproved (', ReviewStatus, ')')
        ELSE 'Expired'
    END AS RemovalReason
FROM vw_PostedAdsInfo AS P
LEFT JOIN vw_ExpiredAds AS EA on P.AdID = EA.AdID
WHERE
    IsWithdrawn = 1
    OR ReviewStatus <> 'Approved'
    OR EA.AdID IS NOT NULL;

-- =============================================================================
-- Messaging
-- Views aggregating the messages exchanged about ads, counted per ad and
-- per person.
-- =============================================================================

-- -------------------------------------------------------------------------------

-- Count how many messages each ad has
CREATE OR REPLACE VIEW vw_NumMessagesPerAd AS
SELECT
    A.AdID,
    A.Title,
    COUNT(M.SenderID) AS NumMessages
FROM 
    Ad AS A
    LEFT JOIN Messages AS M ON M.AdID = A.AdID
GROUP BY
    A.AdID,
    A.Title;

-- -------------------------------------------------------------------------------

-- Calculate total number of messages sent and received per user.
-- Unfolds Messages into one row per participant role so that both sides of
-- every message can be counted in a single pass.
CREATE OR REPLACE VIEW vw_MessageCountsPerUser AS
WITH MessageRoles AS (
    SELECT SenderID    AS PersonID, 'Sent'     AS Role FROM Messages
    UNION ALL
    SELECT RecipientID AS PersonID, 'Received' AS Role FROM Messages
)
SELECT
    P.PersonID,
    CONCAT(P.FirstName, ' ', P.LastName) AS UserName,
    SUM(CASE WHEN MR.Role = 'Sent'     THEN 1 ELSE 0 END) AS NumSent,
    SUM(CASE WHEN MR.Role = 'Received' THEN 1 ELSE 0 END) AS NumReceived
FROM 
    Person AS P
    LEFT JOIN MessageRoles AS MR ON P.PersonID = MR.PersonID
GROUP BY 
    P.PersonID, 
    P.FirstName, 
    P.LastName;
