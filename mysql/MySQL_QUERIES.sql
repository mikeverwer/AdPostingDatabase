--    Created by Mike Verwer | mikeverwer.github.io
-- ** ALL QUERIES IN THIS FILE WORK IN MySQL **

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

-- Q1) Count how many messages each ad has
DROP VIEW IF EXISTS vw_NumMessagesPerAd;

CREATE VIEW vw_NumMessagesPerAd AS
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

-- Q2) Retrieve all messages about a given ad, showing sender and recipient names, message content, and timestamp.
DROP PROCEDURE IF EXISTS GetAllADMessages;

DELIMITER $$

CREATE PROCEDURE GetAllADMessages (p_AdID INT)
BEGIN
    SELECT 
        CONCAT(S.FirstName, ' ', S.LastName) AS SenderName,
        CONCAT(R.FirstName, ' ', R.LastName) AS RecipientName,
        M.Content,
        M.TimeLogged
    FROM 
        Messages AS M 
        INNER JOIN Person AS S ON M.SenderID   = S.PersonID
        INNER JOIN Person AS R ON M.RecipientID = R.PersonID
    WHERE M.AdID = p_AdID
    ORDER BY M.TimeLogged;
END$$

DELIMITER ;

CALL GetAllADMessages(1);
-- -------------------------------------------------------------------------------

-- Q3) Calculate total number of messages sent and recieved per user
DROP VIEW IF EXISTS vw_MessageCountsPerUser;

CREATE VIEW vw_MessageCountsPerUser AS
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

-- -------------------------------------------------------------------------------

-- Q4) Create a view of all approved ads for each board
DROP VIEW IF EXISTS PostedAdsInfo;

CREATE VIEW PostedAdsInfo AS
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

SELECT *
FROM PostedAdsInfo
ORDER BY Building, BldgFloor, Slot;

-- -------------------------------------------------------------------------------

-- Q5) Create View to list board occupancy details: board size, total ad sizes, and remaining board space.
DROP VIEW IF EXISTS vw_BoardSpace;

CREATE VIEW vw_BoardSpace AS
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

SELECT *
FROM vw_BoardSpace
ORDER BY
    Building, 
    BldgFloor, 
    Slot;

-- -------------------------------------------------------------------------------

-- Q6) Create a display view for board occupancy details.
DROP VIEW IF EXISTS vw_BoardSpaceDisplay;

CREATE VIEW vw_BoardSpaceDisplay AS
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

SELECT *
FROM vw_BoardSpaceDisplay
ORDER BY FullnessRank;

-- -------------------------------------------------------------------------------

-- Q7) Procedure to evaluate if a given ad will fit on each board
DROP PROCEDURE IF EXISTS CheckAdFit;

DELIMITER $$
CREATE PROCEDURE CheckAdFit (p_AdID INT)
BEGIN
    SELECT 
        B.Building,
        B.BldgFloor,
        B.Slot,
        FORMAT(B.RemainingBoardSpace, 0) AS 'Available Space (cm²)',
        CASE 
            WHEN B.RemainingBoardSpace - A.AdLength * A.AdWidth > 0 THEN 'May Fit'
            ELSE 'Will Not Fit'
        END AS FitStatus
    FROM
        vw_BoardSpace AS B
        CROSS JOIN Ad AS A
    WHERE A.AdID = p_AdID 
    ORDER BY B.RemainingBoardSpace DESC;
END$$

DELIMITER ;

CALL CheckAdFit(1);

-- -------------------------------------------------------------------------------

-- Q9) Find all ads that are past duration
CREATE OR REPLACE VIEW vw_ExpiredAds AS
SELECT 
    AdID, 
    PostDate, 
    Duration, 
    DATEDIFF(CURRENT_DATE(), PostDate) - Duration AS DaysOverdue
FROM Ad
WHERE 
    DATEDIFF(CURRENT_DATE(), PostDate) - Duration >= 0; 

SELECT * FROM vw_ExpiredAds;

-- -------------------------------------------------------------------------------

-- Q10) Display counts of adds rejected and ads approved for each reviewer
DROP VIEW IF EXISTS vw_ReviewCountsPerReviewer;

CREATE VIEW vw_ReviewCountsPerReviewer AS
SELECT 
    R.PersonID,
    CONCAT(P.FirstName, ' ', P.LastName) AS ReviewerName,
    SUM(CASE WHEN A.AdStatus = 'Approved' THEN 1 ELSE 0 END) AS ApprovedCount,
    SUM(CASE WHEN A.AdStatus = 'Rejected' THEN 1 ELSE 0 END) AS RejectedCount,
    SUM(CASE WHEN A.AdStatus IN ('Approved', 'Rejected') THEN 1 ELSE 0 END) AS TotalReviews
FROM 
    Employee AS R
    LEFT JOIN Person AS P ON R.PersonID = P.PersonID
    LEFT JOIN Ad AS A ON R.PersonID = A.ReviewerID
WHERE R.IsReviewer = 1
GROUP BY
    R.PersonID,
    P.FirstName,
    P.LastName;
    
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

SELECT * FROM vw_ReviewCountsPerReviewer
WHERE PersonID IS NOT NULL
ORDER BY TotalReviews DESC;

-- -------------------------------------------------------------------------------

-- Q11) Show ads that are approved but not posted yet
DROP VIEW IF EXISTS vw_PendingPosting;

CREATE VIEW vw_PendingPosting AS
SELECT * 
FROM Ad AS A
WHERE 
    A.AdStatus = 'Approved' 
    AND NOT EXISTS (
        SELECT 1 
        FROM Ad_Posted_Board AS APB 
        WHERE APB.AdID = A.AdID
    );

-- -------------------------------------------------------------------------------

-- Q12) Procedure to find all the information and locations of a posted ad
DROP PROCEDURE IF EXISTS GetAdPostings;

DELIMITER $$

CREATE PROCEDURE GetAdPostings
(
    p_AdID INT
)
BEGIN
    SELECT *
    FROM PostedAdsInfo
    WHERE AdID = p_AdID;
END$$

DELIMITER ;

CALL GetAdPostings(4);


-- -------------------------------------------------------------------------------

-- Q13) Procedure to find people who have posted multiple rejected ads
DROP PROCEDURE IF EXISTS GetNoncompliantPosters;

DELIMITER $$

CREATE PROCEDURE GetNoncompliantPosters
(
    p_MinRejections INT
)
BEGIN

    IF p_MinRejections IS NULL THEN
        SET p_MinRejections = 2;
    END IF;

    SELECT
        P.PersonID,
        CONCAT(P.FirstName, ' ', P.LastName) AS PosterName,
        COUNT(DISTINCT A.AdID) AS RejectedAdCount
    FROM
        Person AS P
        INNER JOIN Ad AS A ON P.PersonID = A.PosterID
    WHERE A.AdStatus = 'Rejected'
    GROUP BY P.PersonID, P.FirstName, P.LastName
    HAVING COUNT(DISTINCT A.AdID) >= p_MinRejections;
END$$

DELIMITER ;

CALL GetNoncompliantPosters(NULL);

-- -------------------------------------------------------------------------------

-- Q14) Procedure to find the rejection history of a user (poster)
DROP PROCEDURE IF EXISTS GetPosterRejectionHistory;

DELIMITER $$

CREATE PROCEDURE GetPosterRejectionHistory (
    IN p_PosterID INT
)
BEGIN
    IF NOT EXISTS (SELECT 1 FROM Person WHERE PersonID = p_PosterID) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Error: No person exists with the given PersonID.';
    END IF;

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
        A.PosterID = p_PosterID
        AND A.AdStatus = 'Rejected'
    ORDER BY A.AdID;
END$$

DELIMITER ;

CALL GetPosterRejectionHistory(18);

-- -------------------------------------------------------------------------------

-- Q15) Create a veiw to show ads per user type
DROP VIEW IF EXISTS AdsByUserType;

CREATE VIEW AdsByUserType AS
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

SELECT * 
FROM AdsByUserType
ORDER BY UserType, PosterID;

-- -------------------------------------------------------------------------------

-- Q16) Pivot table of ads by user type x ad type
DROP VIEW IF EXISTS vw_AdsByUserTypeAndAdType;

CREATE VIEW vw_AdsByUserTypeAndAdType AS
SELECT
    IFNULL(UserType, 'Total') AS UserType,
    SUM(CASE WHEN AdType = 'Tutorship' THEN 1 ELSE 0 END) AS Tutorship,
    SUM(CASE WHEN AdType = 'Rent'      THEN 1 ELSE 0 END) AS Rent,
    SUM(CASE WHEN AdType = 'Sale'      THEN 1 ELSE 0 END) AS Sale,
    SUM(CASE WHEN AdType = 'Roommate'  THEN 1 ELSE 0 END) AS Roommate,
    SUM(CASE WHEN AdType = 'Event'     THEN 1 ELSE 0 END) AS Event,
    COUNT(*) AS RowTotal
FROM AdsByUserType
GROUP BY UserType WITH ROLLUP;

SELECT * FROM vw_AdsByUserTypeAndAdType;

-- -------------------------------------------------------------------------------

-- Q17) Create a view for the review queue
DROP VIEW IF EXISTS vw_ReviewQueue;

CREATE VIEW vw_ReviewQueue AS
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

SELECT * FROM vw_ReviewQueue;

-- -------------------------------------------------------------------------------

-- Q17) Approve or Reject an ad
DROP PROCEDURE IF EXISTS ReviewAd;

DELIMITER $$

CREATE PROCEDURE ReviewAd 
(
    IN p_AdID INT,
    IN p_Status VARCHAR(10),
    IN p_ReviewerID INT,
    IN p_ReviewDate DATE
)
BEGIN
    -- Validate status
    IF p_Status NOT IN ('Approved', 'Rejected', 'Pending') THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Invalid status. Allowed values are Approved, Rejected, or Pending';
    END IF;

    -- Validate reviewer
    IF p_ReviewerID IS NULL OR p_ReviewerID NOT IN (
        SELECT PersonID 
        FROM Employee 
        WHERE IsReviewer = 1
    ) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Invalid Reviewer ID. Only a Reviewer can evaluate an ad.';
    END IF;

    UPDATE Ad
    SET 
        AdStatus = p_Status,
        ReviewDate = 
            CASE
                WHEN p_Status != 'Pending' THEN
                    IFNULL(p_ReviewDate, CURDATE())
                ELSE NULL
            END,
        ReviewerID = 
            CASE
                WHEN p_Status != 'Pending' THEN p_ReviewerID
                ELSE NULL
            END
    WHERE AdID = p_AdID;
END$$

DELIMITER ;

START TRANSACTION;
    CALL ReviewAd(16, 'Approved', 19, NULL);
ROLLBACK;

-- -------------------------------------------------------------------------------

-- Q18) Set IsReviewer role for an employee
DROP PROCEDURE IF EXISTS SetReviewerPermission;

DELIMITER $$

CREATE PROCEDURE SetReviewerPermission
(
    IN p_EmpID INT,
    IN p_IsRev BIT
)
BEGIN
    IF p_EmpID IS NULL OR p_EmpID NOT IN (
        SELECT PersonID
        FROM Employee
    ) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Invalid ID. Only an employee can be a reviewer';
    END IF;

    UPDATE Employee
    SET IsReviewer = p_IsRev
    WHERE PersonID = p_EmpID;
END$$

DELIMITER ;

START TRANSACTION;
    CALL SetReviewerPermission(20, 1);
ROLLBACK;
-- ------------------------------------------------------------------------------

-- Q19) Create a procedure to post an ad to a given board
    -- this implementation assumes that the user has confirmed 
    -- that the ad will fit on the board separately.
DROP PROCEDURE IF EXISTS PostAd;

DELIMITER $$

CREATE PROCEDURE PostAd (
    -- This procedure must be called inside a transaction the CALLER controls
    -- (START TRANSACTION ... COMMIT/ROLLBACK), so the lock below is held for
    -- the full validate-then-insert sequence instead of just one statement.
    IN p_AdID INT,
    IN p_Bldg VARCHAR(4),
    IN p_Floor INT,
    IN p_Slot CHAR(1)
)
BEGIN
    -- check if AdID is valid: must be an approved ad
    IF NOT EXISTS (
        SELECT 1
        FROM Ad
        WHERE 
            AdStatus = 'Approved'
            AND AdID = p_AdID
        FOR UPDATE
    ) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Error: Ad is not approved.';
    END IF;

    -- check the ad has not expired
    IF p_AdID IN (SELECT AdID FROM vw_ExpiredAds) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Error: Ad posting duration has expired.';
    END IF;

    -- check if given board is valid
    IF NOT EXISTS (
        SELECT 1
        FROM Board  
        WHERE
            Building = p_Bldg AND
            BldgFloor = p_Floor AND
            Slot = p_Slot
    ) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: The given board information does not correspond to a valid board.';
    END IF;

    INSERT INTO Ad_Posted_Board (AdID, Building, BldgFloor, Slot)
    VALUES (p_AdID, p_Bldg, p_Floor, p_Slot);
END$$

DELIMITER ;

-- Posted ad should pass
START TRANSACTION;
    CALL ReviewAd(16, 'Approved', 19, NULL);
    CALL PostAd(16, 'LIB', 1, 'A');
ROLLBACK;

-- Posted ad should fail - ad not approved
START TRANSACTION;
    CALL PostAd(16, 'LIB', 1, 'A');
ROLLBACK;


-- -------------------------------------------------------------------------------

-- Q20) Show Contact information of poster of a given ad
DROP PROCEDURE IF EXISTS GetPosterInfo;

DELIMITER $$

CREATE PROCEDURE GetPosterInfo
(
    IN p_AdID INT
)
BEGIN
    IF NOT EXISTS (SELECT 1 FROM Ad WHERE AdID = p_AdID) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Error: No ad exists with the given AdID.';
    END IF;

    SELECT 
        CONCAT(P.FirstName, ' ', P.LastName) AS PosterName,
        P.Email,
        P.Phone,
        A.Title,
        A.AdType,
        CASE WHEN CM.PersonID IS NOT NULL THEN 'Yes' ELSE 'No' END AS IsCollegeMember,
        COALESCE (CM.Department, 'N/A') AS Department,
        CASE WHEN S.PersonID IS NOT NULL THEN 'Yes' ELSE 'No' END AS IsStudent,
        CASE 
            WHEN S.PersonID IS NOT NULL THEN COALESCE(S.Major, 'Undeclared')
            ELSE 'N/A'
        END AS Major,
        A.AdID
    FROM 
        Person AS P
        INNER JOIN Ad AS A 
            ON P.PersonID = A.PosterID
        LEFT JOIN CollegeMember AS CM
            ON P.PersonID = CM.PersonID
        LEFT JOIN Student AS S
            ON P.PersonID = S.PersonID
    WHERE A.AdID = p_AdID;
END$$

DELIMITER ;

CALL GetPosterInfo(1);

-- -------------------------------------------------------------------------------

-- Q21) Show Contact information of the reviewer of a given ad
DROP PROCEDURE IF EXISTS GetReviewerInfo;

DELIMITER $$

CREATE PROCEDURE GetReviewerInfo
(
    IN p_AdID INT
)
BEGIN
    IF NOT EXISTS (SELECT 1 FROM Ad WHERE AdID = p_AdID) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Error: No ad exists with the given AdID.';
    END IF;

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
    WHERE A.AdID = p_AdID;
END$$

DELIMITER ;

CALL GetReviewerInfo(4);

-- -------------------------------------------------------------------------------

-- Q22) Delete posted ads that are expired
START TRANSACTION;
    DELETE APB
    FROM Ad_Posted_Board AS APB
    JOIN vw_ExpiredAds AS EA ON APB.AdID = EA.AdID;
ROLLBACK;

-- -------------------------------------------------------------------------------

-- Q23) Find posted ads that are not approved (possible if a posted ad goes through
--      a re-review)
DROP VIEW IF EXISTS vw_UnapprovedPostings;

CREATE VIEW vw_UnapprovedPostings AS
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

-- -------------------------------------------------------------------------------

-- Q24) Remove an unapproved ad from the Ad_Posted_Board table.
--      If a specific board is given, it will only remove the ad from that board,
--      otherwise it will remove it from all boards it is currently on.
DROP PROCEDURE IF EXISTS UnpostAd;

DELIMITER $$

CREATE PROCEDURE UnpostAd (
    IN p_AdID      INT,
    IN p_Building  VARCHAR(4),
    IN p_BldgFloor INT,
    IN p_Slot      CHAR(1)
)
BEGIN
    IF NOT EXISTS (SELECT 1 FROM Ad WHERE AdID = p_AdID) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Error: No ad exists with the given AdID.';
    END IF;

    IF (p_Building IS NOT NULL OR p_BldgFloor IS NOT NULL OR p_Slot IS NOT NULL)
       AND (p_Building IS NULL OR p_BldgFloor IS NULL OR p_Slot IS NULL) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Error: Building, BldgFloor, and Slot must all be supplied together, or all omitted to remove every posting.';
    END IF;

    IF p_Building IS NULL THEN
        IF NOT EXISTS (SELECT 1 FROM Ad_Posted_Board WHERE AdID = p_AdID) THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'Error: This ad is not currently posted to any board.';
        END IF;
        DELETE FROM Ad_Posted_Board WHERE AdID = p_AdID;
    ELSE
        IF NOT EXISTS (
            SELECT 1 FROM Ad_Posted_Board 
            WHERE AdID = p_AdID AND Building = p_Building 
              AND BldgFloor = p_BldgFloor AND Slot = p_Slot
        ) THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'Error: This ad is not currently posted to the given board.';
        END IF;
        DELETE FROM Ad_Posted_Board 
        WHERE AdID = p_AdID AND Building = p_Building 
          AND BldgFloor = p_BldgFloor AND Slot = p_Slot;
    END IF;
END$$

DELIMITER ;

-- CALL UnpostAd(7, NULL, NULL, NULL);
-- CALL UnpostAd(7, 'BLD', 1, 'A');

-- -------------------------------------------------------------------------------

-- Q25) Add a person with no college affiliation.
--      Inserts into Person only. Use for members of the public who post ads.
--      This procedure must be called inside a transaction the CALLER controls
--      (START TRANSACTION ... COMMIT/ROLLBACK).
DROP PROCEDURE IF EXISTS AddNonMember;

DELIMITER $$

CREATE PROCEDURE AddNonMember (
    IN  p_FirstName VARCHAR(50),
    IN  p_LastName  VARCHAR(50),
    IN  p_Phone     CHAR(10),
    IN  p_Email     VARCHAR(50),
    OUT p_PersonID  INT
)
BEGIN
    SET p_PersonID = NULL;

    IF p_FirstName IS NULL OR TRIM(p_FirstName) = ''
       OR p_LastName IS NULL OR TRIM(p_LastName) = '' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Error: First and last name are required.';
    END IF;

    IF p_Email IS NULL OR TRIM(p_Email) = '' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Error: Email is required.';
    END IF;

    IF EXISTS (SELECT 1 FROM Person WHERE Email = p_Email) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Error: A person with the given email already exists.';
    END IF;

    INSERT INTO Person (FirstName, LastName, Phone, Email)
    VALUES (p_FirstName, p_LastName, p_Phone, p_Email);

    SET p_PersonID = LAST_INSERT_ID();
END$$

DELIMITER ;

START TRANSACTION;
    CALL AddNonMember('Dana', 'Whitfield', '5551239001', 'dana.whitfield@email.com', @NewNonMember);
    SELECT @NewNonMember AS NewPersonID;
ROLLBACK;

-- -------------------------------------------------------------------------------

-- Q26) Add a college member who is neither a student nor an employee.
--      Intended for people who retain a college ID and board privileges without
--      being enrolled or employed; alumni are the motivating case. Most
--      registrations should use AddStudent or AddEmployee instead, both of which
--      create the CollegeMember row themselves.
--      This procedure must be called inside a transaction the CALLER controls.
DROP PROCEDURE IF EXISTS AddCollegeMember;

DELIMITER $$

CREATE PROCEDURE AddCollegeMember (
    IN  p_FirstName  VARCHAR(50),
    IN  p_LastName   VARCHAR(50),
    IN  p_Phone      CHAR(10),
    IN  p_Email      VARCHAR(50),
    IN  p_CollegeID  CHAR(9),
    IN  p_Department VARCHAR(50),
    OUT p_PersonID   INT
)
BEGIN
    SET p_PersonID = NULL;

    IF p_CollegeID IS NULL OR TRIM(p_CollegeID) = '' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Error: College ID is required.';
    END IF;

    IF EXISTS (SELECT 1 FROM CollegeMember WHERE CollegeID = p_CollegeID) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Error: A college member with the given College ID already exists.';
    END IF;

    CALL AddNonMember(p_FirstName, p_LastName, p_Phone, p_Email, p_PersonID);

    INSERT INTO CollegeMember (PersonID, CollegeID, Department)
    VALUES (p_PersonID, p_CollegeID, p_Department);
END$$

DELIMITER ;

START TRANSACTION;
    CALL AddCollegeMember('Alan', 'Brouwer', '5551239002', 'alan.brouwer@college.edu',
                          'ALM000001', 'Alumni Relations', @NewMember);
    SELECT @NewMember AS NewPersonID;
ROLLBACK;

-- -------------------------------------------------------------------------------

-- Q27) Add a student. Inserts Person, CollegeMember, and Student.
--      Department (the student's academic department) and Major are both supplied
--      by the caller; they are related but distinct, and Major may be NULL for a
--      student who has not declared one.
--      This procedure must be called inside a transaction the CALLER controls.
DROP PROCEDURE IF EXISTS AddStudent;

DELIMITER $$

CREATE PROCEDURE AddStudent (
    IN  p_FirstName  VARCHAR(50),
    IN  p_LastName   VARCHAR(50),
    IN  p_Phone      CHAR(10),
    IN  p_Email      VARCHAR(50),
    IN  p_CollegeID  CHAR(9),
    IN  p_Department VARCHAR(50),
    IN  p_Major      VARCHAR(60),
    OUT p_PersonID   INT
)
BEGIN
    SET p_PersonID = NULL;

    CALL AddCollegeMember(p_FirstName, p_LastName, p_Phone, p_Email,
                          p_CollegeID, p_Department, p_PersonID);

    INSERT INTO Student (PersonID, Major)
    VALUES (p_PersonID, p_Major);
END$$

DELIMITER ;

START TRANSACTION;
    CALL AddStudent('Rosa', 'Iqbal', '5551239003', 'rosa.iqbal@college.edu',
                    'STU000018', 'Mathematics', 'Applied Mathematics', @NewStudent);
    SELECT @NewStudent AS NewPersonID;
ROLLBACK;

-- -------------------------------------------------------------------------------

-- Q28) Add an employee. Inserts Person, CollegeMember, and Employee.
--      Extension requires OfficeLocation (chk_employee_extension_requires_office);
--      an employee with no office must have both NULL.
--      This procedure must be called inside a transaction the CALLER controls.
DROP PROCEDURE IF EXISTS AddEmployee;

DELIMITER $$

CREATE PROCEDURE AddEmployee (
    IN  p_FirstName      VARCHAR(50),
    IN  p_LastName       VARCHAR(50),
    IN  p_Phone          CHAR(10),
    IN  p_Email          VARCHAR(50),
    IN  p_CollegeID      CHAR(9),
    IN  p_Department     VARCHAR(50),
    IN  p_OfficeLocation VARCHAR(15),
    IN  p_Extension      VARCHAR(6),
    IN  p_PositionTitle  VARCHAR(20),
    IN  p_IsReviewer     BIT,
    OUT p_PersonID       INT
)
BEGIN
    SET p_PersonID = NULL;

    IF p_PositionTitle NOT IN ('Faculty', 'Administration', 'Staff', 'Support', 'Specialized') THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Error: Invalid position title. Allowed values are Faculty, Administration, Staff, Support, or Specialized.';
    END IF;

    IF p_Extension IS NOT NULL AND p_OfficeLocation IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Error: An extension cannot be assigned without an office location.';
    END IF;

    CALL AddCollegeMember(p_FirstName, p_LastName, p_Phone, p_Email,
                          p_CollegeID, p_Department, p_PersonID);

    INSERT INTO Employee (PersonID, OfficeLocation, Extension, PositionTitle, IsReviewer)
    VALUES (p_PersonID, p_OfficeLocation, p_Extension, p_PositionTitle, IFNULL(p_IsReviewer, 0));
END$$

DELIMITER ;

START TRANSACTION;
    CALL AddEmployee('Yusuf', 'Demir', '5551239004', 'yusuf.demir@college.edu',
                     'EMP000012', 'Chemistry', 'SCI-215', '7215', 'Faculty', 0, @NewEmployee);
    SELECT @NewEmployee AS NewPersonID;
ROLLBACK;

-- Should fail - extension without an office
START TRANSACTION;
    CALL AddEmployee('Test', 'Case', NULL, 'test.case@college.edu',
                     'EMP000013', NULL, NULL, '9999', 'Support', 0, @BadEmployee);
ROLLBACK;

-- Should fail - duplicate email
START TRANSACTION;
    CALL AddStudent('Duplicate', 'Email', NULL, 'emma.johnson@college.edu',
                    'STU000019', NULL, NULL, @DupEmail);
ROLLBACK;

-- -------------------------------------------------------------------------------

-- Q29) Grant a person College Member status (Person -> CollegeMember).
--      Requires the person already exist in Person and not already be a
--      College Member. Use for someone gaining a College ID without yet
--      being a Student or Employee (e.g. an alum retaining board privileges).
DROP PROCEDURE IF EXISTS GrantCollegeMemberRole;

DELIMITER $$

CREATE PROCEDURE GrantCollegeMemberRole (
    IN p_PersonID   INT,
    IN p_CollegeID  CHAR(9),
    IN p_Department VARCHAR(50)
)
BEGIN
    IF NOT EXISTS (SELECT 1 FROM Person WHERE PersonID = p_PersonID) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Error: No person exists with the given PersonID.';
    END IF;

    IF EXISTS (SELECT 1 FROM CollegeMember WHERE PersonID = p_PersonID) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Error: This person already holds College Member status.';
    END IF;

    IF p_CollegeID IS NULL OR TRIM(p_CollegeID) = '' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Error: College ID is required.';
    END IF;

    IF EXISTS (SELECT 1 FROM CollegeMember WHERE CollegeID = p_CollegeID) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Error: A college member with the given College ID already exists.';
    END IF;

    INSERT INTO CollegeMember (PersonID, CollegeID, Department)
    VALUES (p_PersonID, p_CollegeID, p_Department);
END$$

DELIMITER ;

-- -------------------------------------------------------------------------------

-- Q30) Revoke College Member status (deletes the CollegeMember row).
--      Refuses if the person still holds Student or Employee status, since
--      both are structurally dependent on CollegeMember. Revoke those first.
DROP PROCEDURE IF EXISTS RevokeCollegeMemberRole;

DELIMITER $$

CREATE PROCEDURE RevokeCollegeMemberRole (
    IN p_PersonID INT
)
BEGIN
    IF NOT EXISTS (SELECT 1 FROM CollegeMember WHERE PersonID = p_PersonID) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Error: This person does not currently hold College Member status.';
    END IF;

    IF EXISTS (SELECT 1 FROM Student WHERE PersonID = p_PersonID) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Error: This person still holds Student status. Revoke it first.';
    END IF;

    IF EXISTS (SELECT 1 FROM Employee WHERE PersonID = p_PersonID) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Error: This person still holds Employee status. Revoke it first.';
    END IF;

    DELETE FROM CollegeMember WHERE PersonID = p_PersonID;
END$$

DELIMITER ;

-- -------------------------------------------------------------------------------

-- Q31) Grant a person Student status (CollegeMember -> Student).
--      Requires the person already hold College Member status. Does not
--      check Employee status either way, so this is also how a person who
--      already holds Employee status becomes a dual Student/Employee (e.g.
--      a graduate student TA).
DROP PROCEDURE IF EXISTS GrantStudentRole;

DELIMITER $$

CREATE PROCEDURE GrantStudentRole (
    IN p_PersonID INT,
    IN p_Major    VARCHAR(60)
)
BEGIN
    IF NOT EXISTS (SELECT 1 FROM CollegeMember WHERE PersonID = p_PersonID) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Error: This person must hold College Member status before being granted Student status.';
    END IF;

    IF EXISTS (SELECT 1 FROM Student WHERE PersonID = p_PersonID) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Error: This person already holds Student status.';
    END IF;

    INSERT INTO Student (PersonID, Major)
    VALUES (p_PersonID, p_Major);
END$$

DELIMITER ;

-- -------------------------------------------------------------------------------

-- Q32) Revoke Student status (deletes the Student row only; College Member
--      and, if held, Employee status are untouched).
DROP PROCEDURE IF EXISTS RevokeStudentRole;

DELIMITER $$

CREATE PROCEDURE RevokeStudentRole (
    IN p_PersonID INT
)
BEGIN
    IF NOT EXISTS (SELECT 1 FROM Student WHERE PersonID = p_PersonID) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Error: This person does not currently hold Student status.';
    END IF;

    DELETE FROM Student WHERE PersonID = p_PersonID;
END$$

DELIMITER ;

-- -------------------------------------------------------------------------------

-- Q33) Grant a person Employee status (CollegeMember -> Employee).
--      Requires the person already hold College Member status. Does not
--      check Student status either way, so this is also how an existing
--      Student becomes a dual Student/Employee (e.g. a graduate student TA).
--      Extension requires OfficeLocation. Not to be confused with
--      SetReviewerPermission, which only flips the IsReviewer flag on an
--      Employee row that already exists.
DROP PROCEDURE IF EXISTS GrantEmployeeRole;

DELIMITER $$

CREATE PROCEDURE GrantEmployeeRole (
    IN p_PersonID       INT,
    IN p_OfficeLocation VARCHAR(15),
    IN p_Extension      VARCHAR(6),
    IN p_PositionTitle  VARCHAR(20),
    IN p_IsReviewer     BIT
)
BEGIN
    IF NOT EXISTS (SELECT 1 FROM CollegeMember WHERE PersonID = p_PersonID) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Error: This person must hold College Member status before being granted Employee status.';
    END IF;

    IF EXISTS (SELECT 1 FROM Employee WHERE PersonID = p_PersonID) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Error: This person already holds Employee status.';
    END IF;

    IF p_PositionTitle NOT IN ('Faculty', 'Administration', 'Staff', 'Support', 'Specialized') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Error: Invalid position title. Allowed values are Faculty, Administration, Staff, Support, or Specialized.';
    END IF;

    IF p_Extension IS NOT NULL AND p_OfficeLocation IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Error: An extension cannot be assigned without an office location.';
    END IF;

    INSERT INTO Employee (PersonID, OfficeLocation, Extension, PositionTitle, IsReviewer)
    VALUES (p_PersonID, p_OfficeLocation, p_Extension, p_PositionTitle, IFNULL(p_IsReviewer, 0));
END$$

DELIMITER ;

-- -------------------------------------------------------------------------------

-- Q34) Revoke Employee status. Any ad this person has reviewed has its
--      ReviewerID explicitly cleared first (review history is preserved,
--      matching vw_ReviewCountsPerReviewer's existing handling of deleted
--      reviewers), then the Employee row is deleted. College Member and,
--      if held, Student status are untouched.
--      Not to be confused with SetReviewerPermission, which only flips the
--      IsReviewer flag; this removes the Employee row entirely.
DROP PROCEDURE IF EXISTS RevokeEmployeeRole;

DELIMITER $$

CREATE PROCEDURE RevokeEmployeeRole (
    IN p_PersonID INT
)
BEGIN
    IF NOT EXISTS (SELECT 1 FROM Employee WHERE PersonID = p_PersonID) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Error: This person does not currently hold Employee status.';
    END IF;

    UPDATE Ad SET ReviewerID = NULL WHERE ReviewerID = p_PersonID;

    DELETE FROM Employee WHERE PersonID = p_PersonID;
END$$

DELIMITER ;

-- -------------------------------------------------------------------------------
-- Demonstrates a graduate student TA: Priya Nair (PersonID 21, a Student) is
-- granted Employee status without giving up Student status.
START TRANSACTION;
    CALL GrantEmployeeRole(21, 'MTH-110', '7110', 'Staff', 0);
    SELECT * FROM Student WHERE PersonID = 21;
    SELECT * FROM Employee WHERE PersonID = 21;
ROLLBACK;

-- Should fail - RevokeCollegeMemberRole refuses while Student status remains
START TRANSACTION;
    CALL RevokeCollegeMemberRole(5);  -- Emma Johnson, a Student
ROLLBACK;

-- Should succeed - revoking Employee nulls ReviewerID on ads they reviewed
START TRANSACTION;
    SELECT COUNT(*) AS ReviewedBefore FROM Ad WHERE ReviewerID = 22;
    CALL RevokeEmployeeRole(22);  -- James Harris, a reviewer
    SELECT COUNT(*) AS ReviewedAfter FROM Ad WHERE ReviewerID = 22;  -- expect 0
ROLLBACK;