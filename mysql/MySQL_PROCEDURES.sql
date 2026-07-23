--    Created by Mike Verwer | mikeverwer.github.io
-- ** ALL QUERIES IN THIS FILE WORK IN MySQL **
--
-- LOAD ORDER: 2 of 3
--   MySQL_VIEWS.sql  ->  MySQL_PROCEDURES.sql  ->  MySQL_TESTS.sql
-- Every view in MySQL_VIEWS.sql must exist before this file is run: PostAd
-- reads vw_ExpiredAds, GetAdPostings reads vw_PostedAdsInfo, and CheckAdFit reads
-- vw_BoardSpace. Procedures may call one another across categories
-- (WithdrawAd calls DeleteAdMessages), but MySQL resolves procedure bodies at
-- execution time, so the order within this file does not matter.
--
-- Procedures that mutate data are documented as requiring a caller-controlled
-- transaction. Every such call in MySQL_TESTS.sql is wrapped accordingly.
--
-- NOTE: validation failures here raise via SIGNAL SQLSTATE '45000' with no
-- following LEAVE. Unhandled, this aborts the procedure, which matches the
-- RAISERROR ... RETURN behaviour of the MSSQL versions. A caller that installs
-- a CONTINUE HANDLER would see execution fall through to the write instead.
-- Adding explicit LEAVE labels is tracked as separate work.

USE AdPostingDB;

-- =============================================================================
-- Person & Roles
-- Registering people and managing the roles they hold. Registration is
-- layered: AddNonMember inserts a bare Person, AddCollegeMember wraps it,
-- and AddStudent / AddEmployee wrap that in turn. The Grant/Revoke pairs
-- move an existing person between roles without re-registering them.
-- Also holds the two contact-lookup procedures.
-- =============================================================================

-- -------------------------------------------------------------------------------

-- Add a person with no college affiliation.
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

-- -------------------------------------------------------------------------------

-- Add a college member who is neither a student nor an employee.
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

-- -------------------------------------------------------------------------------

-- Add a student. Inserts Person, CollegeMember, and Student.
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

-- -------------------------------------------------------------------------------

-- Add an employee. Inserts Person, CollegeMember, and Employee.
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

-- -------------------------------------------------------------------------------

-- Grant a person College Member status (Person -> CollegeMember).
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

-- Revoke College Member status (deletes the CollegeMember row).
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

-- Grant a person Student status (CollegeMember -> Student).
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

-- Revoke Student status (deletes the Student row only; College Member
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

-- Grant a person Employee status (CollegeMember -> Employee).
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

-- Revoke Employee status. Any ad this person has reviewed has its
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

-- Set IsReviewer role for an employee. Only flips the flag on an existing
--      Employee row; see GrantEmployeeRole to create that row in the first place.
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

-- -------------------------------------------------------------------------------

-- Show Contact information of poster of a given ad
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
        A.AdID,
        A.ImageFileName
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

-- -------------------------------------------------------------------------------

-- Show Contact information of the reviewer of a given ad
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
        A.ReviewStatus,
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

-- =============================================================================
-- Ad Lifecycle & Review
-- Moving an ad through its states: submission, the review decision, and
-- poster-initiated withdrawal. Also holds the two rejection-history reports,
-- which read the outcome of that review process.
-- =============================================================================

-- -------------------------------------------------------------------------------

-- Submit a new ad for review. Inserts a new Ad row; every other column is
--      left to its table default, which produces ReviewStatus = 'Pending',
--      ReviewerID = NULL, PostDate = NULL, EnteredPending = today, and
--      ReviewDate = NULL -- a state that already satisfies every CHECK
--      constraint on Ad without further logic here. Review (ReviewAd) and
--      physical posting (PostAd) are handled by their own procedures.
--      This procedure must be called inside a transaction the CALLER controls.
--      p_Duration has no server-side default (MySQL procedure parameters
--      cannot carry one); pass NULL to fall back to the table's default of 14.
DROP PROCEDURE IF EXISTS SubmitAd;

DELIMITER $$

CREATE PROCEDURE SubmitAd (
    IN  p_PosterID      INT,
    IN  p_Title         VARCHAR(128),
    IN  p_AdType        VARCHAR(20),
    IN  p_AdLength      INT,
    IN  p_AdWidth       INT,
    IN  p_Duration      INT,
    IN  p_ImageFileName VARCHAR(255),
    OUT p_AdID          INT
)
BEGIN
    SET p_AdID = NULL;

    IF NOT EXISTS (SELECT 1 FROM Person WHERE PersonID = p_PosterID) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Error: No person exists with the given PosterID.';
    END IF;

    IF p_Title IS NULL OR TRIM(p_Title) = '' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Error: Title is required.';
    END IF;

    IF p_AdType NOT IN ('Tutorship', 'Rent', 'Sale', 'Roommate', 'Event', 'Service', 'Other') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Error: Invalid ad type. Allowed values are Tutorship, Rent, Sale, Roommate, Event, Service, or Other.';
    END IF;

    IF p_AdLength IS NULL OR p_AdLength <= 0 OR p_AdWidth IS NULL OR p_AdWidth <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Error: Ad length and width must both be positive.';
    END IF;

    IF p_Duration IS NOT NULL AND p_Duration <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Error: Duration must be positive.';
    END IF;

    IF p_ImageFileName IS NULL OR TRIM(p_ImageFileName) = '' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Error: Image file is required.';
    END IF;

    INSERT INTO Ad (PosterID, Title, AdType, AdLength, AdWidth, Duration)
    VALUES (p_PosterID, p_Title, p_AdType, p_AdLength, p_AdWidth, IFNULL(p_Duration, 14));

    SET p_AdID = LAST_INSERT_ID();
END$$

DELIMITER ;

-- -------------------------------------------------------------------------------

-- Approve or Reject an ad
DROP PROCEDURE IF EXISTS ReviewAd;

DELIMITER $$

CREATE PROCEDURE ReviewAd 
(
    -- This procedure must be called inside a transaction the CALLER controls
    -- (START TRANSACTION ... COMMIT/ROLLBACK), so the lock below is held for
    -- the full validate-then-update sequence instead of just one statement.
    IN p_AdID INT,
    IN p_Status VARCHAR(10),
    IN p_ReviewerID INT,
    IN p_ReviewDate DATE
)
BEGIN
    IF p_Status NOT IN ('Approved', 'Rejected', 'Pending') THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Invalid status. Allowed values are Approved, Rejected, or Pending';
    END IF;

    IF p_ReviewerID IS NULL OR p_ReviewerID NOT IN (
        SELECT PersonID FROM Employee WHERE IsReviewer = 1
    ) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Invalid Reviewer ID. Only a Reviewer can evaluate an ad.';
    END IF;

    IF EXISTS (
        SELECT 1 FROM Ad
        WHERE AdID = p_AdID AND IsWithdrawn = 1
        FOR UPDATE
    ) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Error: This ad has been withdrawn and can no longer be reviewed.';
    END IF;

    UPDATE Ad
    SET 
        ReviewStatus = p_Status,
        PostDate =
            CASE
                WHEN p_Status <> 'Approved' THEN NULL
                ELSE PostDate
            END,
        ReviewDate = 
            CASE
                WHEN p_Status != 'Pending' THEN IFNULL(p_ReviewDate, CURDATE())
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

-- -------------------------------------------------------------------------------

-- Withdraw an ad. Same behavior as the MSSQL version: poster-initiated,
--      sets IsWithdrawn/WithdrawnDate, purges messages via DeleteAdMessages,
--      leaves ReviewStatus and any board postings untouched.
--      This procedure must be called inside a transaction the CALLER controls.
DROP PROCEDURE IF EXISTS WithdrawAd;

DELIMITER $$

CREATE PROCEDURE WithdrawAd (
    IN  p_AdID                INT,
    IN  p_PosterID            INT,
    OUT p_DeletedMessageCount INT
)
BEGIN
    DECLARE v_ActualPosterID INT;
    DECLARE v_AlreadyWithdrawn BIT;

    SET p_DeletedMessageCount = NULL;

    SELECT PosterID, IsWithdrawn INTO v_ActualPosterID, v_AlreadyWithdrawn
    FROM Ad
    WHERE AdID = p_AdID
    FOR UPDATE;

    IF v_ActualPosterID IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Error: No ad exists with the given AdID.';
    END IF;

    IF v_ActualPosterID <> p_PosterID THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Error: Only the ad''s poster may withdraw it.';
    END IF;

    IF v_AlreadyWithdrawn = 1 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Error: This ad has already been withdrawn.';
    END IF;

    UPDATE Ad
    SET IsWithdrawn = 1, WithdrawnDate = CURDATE()
    WHERE AdID = p_AdID;

    CALL DeleteAdMessages(p_AdID, p_DeletedMessageCount);
END$$

DELIMITER ;

-- -------------------------------------------------------------------------------

-- Permanently delete an ad. Admin-initiated, and distinct from WithdrawAd:
--      withdrawal is a reversible-looking flag that preserves the ad record and
--      its review history, while this removes the row outright. Refuses while
--      the ad is still posted to any board, since fk_adpostedboard_ad is
--      ON DELETE CASCADE and would otherwise silently strip it from physical
--      boards with no takedown worklist entry -- run UnpostAd first (see
--      vw_PendingRemoval for the ads awaiting takedown). Messages are removed
--      explicitly via DeleteAdMessages, because fk_messages_ad is deliberately
--      NO ACTION rather than cascading.
--      The ad's ImageFileName is returned so the caller can clean up the stored
--      file; the database holds only the reference, not the file itself.
--      This procedure must be called inside a transaction the CALLER controls.
--      This procedure is a mederation tool, not to be used for clean-up.
DROP PROCEDURE IF EXISTS DeleteAd;

DELIMITER $$

CREATE PROCEDURE DeleteAd (
    IN  p_AdID                INT,
    IN  p_ReviewerID          INT,
    OUT p_DeletedMessageCount INT,
    OUT p_ImageFileName           VARCHAR(255)
)
BEGIN
    DECLARE v_PostedCount    INT;

    SET p_DeletedMessageCount = NULL;
    SET p_ImageFileName = NULL;

    SELECT ImageFileName INTO p_ImageFileName
    FROM Ad
    WHERE AdID = p_AdID
    FOR UPDATE;

    IF p_ImageFileName IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Error: No ad exists with the given AdID.';
    END IF;

    IF p_ReviewerID IS NULL OR p_ReviewerID NOT IN (
        SELECT PersonID FROM Employee WHERE IsReviewer = 1
    ) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Invalid Reviewer ID. Only a Reviewer can evaluate an ad.';
    END IF;

    SELECT COUNT(*) INTO v_PostedCount
    FROM Ad_Posted_Board
    WHERE AdID = p_AdID
    FOR UPDATE;

    IF v_PostedCount > 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Error: This ad is still posted to one or more boards. Unpost it first.';
    END IF;

    CALL DeleteAdMessages(p_AdID, p_DeletedMessageCount);

    DELETE FROM Ad WHERE AdID = p_AdID;
END$$

DELIMITER ;

-- -------------------------------------------------------------------------------

-- Procedure to find people who have posted multiple rejected ads.
--      p_MinRejections has no server-side default (MySQL procedure parameters
--      cannot carry one); pass NULL to fall back to 2.
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
    WHERE A.ReviewStatus = 'Rejected'
    GROUP BY P.PersonID, P.FirstName, P.LastName
    HAVING COUNT(DISTINCT A.AdID) >= p_MinRejections;
END$$

DELIMITER ;

-- -------------------------------------------------------------------------------

-- Procedure to find the rejection history of a user (poster)
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
        AND A.ReviewStatus = 'Rejected'
    ORDER BY A.AdID;
END$$

DELIMITER ;

-- =============================================================================
-- Board & Posting
-- Creating and retiring the physical boards, placing approved ads onto them,
-- removing them again, and the two read-only helpers for checking fit and
-- looking up where an ad currently hangs.
-- =============================================================================

-- -------------------------------------------------------------------------------

-- Add a new board. The only real constraint is that the location
--      (Building, BldgFloor, Slot) not already be in use.
DROP PROCEDURE IF EXISTS NewBoard;

DELIMITER $$

CREATE PROCEDURE NewBoard (
    IN p_Building    VARCHAR(4),
    IN p_BldgFloor   INT,
    IN p_Slot        CHAR(1),
    IN p_BoardLength INT,
    IN p_BoardWidth  INT
)
BEGIN
    IF EXISTS (
        SELECT 1 FROM Board
        WHERE Building = p_Building AND BldgFloor = p_BldgFloor AND Slot = p_Slot
    ) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Error: A board already exists at the given location.';
    END IF;

    IF p_BoardLength IS NULL OR p_BoardLength <= 0 OR p_BoardWidth IS NULL OR p_BoardWidth <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Error: Board length and width must both be positive.';
    END IF;

    INSERT INTO Board (Building, BldgFloor, Slot, BoardLength, BoardWidth)
    VALUES (p_Building, p_BldgFloor, p_Slot, p_BoardLength, p_BoardWidth);
END$$

DELIMITER ;

-- -------------------------------------------------------------------------------

-- Retire (permanently remove) a board. Refuses if any ad is currently
--      posted there -- fk_adpostedboard_board uses ON DELETE CASCADE, which
--      would otherwise silently remove those postings. Clear the board with
--      UnpostAd first. Hard delete: a board's identity is just its physical
--      location, and there's no history worth preserving once it's gone,
--      unlike the flag used for Ad withdrawal.
--      This procedure must be called inside a transaction the CALLER controls.
DROP PROCEDURE IF EXISTS RetireBoard;

DELIMITER $$

CREATE PROCEDURE RetireBoard (
    IN p_Building  VARCHAR(4),
    IN p_BldgFloor INT,
    IN p_Slot      CHAR(1)
)
BEGIN
    DECLARE v_PostedCount INT;

    IF NOT EXISTS (
        SELECT 1 FROM Board
        WHERE Building = p_Building AND BldgFloor = p_BldgFloor AND Slot = p_Slot
    ) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Error: No board exists at the given location.';
    END IF;

    SELECT COUNT(*) INTO v_PostedCount
    FROM Ad_Posted_Board
    WHERE Building = p_Building AND BldgFloor = p_BldgFloor AND Slot = p_Slot;
    FOR UPDATE;

    IF v_PostedCount > 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Error: This board still has ad(s) posted to it. Unpost them first.';
    END IF;

    DELETE FROM Board
    WHERE Building = p_Building AND BldgFloor = p_BldgFloor AND Slot = p_Slot;
END$$

DELIMITER ;

-- -------------------------------------------------------------------------------

-- Create a procedure to post an ad to a given board
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
            ReviewStatus = 'Approved'
            AND AdID = p_AdID
        FOR UPDATE
    ) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Error: Ad is not approved.';
    END IF;
    
    -- check the ad has not been withdrawn
    IF EXISTS (
        SELECT 1 FROM Ad WHERE AdID = p_AdID AND IsWithdrawn = 1
    ) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Error: This ad has been withdrawn and cannot be posted.';
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

    UPDATE Ad SET PostDate = CURDATE() WHERE AdID = p_AdID;
    INSERT INTO Ad_Posted_Board (AdID, Building, BldgFloor, Slot)
        VALUES (p_AdID, p_Bldg, p_Floor, p_Slot);
END$$

DELIMITER ;

-- -------------------------------------------------------------------------------

-- Remove an unapproved ad from the Ad_Posted_Board table.
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

-- -------------------------------------------------------------------------------

-- Procedure to evaluate if a given ad will fit on each board
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

-- -------------------------------------------------------------------------------

-- Procedure to find all the information and locations of a posted ad
DROP PROCEDURE IF EXISTS GetAdPostings;

DELIMITER $$

CREATE PROCEDURE GetAdPostings
(
    p_AdID INT
)
BEGIN
    SELECT *
    FROM vw_PostedAdsInfo
    WHERE AdID = p_AdID;
END$$

DELIMITER ;

-- =============================================================================
-- Messaging
-- Sending, retrieving, and deleting the messages exchanged about an ad.
-- DeleteAdMessages is also the mechanism WithdrawAd uses to clear
-- fk_messages_ad before flagging an ad as withdrawn.
-- =============================================================================

-- -------------------------------------------------------------------------------

-- Send a message about an ad. TimeLogged is left to its table default
--      (CURRENT_TIMESTAMP). Same two business rules as the MSSQL version:
--      the ad's poster must be sender or recipient, and messaging is only
--      allowed on an Approved ad unless the sender or recipient is a
--      reviewer generally (not necessarily this ad's own reviewer, since
--      there is currently no way to assign one before an outright decision).
--      Self-messaging is intentionally allowed.
--      This procedure must be called inside a transaction the CALLER controls.
DROP PROCEDURE IF EXISTS SendMessage;

DELIMITER $$

CREATE PROCEDURE SendMessage (
    IN p_SenderID    INT,
    IN p_AdID        INT,
    IN p_RecipientID INT,
    IN p_Content     TEXT
)
BEGIN
    DECLARE v_PosterID INT;
    DECLARE v_ReviewStatus VARCHAR(10);

    SELECT PosterID, ReviewStatus INTO v_PosterID, v_ReviewStatus
    FROM Ad WHERE AdID = p_AdID;

    IF EXISTS (SELECT 1 FROM Ad WHERE AdID = p_AdID AND IsWithdrawn = 1) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Error: This ad has been withdrawn; no further messages are allowed.';
    END IF;

    IF v_PosterID IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Error: No ad exists with the given AdID.';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM Person WHERE PersonID = p_SenderID) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Error: No person exists with the given SenderID.';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM Person WHERE PersonID = p_RecipientID) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Error: No person exists with the given RecipientID.';
    END IF;

    IF v_PosterID NOT IN (p_SenderID, p_RecipientID) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Error: This ad''s poster must be either the sender or the recipient.';
    END IF;

    IF v_ReviewStatus <> 'Approved'
       AND NOT EXISTS (
            SELECT 1 FROM Employee
            WHERE IsReviewer = 1 AND PersonID IN (p_SenderID, p_RecipientID)
       ) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Error: This ad is not Approved, and neither party is a reviewer.';
    END IF;

    IF p_Content IS NULL OR TRIM(p_Content) = '' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Error: Message content cannot be blank.';
    END IF;

    INSERT INTO Messages (SenderID, AdID, RecipientID, Content)
    VALUES (p_SenderID, p_AdID, p_RecipientID, p_Content);
END$$

DELIMITER ;

-- -------------------------------------------------------------------------------

-- Retrieve all messages about a given ad, showing sender and recipient names,
--     message content, and timestamp.
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

-- -------------------------------------------------------------------------------

-- Delete a single message, identified by its full primary key
--      (SenderID, AdID, TimeLogged). Messages has no surrogate key, so a
--      caller offering to delete one line of a displayed conversation needs
--      to pass back the exact triple it was given when the message was
--      retrieved.
--      This procedure must be called inside a transaction the CALLER controls.
DROP PROCEDURE IF EXISTS DeleteMessage;

DELIMITER $$

CREATE PROCEDURE DeleteMessage (
    IN p_SenderID   INT,
    IN p_AdID       INT,
    IN p_TimeLogged DATETIME
)
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM Messages
        WHERE SenderID = p_SenderID AND AdID = p_AdID AND TimeLogged = p_TimeLogged
    ) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Error: No message exists with the given SenderID, AdID, and TimeLogged.';
    END IF;

    DELETE FROM Messages
    WHERE SenderID = p_SenderID AND AdID = p_AdID AND TimeLogged = p_TimeLogged;
END$$

DELIMITER ;

-- -------------------------------------------------------------------------------

-- Delete every message attached to a given ad. This is the mechanism
--      WithdrawAd will use to clear fk_messages_ad (RESTRICT) before deleting
--      the Ad row itself -- that restriction is deliberate (see README), so
--      messages must be removed explicitly rather than cascaded away.
--      This procedure must be called inside a transaction the CALLER controls.
DROP PROCEDURE IF EXISTS DeleteAdMessages;

DELIMITER $$

CREATE PROCEDURE DeleteAdMessages (
    IN  p_AdID         INT,
    OUT p_DeletedCount INT
)
BEGIN
    SET p_DeletedCount = NULL;

    IF NOT EXISTS (SELECT 1 FROM Ad WHERE AdID = p_AdID) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Error: No ad exists with the given AdID.';
    END IF;

    DELETE FROM Messages WHERE AdID = p_AdID;
    SET p_DeletedCount = ROW_COUNT();
END$$

DELIMITER ;
