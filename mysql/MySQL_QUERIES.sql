-- 
-- Group 10
-- Members: Ivan Aupart, MySQL Expert
--          Mike Verwer, MS SQL Expert
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

SELECT A.AdID,
       A.Title,
       (
            SELECT COUNT(*)
            FROM Messages AS M
            WHERE M.AdID = A.AdID
        ) AS NumMessages
FROM Ad AS A;


-- -------------------------------------------------------------------------------

-- Q2) Retrieve all messages about a given ad, showing sender and recipient names, message content, and timestamp.
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

-- Q4) Create a view of all approved ads for each board
CREATE VIEW PostedAdsInfo AS
SELECT 
    APB.Building,
    APB.BldgFloor,
    APB.Place,
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

SELECT *
FROM PostedAdsInfo
ORDER BY Building, BldgFloor, Place;

-- -------------------------------------------------------------------------------

-- Q5) Create View to list board occupancy details: board size, total ad sizes, and remaining board space.
DROP VIEW IF EXISTS BoardSpace;

CREATE VIEW BoardSpace AS
SELECT 
    B.Building,
    B.BldgFloor,
    B.Place,
    B.BoardWidth,
    B.BoardLength,
    (B.BoardWidth * B.BoardLength) AS BoardArea,
    IFNULL(SUM(A.AdWidth * A.AdLength), 0) AS TotalAdArea,
    (B.BoardWidth * B.BoardLength) - IFNULL(SUM(A.AdWidth * A.AdLength), 0) AS RemainingBoardSpace
FROM 
    Board AS B
    LEFT JOIN (
        SELECT 
            APB.Building,
            APB.BldgFloor,
            APB.Place,
            A.AdWidth,
            A.AdLength
        FROM Ad_Posted_Board AS APB
        INNER JOIN Ad AS A ON A.AdID = APB.AdID
    ) AS A
    ON A.Building = B.Building 
    AND A.BldgFloor = B.BldgFloor 
    AND A.Place = B.Place
GROUP BY 
    B.Building, 
    B.BldgFloor, 
    B.Place,
    B.BoardWidth,
    B.BoardLength;


-- DROP VIEW BoardSpace;
SELECT *
FROM BoardSpace
ORDER BY
    Building, 
    BldgFloor, 
    Place;

SELECT * FROM Board;

-- -------------------------------------------------------------------------------

-- Q6) Procedure to evaluate if a given ad will fit on each board
DELIMITER $$
CREATE PROCEDURE CheckAdFit (p_AdID INT)
BEGIN
    SELECT 
        B.Building,
        B.BldgFloor,
        B.Place,
        B.RemainingBoardSpace,
        CASE 
            WHEN B.RemainingBoardSpace - A.AdLength * A.AdWidth > 0 THEN 'May Fit'
            ELSE 'Will Not Fit'
        END AS FitStatus
    FROM
        BoardSpace AS B
        CROSS JOIN Ad AS A
    WHERE A.AdID = p_AdID 
    ORDER BY B.RemainingBoardSpace;
END$$

DELIMITER ;

CALL CheckAdFit(1);

-- -------------------------------------------------------------------------------

-- Q7) Find largest ad(s) posted to a board by area, displaying ad dimensions
SELECT
    A.AdID,
    A.AdLength,
    A.AdWidth,
    A.AdLength * A.AdWidth AS AdArea
FROM 
    Ad AS A 
    INNER JOIN Ad_Posted_Board AS APB ON A.AdID = APB.AdID
WHERE 
    A.AdLength * A.AdWidth = (
        SELECT MAX(A2.AdLength * A2.AdWidth)
        FROM Ad AS A2
        INNER JOIN Ad_Posted_Board AS APB2 ON A2.AdID = APB2.AdID
    );

-- -------------------------------------------------------------------------------

-- Q8) Show number of ads on each board
SELECT 
    B.Building, 
    B.BldgFloor, 
    B.Place,
    COUNT(APB.AdID) AS NumAds
FROM Board AS B 
    LEFT JOIN Ad_Posted_Board AS APB ON 
        B.Building  = APB.Building AND 
        B.BldgFloor = APB.BldgFloor AND 
        B.Place     = APB.Place
GROUP BY
    B.Building, 
    B.BldgFloor, 
    B.Place;

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
SELECT 
    R.PersonID,
    CONCAT(P.FirstName, ' ', P.LastName) AS ReviewerName,
    SUM(CASE WHEN A.AdStatus = 'Approved' THEN 1 ELSE 0 END) AS ApprovedCount,
    SUM(CASE WHEN A.AdStatus = 'Rejected' THEN 1 ELSE 0 END) AS RejectedCount
FROM 
    Employee AS R
    INNER JOIN Person AS P ON R.PersonID = P.PersonID
    INNER JOIN Ad AS A ON R.PersonID = A.ReviewerID
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
    COUNT(DISTINCT CONCAT(Building, BldgFloor, Place)) AS PostingCount
FROM Ad_Posted_Board
GROUP BY 
    AdID
HAVING 
    COUNT(DISTINCT CONCAT(Building, BldgFloor, Place)) > 1;

-- -------------------------------------------------------------------------------

-- Q13) Find people who have posted at least one rejected ad showing poster, ad title, and reviewer name
SELECT DISTINCT 
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

-- Q14) Create a veiw to show ads per user type
CREATE VIEW AdsByUserType AS
SELECT 
    A.AdID,
    A.PosterID,
    CASE 
        WHEN A.PosterID IN (
            SELECT S.PersonID 
            FROM Student AS S) 
        THEN 'Student'
        WHEN A.PosterID IN (
            SELECT E.PersonID 
            FROM Employee AS E 
            WHERE E.PositionTitle = 'Faculty') 
        THEN 'Faculty'
        WHEN A.PosterID IN (
            SELECT E2.PersonID 
            FROM Employee AS E2 
            WHERE E2.PositionTitle <> 'Faculty') 
        THEN 'Staff'
        WHEN A.PosterID NOT IN (
            SELECT CM.PersonID 
            FROM CollegeMember AS CM) 
        THEN 'Non-Member'
        ELSE 'Non-Member'
    END AS UserType
FROM 
    Ad AS A
    LEFT JOIN Person AS P ON A.PosterID = P.PersonID
    LEFT JOIN CollegeMember AS CM ON A.PosterID = CM.PersonID
    LEFT JOIN Employee AS E ON A.PosterID = E.PersonID
    LEFT JOIN Student AS S ON A.PosterID = S.PersonID;

SELECT * 
FROM AdsByUserType
ORDER BY UserType, PosterID;

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

-- Q17) Approve or Reject an ad
DELIMITER $$

CREATE PROCEDURE ReviewAd 
(
    IN p_AdID INT,
    IN p_Status VARCHAR(10),
    IN p_ReviewerID INT,
    IN p_PostDate DATE
)
BEGIN
    -- Validate status
    IF p_Status NOT IN ('Approved', 'Rejected', 'Pending') THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Invalid status. Allowed values are Approved, Rejected, or Pending';
    END IF;

    -- Validate reviewer
    IF p_ReviewerID NOT IN (
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
        PostDate = 
            CASE
                WHEN p_Status = 'Approved' THEN
                    IFNULL(p_PostDate, CURDATE())
                ELSE NULL
            END,
        ReviewerID = 
            CASE
                WHEN p_Status = 'Pending' THEN NULL
                ELSE p_ReviewerID
            END
    WHERE AdID = p_AdID;
END$$

DELIMITER ;

-- DROP PROCEDURE ReviewAd;
CALL ReviewAd(16, 'Approved', 19, NULL);

SELECT * FROM Ad WHERE AdID = 16;

-- -------------------------------------------------------------------------------

-- Q18) Assign a reviewer
DELIMITER $$

CREATE PROCEDURE AssignReviewer
(
    IN p_EmpID INT,
    IN p_IsRev BIT
)
BEGIN
    IF p_EmpID NOT IN (
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

CALL AssignReviewer(20, 1);

-- ------------------------------------------------------------------------------

-- Q19) Create a procedure to post an ad to a given board
    -- this implementation assumes that the user has confirmed 
    -- that the ad will fit on the board separately.
DELIMITER $$

CREATE PROCEDURE PostAd
(
    IN p_AdID INT,
    IN p_Bldg CHAR(3),
    IN p_Floor INT,
    IN p_Plc CHAR(1)
)
BEGIN
    -- check if AdID is valid
        -- must be approved ad
        -- must not be expired
    IF p_AdID NOT IN (
        SELECT AdID
        FROM Ad
        WHERE 
            AdStatus = 'Approved' AND
            PostDate > CURDATE()
    ) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Error: Ad is either not approved, or expired.';
    END IF;

    -- check if given board is valid
    IF NOT EXISTS (
        SELECT 1
        FROM Board  
        WHERE
            Building = p_Bldg AND
            BldgFloor = p_Floor AND
            Place = p_Plc
    ) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: The given board information does not correspond to a valid board.';
    END IF;

    INSERT INTO Ad_Posted_Board (AdID, Building, BldgFloor, Place)
    VALUES (p_AdID, p_Bldg, p_Floor, p_Plc);
END$$

DELIMITER ;

-- -------------------------------------------------------------------------------

-- Q20) Show Contact information of poster of a given ad
DROP PROCEDURE IF EXISTS GetPosterInfo

DELIMITER $$

CREATE PROCEDURE GetPosterInfo
(
    IN p_AdID INT
)
BEGIN
    SELECT 
        CONCAT(P.FirstName, ' ', P.LastName) AS PosterName,
        P.Email,
        P.Phone,
        A.AdID,
        A.Title,
        A.AdType
    FROM 
        Person AS P
        INNER JOIN Ad AS A 
            ON P.PersonID = A.PosterID  
    WHERE A.AdID = p_AdID;
END$$

CALL GetPosterInfo(1);

-- -------------------------------------------------------------------------------

-- Q21) Delete posted ads that are expired
DELETE APB
FROM Ad_Posted_Board AS APB
JOIN vw_ExpiredAds AS EA ON APB.AdID = EA.AdID;

