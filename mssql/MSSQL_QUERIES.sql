--    Created by Mike Verwer | mikeverwer.github.io
-- ** ALL QUERIES IN THIS FILE WORK IN MS SQL Server **

/*
Most queries work on MySQL and MS SQL Server, but there are a number of syntax
differences in many of the queries.
The major differences that appear most often are described here:
  A) MySQL does not support the use of the GO batch separator. It is needed in
    the MS SQL version to properly allow for the creation of VIEWs and PROCEDUREs
  B) The syntax for creating PROCEDUREs is different between the two:
    - MySQL requires setting a DELIMITER, MS SQL does not.
    - MySQL parameters are not defined or referenced with an '@'
    - In MySQL, parameters are are enclosed in parentheses. In MS SQL the AS
    keyword indicates the end of the parameter list.
  C) Flow control statements in MySQL do not use IF ... BEGIN ... END blocks, 
    instead they use IF ... THEN ... END IF blocks.
  D) RAISERROR('message', 16, 1) ... RETURN syntax is not valid in MySQL. 
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'message' is used instead. 
  E) CREATE OR ALTER [VIEW | PROCEDURE] is not valid in MySQL, CREATE OR REPLACE
    is used instead.
  F) PROCEDURE call syntax uses EXEC MyProc @param = value... in MS SQL but MySQL 
    uses CALL MyProc(value,...) 

Aside from these major differences there are a number of other idiosyncrasies,
particularly when it comes to using dates and datetimes.
    - MySQL supports the CURRENT_DATE() function that returns a DATE datatype,
    but SQL Server uses the GETDATE() function that returns a DATETIME. Therefor,
    in places where the current DATE is needed, we use CAST(GETDATE() AS DATE).
    - MySQL and MS SQL both support the DATEDIFF() function, but they implement it
    differently. 
        - In MySQL DATEDIFF(date1, date2) returns the number of days between the 
        given dates (date1 - date2).
        - In MS SQL DATEDIFF(interval, date1, date2) returns the difference between
        the two dates in units of the given interval, eg: DAY, YEAR, etc.
*/
-- -------------------------------------------------------------------------------

USE AdPostingDB;
GO

-- Q1) Count how many messages each ad has
CREATE OR ALTER VIEW vw_NumMessagesPerAd AS
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

GO
SELECT * FROM vw_NumMessagesPerAd;

-- -------------------------------------------------------------------------------
GO
-- Q2) Retrieve all messages about a given ad, showing sender and recipient names, 
--     message content, and timestamp.
CREATE OR ALTER PROCEDURE GetAllADMessages 
	@_AdID INT 
AS
BEGIN
	SELECT 
        
		CONCAT(S.FirstName, ' ', S.LastName) AS SenderName,
		CONCAT(R.FirstName, ' ', R.LastName) AS RecipientName,
		M.Content,
		M.TimeLogged
	FROM 
		Messages AS M 
		INNER JOIN Person AS S ON M.SenderID = S.PersonID
		INNER JOIN Person AS R ON M.RecipientID = R.PersonID
	WHERE M.AdID = @_AdID
	ORDER BY TimeLogged;
END
GO

EXEC GetAllADMessages @_AdID = 1;

-- -------------------------------------------------------------------------------
GO
-- Q3) Calculate total number of messages sent and recieved per user
CREATE OR ALTER VIEW vw_MessageCountsPerUser AS
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

GO
SELECT * FROM vw_MessageCountsPerUser

-- -------------------------------------------------------------------------------
GO
-- Q4) Create a view of all approved ads for each board
CREATE OR ALTER VIEW PostedAdsInfo AS
SELECT 
	APB.Building,
    APB.BldgFloor,
    APB.Slot,
    Ad.AdID,
    Ad.Title,
	Ad.AdType,
	Ad.PosterID,
	Ad.ReviewerID,    
    Ad.AdStatus,
    Ad.ReviewDate,
    Ad.PostDate,
    Ad.Duration,
    Ad.AdWidth,
    Ad.AdLength
FROM 
	Ad_Posted_Board AS APB 
	INNER JOIN Ad ON APB.AdID = Ad.AdID;
GO

SELECT *
FROM PostedAdsInfo
ORDER BY Building, BldgFloor, Slot;

-- -------------------------------------------------------------------------------
GO
-- Q5) Create view to list board occupancy details: number of posted ads, board  
--      size, total ad sizes, and remaining board space.
CREATE OR ALTER VIEW vw_BoardSpace AS
SELECT
    B.Building,
    B.BldgFloor,
    B.Slot,
    COUNT(DISTINCT A.AdID) AS NumAds,
    B.BoardWidth,
    B.BoardLength,
    B.BoardWidth * B.BoardLength AS BoardArea,
    ISNULL(SUM(A.AdWidth * A.AdLength), 0) AS TotalAdArea,
    (B.BoardWidth * B.BoardLength) - ISNULL(SUM(A.AdWidth * A.AdLength), 0) 
        AS RemainingBoardSpace
FROM 
    PostedAdsInfo AS A
    RIGHT JOIN Board AS B ON 
		A.Building = B.Building 
        AND A.BldgFloor = B.BldgFloor 
        AND A.Slot = B.Slot
GROUP BY 
    B.Building, 
    B.BldgFloor, 
    B.Slot,
    B.BoardWidth,
    B.BoardLength
GO

SELECT *
FROM vw_BoardSpace
ORDER BY
    Building, 
    BldgFloor, 
    Slot;

-- -------------------------------------------------------------------------------
GO
-- Q6) Create a display view for board occupancy details.
CREATE OR ALTER VIEW vw_BoardSpaceDisplay AS
SELECT
    CONCAT(Building, '-', BldgFloor, '-', Slot) AS BoardID,
    NumAds,
    BoardWidth,
    BoardLength,
    FORMAT(BoardArea, '#,0') AS BoardArea,
    FORMAT(TotalAdArea , '#,0') AS TotalAdArea,
    FORMAT(RemainingBoardSpace , '#,0') AS AvailableSpace,
    RANK() OVER (ORDER BY RemainingBoardSpace ASC) AS FullnessRank
FROM vw_BoardSpace
GO

SELECT *
FROM vw_BoardSpaceDisplay
ORDER BY FullnessRank;

-- -------------------------------------------------------------------------------
GO
-- Q7) Procedure to evaluate if a given ad will fit on each board
CREATE OR ALTER PROCEDURE CheckAdFit 
@_AdID INT 
AS
BEGIN
    SELECT 
        B.Building,
        B.BldgFloor,
        B.Slot,
        FORMAT(B.RemainingBoardSpace, '#,0') AS 'Available Space (cm²)',
        CASE 
            WHEN B.RemainingBoardSpace - A.AdLength * A.AdWidth > 0 THEN 'May Fit'
            ELSE 'Will Not Fit'
        END AS FitStatus
    FROM
        vw_BoardSpace AS B
        CROSS JOIN Ad as A
    WHERE A.AdID = @_AdID 
    ORDER BY B.RemainingBoardSpace DESC;
END
GO

EXEC CheckAdFit @_AdID = 1;

-- -------------------------------------------------------------------------------
GO
-- Q9) Find all ads that are past duration
CREATE OR ALTER VIEW vw_ExpiredAds
AS
SELECT 
    AdID, 
    PostDate, 
    Duration, 
    DATEDIFF(DAY, PostDate, CAST(GETDATE() AS DATE)) - Duration AS DaysOverdue
FROM Ad
WHERE 
    DATEDIFF(DAY, PostDate, CAST(GETDATE() AS DATE)) - Duration >= 0;
GO

SELECT * FROM vw_ExpiredAds;

-- -------------------------------------------------------------------------------
GO
-- Q10) Display counts of adds rejected and ads approved for each reviewer
CREATE OR ALTER VIEW vw_ReviewCountsPerReviewer AS
SELECT 
    R.PersonID,
    CONCAT(P.FirstName, ' ', P.LastName) AS ReviewerName,
    SUM(CASE WHEN A.AdStatus = 'Approved' THEN 1 ELSE 0 END) AS ApprovedCount,
    SUM(CASE WHEN A.AdStatus = 'Rejected' THEN 1 ELSE 0 END) AS RejectedCount,
    SUM(CASE WHEN A.AdStatus IN ('Approved', 'Rejected') THEN 1 ELSE 0 END) AS TotalReviews
FROM 
    Employee AS R
    LEFT JOIN Person AS P ON R.PersonID = P.PersonID
    LEFT JOIN Ad as A ON R.PersonID = A.ReviewerID
WHERE R.IsReviewer = 1
GROUP BY
    R.PersonID,
    P.FirstName,
    P.LastName

UNION ALL

SELECT 
    NULL AS PersonID,
    'Deleted Reviewer(s)' AS ReviewerName,
    SUM(CASE WHEN AdStatus = 'Approved' THEN 1 ELSE 0 END) AS ApprovedCount,
    SUM(CASE WHEN AdStatus = 'Rejected' THEN 1 ELSE 0 END) AS RejectedCount,
    COUNT(*) AS TotalReviews
FROM Ad
WHERE ReviewerID IS NULL AND AdStatus IN ('Approved', 'Rejected')
HAVING COUNT(*) > 0;

GO
SELECT * FROM vw_ReviewCountsPerReviewer
WHERE PersonID IS NOT NULL
ORDER BY TotalReviews DESC;

-- -------------------------------------------------------------------------------
GO
-- Q11) Show ads that are approved but not posted yet
CREATE OR ALTER VIEW vw_PendingPosting 
AS
SELECT * 
FROM Ad AS A
WHERE 
    A.AdStatus = 'Approved' 
    AND NOT EXISTS (
        SELECT 1 
        FROM Ad_Posted_Board AS APB 
        WHERE APB.AdID = A.AdID
    );

GO
SELECT * FROM vw_PendingPosting;

-- -------------------------------------------------------------------------------
GO
-- Q12) Procedure to find all the information and locations of a posted ad
CREATE OR ALTER PROCEDURE GetAdPostings
    @_AdID INT
AS
BEGIN
    SELECT *
    FROM PostedAdsInfo
    WHERE AdID = @_AdID
END

GO
EXEC GetAdPostings @_AdID = 14;

-- -------------------------------------------------------------------------------
GO
-- Q13) Procedure to find people who have posted multiple rejected ads
CREATE OR ALTER PROCEDURE GetNoncompliantPosters
    @_MinRejections INT = 2
AS
BEGIN
    SELECT
        P.PersonID,
        CONCAT(P.FirstName, ' ', P.LastName) AS PosterName,
        COUNT(DISTINCT A.AdID) AS RejectedAdCount
    FROM
        Person AS P
        INNER JOIN Ad AS A ON P.PersonID = A.PosterID
    WHERE A.AdStatus = 'Rejected'
    GROUP BY P.PersonID, P.FirstName, P.LastName
    HAVING COUNT(DISTINCT A.AdID) >= @_MinRejections;
END

GO
EXEC GetNoncompliantPosters;

-- -------------------------------------------------------------------------------
GO
-- Q14) Procedure to find the rejection history of a user (poster)
CREATE OR ALTER PROCEDURE GetPosterRejectionHistory
    @_PosterID INT
AS
BEGIN
    IF NOT EXISTS (SELECT 1 FROM Person WHERE PersonID = @_PosterID)
    BEGIN
        RAISERROR('Error: No person exists with the given PersonID.', 16, 1);
        RETURN;
    END

    SELECT
        A.AdID,
        A.Title,
        A.AdType,
        CASE WHEN E.PersonID IS NOT NULL
             THEN CONCAT(P.FirstName, ' ', P.LastName)
             ELSE 'No reviewer on record'
        END AS ReviewerName
    FROM
        Ad AS A
        LEFT JOIN Employee AS E ON A.ReviewerID = E.PersonID
        LEFT JOIN Person AS P ON E.PersonID = P.PersonID
    WHERE
        A.PosterID = @_PosterID
        AND A.AdStatus = 'Rejected'
    ORDER BY A.AdID;
END
GO

EXEC GetPosterRejectionHistory @_PosterID = 19;

-- -------------------------------------------------------------------------------
GO
-- Q15) Create a veiw to show ads per user type
CREATE OR ALTER VIEW AdsByUserType AS
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
    LEFT JOIN Student AS S ON A.PosterID = S.PersonID
GO

SELECT * 
FROM AdsByUserType
ORDER BY UserType, PosterID

-- -------------------------------------------------------------------------------
GO
-- Q16) Pivot table of ads by user type x ad type
CREATE OR ALTER VIEW vw_AdsByUserTypeAndAdType AS
SELECT
    ISNULL(UserType, 'Total') AS UserType,
    SUM(CASE WHEN AdType = 'Tutorship' THEN 1 ELSE 0 END) AS Tutorship,
    SUM(CASE WHEN AdType = 'Rent'      THEN 1 ELSE 0 END) AS Rent,
    SUM(CASE WHEN AdType = 'Sale'      THEN 1 ELSE 0 END) AS Sale,
    SUM(CASE WHEN AdType = 'Roommate'  THEN 1 ELSE 0 END) AS Roommate,
    SUM(CASE WHEN AdType = 'Event'     THEN 1 ELSE 0 END) AS Event,
    COUNT(*) AS RowTotal
FROM AdsByUserType
GROUP BY ROLLUP(UserType);

GO
SELECT * FROM vw_AdsByUserTypeAndAdType;

-- -------------------------------------------------------------------------------
GO
-- Q17) Create a view for the review queue
CREATE OR ALTER VIEW vw_ReviewQueue AS
SELECT
    A.AdID,
    CONCAT(P.FirstName, ' ', P.LastName) AS PosterName,
    A.Title,
    A.AdType,
    ROW_NUMBER() OVER (ORDER BY A.EnteredPending, A.AdID) AS QueuePosition
FROM
    Ad AS A
    INNER JOIN Person AS P ON A.PosterID = P.PersonID
WHERE A.AdStatus = 'Pending';

GO
SELECT * FROM vw_ReviewQueue;

-- -------------------------------------------------------------------------------
GO
-- Q17) Approve or Reject an ad
CREATE OR ALTER PROCEDURE ReviewAd 
    @_AdID INT,
    @_Status VARCHAR(10),
    @_ReviewerID INT,
    @_ReviewDate DATE = NULL
AS
BEGIN
    IF @_Status NOT IN ('Approved', 'Rejected', 'Pending')
    BEGIN 
        RAISERROR('Invalid status. Allowed values are Approved, Rejected, or Pending', 16, 1);
        RETURN;
    END
    IF @_ReviewerID IS NULL OR @_ReviewerID NOT IN (
        SELECT PersonID 
        FROM Employee 
        WHERE IsReviewer = 1)
    BEGIN
        RAISERROR('Invalid Reviewer ID. Only a Reviewer can evaluate an ad.', 16, 1);
        RETURN;
    END

    UPDATE Ad
    SET 
        AdStatus = @_Status,
        ReviewDate = 
            CASE
                WHEN @_Status != 'Pending' THEN
                CASE    
                    WHEN @_ReviewDate IS NULL THEN CAST(GETDATE() AS DATE)
                    ELSE @_ReviewDate
                END
                ELSE NULL
            END,
        ReviewerID = 
            CASE
                WHEN @_Status != 'Pending' THEN @_ReviewerID
                ELSE NULL
            END
    WHERE AdID = @_AdID
END
GO

BEGIN TRANSACTION;
    EXEC ReviewAd @_AdID = 16, @_Status = 'Approved', @_ReviewerID = 19;
ROLLBACK TRANSACTION;

-- -------------------------------------------------------------------------------
GO
-- Q18) Set IsReviewer role for an employee
CREATE OR ALTER PROCEDURE SetReviewerPermission
@_EmpID INT,
@_IsRev BIT
AS
BEGIN
    IF @_EmpID IS NULL OR @_EmpID NOT IN (
        SELECT PersonID
        FROM Employee
    )
    BEGIN
        RAISERROR ('Invalid ID. Only an employee can be a reviewer', 16, 1);
        RETURN;
    END
    UPDATE Employee
    SET IsReviewer = @_IsRev
    WHERE PersonID = @_EmpID
END
GO

BEGIN TRANSACTION;
    EXEC SetReviewerPermission @_EmpID=20, @_IsRev=1;
ROLLBACK TRANSACTION;

-- -------------------------------------------------------------------------------
GO
-- Q19) Create a procedure to post an ad to a given board
    -- this implementation assumes that the user has confirmed 
    -- that the ad will fit on the board separately.
CREATE OR ALTER PROCEDURE PostAd
    -- This procedure must be called inside a transaction the CALLER controls
    -- (BEGIN TRANSACTION ... COMMIT/ROLLBACK), so the lock below is held for
    -- the full validate-then-insert sequence instead of just one statement.
    @_AdID  INT,
    @_Bldg  VARCHAR(4),
    @_Floor INT,
    @_Slot  CHAR(1)
AS
BEGIN
    -- check if AdID is valid
        -- must be approved ad
        -- must not be expired
    IF NOT EXISTS (
        SELECT 1
        FROM Ad WITH (UPDLOCK, HOLDLOCK)
        WHERE 
            AdStatus = 'Approved'
            AND AdID = @_AdID
    )
    BEGIN
        RAISERROR('Error: Ad is not approved.', 16, 1);
        RETURN;
    END
    IF @_AdID IN (SELECT AdID FROM vw_ExpiredAds)
    BEGIN
        RAISERROR('Error: Ad posting duration has expired.', 16, 1);
        RETURN;
    END
    -- check if given board is valid
    IF NOT EXISTS (
        SELECT 1
        FROM Board  
        WHERE
            Building = @_Bldg AND
            BldgFloor = @_Floor AND
            Slot = @_Slot
    )
    BEGIN
        RAISERROR('ERROR: The given board information does not correspond to a valid board.', 16, 1);
        RETURN;
    END

    INSERT INTO Ad_Posted_Board (AdID, Building, BldgFloor, Slot) VALUES
    (@_AdID, @_Bldg, @_Floor, @_Slot);
END
GO

-- Posted ad should pass
BEGIN TRANSACTION;
    EXEC ReviewAd @_AdID = 16, @_Status = 'Approved', @_ReviewerID = 19;
    EXEC PostAd @_AdID=16, @_Bldg='LIB', @_Floor=1, @_Slot='A';
ROLLBACK TRANSACTION;

-- Posted ad should fail - ad not approved
BEGIN TRANSACTION;
    EXEC PostAd @_AdID=16, @_Bldg='LIB', @_Floor=1, @_Slot='A';
ROLLBACK TRANSACTION;

-- -------------------------------------------------------------------------------
GO
-- Q20) Show Contact information of the poster of a given ad
CREATE OR ALTER PROCEDURE GetPosterInfo
    @_AdID INT
AS
BEGIN
    IF NOT EXISTS (SELECT 1 FROM Ad WHERE AdID = @_AdID)
    BEGIN
        RAISERROR('Error: No ad exists with the given AdID.', 16, 1);
        RETURN;
    END

    SELECT 
        CONCAT(P.FirstName, ' ', P.LastName) AS PosterName,
        P.Email,
        P.Phone,
        A.Title,
        A.AdType,
        CASE WHEN CM.PersonID IS NOT NULL THEN 'Yes' ELSE 'No' END AS IsCollegeMember,
        COALESCE(CM.Department, 'N/A') AS Department,
        CASE WHEN S.PersonID IS NOT NULL THEN 'Yes' ELSE 'No' END AS IsStudent,
        CASE 
            WHEN S.PersonID IS NOT NULL THEN COALESCE(S.Major, 'Undeclared')
            ELSE 'N/A'
        END AS Major,
        A.AdID
    FROM 
        Person AS P
        INNER JOIN Ad AS A ON P.PersonID = A.PosterID
        LEFT JOIN CollegeMember AS CM ON P.PersonID = CM.PersonID
        LEFT JOIN Student AS S ON P.PersonID = S.PersonID
    WHERE A.AdID = @_AdID
END
GO

EXEC GetPosterInfo @_AdID = 2;

-- -------------------------------------------------------------------------------
GO
-- Q21) Show Contact information of the reviewer of a given ad
CREATE OR ALTER PROCEDURE GetReviewerInfo
    @_AdID INT
AS
BEGIN
    IF NOT EXISTS (SELECT 1 FROM Ad WHERE AdID = @_AdID)
    BEGIN
        RAISERROR('Error: No ad exists with the given AdID.', 16, 1);
        RETURN;
    END

    SELECT
        A.Title,
        A.AdType,
        A.AdStatus,
        CASE WHEN E.PersonID IS NOT NULL 
             THEN CONCAT(P.FirstName, ' ', P.LastName) 
             ELSE 'No reviewer on record' 
        END AS ReviewerName,
        P.Email,
        P.Phone,
        E.OfficeLocation,
        E.Extension,
        E.PositionTitle
    FROM
        Ad AS A
        LEFT JOIN Employee AS E ON A.ReviewerID = E.PersonID
        LEFT JOIN Person AS P ON E.PersonID = P.PersonID
    WHERE A.AdID = @_AdID
END
GO

EXEC GetReviewerInfo @_AdID = 22;

-- -------------------------------------------------------------------------------
GO
-- Q22) Delete posted ads that are expired
BEGIN TRANSACTION;
    DELETE APB
    FROM Ad_Posted_Board AS APB
    JOIN vw_ExpiredAds AS EA ON APB.AdID = EA.AdID;
ROLLBACK TRANSACTION;

-- -------------------------------------------------------------------------------
GO
-- Q23) Find posted ads that are not approved (possible if a posted ad goes through
--      a re-review)
CREATE OR ALTER VIEW vw_UnapprovedPostings AS
SELECT
    Building,
    BldgFloor,
    Slot,
    AdID,
    Title,
    AdStatus,
    ReviewDate
FROM PostedAdsInfo
WHERE AdStatus <> 'Approved';

GO
SELECT * FROM vw_UnapprovedPostings;

-- -------------------------------------------------------------------------------
GO
-- Q24) Remove an unapproved ad from the Ad_Posted_Board table.
--      If a specific board is given, it will only remove the ad from that board,
--      otherwise it will remove it from all boards it is currently on.
CREATE OR ALTER PROCEDURE UnpostAd
    @_AdID      INT,
    @_Building  VARCHAR(4) = NULL,
    @_BldgFloor INT        = NULL,
    @_Slot      CHAR(1)    = NULL
AS
BEGIN
    IF NOT EXISTS (SELECT 1 FROM Ad WHERE AdID = @_AdID)
    BEGIN
        RAISERROR('Error: No ad exists with the given AdID.', 16, 1);
        RETURN;
    END

    IF (@_Building IS NOT NULL OR @_BldgFloor IS NOT NULL OR @_Slot IS NOT NULL)
       AND (@_Building IS NULL OR @_BldgFloor IS NULL OR @_Slot IS NULL)
    BEGIN
        RAISERROR('Error: Building, BldgFloor, and Slot must all be supplied together, or all omitted to remove every posting.', 16, 1);
        RETURN;
    END

    IF @_Building IS NULL
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM Ad_Posted_Board WHERE AdID = @_AdID)
        BEGIN
            RAISERROR('Error: This ad is not currently posted to any board.', 16, 1);
            RETURN;
        END
        DELETE FROM Ad_Posted_Board WHERE AdID = @_AdID;
    END
    ELSE
    BEGIN
        IF NOT EXISTS (
            SELECT 1 FROM Ad_Posted_Board 
            WHERE AdID = @_AdID AND Building = @_Building 
              AND BldgFloor = @_BldgFloor AND Slot = @_Slot
        )
        BEGIN
            RAISERROR('Error: This ad is not currently posted to the given board.', 16, 1);
            RETURN;
        END
        DELETE FROM Ad_Posted_Board 
        WHERE AdID = @_AdID AND Building = @_Building 
          AND BldgFloor = @_BldgFloor AND Slot = @_Slot;
    END
END
GO

-- EXEC UnpostAd @_AdID = 7;                                    -- remove from every board
-- EXEC UnpostAd @_AdID = 7, @_Building = 'BLD', @_BldgFloor = 1, @_Slot = 'A';  -- one board only

-- -------------------------------------------------------------------------------
GO
-- Q25) Add a person with no college affiliation.
--      Inserts into Person only. Use for members of the public who post ads
--      (see the non-member posters in the seed data).
--      This procedure must be called inside a transaction the CALLER controls
--      (BEGIN TRANSACTION ... COMMIT/ROLLBACK).
CREATE OR ALTER PROCEDURE AddNonMember
    @_FirstName VARCHAR(50),
    @_LastName  VARCHAR(50),
    @_Phone     CHAR(10)    = NULL,
    @_Email     VARCHAR(50),
    @_PersonID  INT         = NULL OUTPUT
AS
BEGIN
    IF @_FirstName IS NULL OR LTRIM(RTRIM(@_FirstName)) = ''
       OR @_LastName IS NULL OR LTRIM(RTRIM(@_LastName)) = ''
    BEGIN
        RAISERROR('Error: First and last name are required.', 16, 1);
        RETURN;
    END

    IF @_Email IS NULL OR LTRIM(RTRIM(@_Email)) = ''
    BEGIN
        RAISERROR('Error: Email is required.', 16, 1);
        RETURN;
    END

    IF EXISTS (SELECT 1 FROM Person WHERE Email = @_Email)
    BEGIN
        RAISERROR('Error: A person with the given email already exists.', 16, 1);
        RETURN;
    END

    INSERT INTO Person (FirstName, LastName, Phone, Email)
    VALUES (@_FirstName, @_LastName, @_Phone, @_Email);

    SET @_PersonID = SCOPE_IDENTITY();
END
GO

BEGIN TRANSACTION;
    DECLARE @NewNonMember INT;
    EXEC AddNonMember
        @_FirstName = 'Dana', @_LastName = 'Whitfield',
        @_Phone = '5551239001', @_Email = 'dana.whitfield@email.com',
        @_PersonID = @NewNonMember OUTPUT;
    SELECT @NewNonMember AS NewPersonID;
ROLLBACK TRANSACTION;

-- -------------------------------------------------------------------------------
GO
-- Q26) Add a college member who is neither a student nor an employee.
--      Intended for people who retain a college ID and board privileges without
--      being enrolled or employed; alumni are the motivating case. Most
--      registrations should use AddStudent or AddEmployee instead, both of which
--      create the CollegeMember row themselves.
--      This procedure must be called inside a transaction the CALLER controls.
CREATE OR ALTER PROCEDURE AddCollegeMember
    @_FirstName  VARCHAR(50),
    @_LastName   VARCHAR(50),
    @_Phone      CHAR(10)    = NULL,
    @_Email      VARCHAR(50),
    @_CollegeID  CHAR(9),
    @_Department VARCHAR(50) = NULL,
    @_PersonID   INT         = NULL OUTPUT
AS
BEGIN
    IF @_CollegeID IS NULL OR LTRIM(RTRIM(@_CollegeID)) = ''
    BEGIN
        RAISERROR('Error: College ID is required.', 16, 1);
        RETURN;
    END

    IF EXISTS (SELECT 1 FROM CollegeMember WHERE CollegeID = @_CollegeID)
    BEGIN
        RAISERROR('Error: A college member with the given College ID already exists.', 16, 1);
        RETURN;
    END

    EXEC AddNonMember
        @_FirstName = @_FirstName, @_LastName = @_LastName,
        @_Phone     = @_Phone,     @_Email    = @_Email,
        @_PersonID  = @_PersonID OUTPUT;

    IF @_PersonID IS NULL RETURN;  -- AddNonMember raised and returned

    INSERT INTO CollegeMember (PersonID, CollegeID, Department)
    VALUES (@_PersonID, @_CollegeID, @_Department);
END
GO

BEGIN TRANSACTION;
    DECLARE @NewMember INT;
    EXEC AddCollegeMember
        @_FirstName = 'Alan', @_LastName = 'Brouwer',
        @_Phone = '5551239002', @_Email = 'alan.brouwer@college.edu',
        @_CollegeID = 'ALM000001', @_Department = 'Alumni Relations',
        @_PersonID = @NewMember OUTPUT;
    SELECT @NewMember AS NewPersonID;
ROLLBACK TRANSACTION;

-- -------------------------------------------------------------------------------
GO
-- Q27) Add a student. Inserts Person, CollegeMember, and Student.
--      Department (the student's academic department) and Major are both supplied
--      by the caller; they are related but distinct, and Major may be NULL for a
--      student who has not declared one.
--      This procedure must be called inside a transaction the CALLER controls.
CREATE OR ALTER PROCEDURE AddStudent
    @_FirstName  VARCHAR(50),
    @_LastName   VARCHAR(50),
    @_Phone      CHAR(10)    = NULL,
    @_Email      VARCHAR(50),
    @_CollegeID  CHAR(9),
    @_Department VARCHAR(50) = NULL,
    @_Major      VARCHAR(60) = NULL,
    @_PersonID   INT         = NULL OUTPUT
AS
BEGIN
    EXEC AddCollegeMember
        @_FirstName  = @_FirstName,  @_LastName   = @_LastName,
        @_Phone      = @_Phone,      @_Email      = @_Email,
        @_CollegeID  = @_CollegeID,  @_Department = @_Department,
        @_PersonID   = @_PersonID OUTPUT;

    IF @_PersonID IS NULL RETURN;  -- a nested procedure raised and returned

    INSERT INTO Student (PersonID, Major)
    VALUES (@_PersonID, @_Major);
END
GO

BEGIN TRANSACTION;
    DECLARE @NewStudent INT;
    EXEC AddStudent
        @_FirstName = 'Rosa', @_LastName = 'Iqbal',
        @_Phone = '5551239003', @_Email = 'rosa.iqbal@college.edu',
        @_CollegeID = 'STU000018', @_Department = 'Mathematics',
        @_Major = 'Applied Mathematics',
        @_PersonID = @NewStudent OUTPUT;
    SELECT @NewStudent AS NewPersonID;
ROLLBACK TRANSACTION;

-- -------------------------------------------------------------------------------
GO
-- Q28) Add an employee. Inserts Person, CollegeMember, and Employee.
--      Extension requires OfficeLocation (chk_employee_extension_requires_office);
--      an employee with no office must have both NULL.
--      This procedure must be called inside a transaction the CALLER controls.
CREATE OR ALTER PROCEDURE AddEmployee
    @_FirstName      VARCHAR(50),
    @_LastName       VARCHAR(50),
    @_Phone          CHAR(10)    = NULL,
    @_Email          VARCHAR(50),
    @_CollegeID      CHAR(9),
    @_Department     VARCHAR(50) = NULL,
    @_OfficeLocation VARCHAR(15) = NULL,
    @_Extension      VARCHAR(6)  = NULL,
    @_PositionTitle  VARCHAR(20),
    @_IsReviewer     BIT         = 0,
    @_PersonID       INT         = NULL OUTPUT
AS
BEGIN
    IF @_PositionTitle NOT IN ('Faculty', 'Administration', 'Staff', 'Support', 'Specialized')
    BEGIN
        RAISERROR('Error: Invalid position title. Allowed values are Faculty, Administration, Staff, Support, or Specialized.', 16, 1);
        RETURN;
    END

    IF @_Extension IS NOT NULL AND @_OfficeLocation IS NULL
    BEGIN
        RAISERROR('Error: An extension cannot be assigned without an office location.', 16, 1);
        RETURN;
    END

    EXEC AddCollegeMember
        @_FirstName  = @_FirstName,  @_LastName   = @_LastName,
        @_Phone      = @_Phone,      @_Email      = @_Email,
        @_CollegeID  = @_CollegeID,  @_Department = @_Department,
        @_PersonID   = @_PersonID OUTPUT;

    IF @_PersonID IS NULL RETURN;  -- a nested procedure raised and returned

    INSERT INTO Employee (PersonID, OfficeLocation, Extension, PositionTitle, IsReviewer)
    VALUES (@_PersonID, @_OfficeLocation, @_Extension, @_PositionTitle, @_IsReviewer);
END
GO

BEGIN TRANSACTION;
    DECLARE @NewEmployee INT;
    EXEC AddEmployee
        @_FirstName = 'Yusuf', @_LastName = 'Demir',
        @_Phone = '5551239004', @_Email = 'yusuf.demir@college.edu',
        @_CollegeID = 'EMP000012', @_Department = 'Chemistry',
        @_OfficeLocation = 'SCI-215', @_Extension = '7215',
        @_PositionTitle = 'Faculty', @_IsReviewer = 0,
        @_PersonID = @NewEmployee OUTPUT;
    SELECT @NewEmployee AS NewPersonID;
ROLLBACK TRANSACTION;

-- Should fail - extension without an office
BEGIN TRANSACTION;
    DECLARE @BadEmployee INT;
    EXEC AddEmployee
        @_FirstName = 'Test', @_LastName = 'Case',
        @_Email = 'test.case@college.edu', @_CollegeID = 'EMP000013',
        @_Extension = '9999', @_PositionTitle = 'Support',
        @_PersonID = @BadEmployee OUTPUT;
ROLLBACK TRANSACTION;

-- Should fail - duplicate email
BEGIN TRANSACTION;
    DECLARE @DupEmail INT;
    EXEC AddStudent
        @_FirstName = 'Duplicate', @_LastName = 'Email',
        @_Email = 'emma.johnson@college.edu', @_CollegeID = 'STU000019',
        @_PersonID = @DupEmail OUTPUT;
ROLLBACK TRANSACTION;

-- -------------------------------------------------------------------------------
GO
-- Q29) Grant a person College Member status (Person -> CollegeMember).
--      Requires the person already exist in Person and not already be a
--      College Member. Use for someone gaining a College ID without yet
--      being a Student or Employee (e.g. an alum retaining board privileges).
CREATE OR ALTER PROCEDURE GrantCollegeMemberRole
    @_PersonID   INT,
    @_CollegeID  CHAR(9),
    @_Department VARCHAR(50) = NULL
AS
BEGIN
    IF NOT EXISTS (SELECT 1 FROM Person WHERE PersonID = @_PersonID)
    BEGIN
        RAISERROR('Error: No person exists with the given PersonID.', 16, 1);
        RETURN;
    END

    IF EXISTS (SELECT 1 FROM CollegeMember WHERE PersonID = @_PersonID)
    BEGIN
        RAISERROR('Error: This person already holds College Member status.', 16, 1);
        RETURN;
    END

    IF @_CollegeID IS NULL OR LTRIM(RTRIM(@_CollegeID)) = ''
    BEGIN
        RAISERROR('Error: College ID is required.', 16, 1);
        RETURN;
    END

    IF EXISTS (SELECT 1 FROM CollegeMember WHERE CollegeID = @_CollegeID)
    BEGIN
        RAISERROR('Error: A college member with the given College ID already exists.', 16, 1);
        RETURN;
    END

    INSERT INTO CollegeMember (PersonID, CollegeID, Department)
    VALUES (@_PersonID, @_CollegeID, @_Department);
END
GO

-- -------------------------------------------------------------------------------
GO
-- Q30) Revoke College Member status (deletes the CollegeMember row).
--      Refuses if the person still holds Student or Employee status, since
--      both are structurally dependent on CollegeMember (fk_student_collegemember,
--      fk_employee_collegemember). Revoke those first.
CREATE OR ALTER PROCEDURE RevokeCollegeMemberRole
    @_PersonID INT
AS
BEGIN
    IF NOT EXISTS (SELECT 1 FROM CollegeMember WHERE PersonID = @_PersonID)
    BEGIN
        RAISERROR('Error: This person does not currently hold College Member status.', 16, 1);
        RETURN;
    END

    IF EXISTS (SELECT 1 FROM Student WHERE PersonID = @_PersonID)
    BEGIN
        RAISERROR('Error: This person still holds Student status. Revoke it first.', 16, 1);
        RETURN;
    END

    IF EXISTS (SELECT 1 FROM Employee WHERE PersonID = @_PersonID)
    BEGIN
        RAISERROR('Error: This person still holds Employee status. Revoke it first.', 16, 1);
        RETURN;
    END

    DELETE FROM CollegeMember WHERE PersonID = @_PersonID;
END
GO

-- -------------------------------------------------------------------------------
GO
-- Q31) Grant a person Student status (CollegeMember -> Student).
--      Requires the person already hold College Member status. Does not
--      check Employee status either way, so this is also how a person who
--      already holds Employee status becomes a dual Student/Employee (e.g.
--      a graduate student TA).
CREATE OR ALTER PROCEDURE GrantStudentRole
    @_PersonID INT,
    @_Major    VARCHAR(60) = NULL
AS
BEGIN
    IF NOT EXISTS (SELECT 1 FROM CollegeMember WHERE PersonID = @_PersonID)
    BEGIN
        RAISERROR('Error: This person must hold College Member status before being granted Student status.', 16, 1);
        RETURN;
    END

    IF EXISTS (SELECT 1 FROM Student WHERE PersonID = @_PersonID)
    BEGIN
        RAISERROR('Error: This person already holds Student status.', 16, 1);
        RETURN;
    END

    INSERT INTO Student (PersonID, Major)
    VALUES (@_PersonID, @_Major);
END
GO

-- -------------------------------------------------------------------------------
GO
-- Q32) Revoke Student status (deletes the Student row only; College Member
--      and, if held, Employee status are untouched).
CREATE OR ALTER PROCEDURE RevokeStudentRole
    @_PersonID INT
AS
BEGIN
    IF NOT EXISTS (SELECT 1 FROM Student WHERE PersonID = @_PersonID)
    BEGIN
        RAISERROR('Error: This person does not currently hold Student status.', 16, 1);
        RETURN;
    END

    DELETE FROM Student WHERE PersonID = @_PersonID;
END
GO

-- -------------------------------------------------------------------------------
GO
-- Q33) Grant a person Employee status (CollegeMember -> Employee).
--      Requires the person already hold College Member status. Does not
--      check Student status either way, so this is also how an existing
--      Student becomes a dual Student/Employee (e.g. a graduate student TA).
--      Extension requires OfficeLocation (chk_employee_extension_requires_office).
--      Not to be confused with SetReviewerPermission, which only flips the
--      IsReviewer flag on an Employee row that already exists.
CREATE OR ALTER PROCEDURE GrantEmployeeRole
    @_PersonID       INT,
    @_OfficeLocation VARCHAR(15) = NULL,
    @_Extension      VARCHAR(6)  = NULL,
    @_PositionTitle  VARCHAR(20),
    @_IsReviewer     BIT         = 0
AS
BEGIN
    IF NOT EXISTS (SELECT 1 FROM CollegeMember WHERE PersonID = @_PersonID)
    BEGIN
        RAISERROR('Error: This person must hold College Member status before being granted Employee status.', 16, 1);
        RETURN;
    END

    IF EXISTS (SELECT 1 FROM Employee WHERE PersonID = @_PersonID)
    BEGIN
        RAISERROR('Error: This person already holds Employee status.', 16, 1);
        RETURN;
    END

    IF @_PositionTitle NOT IN ('Faculty', 'Administration', 'Staff', 'Support', 'Specialized')
    BEGIN
        RAISERROR('Error: Invalid position title. Allowed values are Faculty, Administration, Staff, Support, or Specialized.', 16, 1);
        RETURN;
    END

    IF @_Extension IS NOT NULL AND @_OfficeLocation IS NULL
    BEGIN
        RAISERROR('Error: An extension cannot be assigned without an office location.', 16, 1);
        RETURN;
    END

    INSERT INTO Employee (PersonID, OfficeLocation, Extension, PositionTitle, IsReviewer)
    VALUES (@_PersonID, @_OfficeLocation, @_Extension, @_PositionTitle, @_IsReviewer);
END
GO

-- -------------------------------------------------------------------------------
GO
-- Q34) Revoke Employee status. Any ad this person has reviewed has its
--      ReviewerID explicitly cleared first (review history is preserved,
--      matching vw_ReviewCountsPerReviewer's existing handling of deleted
--      reviewers), then the Employee row is deleted. College Member and,
--      if held, Student status are untouched.
--      Not to be confused with SetReviewerPermission, which only flips the
--      IsReviewer flag; this removes the Employee row entirely.
CREATE OR ALTER PROCEDURE RevokeEmployeeRole
    @_PersonID INT
AS
BEGIN
    IF NOT EXISTS (SELECT 1 FROM Employee WHERE PersonID = @_PersonID)
    BEGIN
        RAISERROR('Error: This person does not currently hold Employee status.', 16, 1);
        RETURN;
    END

    UPDATE Ad SET ReviewerID = NULL WHERE ReviewerID = @_PersonID;

    DELETE FROM Employee WHERE PersonID = @_PersonID;
END
GO

-- -------------------------------------------------------------------------------
-- Demonstrates a graduate student TA: Priya Nair (PersonID 21, a Student) is
-- granted Employee status without giving up Student status.
BEGIN TRANSACTION;
    EXEC GrantEmployeeRole
        @_PersonID = 21, @_OfficeLocation = 'MTH-110', @_Extension = '7110',
        @_PositionTitle = 'Staff', @_IsReviewer = 0;
    SELECT * FROM Student WHERE PersonID = 21;    -- still present
    SELECT * FROM Employee WHERE PersonID = 21;   -- now present too
ROLLBACK TRANSACTION;

-- Should fail - RevokeCollegeMemberRole refuses while Student status remains
BEGIN TRANSACTION;
    EXEC RevokeCollegeMemberRole @_PersonID = 5;  -- Emma Johnson, a Student
ROLLBACK TRANSACTION;

-- Should succeed - revoking Employee nulls ReviewerID on ads they reviewed
BEGIN TRANSACTION;
    SELECT COUNT(*) AS ReviewedBefore FROM Ad WHERE ReviewerID = 22;
    EXEC RevokeEmployeeRole @_PersonID = 22;  -- James Harris, a reviewer
    SELECT COUNT(*) AS ReviewedAfter FROM Ad WHERE ReviewerID = 22;  -- expect 0
ROLLBACK TRANSACTION;

-- -------------------------------------------------------------------------------
GO
-- Q35) Submit a new ad for review. Inserts a new Ad row; every other column is
--      left to its table default, which produces AdStatus = 'Pending',
--      ReviewerID = NULL, PostDate = NULL, EnteredPending = today, and
--      ReviewDate = NULL -- a state that already satisfies every CHECK
--      constraint on Ad without further logic here. Review (ReviewAd) and
--      physical posting (PostAd) are handled by their own procedures.
--      This procedure must be called inside a transaction the CALLER controls.
CREATE OR ALTER PROCEDURE SubmitAd
    @_PosterID INT,
    @_Title    VARCHAR(128),
    @_AdType   VARCHAR(20),
    @_AdLength INT,
    @_AdWidth  INT,
    @_Duration INT = 14,
    @_AdID     INT = NULL OUTPUT
AS
BEGIN
    IF NOT EXISTS (SELECT 1 FROM Person WHERE PersonID = @_PosterID)
    BEGIN
        RAISERROR('Error: No person exists with the given PosterID.', 16, 1);
        RETURN;
    END

    IF @_Title IS NULL OR LTRIM(RTRIM(@_Title)) = ''
    BEGIN
        RAISERROR('Error: Title is required.', 16, 1);
        RETURN;
    END

    IF @_AdType NOT IN ('Tutorship', 'Rent', 'Sale', 'Roommate', 'Event', 'Service', 'Other')
    BEGIN
        RAISERROR('Error: Invalid ad type. Allowed values are Tutorship, Rent, Sale, Roommate, Event, Service, or Other.', 16, 1);
        RETURN;
    END

    IF @_AdLength IS NULL OR @_AdLength <= 0 OR @_AdWidth IS NULL OR @_AdWidth <= 0
    BEGIN
        RAISERROR('Error: Ad length and width must both be positive.', 16, 1);
        RETURN;
    END

    IF @_Duration IS NULL OR @_Duration <= 0
    BEGIN
        RAISERROR('Error: Duration must be positive.', 16, 1);
        RETURN;
    END

    INSERT INTO Ad (PosterID, Title, AdType, AdLength, AdWidth, Duration)
    VALUES (@_PosterID, @_Title, @_AdType, @_AdLength, @_AdWidth, @_Duration);

    SET @_AdID = SCOPE_IDENTITY();
END
GO

BEGIN TRANSACTION;
    DECLARE @NewAd INT;
    EXEC SubmitAd
        @_PosterID = 3, @_Title = 'Kayak for Sale', @_AdType = 'Sale',
        @_AdLength = 350, @_AdWidth = 90, @_AdID = @NewAd OUTPUT;
    SELECT * FROM Ad WHERE AdID = @NewAd;
ROLLBACK TRANSACTION;

-- Should fail - invalid ad type
BEGIN TRANSACTION;
    DECLARE @BadAd INT;
    EXEC SubmitAd
        @_PosterID = 1, @_Title = 'Test', @_AdType = 'Rummage',
        @_AdLength = 100, @_AdWidth = 100, @_AdID = @BadAd OUTPUT;
ROLLBACK TRANSACTION;