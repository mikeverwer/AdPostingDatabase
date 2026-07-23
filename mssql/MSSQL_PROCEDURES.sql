--    Created by Mike Verwer | mikeverwer.github.io
-- ** ALL QUERIES IN THIS FILE WORK IN MS SQL Server **
--
-- LOAD ORDER: 2 of 3
--   MSSQL_VIEWS.sql  ->  MSSQL_PROCEDURES.sql  ->  MSSQL_TESTS.sql
-- Every view in MSSQL_VIEWS.sql must exist before this file is run: PostAd
-- reads vw_ExpiredAds, GetAdPostings reads vw_PostedAdsInfo, and CheckAdFit reads
-- vw_BoardSpace. Procedures may call one another across categories
-- (WithdrawAd calls DeleteAdMessages), but SQL Server resolves procedure
-- bodies at execution time, so the order within this file does not matter.
--
-- Procedures that mutate data are documented as requiring a caller-controlled
-- transaction. Every such call in MSSQL_TESTS.sql is wrapped accordingly.

USE AdPostingDB;
GO

-- =============================================================================
-- Person & Roles
-- Registering people and managing the roles they hold. Registration is
-- layered: AddNonMember inserts a bare Person, AddCollegeMember wraps it,
-- and AddStudent / AddEmployee wrap that in turn. The Grant/Revoke pairs
-- move an existing person between roles without re-registering them.
-- Also holds the two contact-lookup procedures.
-- =============================================================================

-- -------------------------------------------------------------------------------
GO
-- Add a person with no college affiliation.
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

-- -------------------------------------------------------------------------------
GO
-- Add a college member who is neither a student nor an employee.
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

-- -------------------------------------------------------------------------------
GO
-- Add a student. Inserts Person, CollegeMember, and Student.
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

-- -------------------------------------------------------------------------------
GO
-- Add an employee. Inserts Person, CollegeMember, and Employee.
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

-- -------------------------------------------------------------------------------
GO
-- Grant a person College Member status (Person -> CollegeMember).
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
-- Revoke College Member status (deletes the CollegeMember row).
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
-- Grant a person Student status (CollegeMember -> Student).
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
-- Revoke Student status (deletes the Student row only; College Member
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
-- Grant a person Employee status (CollegeMember -> Employee).
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
-- Revoke Employee status. Any ad this person has reviewed has its
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
GO
-- Set IsReviewer role for an employee. Only flips the flag on an existing
--      Employee row; see GrantEmployeeRole to create that row in the first place.
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

-- -------------------------------------------------------------------------------
GO
-- Show Contact information of the poster of a given ad
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
        A.AdID,
        A.ImageFileName
    FROM 
        Person AS P
        INNER JOIN Ad AS A ON P.PersonID = A.PosterID
        LEFT JOIN CollegeMember AS CM ON P.PersonID = CM.PersonID
        LEFT JOIN Student AS S ON P.PersonID = S.PersonID
    WHERE A.AdID = @_AdID
END
GO

-- -------------------------------------------------------------------------------
GO
-- Show Contact information of the reviewer of a given ad
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
    WHERE A.AdID = @_AdID
END
GO

-- =============================================================================
-- Ad Lifecycle & Review
-- Moving an ad through its states: submission, the review decision, and
-- poster-initiated withdrawal. Also holds the two rejection-history reports,
-- which read the outcome of that review process.
-- =============================================================================

-- -------------------------------------------------------------------------------
GO
-- Submit a new ad for review. Inserts a new Ad row; every other column is
--      left to its table default, which produces ReviewStatus = 'Pending',
--      ReviewerID = NULL, PostDate = NULL, EnteredPending = today, and
--      ReviewDate = NULL -- a state that already satisfies every CHECK
--      constraint on Ad without further logic here. Review (ReviewAd) and
--      physical posting (PostAd) are handled by their own procedures.
--      This procedure must be called inside a transaction the CALLER controls.
CREATE OR ALTER PROCEDURE SubmitAd
    @_PosterID      INT,
    @_Title         VARCHAR(128),
    @_AdType        VARCHAR(20),
    @_AdLength      INT,
    @_AdWidth       INT,
    @_Duration      INT = 14,
    @_ImageFileName VARCHAR(255),
    @_AdID          INT = NULL OUTPUT
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

    IF @_ImageFileName IS NULL OR LTRIM(RTRIM(@_ImageFileName)) = ''
    BEGIN
        RAISERROR('Error: Image file is required.', 16, 1);
        RETURN;
    END

    INSERT INTO Ad (PosterID, Title, AdType, AdLength, AdWidth, Duration)
    VALUES (@_PosterID, @_Title, @_AdType, @_AdLength, @_AdWidth, @_Duration);

    SET @_AdID = SCOPE_IDENTITY();
END
GO

-- -------------------------------------------------------------------------------
GO
-- Approve or Reject an ad
CREATE OR ALTER PROCEDURE ReviewAd 
    -- This procedure must be called inside a transaction the CALLER controls
    -- (BEGIN TRANSACTION ... COMMIT/ROLLBACK), so the lock below is held for
    -- the full validate-then-update sequence instead of just one statement.
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
        SELECT PersonID FROM Employee WHERE IsReviewer = 1)
    BEGIN
        RAISERROR('Invalid Reviewer ID. Only a Reviewer can evaluate an ad.', 16, 1);
        RETURN;
    END

    IF EXISTS (
        SELECT 1 FROM Ad WITH (UPDLOCK, HOLDLOCK)
        WHERE AdID = @_AdID AND IsWithdrawn = 1
    )
    BEGIN
        RAISERROR('Error: This ad has been withdrawn and can no longer be reviewed.', 16, 1);
        RETURN;
    END

    UPDATE Ad
    SET 
        ReviewStatus = @_Status,
        PostDate =
            CASE
                WHEN @_Status <> 'Approved' THEN NULL
                ELSE PostDate
            END,
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

-- -------------------------------------------------------------------------------
GO
-- Withdraw an ad. Poster-initiated; sets IsWithdrawn/WithdrawnDate and
--      purges every message on the ad (via DeleteAdMessages), but does NOT
--      touch ReviewStatus and does NOT remove the ad from any board it is
--      currently posted to. Physical takedown is a separate, admin-run step
--      (UnpostAd), surfaced by vw_PendingRemoval once this has run.
--      Withdrawal is one-way: ReviewAd refuses to act on an already-withdrawn ad.
--      This procedure must be called inside a transaction the CALLER controls.
CREATE OR ALTER PROCEDURE WithdrawAd
    @_AdID                INT,
    @_PosterID            INT,
    @_DeletedMessageCount INT = NULL OUTPUT
AS
BEGIN
    DECLARE @ActualPosterID INT, @AlreadyWithdrawn BIT;

    SELECT @ActualPosterID = PosterID, @AlreadyWithdrawn = IsWithdrawn
    FROM Ad WITH (UPDLOCK, HOLDLOCK)
    WHERE AdID = @_AdID;

    IF @ActualPosterID IS NULL
    BEGIN
        RAISERROR('Error: No ad exists with the given AdID.', 16, 1);
        RETURN;
    END

    IF @ActualPosterID <> @_PosterID
    BEGIN
        RAISERROR('Error: Only the ad''s poster may withdraw it.', 16, 1);
        RETURN;
    END

    IF @AlreadyWithdrawn = 1
    BEGIN
        RAISERROR('Error: This ad has already been withdrawn.', 16, 1);
        RETURN;
    END

    UPDATE Ad
    SET IsWithdrawn = 1, WithdrawnDate = CAST(GETDATE() AS DATE)
    WHERE AdID = @_AdID;

    EXEC DeleteAdMessages @_AdID = @_AdID, @_DeletedCount = @_DeletedMessageCount OUTPUT;
END

-- -------------------------------------------------------------------------------
GO
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
CREATE OR ALTER PROCEDURE DeleteAd
    @_AdID                INT,
    @_ReviewerID          INT,
    @_DeletedMessageCount INT          = NULL OUTPUT,
    @_ImageFileName       VARCHAR(255) = NULL OUTPUT
AS
BEGIN
    SELECT @_ImageFileName = ImageFileName
    FROM Ad WITH (UPDLOCK, HOLDLOCK)
    WHERE AdID = @_AdID;

    IF @_ImageFileName IS NULL
    BEGIN
        RAISERROR('Error: No ad exists with the given AdID.', 16, 1);
        RETURN;
    END

    IF @_ReviewerID IS NULL OR @_ReviewerID NOT IN (
        SELECT PersonID FROM Employee WHERE IsReviewer = 1)
    BEGIN
        RAISERROR('Invalid Reviewer ID. Only a Reviewer can evaluate an ad.', 16, 1);
        RETURN;
    END

    DECLARE @PostedCount INT;
    SELECT @PostedCount = COUNT(*)
    FROM Ad_Posted_Board WITH (UPDLOCK, HOLDLOCK)
    WHERE AdID = @_AdID;

    IF @PostedCount > 0
    BEGIN
        RAISERROR('Error: This ad is still posted to %d board(s). Unpost it first.', 16, 1, @PostedCount);
        RETURN;
    END

    EXEC DeleteAdMessages @_AdID = @_AdID, @_DeletedCount = @_DeletedMessageCount OUTPUT;

    DELETE FROM Ad WHERE AdID = @_AdID;
END

-- -------------------------------------------------------------------------------
GO
-- Procedure to find people who have posted multiple rejected ads
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
    WHERE A.ReviewStatus = 'Rejected'
    GROUP BY P.PersonID, P.FirstName, P.LastName
    HAVING COUNT(DISTINCT A.AdID) >= @_MinRejections;
END
GO

-- -------------------------------------------------------------------------------
GO
-- Procedure to find the rejection history of a user (poster)
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
        AND A.ReviewStatus = 'Rejected'
    ORDER BY A.AdID;
END
GO

-- =============================================================================
-- Board & Posting
-- Creating and retiring the physical boards, placing approved ads onto them,
-- removing them again, and the two read-only helpers for checking fit and
-- looking up where an ad currently hangs.
-- =============================================================================

-- -------------------------------------------------------------------------------
GO
-- Add a new board. The only real constraint is that the location
--      (Building, BldgFloor, Slot) not already be in use.
CREATE OR ALTER PROCEDURE NewBoard
    @_Building    VARCHAR(4),
    @_BldgFloor   INT,
    @_Slot        CHAR(1),
    @_BoardLength INT,
    @_BoardWidth  INT
AS
BEGIN
    IF EXISTS (
        SELECT 1 FROM Board
        WHERE Building = @_Building AND BldgFloor = @_BldgFloor AND Slot = @_Slot
    )
    BEGIN
        RAISERROR('Error: A board already exists at the given location.', 16, 1);
        RETURN;
    END

    IF @_BoardLength IS NULL OR @_BoardLength <= 0 OR @_BoardWidth IS NULL OR @_BoardWidth <= 0
    BEGIN
        RAISERROR('Error: Board length and width must both be positive.', 16, 1);
        RETURN;
    END

    INSERT INTO Board (Building, BldgFloor, Slot, BoardLength, BoardWidth)
    VALUES (@_Building, @_BldgFloor, @_Slot, @_BoardLength, @_BoardWidth);
END
GO

-- -------------------------------------------------------------------------------
GO
-- Retire (permanently remove) a board. Refuses if any ad is currently
--      posted there -- fk_adpostedboard_board is ON DELETE CASCADE, which
--      would otherwise silently remove those postings, exactly the kind of
--      invisible physical-world side effect UnpostAd exists to make explicit.
--      Clear the board with UnpostAd (per-ad, or looped by the caller) first.
--      A board's identity is just its physical location; unlike Ad, there is
--      no history worth preserving once it is gone, so this is a hard delete
--      rather than a flag.
--      This procedure must be called inside a transaction the CALLER controls.
CREATE OR ALTER PROCEDURE RetireBoard
    @_Building  VARCHAR(4),
    @_BldgFloor INT,
    @_Slot      CHAR(1)
AS
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM Board
        WHERE Building = @_Building AND BldgFloor = @_BldgFloor AND Slot = @_Slot
    )
    BEGIN
        RAISERROR('Error: No board exists at the given location.', 16, 1);
        RETURN;
    END

    DECLARE @PostedCount INT;
    SELECT @PostedCount = COUNT(*)
    FROM Ad_Posted_Board WITH (UPDLOCK, HOLDLOCK)
    WHERE Building = @_Building AND BldgFloor = @_BldgFloor AND Slot = @_Slot;

    IF @PostedCount > 0
    BEGIN
        RAISERROR('Error: This board still has %d ad(s) posted to it. Unpost them first.', 16, 1, @PostedCount);
        RETURN;
    END

    DELETE FROM Board
    WHERE Building = @_Building AND BldgFloor = @_BldgFloor AND Slot = @_Slot;
END
GO

-- -------------------------------------------------------------------------------
GO
-- Create a procedure to post an ad to a given board
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
            ReviewStatus = 'Approved'
            AND AdID = @_AdID
    )
    BEGIN
        RAISERROR('Error: Ad is not approved.', 16, 1);
        RETURN;
    END
    
    -- check the ad has not been withdrawn
    IF EXISTS (
        SELECT 1 FROM Ad WHERE AdID = @_AdID AND IsWithdrawn = 1
    )
    BEGIN
        RAISERROR('Error: This ad has been withdrawn and cannot be posted.', 16, 1);
        RETURN;
    END
        
    -- check the ad has not expired
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

    UPDATE Ad SET PostDate = CAST(GETDATE() AS DATE) WHERE AdID = @_AdID;
    INSERT INTO Ad_Posted_Board (AdID, Building, BldgFloor, Slot) VALUES
        (@_AdID, @_Bldg, @_Floor, @_Slot);
END
GO

-- -------------------------------------------------------------------------------
GO
-- Remove an unapproved ad from the Ad_Posted_Board table.
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

-- -------------------------------------------------------------------------------
GO
-- Procedure to evaluate if a given ad will fit on each board
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

-- -------------------------------------------------------------------------------
GO
-- Procedure to find all the information and locations of a posted ad
CREATE OR ALTER PROCEDURE GetAdPostings
    @_AdID INT
AS
BEGIN
    SELECT *
    FROM vw_PostedAdsInfo
    WHERE AdID = @_AdID
END
GO

-- =============================================================================
-- Messaging
-- Sending, retrieving, and deleting the messages exchanged about an ad.
-- DeleteAdMessages is also the mechanism WithdrawAd uses to clear
-- fk_messages_ad before flagging an ad as withdrawn.
-- =============================================================================

-- -------------------------------------------------------------------------------
GO
-- Send a message about an ad. TimeLogged is left to its table default
--      (CURRENT_TIMESTAMP), the same way SubmitAd leaves EnteredPending to
--      its own default.
--
--      Two business rules restrict who can message whom, beyond the FK
--      requirement that the sender, recipient, and ad all exist:
--        - The ad's PosterID must be either the sender or the recipient.
--          This isn't a general messaging system; every conversation is
--          about a specific ad and involves whoever posted it.
--        - Messaging is only allowed on an Approved ad, UNLESS the sender or
--          recipient is a reviewer (Employee.IsReviewer = 1), in which case
--          messaging is allowed regardless of ReviewStatus, so a reviewer can
--          ask the poster a clarifying question before a decision is made.
--          This checks reviewer status generally, not whether that specific
--          person is THIS ad's ReviewerID -- there is currently no way to
--          assign a reviewer to an ad before an outright Approve/Reject
--          decision, so a per-ad check isn't yet meaningful.
--      Self-messaging is intentionally allowed (SenderID = RecipientID);
--      only the seed data avoids it, not the schema or this procedure.
--      This procedure must be called inside a transaction the CALLER controls.
CREATE OR ALTER PROCEDURE SendMessage
    @_SenderID    INT,
    @_AdID        INT,
    @_RecipientID INT,
    @_Content     VARCHAR(MAX)
AS
BEGIN
    DECLARE @PosterID INT, @ReviewStatus VARCHAR(10);

    SELECT @PosterID = PosterID, @ReviewStatus = ReviewStatus
    FROM Ad WHERE AdID = @_AdID;

    IF EXISTS (SELECT 1 FROM Ad WHERE AdID = @_AdID AND IsWithdrawn = 1)
    BEGIN
        RAISERROR('Error: This ad has been withdrawn; no further messages are allowed.', 16, 1);
        RETURN;
    END

    IF @PosterID IS NULL
    BEGIN
        RAISERROR('Error: No ad exists with the given AdID.', 16, 1);
        RETURN;
    END

    IF NOT EXISTS (SELECT 1 FROM Person WHERE PersonID = @_SenderID)
    BEGIN
        RAISERROR('Error: No person exists with the given SenderID.', 16, 1);
        RETURN;
    END

    IF NOT EXISTS (SELECT 1 FROM Person WHERE PersonID = @_RecipientID)
    BEGIN
        RAISERROR('Error: No person exists with the given RecipientID.', 16, 1);
        RETURN;
    END

    IF @PosterID NOT IN (@_SenderID, @_RecipientID)
    BEGIN
        RAISERROR('Error: This ad''s poster must be either the sender or the recipient.', 16, 1);
        RETURN;
    END

    IF @ReviewStatus <> 'Approved'
       AND NOT EXISTS (
            SELECT 1 FROM Employee
            WHERE IsReviewer = 1 AND PersonID IN (@_SenderID, @_RecipientID)
       )
    BEGIN
        RAISERROR('Error: This ad is not Approved, and neither party is a reviewer.', 16, 1);
        RETURN;
    END

    IF @_Content IS NULL OR LTRIM(RTRIM(@_Content)) = ''
    BEGIN
        RAISERROR('Error: Message content cannot be blank.', 16, 1);
        RETURN;
    END

    INSERT INTO Messages (SenderID, AdID, RecipientID, Content)
    VALUES (@_SenderID, @_AdID, @_RecipientID, @_Content);
END
GO

-- -------------------------------------------------------------------------------
GO
-- Retrieve all messages about a given ad, showing sender and recipient names, 
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

-- -------------------------------------------------------------------------------
GO
-- Delete a single message, identified by its full primary key
--      (SenderID, AdID, TimeLogged). Messages has no surrogate key, so a
--      caller offering to delete one line of a displayed conversation needs
--      to pass back the exact triple it was given when the message was
--      retrieved.
--      This procedure must be called inside a transaction the CALLER controls.
CREATE OR ALTER PROCEDURE DeleteMessage
    @_SenderID   INT,
    @_AdID       INT,
    @_TimeLogged DATETIME
AS
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM Messages
        WHERE SenderID = @_SenderID AND AdID = @_AdID AND TimeLogged = @_TimeLogged
    )
    BEGIN
        RAISERROR('Error: No message exists with the given SenderID, AdID, and TimeLogged.', 16, 1);
        RETURN;
    END

    DELETE FROM Messages
    WHERE SenderID = @_SenderID AND AdID = @_AdID AND TimeLogged = @_TimeLogged;
END
GO

-- -------------------------------------------------------------------------------
GO
-- Delete every message attached to a given ad. This is the mechanism
--      WithdrawAd will use to clear fk_messages_ad (ON DELETE NO ACTION in
--      MSSQL, RESTRICT in MySQL) before deleting the Ad row itself -- that
--      restriction is deliberate (see README), so messages must be removed
--      explicitly rather than cascaded away.
--      This procedure must be called inside a transaction the CALLER controls.
CREATE OR ALTER PROCEDURE DeleteAdMessages
    @_AdID         INT,
    @_DeletedCount INT = NULL OUTPUT
AS
BEGIN
    IF NOT EXISTS (SELECT 1 FROM Ad WHERE AdID = @_AdID)
    BEGIN
        RAISERROR('Error: No ad exists with the given AdID.', 16, 1);
        RETURN;
    END

    DELETE FROM Messages WHERE AdID = @_AdID;
    SET @_DeletedCount = @@ROWCOUNT;
END
GO
