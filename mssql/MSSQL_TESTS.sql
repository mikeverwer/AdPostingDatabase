--    Created by Mike Verwer | mikeverwer.github.io
-- ** ALL QUERIES IN THIS FILE WORK IN MS SQL Server **
--
-- LOAD ORDER: 3 of 3
--   MSSQL_VIEWS.sql  ->  MSSQL_PROCEDURES.sql  ->  MSSQL_TESTS.sql
-- Requires every view and procedure to already exist, and assumes the seed
-- data in MSSQL_INSERT.sql has been loaded. Specific IDs below refer to that
-- seed data: reviewers are PersonIDs 22, 26, 28, and 29; students are 5-21;
-- non-college members are 1-4; AdID 1 is Approved and posted with messages;
-- AdID 19 is Approved but not yet posted; AdID 25 is Pending, posted by 17.
--
-- Every procedure test that writes is wrapped in BEGIN TRANSACTION ...
-- ROLLBACK TRANSACTION, with a SELECT inside the transaction so the change is
-- visible before it is undone. Tests labelled "should fail" are expected to
-- raise; that raise is the pass condition.
--
-- NOTE: rolling back does not reset IDENTITY counters, so PersonID and AdID
-- values assigned by AddNonMember / SubmitAd will advance across repeated
-- runs of this file. That is expected and not a defect.

USE AdPostingDB;
GO

-- =============================================================================
-- Person & Roles
-- Registration procedures, the Grant/Revoke role pairs, the reviewer-flag
-- toggle, and the two contact lookups.
-- =============================================================================

-- -------------------------------------------------------------------------------
GO
-- AddNonMember: register a member of the public
-- Should succeed - new person, unused email
BEGIN TRANSACTION;
    DECLARE @NewNonMember INT;
    EXEC AddNonMember
        @_FirstName = 'Dana', @_LastName = 'Whitfield',
        @_Phone = '5551239001', @_Email = 'dana.whitfield@email.com',
        @_PersonID = @NewNonMember OUTPUT;
    SELECT @NewNonMember AS NewPersonID;
    SELECT PersonID, FirstName, LastName, Email FROM Person WHERE PersonID = @NewNonMember;
ROLLBACK TRANSACTION;

-- Should fail - email already belongs to Emma Johnson (PersonID 5)
BEGIN TRANSACTION;
    DECLARE @DupNonMember INT;
    EXEC AddNonMember
        @_FirstName = 'Duplicate', @_LastName = 'Email',
        @_Email = 'emma.johnson@college.edu',
        @_PersonID = @DupNonMember OUTPUT;
ROLLBACK TRANSACTION;

-- Should fail - blank last name
BEGIN TRANSACTION;
    DECLARE @NoNameNonMember INT;
    EXEC AddNonMember
        @_FirstName = 'Nameless', @_LastName = '   ',
        @_Email = 'nameless@email.com',
        @_PersonID = @NoNameNonMember OUTPUT;
ROLLBACK TRANSACTION;

-- -------------------------------------------------------------------------------
GO
-- AddCollegeMember: register an alum retaining board privileges
-- Should succeed - unused CollegeID and email
BEGIN TRANSACTION;
    DECLARE @NewMember INT;
    EXEC AddCollegeMember
        @_FirstName = 'Alan', @_LastName = 'Brouwer',
        @_Phone = '5551239002', @_Email = 'alan.brouwer@college.edu',
        @_CollegeID = 'ALM000001', @_Department = 'Alumni Relations',
        @_PersonID = @NewMember OUTPUT;
    SELECT @NewMember AS NewPersonID;
    SELECT PersonID, CollegeID, Department FROM CollegeMember WHERE PersonID = @NewMember;
ROLLBACK TRANSACTION;

-- Should fail - CollegeID STU000001 already belongs to Emma Johnson
BEGIN TRANSACTION;
    DECLARE @DupCollegeID INT;
    EXEC AddCollegeMember
        @_FirstName = 'Duplicate', @_LastName = 'CollegeID',
        @_Email = 'duplicate.collegeid@college.edu',
        @_CollegeID = 'STU000001',
        @_PersonID = @DupCollegeID OUTPUT;
ROLLBACK TRANSACTION;

-- -------------------------------------------------------------------------------
GO
-- AddStudent: full three-table registration (Person, CollegeMember, Student)
-- Should succeed - all three rows created
BEGIN TRANSACTION;
    DECLARE @NewStudent INT;
    EXEC AddStudent
        @_FirstName = 'Rosa', @_LastName = 'Iqbal',
        @_Phone = '5551239003', @_Email = 'rosa.iqbal@college.edu',
        @_CollegeID = 'STU000018', @_Department = 'Mathematics',
        @_Major = 'Applied Mathematics',
        @_PersonID = @NewStudent OUTPUT;
    SELECT @NewStudent AS NewPersonID;
    SELECT
        P.PersonID, P.FirstName, P.LastName,
        CM.CollegeID, CM.Department,
        S.Major
    FROM Person AS P
        INNER JOIN CollegeMember AS CM ON P.PersonID = CM.PersonID
        INNER JOIN Student AS S ON P.PersonID = S.PersonID
    WHERE P.PersonID = @NewStudent;
ROLLBACK TRANSACTION;

-- Should succeed - Major left NULL for an undeclared student
BEGIN TRANSACTION;
    DECLARE @UndeclaredStudent INT;
    EXEC AddStudent
        @_FirstName = 'Undeclared', @_LastName = 'Student',
        @_Email = 'undeclared.student@college.edu',
        @_CollegeID = 'STU000020', @_Department = 'General Studies',
        @_PersonID = @UndeclaredStudent OUTPUT;
    SELECT PersonID, Major FROM Student WHERE PersonID = @UndeclaredStudent;
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
-- AddEmployee: full three-table registration (Person, CollegeMember, Employee)
-- Should succeed - office and extension supplied together
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
    SELECT PersonID, OfficeLocation, Extension, PositionTitle, IsReviewer
    FROM Employee WHERE PersonID = @NewEmployee;
ROLLBACK TRANSACTION;

-- Should succeed - no office, no extension (matches Chloe Allen, PersonID 27)
BEGIN TRANSACTION;
    DECLARE @OfficelessEmployee INT;
    EXEC AddEmployee
        @_FirstName = 'Remote', @_LastName = 'Worker',
        @_Email = 'remote.worker@college.edu', @_CollegeID = 'EMP000014',
        @_PositionTitle = 'Support',
        @_PersonID = @OfficelessEmployee OUTPUT;
    SELECT PersonID, OfficeLocation, Extension FROM Employee WHERE PersonID = @OfficelessEmployee;
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

-- Should fail - invalid position title
BEGIN TRANSACTION;
    DECLARE @BadTitleEmployee INT;
    EXEC AddEmployee
        @_FirstName = 'Bad', @_LastName = 'Title',
        @_Email = 'bad.title@college.edu', @_CollegeID = 'EMP000015',
        @_PositionTitle = 'Custodian',
        @_PersonID = @BadTitleEmployee OUTPUT;
ROLLBACK TRANSACTION;

-- -------------------------------------------------------------------------------
GO
-- GrantCollegeMemberRole: promote an existing Person to College Member
-- Should succeed - John Smith (PersonID 1) is a non-member
BEGIN TRANSACTION;
    EXEC GrantCollegeMemberRole @_PersonID = 1, @_CollegeID = 'ALM000002', @_Department = 'Alumni Relations';
    SELECT PersonID, CollegeID, Department FROM CollegeMember WHERE PersonID = 1;
ROLLBACK TRANSACTION;

-- Should fail - Emma Johnson (PersonID 5) already holds College Member status
BEGIN TRANSACTION;
    EXEC GrantCollegeMemberRole @_PersonID = 5, @_CollegeID = 'ALM000003';
ROLLBACK TRANSACTION;

-- Should fail - no such person
BEGIN TRANSACTION;
    EXEC GrantCollegeMemberRole @_PersonID = 9999, @_CollegeID = 'ALM000004';
ROLLBACK TRANSACTION;

-- -------------------------------------------------------------------------------
GO
-- RevokeCollegeMemberRole: strip College Member status
-- Should succeed - grant it to a non-member first, then take it away again
BEGIN TRANSACTION;
    EXEC GrantCollegeMemberRole @_PersonID = 2, @_CollegeID = 'ALM000005';
    SELECT COUNT(*) AS MemberRowsBefore FROM CollegeMember WHERE PersonID = 2;  -- expect 1
    EXEC RevokeCollegeMemberRole @_PersonID = 2;
    SELECT COUNT(*) AS MemberRowsAfter FROM CollegeMember WHERE PersonID = 2;   -- expect 0
ROLLBACK TRANSACTION;

-- Should fail - RevokeCollegeMemberRole refuses while Student status remains
BEGIN TRANSACTION;
    EXEC RevokeCollegeMemberRole @_PersonID = 5;  -- Emma Johnson, a Student
ROLLBACK TRANSACTION;

-- Should fail - James Harris (PersonID 22) still holds Employee status
BEGIN TRANSACTION;
    EXEC RevokeCollegeMemberRole @_PersonID = 22;
ROLLBACK TRANSACTION;

-- -------------------------------------------------------------------------------
GO
-- GrantStudentRole: add Student status to an existing College Member
-- Should succeed - Emily Clark (PersonID 23) is an Employee, becomes dual-role
BEGIN TRANSACTION;
    EXEC GrantStudentRole @_PersonID = 23, @_Major = 'Educational Leadership';
    SELECT PersonID, Major FROM Student WHERE PersonID = 23;
    SELECT PersonID, PositionTitle FROM Employee WHERE PersonID = 23;  -- still present
ROLLBACK TRANSACTION;

-- Should fail - Emma Johnson (PersonID 5) already holds Student status
BEGIN TRANSACTION;
    EXEC GrantStudentRole @_PersonID = 5, @_Major = 'Physics';
ROLLBACK TRANSACTION;

-- Should fail - John Smith (PersonID 1) is not a College Member
BEGIN TRANSACTION;
    EXEC GrantStudentRole @_PersonID = 1, @_Major = 'Physics';
ROLLBACK TRANSACTION;

-- -------------------------------------------------------------------------------
GO
-- RevokeStudentRole: strip Student status, leaving College Member intact
-- Should succeed - Liam Davis (PersonID 6) keeps his CollegeMember row
BEGIN TRANSACTION;
    EXEC RevokeStudentRole @_PersonID = 6;
    SELECT COUNT(*) AS StudentRows FROM Student WHERE PersonID = 6;              -- expect 0
    SELECT COUNT(*) AS CollegeMemberRows FROM CollegeMember WHERE PersonID = 6;  -- expect 1
ROLLBACK TRANSACTION;

-- Should fail - James Harris (PersonID 22) is not a Student
BEGIN TRANSACTION;
    EXEC RevokeStudentRole @_PersonID = 22;
ROLLBACK TRANSACTION;

-- -------------------------------------------------------------------------------
GO
-- GrantEmployeeRole: add Employee status to an existing College Member.
-- Demonstrates a graduate student TA: Priya Nair (PersonID 21, a Student) is
-- granted Employee status without giving up Student status.
BEGIN TRANSACTION;
    EXEC GrantEmployeeRole
        @_PersonID = 21, @_OfficeLocation = 'MTH-110', @_Extension = '7110',
        @_PositionTitle = 'Staff', @_IsReviewer = 0;
    SELECT * FROM Student WHERE PersonID = 21;    -- still present
    SELECT * FROM Employee WHERE PersonID = 21;   -- now present too
ROLLBACK TRANSACTION;

-- Should fail - James Harris (PersonID 22) already holds Employee status
BEGIN TRANSACTION;
    EXEC GrantEmployeeRole @_PersonID = 22, @_PositionTitle = 'Staff';
ROLLBACK TRANSACTION;

-- Should fail - extension without an office
BEGIN TRANSACTION;
    EXEC GrantEmployeeRole @_PersonID = 20, @_Extension = '9999', @_PositionTitle = 'Support';
ROLLBACK TRANSACTION;

-- -------------------------------------------------------------------------------
GO
-- RevokeEmployeeRole: strip Employee status, preserving review history
-- Should succeed - revoking Employee nulls ReviewerID on ads they reviewed
BEGIN TRANSACTION;
    SELECT COUNT(*) AS ReviewedBefore FROM Ad WHERE ReviewerID = 22;
    EXEC RevokeEmployeeRole @_PersonID = 22;  -- James Harris, a reviewer
    SELECT COUNT(*) AS ReviewedAfter FROM Ad WHERE ReviewerID = 22;  -- expect 0
    -- Those reviews are still counted, now under 'Deleted Reviewer(s)'
    SELECT * FROM vw_ReviewCountsPerReviewer WHERE PersonID IS NULL;
ROLLBACK TRANSACTION;

-- Should fail - Emma Johnson (PersonID 5) is a Student, not an Employee
BEGIN TRANSACTION;
    EXEC RevokeEmployeeRole @_PersonID = 5;
ROLLBACK TRANSACTION;

-- -------------------------------------------------------------------------------
GO
-- SetReviewerPermission: toggle the IsReviewer flag on an existing Employee
-- Should succeed - Thomas Okafor (PersonID 30) is an Employee, not yet a reviewer
BEGIN TRANSACTION;
    EXEC SetReviewerPermission @_EmpID = 30, @_IsRev = 1;
    SELECT PersonID, IsReviewer FROM Employee WHERE PersonID = 30;  -- expect 1
ROLLBACK TRANSACTION;

-- Should succeed - revoking the flag from an existing reviewer
BEGIN TRANSACTION;
    EXEC SetReviewerPermission @_EmpID = 26, @_IsRev = 0;
    SELECT PersonID, IsReviewer FROM Employee WHERE PersonID = 26;  -- expect 0
ROLLBACK TRANSACTION;

-- Should fail - Emma Johnson (PersonID 5) is a Student, not an Employee
BEGIN TRANSACTION;
    EXEC SetReviewerPermission @_EmpID = 5, @_IsRev = 1;
ROLLBACK TRANSACTION;

-- -------------------------------------------------------------------------------
GO
-- GetPosterInfo: contact card for whoever posted a given ad
-- Should succeed - AdID 1 was posted by John Smith, a non-member
EXEC GetPosterInfo @_AdID = 1;

-- Should succeed - AdID 2 was posted by Emma Johnson, a Student
EXEC GetPosterInfo @_AdID = 2;

-- Should fail - no such ad
EXEC GetPosterInfo @_AdID = 9999;

-- -------------------------------------------------------------------------------
GO
-- GetReviewerInfo: contact card for whoever reviewed a given ad
-- Should succeed - AdID 1 was reviewed by James Harris (PersonID 22)
EXEC GetReviewerInfo @_AdID = 1;

-- Should succeed - AdID 25 is Pending, so it has no reviewer on record
EXEC GetReviewerInfo @_AdID = 25;

-- Should fail - no such ad
EXEC GetReviewerInfo @_AdID = 9999;

-- =============================================================================
-- Ad Lifecycle & Review
-- Submission, the review decision, withdrawal, and the views and reports that
-- track an ad's progress through those states.
-- =============================================================================

-- -------------------------------------------------------------------------------
GO
-- vw_ExpiredAds: ads whose posting duration has elapsed
SELECT *
FROM vw_ExpiredAds
ORDER BY DaysOverdue DESC, AdID;

-- -------------------------------------------------------------------------------
GO
-- vw_ReviewQueue: ads awaiting a review decision, oldest first
SELECT *
FROM vw_ReviewQueue
ORDER BY QueuePosition;

-- -------------------------------------------------------------------------------
GO
-- vw_ReviewCountsPerReviewer: approvals and rejections per reviewer
SELECT *
FROM vw_ReviewCountsPerReviewer
ORDER BY TotalReviews DESC, ReviewerName;

-- -------------------------------------------------------------------------------
GO
-- AdsByUserType: every ad tagged with the type of user who posted it
SELECT *
FROM AdsByUserType
ORDER BY UserType, PosterID, AdID;

-- -------------------------------------------------------------------------------
GO
-- vw_AdsByUserTypeAndAdType: pivot of user type against ad type, with totals
SELECT *
FROM vw_AdsByUserTypeAndAdType
ORDER BY RowTotal DESC, UserType;

-- -------------------------------------------------------------------------------
GO
-- SubmitAd: create a new ad in Pending status
-- Should succeed - defaults produce Pending, no reviewer, no post date
BEGIN TRANSACTION;
    DECLARE @NewAd INT;
    EXEC SubmitAd
        @_PosterID = 3, @_Title = 'Kayak for Sale', @_AdType = 'Sale',
        @_AdLength = 350, @_AdWidth = 90, @_ImageFileName = 'kayak.jpg', 
        @_AdID = @NewAd OUTPUT;
    SELECT * FROM Ad WHERE AdID = @NewAd;
ROLLBACK TRANSACTION;

-- Should succeed - explicit duration overrides the default of 14
BEGIN TRANSACTION;
    DECLARE @LongAd INT;
    EXEC SubmitAd
        @_PosterID = 5, @_Title = 'Semester-Long Tutoring', @_AdType = 'Tutorship',
        @_AdLength = 300, @_AdWidth = 200, @_Duration = 90, 
        @_ImageFileName = 'tutor-poster.jpg', @_AdID = @LongAd OUTPUT;
    SELECT AdID, Title, Duration, ReviewStatus FROM Ad WHERE AdID = @LongAd;
ROLLBACK TRANSACTION;

-- Should fail - invalid ad type
BEGIN TRANSACTION;
    DECLARE @BadAd INT;
    EXEC SubmitAd
        @_PosterID = 1, @_Title = 'Test', @_AdType = 'Rummage',
        @_AdLength = 100, @_AdWidth = 100, @_ImageFileName = 'bad-post.jpg',
        @_AdID = @BadAd OUTPUT;
ROLLBACK TRANSACTION;

-- Should fail - no such poster
BEGIN TRANSACTION;
    DECLARE @NoPosterAd INT;
    EXEC SubmitAd
        @_PosterID = 9999, @_Title = 'Orphan Ad', @_AdType = 'Sale',
        @_AdLength = 100, @_AdWidth = 100, @_ImageFileName = 'bad-post.jpg',
        @_AdID = @NoPosterAd OUTPUT;
ROLLBACK TRANSACTION;

-- Should fail - non-positive dimensions
BEGIN TRANSACTION;
    DECLARE @ZeroAd INT;
    EXEC SubmitAd
        @_PosterID = 1, @_Title = 'Zero Width', @_AdType = 'Sale',
        @_AdLength = 100, @_AdWidth = 0,  @_ImageFileName = 'bad-post.jpg',
        @_AdID = @ZeroAd OUTPUT;
ROLLBACK TRANSACTION;

-- Should fail - blank image filename
BEGIN TRANSACTION;
    DECLARE @NoImageAd INT;
    EXEC SubmitAd
        @_PosterID = 1, @_Title = 'Missing Image', @_AdType = 'Sale',
        @_AdLength = 100, @_AdWidth = 100,  @_ImageFileName = '',
        @_AdID = @NoImageAd OUTPUT;
ROLLBACK TRANSACTION;

-- -------------------------------------------------------------------------------
GO
-- ReviewAd: approve, reject, or return an ad to the review queue
-- Should succeed - AdID 25 is Pending; PersonID 22 is a reviewer
BEGIN TRANSACTION;
    EXEC ReviewAd @_AdID = 25, @_Status = 'Approved', @_ReviewerID = 22;
    SELECT AdID, ReviewStatus, ReviewerID, ReviewDate FROM Ad WHERE AdID = 25;
ROLLBACK TRANSACTION;

-- Should succeed - rejecting instead, with an explicit review date
BEGIN TRANSACTION;
    EXEC ReviewAd @_AdID = 25, @_Status = 'Rejected', @_ReviewerID = 26, @_ReviewDate = '2026-07-20';
    SELECT AdID, ReviewStatus, ReviewerID, ReviewDate FROM Ad WHERE AdID = 25;
ROLLBACK TRANSACTION;

-- Should succeed - returning an approved ad to Pending clears reviewer and date
BEGIN TRANSACTION;
    EXEC ReviewAd @_AdID = 1, @_Status = 'Pending', @_ReviewerID = 22;
    SELECT AdID, ReviewStatus, ReviewerID, ReviewDate FROM Ad WHERE AdID = 1;
ROLLBACK TRANSACTION;

-- Should fail - PersonID 19 is a student, not a reviewer
BEGIN TRANSACTION;
    EXEC ReviewAd @_AdID = 25, @_Status = 'Approved', @_ReviewerID = 19;
ROLLBACK TRANSACTION;

-- Should fail - invalid status
BEGIN TRANSACTION;
    EXEC ReviewAd @_AdID = 25, @_Status = 'Deferred', @_ReviewerID = 22;
ROLLBACK TRANSACTION;

-- Should fail - a withdrawn ad can no longer be reviewed
BEGIN TRANSACTION;
    DECLARE @WithdrawnFirst INT;
    EXEC WithdrawAd @_AdID = 25, @_PosterID = 17, @_DeletedMessageCount = @WithdrawnFirst OUTPUT;
    EXEC ReviewAd @_AdID = 25, @_Status = 'Approved', @_ReviewerID = 22;
ROLLBACK TRANSACTION;

-- -------------------------------------------------------------------------------
GO
-- WithdrawAd: poster pulls their own ad and its message history
-- Should succeed - AdID 1 was posted by PersonID 1 and has messages attached
BEGIN TRANSACTION;
    DECLARE @Deleted INT;
    EXEC WithdrawAd @_AdID = 1, @_PosterID = 1, @_DeletedMessageCount = @Deleted OUTPUT;
    SELECT @Deleted AS MessagesDeleted;
    SELECT ReviewStatus, IsWithdrawn, WithdrawnDate FROM Ad WHERE AdID = 1;
    -- Board postings are deliberately left in place, and now surface for takedown
    SELECT * FROM vw_PendingRemoval WHERE AdID = 1;
ROLLBACK TRANSACTION;

-- Should fail - wrong poster
BEGIN TRANSACTION;
    DECLARE @BadWithdraw INT;
    EXEC WithdrawAd @_AdID = 1, @_PosterID = 999, @_DeletedMessageCount = @BadWithdraw OUTPUT;
ROLLBACK TRANSACTION;

-- Should fail - withdrawal is one-way
BEGIN TRANSACTION;
    DECLARE @FirstWithdraw INT, @SecondWithdraw INT;
    EXEC WithdrawAd @_AdID = 1, @_PosterID = 1, @_DeletedMessageCount = @FirstWithdraw OUTPUT;
    EXEC WithdrawAd @_AdID = 1, @_PosterID = 1, @_DeletedMessageCount = @SecondWithdraw OUTPUT;
ROLLBACK TRANSACTION;

-- Should fail - no such ad
BEGIN TRANSACTION;
    DECLARE @NoAdWithdraw INT;
    EXEC WithdrawAd @_AdID = 9999, @_PosterID = 1, @_DeletedMessageCount = @NoAdWithdraw OUTPUT;
ROLLBACK TRANSACTION;

-- -------------------------------------------------------------------------------
GO
-- DeleteAd: permanently remove an ad, returning its image for cleanup.
-- Moderation action -- authorization is by Reviewer status, not by poster.
-- Should succeed - AdID 19 is Approved but not posted to any board
BEGIN TRANSACTION;
    DECLARE @DelMsgs INT, @DelImage VARCHAR(255);
    EXEC DeleteAd @_AdID = 19, @_ReviewerID = 22,
        @_DeletedMessageCount = @DelMsgs OUTPUT, @_ImageFileName = @DelImage OUTPUT;
    SELECT @DelMsgs AS MessagesDeleted, @DelImage AS ImageToClean;
    SELECT COUNT(*) AS AdRows FROM Ad WHERE AdID = 19;  -- expect 0
ROLLBACK TRANSACTION;

-- Should succeed - unpost first, then delete an ad that was on a board.
-- AdID 1 has messages attached, so MessagesDeleted should be non-zero.
BEGIN TRANSACTION;
    DECLARE @UnpostMsgs INT, @UnpostImage VARCHAR(255);
    EXEC UnpostAd @_AdID = 1, @_Building = 'BLD', @_BldgFloor = 1, @_Slot = 'A';
    EXEC DeleteAd @_AdID = 1, @_ReviewerID = 26,
        @_DeletedMessageCount = @UnpostMsgs OUTPUT, @_ImageFileName = @UnpostImage OUTPUT;
    SELECT @UnpostMsgs AS MessagesDeleted, @UnpostImage AS ImageToClean;
    SELECT COUNT(*) AS AdRows      FROM Ad              WHERE AdID = 1;  -- expect 0
    SELECT COUNT(*) AS MessageRows FROM Messages        WHERE AdID = 1;  -- expect 0
    SELECT COUNT(*) AS PostingRows FROM Ad_Posted_Board WHERE AdID = 1;  -- expect 0
ROLLBACK TRANSACTION;

-- Should succeed - a Pending ad with no messages reports zero deleted
BEGIN TRANSACTION;
    DECLARE @PendMsgs INT, @PendImage VARCHAR(255);
    EXEC DeleteAd @_AdID = 25, @_ReviewerID = 28,
        @_DeletedMessageCount = @PendMsgs OUTPUT, @_ImageFileName = @PendImage OUTPUT;
    SELECT @PendMsgs AS MessagesDeleted;  -- expect 0
ROLLBACK TRANSACTION;

-- Should fail - AdID 1 is still posted to a board
BEGIN TRANSACTION;
    DECLARE @PostedMsgs INT, @PostedImage VARCHAR(255);
    EXEC DeleteAd @_AdID = 1, @_ReviewerID = 22,
        @_DeletedMessageCount = @PostedMsgs OUTPUT, @_ImageFileName = @PostedImage OUTPUT;
ROLLBACK TRANSACTION;

-- Should fail - PersonID 5 is a Student, not a Reviewer; a poster can no
-- longer delete their own ad under this authorization model
BEGIN TRANSACTION;
    DECLARE @NonRevMsgs INT, @NonRevImage VARCHAR(255);
    EXEC DeleteAd @_AdID = 19, @_ReviewerID = 5,
        @_DeletedMessageCount = @NonRevMsgs OUTPUT, @_ImageFileName = @NonRevImage OUTPUT;
ROLLBACK TRANSACTION;

-- Should fail - NULL reviewer ID
BEGIN TRANSACTION;
    DECLARE @NullRevMsgs INT, @NullRevImage VARCHAR(255);
    EXEC DeleteAd @_AdID = 19, @_ReviewerID = NULL,
        @_DeletedMessageCount = @NullRevMsgs OUTPUT, @_ImageFileName = @NullRevImage OUTPUT;
ROLLBACK TRANSACTION;

-- Should fail - no such ad
BEGIN TRANSACTION;
    DECLARE @NoAdMsgs INT, @NoAdImage VARCHAR(255);
    EXEC DeleteAd @_AdID = 9999, @_ReviewerID = 22,
        @_DeletedMessageCount = @NoAdMsgs OUTPUT, @_ImageFileName = @NoAdImage OUTPUT;
ROLLBACK TRANSACTION;

-- Should succeed - deletion is permitted after withdrawal, and is the
-- mechanism by which a withdrawn ad is eventually purged
BEGIN TRANSACTION;
    DECLARE @WdMsgs INT, @WdDelMsgs INT, @WdImage VARCHAR(255);
    EXEC WithdrawAd @_AdID = 19, @_PosterID = 15, @_DeletedMessageCount = @WdMsgs OUTPUT;
    EXEC DeleteAd @_AdID = 19, @_ReviewerID = 29,
        @_DeletedMessageCount = @WdDelMsgs OUTPUT, @_ImageFileName = @WdImage OUTPUT;
    SELECT COUNT(*) AS AdRows FROM Ad WHERE AdID = 19;  -- expect 0
ROLLBACK TRANSACTION;

-- -------------------------------------------------------------------------------
GO
-- GetNoncompliantPosters: posters with repeated rejections
-- Should succeed - default threshold of 2 rejections
EXEC GetNoncompliantPosters;

-- Should succeed - stricter threshold; Amelia White (PersonID 19) has 3
EXEC GetNoncompliantPosters @_MinRejections = 3;

-- Should succeed - threshold above any poster's count, returning no rows
EXEC GetNoncompliantPosters @_MinRejections = 99;

-- -------------------------------------------------------------------------------
GO
-- GetPosterRejectionHistory: every rejected ad for one poster
-- Should succeed - Amelia White (PersonID 19) has three rejected ads
EXEC GetPosterRejectionHistory @_PosterID = 19;

-- Should succeed - John Smith (PersonID 1) has none, returning no rows
EXEC GetPosterRejectionHistory @_PosterID = 1;

-- Should fail - no such person
EXEC GetPosterRejectionHistory @_PosterID = 9999;

-- =============================================================================
-- Board & Posting
-- Board creation and retirement, placing and removing ads, and the space
-- accounting views that report on the result.
-- =============================================================================

-- -------------------------------------------------------------------------------
GO
-- vw_PostedAdsInfo: every ad currently on a board, with its full ad record
SELECT *
FROM vw_PostedAdsInfo
ORDER BY Building, BldgFloor, Slot, AdID;

-- -------------------------------------------------------------------------------
GO
-- vw_BoardSpace: per-board occupancy and remaining space
SELECT *
FROM vw_BoardSpace
ORDER BY
    Building, 
    BldgFloor, 
    Slot;

-- -------------------------------------------------------------------------------
GO
-- vw_BoardSpaceDisplay: the same accounting, formatted and ranked by fullness
SELECT *
FROM vw_BoardSpaceDisplay
ORDER BY FullnessRank;

-- -------------------------------------------------------------------------------
GO
-- vw_PendingPosting: approved ads that have not been placed on a board yet
SELECT *
FROM vw_PendingPosting
ORDER BY ReviewDate, AdID;

-- -------------------------------------------------------------------------------
GO
-- vw_PendingRemoval: ads that should be removed from boards.
SELECT *
FROM vw_PendingRemoval
ORDER BY RemovalPriority, DaysOverdue DESC, AdID;

-- -------------------------------------------------------------------------------
GO
-- NewBoard: register a new physical board
-- Should succeed - fresh board
BEGIN TRANSACTION;
    EXEC NewBoard @_Building = 'SCI', @_BldgFloor = 1, @_Slot = 'A', @_BoardLength = 2200, @_BoardWidth = 1600;
    SELECT * FROM Board WHERE Building = 'SCI';
ROLLBACK TRANSACTION;

-- Should fail - duplicate location
BEGIN TRANSACTION;
    EXEC NewBoard @_Building = 'BLD', @_BldgFloor = 1, @_Slot = 'A', @_BoardLength = 2000, @_BoardWidth = 1500;
ROLLBACK TRANSACTION;

-- Should fail - non-positive dimensions
BEGIN TRANSACTION;
    EXEC NewBoard @_Building = 'SCI', @_BldgFloor = 2, @_Slot = 'A', @_BoardLength = 0, @_BoardWidth = 1500;
ROLLBACK TRANSACTION;

-- -------------------------------------------------------------------------------
GO
-- RetireBoard: permanently remove a board
-- Should succeed - a freshly created board has nothing posted to it
BEGIN TRANSACTION;
    EXEC NewBoard @_Building = 'SCI', @_BldgFloor = 1, @_Slot = 'A', @_BoardLength = 2200, @_BoardWidth = 1600;
    SELECT COUNT(*) AS BoardsBefore FROM Board WHERE Building = 'SCI';  -- expect 1
    EXEC RetireBoard @_Building = 'SCI', @_BldgFloor = 1, @_Slot = 'A';
    SELECT COUNT(*) AS BoardsAfter FROM Board WHERE Building = 'SCI';   -- expect 0
ROLLBACK TRANSACTION;

-- Should fail - board still populated
BEGIN TRANSACTION;
    EXEC RetireBoard @_Building = 'BLD', @_BldgFloor = 1, @_Slot = 'A';
ROLLBACK TRANSACTION;

-- Should fail - no board at that location
BEGIN TRANSACTION;
    EXEC RetireBoard @_Building = 'XXX', @_BldgFloor = 9, @_Slot = 'Z';
ROLLBACK TRANSACTION;

-- Should succeed - clear the board first, then retire it.
-- NWN-2-A holds AdIDs 15 and 16 in the seed data.
BEGIN TRANSACTION;
    EXEC UnpostAd @_AdID = 15, @_Building = 'NWN', @_BldgFloor = 2, @_Slot = 'A';
    EXEC UnpostAd @_AdID = 16, @_Building = 'NWN', @_BldgFloor = 2, @_Slot = 'A';
    SELECT COUNT(*) AS PostingsRemaining FROM Ad_Posted_Board
    WHERE Building = 'NWN' AND BldgFloor = 2 AND Slot = 'A';  -- expect 0
    EXEC RetireBoard @_Building = 'NWN', @_BldgFloor = 2, @_Slot = 'A';
    SELECT COUNT(*) AS BoardRows FROM Board
    WHERE Building = 'NWN' AND BldgFloor = 2 AND Slot = 'A';  -- expect 0
ROLLBACK TRANSACTION;

-- -------------------------------------------------------------------------------
GO
-- PostAd: place an approved ad on a board
-- Should succeed - AdID 19 is Approved but not yet posted anywhere
BEGIN TRANSACTION;
    EXEC PostAd @_AdID = 19, @_Bldg = 'LIB', @_Floor = 1, @_Slot = 'A';
    SELECT * FROM Ad_Posted_Board WHERE AdID = 19;
ROLLBACK TRANSACTION;

-- Should succeed - approve a Pending ad, then post it in the same transaction
BEGIN TRANSACTION;
    EXEC ReviewAd @_AdID = 25, @_Status = 'Approved', @_ReviewerID = 22;
    EXEC PostAd @_AdID = 25, @_Bldg = 'LIB', @_Floor = 1, @_Slot = 'A';
    SELECT * FROM vw_PostedAdsInfo WHERE AdID = 25;
ROLLBACK TRANSACTION;

-- Should fail - AdID 25 is Pending without the ReviewAd call above
BEGIN TRANSACTION;
    EXEC PostAd @_AdID = 25, @_Bldg = 'LIB', @_Floor = 1, @_Slot = 'A';
ROLLBACK TRANSACTION;

-- Should fail - no board at that location
BEGIN TRANSACTION;
    EXEC PostAd @_AdID = 19, @_Bldg = 'XXX', @_Floor = 9, @_Slot = 'Z';
ROLLBACK TRANSACTION;

-- Should fail - a withdrawn ad cannot be posted
BEGIN TRANSACTION;
    DECLARE @WithdrawnForPost INT;
    EXEC WithdrawAd @_AdID = 19, @_PosterID = 15, @_DeletedMessageCount = @WithdrawnForPost OUTPUT;
    EXEC PostAd @_AdID = 19, @_Bldg = 'LIB', @_Floor = 1, @_Slot = 'A';
ROLLBACK TRANSACTION;

-- -------------------------------------------------------------------------------
GO
-- UnpostAd: take an ad down from one board, or from all of them
-- Should succeed - AdID 1 is posted only to BLD-1-A
BEGIN TRANSACTION;
    EXEC UnpostAd @_AdID = 1, @_Building = 'BLD', @_BldgFloor = 1, @_Slot = 'A';
    SELECT COUNT(*) AS PostingsRemaining FROM Ad_Posted_Board WHERE AdID = 1;  -- expect 0
ROLLBACK TRANSACTION;

-- Should succeed - AdID 7 is posted to four boards; omitting the location clears all
BEGIN TRANSACTION;
    SELECT COUNT(*) AS PostingsBefore FROM Ad_Posted_Board WHERE AdID = 7;  -- expect 4
    EXEC UnpostAd @_AdID = 7;
    SELECT COUNT(*) AS PostingsAfter FROM Ad_Posted_Board WHERE AdID = 7;   -- expect 0
ROLLBACK TRANSACTION;

-- Should fail - AdID 19 is approved but not posted to any board
BEGIN TRANSACTION;
    EXEC UnpostAd @_AdID = 19;
ROLLBACK TRANSACTION;

-- Should fail - AdID 1 is not posted to that particular board
BEGIN TRANSACTION;
    EXEC UnpostAd @_AdID = 1, @_Building = 'NWN', @_BldgFloor = 1, @_Slot = 'A';
ROLLBACK TRANSACTION;

-- Should fail - partial board location
BEGIN TRANSACTION;
    EXEC UnpostAd @_AdID = 1, @_Building = 'BLD';
ROLLBACK TRANSACTION;

-- Should fail - no such ad
BEGIN TRANSACTION;
    EXEC UnpostAd @_AdID = 9999;
ROLLBACK TRANSACTION;

-- -------------------------------------------------------------------------------
GO
-- CheckAdFit: report which boards a given ad could fit on
-- Should succeed - AdID 1 is a normal-sized ad
EXEC CheckAdFit @_AdID = 1;

-- Should succeed - AdID 33 ('Giant Ad', 3500x2100) fits nowhere
EXEC CheckAdFit @_AdID = 33;

-- Should succeed - no such ad returns no rows rather than raising
EXEC CheckAdFit @_AdID = 9999;

-- -------------------------------------------------------------------------------
GO
-- GetAdPostings: every board a given ad currently hangs on
-- Should succeed - AdID 7 is posted to four boards
EXEC GetAdPostings @_AdID = 7;

-- Should succeed - AdID 19 is approved but unposted, returning no rows
EXEC GetAdPostings @_AdID = 19;

-- =============================================================================
-- Messaging
-- The message views, plus sending, retrieving, and deleting the messages
-- exchanged about an ad.
-- =============================================================================

-- -------------------------------------------------------------------------------
GO
-- vw_NumMessagesPerAd: message volume per ad, busiest first
SELECT *
FROM vw_NumMessagesPerAd
ORDER BY NumMessages DESC, AdID;

-- -------------------------------------------------------------------------------
GO
-- vw_MessageCountsPerUser: messages sent and received per person
SELECT *
FROM vw_MessageCountsPerUser
ORDER BY NumSent + NumReceived DESC, PersonID;

-- -------------------------------------------------------------------------------
GO
-- SendMessage: post a message against an ad
-- Approved ad, poster messaging a prospective buyer: should succeed
BEGIN TRANSACTION;
    EXEC SendMessage @_SenderID = 1, @_AdID = 1, @_RecipientID = 18, @_Content = 'Is this still available?';
    SELECT SenderID, RecipientID, Content FROM Messages
    WHERE AdID = 1 AND SenderID = 1 AND RecipientID = 18;
ROLLBACK TRANSACTION;

-- Pending ad, a reviewer asking the poster a clarifying question: should succeed
BEGIN TRANSACTION;
    EXEC SendMessage @_SenderID = 22, @_AdID = 25, @_RecipientID = 17, @_Content = 'Can you confirm the dimensions?';
    SELECT SenderID, RecipientID, Content FROM Messages WHERE AdID = 25;
ROLLBACK TRANSACTION;

-- Should fail - poster not involved on either side
BEGIN TRANSACTION;
    EXEC SendMessage @_SenderID = 18, @_AdID = 25, @_RecipientID = 22, @_Content = 'hi';
ROLLBACK TRANSACTION;

-- Should fail - Pending ad, neither party is a reviewer
BEGIN TRANSACTION;
    EXEC SendMessage @_SenderID = 17, @_AdID = 25, @_RecipientID = 18, @_Content = 'hi';
ROLLBACK TRANSACTION;

-- Should fail - blank content
BEGIN TRANSACTION;
    EXEC SendMessage @_SenderID = 1, @_AdID = 1, @_RecipientID = 18, @_Content = '   ';
ROLLBACK TRANSACTION;

-- Should fail - no such ad
BEGIN TRANSACTION;
    EXEC SendMessage @_SenderID = 1, @_AdID = 9999, @_RecipientID = 18, @_Content = 'hi';
ROLLBACK TRANSACTION;

-- Should fail - a withdrawn ad accepts no further messages
BEGIN TRANSACTION;
    DECLARE @WithdrawnForMessage INT;
    EXEC WithdrawAd @_AdID = 1, @_PosterID = 1, @_DeletedMessageCount = @WithdrawnForMessage OUTPUT;
    EXEC SendMessage @_SenderID = 1, @_AdID = 1, @_RecipientID = 18, @_Content = 'still there?';
ROLLBACK TRANSACTION;

-- -------------------------------------------------------------------------------
GO
-- GetAllADMessages: full conversation on one ad, in chronological order
-- Should succeed - AdID 1 has seven messages
EXEC GetAllADMessages @_AdID = 1;

-- Should succeed - AdID 25 is Pending with no messages, returning no rows
EXEC GetAllADMessages @_AdID = 25;

-- -------------------------------------------------------------------------------
GO
-- DeleteMessage: remove one message by its full primary key
-- Delete one message: should succeed
BEGIN TRANSACTION;
    EXEC DeleteMessage @_SenderID = 5, @_AdID = 1, @_TimeLogged = '2026-06-17 10:30:00';
    SELECT COUNT(*) AS RemainingOnAd1 FROM Messages WHERE AdID = 1;  -- one fewer than before
ROLLBACK TRANSACTION;

-- Should fail - no message with that exact key
BEGIN TRANSACTION;
    EXEC DeleteMessage @_SenderID = 999, @_AdID = 1, @_TimeLogged = '2026-06-17 10:30:00';
ROLLBACK TRANSACTION;

-- Should fail - right sender and ad, wrong timestamp
BEGIN TRANSACTION;
    EXEC DeleteMessage @_SenderID = 5, @_AdID = 1, @_TimeLogged = '2026-06-17 10:31:00';
ROLLBACK TRANSACTION;

-- -------------------------------------------------------------------------------
GO
-- DeleteAdMessages: clear every message attached to one ad
-- Bulk delete every message on an ad: should succeed
BEGIN TRANSACTION;
    DECLARE @BulkDeleted INT;
    EXEC DeleteAdMessages @_AdID = 1, @_DeletedCount = @BulkDeleted OUTPUT;
    SELECT @BulkDeleted AS MessagesDeleted;
    SELECT COUNT(*) AS RemainingOnAd1 FROM Messages WHERE AdID = 1;  -- expect 0
ROLLBACK TRANSACTION;

-- Should succeed - an ad with no messages reports zero deleted
BEGIN TRANSACTION;
    DECLARE @NoneDeleted INT;
    EXEC DeleteAdMessages @_AdID = 25, @_DeletedCount = @NoneDeleted OUTPUT;
    SELECT @NoneDeleted AS MessagesDeleted;  -- expect 0
ROLLBACK TRANSACTION;

-- Should fail - no such ad
BEGIN TRANSACTION;
    DECLARE @BadDeleted INT;
    EXEC DeleteAdMessages @_AdID = 9999, @_DeletedCount = @BadDeleted OUTPUT;
ROLLBACK TRANSACTION;
