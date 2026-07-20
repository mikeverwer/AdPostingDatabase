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

SELECT A.AdID,
       A.Title,
       (
            SELECT COUNT(*)
            FROM Messages AS M
            WHERE M.AdID = A.AdID
        ) AS NumMessages
FROM Ad A;

-- -------------------------------------------------------------------------------

GO
-- Q2) Retrieve all messages about a given ad, showing sender and recipient names, message content, and timestamp.
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

-- Q3) Calculate total number of messages sent and recieved per user
SELECT
    P.PersonID,
	CONCAT(P.FirstName, ' ', P.LastName) AS UserName,
    SentCounts.NumSent,
    RecievedCounts.NumRecieved
FROM 
    Person AS P
    LEFT JOIN (
        SELECT SenderID, COUNT(SenderID) AS NumSent
        FROM Messages
        GROUP BY SenderID
    ) AS SentCounts ON P.PersonID = SentCounts.SenderID
    LEFT JOIN (
        SELECT RecipientID, COUNT(RecipientID) AS NumRecieved
        FROM Messages
        GROUP BY RecipientID
    ) AS RecievedCounts ON P.PersonID = RecievedCounts.RecipientID;

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
-- Q5) Create to list board occupancy details: board size, total ad sizes, and remaining board space.
CREATE OR ALTER VIEW BoardSpace AS
SELECT 
    B.Building,
    B.BldgFloor,
    B.Slot,
    B.BoardWidth,
    B.BoardLength,
    (B.BoardWidth * B.BoardLength) AS BoardArea,
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
FROM BoardSpace
ORDER BY
    Building, 
    BldgFloor, 
    Slot;

SELECT * FROM Board;

-- -------------------------------------------------------------------------------

GO
-- Q6) Procedure to evaluate if a given ad will fit on each board
CREATE OR ALTER PROCEDURE CheckAdFit 
@_AdID INT 
AS
BEGIN
    SELECT 
        B.Building,
        B.BldgFloor,
        B.Slot,
        B.RemainingBoardSpace,
        CASE 
            WHEN B.RemainingBoardSpace - A.AdLength * A.AdWidth > 0 THEN 'May Fit'
            ELSE 'Will Not Fit'
        END AS FitStatus
    FROM
        BoardSpace AS B
        CROSS JOIN Ad as A
    WHERE A.AdID = @_AdID 
    ORDER BY B.RemainingBoardSpace;
END
GO

EXEC CheckAdFit @_AdID = 1;

-- -------------------------------------------------------------------------------

-- Q7) Find largest ad(s) posted to a board by area, displaying ad dimensions
SELECT
    A.AdID,
    A.AdLength,
    A.AdWidth,
    A.AdLength * A.AdWidth AS AdArea
FROM 
    Ad As A 
    INNER JOIN Ad_Posted_Board AS APB ON A.AdID = APB.AdID
WHERE 
    A.AdLength * A.AdWidth = (
        SELECT MAX(AdLength * AdWidth)
        FROM Ad AS A2
        INNER JOIN Ad_Posted_Board AS APB2 ON A2.AdID = APB2.AdID
    );

-- -------------------------------------------------------------------------------

-- Q8) Show number of ads on each board
SELECT 
    B.Building, 
    B.BldgFloor, 
    B.Slot,
    COUNT(APB.AdID) AS NumAds
FROM Board AS B 
    LEFT JOIN Ad_Posted_Board AS APB ON 
        B.Building = APB.Building AND 
        B.BldgFloor = APB.BldgFloor AND 
        B.Slot = APB.Slot
GROUP BY
    B.Building, 
    B.BldgFloor, 
    B.Slot;

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

-- Q10) Display counts of adds rejected and ads approved for each reviewer
SELECT 
    R.PersonID,
    CONCAT(P.FirstName, ' ', P.LastName) AS ReviewerName,
    COUNT(CASE WHEN A.AdStatus = 'Approved' THEN 1 END) AS ApprovedCount,
    COUNT(CASE WHEN A.AdStatus = 'Rejected' THEN 1 END) AS RejectedCount
FROM 
    Employee AS R
    INNER JOIN Person AS P ON R.PersonID = P.PersonID
    INNER JOIN Ad as A ON R.PersonID = A.ReviewerID
GROUP BY
    R.PersonID,
    P.FirstName,
    P.LastName;

-- -------------------------------------------------------------------------------

-- Q11) Show ads that are approved but not posted yet
SELECT * 
FROM Ad AS A
WHERE 
    A.AdStatus = 'Approved' AND 
    A.AdID NOT IN (
        SELECT AdID FROM Ad_Posted_Board
    );

-- -------------------------------------------------------------------------------

-- Q12) Show ads that are posted to multiple boards
SELECT 
    AdID, 
    COUNT(DISTINCT CONCAT(Building, BldgFloor, Slot)) AS PostingCount
FROM Ad_Posted_Board
GROUP BY 
    AdID
HAVING 
    COUNT(DISTINCT CONCAT(Building, BldgFloor, Slot)) > 1;

-- -------------------------------------------------------------------------------

-- Q13) Find people who have posted at least one rejected ad showing poster, ad title, and reviewer name
SELECT 
    P.PersonID,
    CONCAT(P.FirstName, ' ', P.LastName) AS PosterName,
    A.AdID,
    A.Title,
    CONCAT(R.FirstName, ' ', R.LastName) AS ReviewerName
FROM 
    Person AS P
    INNER JOIN Ad AS A ON P.PersonID = A.PosterID 
    INNER JOIN Person AS R ON R.PersonID = A.ReviewerID
WHERE A.AdStatus = 'Rejected';

-- -------------------------------------------------------------------------------

GO
-- Q14) Create a veiw to show ads per user type
CREATE OR ALTER VIEW AdsByUserType AS
SELECT 
    A.AdID,
    A.PosterID,
    CASE 
        WHEN A.PosterID IN (
            SELECT S.PersonID 
            FROM Student) 
        THEN 'Student'
        WHEN A.PosterID IN (
            SELECT E.PersonID 
            FROM Employee 
            WHERE E.PositionTitle = 'Faculty') 
        THEN 'Faculty'
        WHEN A.PosterID IN (
            SELECT E.PersonID 
            FROM Employee 
            WHERE E.PositionTitle != 'Faculty') 
        THEN 'Staff'
        WHEN A.PosterID NOT IN (
            SELECT CM.PersonID 
            FROM CollegeMember) 
        THEN 'Non-Member'
        ELSE 'Non-Member'
    END AS UserType
FROM 
    Ad AS A
    LEFT JOIN Person AS P ON A.PosterID = P.PersonID
    LEFT JOIN CollegeMember AS CM ON A.PosterID = CM.PersonID
    LEFT JOIN Employee AS E ON A.PosterID = E.PersonID
    LEFT JOIN Student AS S ON A.PosterID = S.PersonID
GO

SELECT * 
FROM AdsByUserType
ORDER BY UserType, PosterID

-- -------------------------------------------------------------------------------

-- Q15) Count ads per user type
SELECT 
    UserType,
    COUNT(AdID) AS NumAds
FROM AdsByUserType
GROUP BY 
    UserType;

-- -------------------------------------------------------------------------------

-- Q16) Count all ads by Ad Type
SELECT 
    AdType,
    COUNT(AdID) AS AdCount
FROM Ad
GROUP BY
    AdType;

-- -------------------------------------------------------------------------------

GO
-- Q17) Approve or Reject an ad
CREATE OR ALTER PROCEDURE ReviewAd 
    @_AdID INT,
    @_Status VARCHAR(10),
    @_ReviewerID INT,
    @_PostDate DATE = NULL
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
        PostDate = 
            CASE
                WHEN @_Status = 'Approved' THEN
                CASE    
                    WHEN @_PostDate IS NULL THEN CAST(GETDATE() AS DATE)
                    ELSE @_PostDate
                END
                ELSE NULL
            END,
        ReviewerID = 
            CASE
                WHEN @_Status = 'Pending' THEN NULL
                ELSE @_ReviewerID
            END
    WHERE AdID = @_AdID
END
GO

BEGIN TRANSACTION;
    EXEC ReviewAd @_AdID = 16, @_Status = 'Approved', @_ReviewerID = 19;
ROLLBACK TRANSACTION;
-- -------------------------------------------------------------------------------

GO
-- Q18) Assign a reviewer
CREATE OR ALTER PROCEDURE AssignReviewer
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
    EXEC AssignReviewer @_EmpID=20, @_IsRev=1;
ROLLBACK TRANSACTION;
-- -------------------------------------------------------------------------------

-- Q19) Create a procedure to post an ad to a given board
    -- this implementation assumes that the user has confirmed 
    -- that the ad will fit on the board separately.
GO
CREATE OR ALTER PROCEDURE PostAd
    @_AdID  INT,
    @_Bldg  VARCHAR(4),
    @_Floor INT,
    @_Slot  CHAR(1)
AS
BEGIN
    -- check if AdID is valid
        -- must be approved ad
        -- must not be expired
    IF @_AdID IS NULL OR @_AdID NOT IN (
        SELECT AdID
        FROM Ad
        WHERE 
            AdStatus = 'Approved'
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

BEGIN TRANSACTION;
    EXEC PostAd()

-- -------------------------------------------------------------------------------

-- Q20) Show Contact information of poster of a given ad
GO
CREATE OR ALTER PROCEDURE GetPosterInfo
    @_AdID INT
AS
BEGIN
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

-- Q21) Delete posted ads that are expired
BEGIN TRANSACTION;
    DELETE APB
    FROM Ad_Posted_Board AS APB
    JOIN vw_ExpiredAds AS EA ON APB.AdID = EA.AdID;
ROLLBACK TRANSACTION;
