--    Created by Mike Verwer | mikeverwer.github.io
-- ** ALL QUERIES IN THIS FILE WORK IN MySQL **
--
-- LOAD ORDER: 3 of 3
--   MySQL_VIEWS.sql  ->  MySQL_PROCEDURES.sql  ->  MySQL_TESTS.sql
-- Requires every view and procedure to already exist, and assumes the seed
-- data in MySQL_INSERT.sql has been loaded. Specific IDs below refer to that
-- seed data: reviewers are PersonIDs 22, 26, 28, and 29; students are 5-21;
-- non-college members are 1-4; AdID 1 is Approved and posted with messages;
-- AdID 19 is Approved but not yet posted; AdID 25 is Pending, posted by 17.
--
-- Every procedure test that writes is wrapped in START TRANSACTION ...
-- ROLLBACK, with a SELECT inside the transaction so the change is visible
-- before it is undone. Tests labelled "should fail" are expected to raise;
-- that raise is the pass condition.
--
-- NOTE: rolling back does not reset AUTO_INCREMENT counters, so PersonID and
-- AdID values assigned by AddNonMember / SubmitAd will advance across repeated
-- runs of this file. That is expected and not a defect.

USE AdPostingDB;

-- =============================================================================
-- Person & Roles
-- Registration procedures, the Grant/Revoke role pairs, the reviewer-flag
-- toggle, and the two contact lookups.
-- =============================================================================

-- -------------------------------------------------------------------------------

-- AddNonMember: register a member of the public
-- Should succeed - new person, unused email
START TRANSACTION;
    CALL AddNonMember('Dana', 'Whitfield', '5551239001', 'dana.whitfield@email.com', @NewNonMember);
    SELECT @NewNonMember AS NewPersonID;
    SELECT PersonID, FirstName, LastName, Email FROM Person WHERE PersonID = @NewNonMember;
ROLLBACK;

-- Should fail - email already belongs to Emma Johnson (PersonID 5)
START TRANSACTION;
    CALL AddNonMember('Duplicate', 'Email', NULL, 'emma.johnson@college.edu', @DupNonMember);
ROLLBACK;

-- Should fail - blank last name
START TRANSACTION;
    CALL AddNonMember('Nameless', '   ', NULL, 'nameless@email.com', @NoNameNonMember);
ROLLBACK;

-- -------------------------------------------------------------------------------

-- AddCollegeMember: register an alum retaining board privileges
-- Should succeed - unused CollegeID and email
START TRANSACTION;
    CALL AddCollegeMember('Alan', 'Brouwer', '5551239002', 'alan.brouwer@college.edu',
                          'ALM000001', 'Alumni Relations', @NewMember);
    SELECT @NewMember AS NewPersonID;
    SELECT PersonID, CollegeID, Department FROM CollegeMember WHERE PersonID = @NewMember;
ROLLBACK;

-- Should fail - CollegeID STU000001 already belongs to Emma Johnson
START TRANSACTION;
    CALL AddCollegeMember('Duplicate', 'CollegeID', NULL, 'duplicate.collegeid@college.edu',
                          'STU000001', NULL, @DupCollegeID);
ROLLBACK;

-- -------------------------------------------------------------------------------

-- AddStudent: full three-table registration (Person, CollegeMember, Student)
-- Should succeed - all three rows created
START TRANSACTION;
    CALL AddStudent('Rosa', 'Iqbal', '5551239003', 'rosa.iqbal@college.edu',
                    'STU000018', 'Mathematics', 'Applied Mathematics', @NewStudent);
    SELECT @NewStudent AS NewPersonID;
    SELECT
        P.PersonID, P.FirstName, P.LastName,
        CM.CollegeID, CM.Department,
        S.Major
    FROM Person AS P
        INNER JOIN CollegeMember AS CM ON P.PersonID = CM.PersonID
        INNER JOIN Student AS S ON P.PersonID = S.PersonID
    WHERE P.PersonID = @NewStudent;
ROLLBACK;

-- Should succeed - Major left NULL for an undeclared student
START TRANSACTION;
    CALL AddStudent('Undeclared', 'Student', NULL, 'undeclared.student@college.edu',
                    'STU000020', 'General Studies', NULL, @UndeclaredStudent);
    SELECT PersonID, Major FROM Student WHERE PersonID = @UndeclaredStudent;
ROLLBACK;

-- Should fail - duplicate email
START TRANSACTION;
    CALL AddStudent('Duplicate', 'Email', NULL, 'emma.johnson@college.edu',
                    'STU000019', NULL, NULL, @DupEmail);
ROLLBACK;

-- -------------------------------------------------------------------------------

-- AddEmployee: full three-table registration (Person, CollegeMember, Employee)
-- Should succeed - office and extension supplied together
START TRANSACTION;
    CALL AddEmployee('Yusuf', 'Demir', '5551239004', 'yusuf.demir@college.edu',
                     'EMP000012', 'Chemistry', 'SCI-215', '7215', 'Faculty', 0, @NewEmployee);
    SELECT @NewEmployee AS NewPersonID;
    SELECT PersonID, OfficeLocation, Extension, PositionTitle, IsReviewer
    FROM Employee WHERE PersonID = @NewEmployee;
ROLLBACK;

-- Should succeed - no office, no extension (matches Chloe Allen, PersonID 27)
START TRANSACTION;
    CALL AddEmployee('Remote', 'Worker', NULL, 'remote.worker@college.edu',
                     'EMP000014', NULL, NULL, NULL, 'Support', 0, @OfficelessEmployee);
    SELECT PersonID, OfficeLocation, Extension FROM Employee WHERE PersonID = @OfficelessEmployee;
ROLLBACK;

-- Should fail - extension without an office
START TRANSACTION;
    CALL AddEmployee('Test', 'Case', NULL, 'test.case@college.edu',
                     'EMP000013', NULL, NULL, '9999', 'Support', 0, @BadEmployee);
ROLLBACK;

-- Should fail - invalid position title
START TRANSACTION;
    CALL AddEmployee('Bad', 'Title', NULL, 'bad.title@college.edu',
                     'EMP000015', NULL, NULL, NULL, 'Custodian', 0, @BadTitleEmployee);
ROLLBACK;

-- -------------------------------------------------------------------------------

-- GrantCollegeMemberRole: promote an existing Person to College Member
-- Should succeed - John Smith (PersonID 1) is a non-member
START TRANSACTION;
    CALL GrantCollegeMemberRole(1, 'ALM000002', 'Alumni Relations');
    SELECT PersonID, CollegeID, Department FROM CollegeMember WHERE PersonID = 1;
ROLLBACK;

-- Should fail - Emma Johnson (PersonID 5) already holds College Member status
START TRANSACTION;
    CALL GrantCollegeMemberRole(5, 'ALM000003', NULL);
ROLLBACK;

-- Should fail - no such person
START TRANSACTION;
    CALL GrantCollegeMemberRole(9999, 'ALM000004', NULL);
ROLLBACK;

-- -------------------------------------------------------------------------------

-- RevokeCollegeMemberRole: strip College Member status
-- Should succeed - grant it to a non-member first, then take it away again
START TRANSACTION;
    CALL GrantCollegeMemberRole(2, 'ALM000005', NULL);
    SELECT COUNT(*) AS MemberRowsBefore FROM CollegeMember WHERE PersonID = 2;  -- expect 1
    CALL RevokeCollegeMemberRole(2);
    SELECT COUNT(*) AS MemberRowsAfter FROM CollegeMember WHERE PersonID = 2;   -- expect 0
ROLLBACK;

-- Should fail - RevokeCollegeMemberRole refuses while Student status remains
START TRANSACTION;
    CALL RevokeCollegeMemberRole(5);  -- Emma Johnson, a Student
ROLLBACK;

-- Should fail - James Harris (PersonID 22) still holds Employee status
START TRANSACTION;
    CALL RevokeCollegeMemberRole(22);
ROLLBACK;

-- -------------------------------------------------------------------------------

-- GrantStudentRole: add Student status to an existing College Member
-- Should succeed - Emily Clark (PersonID 23) is an Employee, becomes dual-role
START TRANSACTION;
    CALL GrantStudentRole(23, 'Educational Leadership');
    SELECT PersonID, Major FROM Student WHERE PersonID = 23;
    SELECT PersonID, PositionTitle FROM Employee WHERE PersonID = 23;  -- still present
ROLLBACK;

-- Should fail - Emma Johnson (PersonID 5) already holds Student status
START TRANSACTION;
    CALL GrantStudentRole(5, 'Physics');
ROLLBACK;

-- Should fail - John Smith (PersonID 1) is not a College Member
START TRANSACTION;
    CALL GrantStudentRole(1, 'Physics');
ROLLBACK;

-- -------------------------------------------------------------------------------

-- RevokeStudentRole: strip Student status, leaving College Member intact
-- Should succeed - Liam Davis (PersonID 6) keeps his CollegeMember row
START TRANSACTION;
    CALL RevokeStudentRole(6);
    SELECT COUNT(*) AS StudentRows FROM Student WHERE PersonID = 6;              -- expect 0
    SELECT COUNT(*) AS CollegeMemberRows FROM CollegeMember WHERE PersonID = 6;  -- expect 1
ROLLBACK;

-- Should fail - James Harris (PersonID 22) is not a Student
START TRANSACTION;
    CALL RevokeStudentRole(22);
ROLLBACK;

-- -------------------------------------------------------------------------------

-- GrantEmployeeRole: add Employee status to an existing College Member.
-- Demonstrates a graduate student TA: Priya Nair (PersonID 21, a Student) is
-- granted Employee status without giving up Student status.
START TRANSACTION;
    CALL GrantEmployeeRole(21, 'MTH-110', '7110', 'Staff', 0);
    SELECT * FROM Student WHERE PersonID = 21;    -- still present
    SELECT * FROM Employee WHERE PersonID = 21;   -- now present too
ROLLBACK;

-- Should fail - James Harris (PersonID 22) already holds Employee status
START TRANSACTION;
    CALL GrantEmployeeRole(22, NULL, NULL, 'Staff', 0);
ROLLBACK;

-- Should fail - extension without an office
START TRANSACTION;
    CALL GrantEmployeeRole(20, NULL, '9999', 'Support', 0);
ROLLBACK;

-- -------------------------------------------------------------------------------

-- RevokeEmployeeRole: strip Employee status, preserving review history
-- Should succeed - revoking Employee nulls ReviewerID on ads they reviewed
START TRANSACTION;
    SELECT COUNT(*) AS ReviewedBefore FROM Ad WHERE ReviewerID = 22;
    CALL RevokeEmployeeRole(22);  -- James Harris, a reviewer
    SELECT COUNT(*) AS ReviewedAfter FROM Ad WHERE ReviewerID = 22;  -- expect 0
    -- Those reviews are still counted, now under 'Deleted Reviewer(s)'
    SELECT * FROM vw_ReviewCountsPerReviewer WHERE PersonID IS NULL;
ROLLBACK;

-- Should fail - Emma Johnson (PersonID 5) is a Student, not an Employee
START TRANSACTION;
    CALL RevokeEmployeeRole(5);
ROLLBACK;

-- -------------------------------------------------------------------------------

-- EditUserCoreInfo: update a person's core contact info
-- Should succeed - John Smith (PersonID 1), unused new email
START TRANSACTION;
    CALL EditUserCoreInfo(1, 'Jon', 'Smith', '5551239999', 'jon.smith@newmail.com');
    SELECT FirstName, LastName, Phone, Email FROM Person WHERE PersonID = 1;
ROLLBACK;

-- Should succeed - keeping the same email is not a collision with yourself
START TRANSACTION;
    CALL EditUserCoreInfo(5, 'Emma', 'Johnson', '5551230000', 'emma.johnson@college.edu');
    SELECT Phone FROM Person WHERE PersonID = 5;
ROLLBACK;

-- Should fail - email collides with another real person
START TRANSACTION;
    SELECT Email INTO @TakenEmail FROM Person WHERE PersonID <> 1 LIMIT 1;
    CALL EditUserCoreInfo(1, 'Jon', 'Smith', NULL, @TakenEmail);
ROLLBACK;

-- Should fail - blank last name
START TRANSACTION;
    CALL EditUserCoreInfo(1, 'Jon', '   ', NULL, 'jon@newmail.com');
ROLLBACK;

-- Should fail - no such person
START TRANSACTION;
    CALL EditUserCoreInfo(9999, 'X', 'Y', NULL, 'x@y.com');
ROLLBACK;

-- -------------------------------------------------------------------------------

-- EditCollegeMemberInfo: update CollegeID and/or Department
-- Should succeed - Liam Davis (PersonID 6) is a College Member
START TRANSACTION;
    CALL EditCollegeMemberInfo(6, 'STU000099', 'Physics');
    SELECT CollegeID, Department FROM CollegeMember WHERE PersonID = 6;
ROLLBACK;

-- Should succeed - keeping the same CollegeID is not a collision with yourself
START TRANSACTION;
    SELECT CollegeID INTO @OwnCollegeID FROM CollegeMember WHERE PersonID = 6;
    CALL EditCollegeMemberInfo(6, @OwnCollegeID, 'Renamed Dept');
    SELECT Department FROM CollegeMember WHERE PersonID = 6;
ROLLBACK;

-- Should fail - CollegeID collides with another real college member
START TRANSACTION;
    SELECT CollegeID INTO @TakenCollegeID FROM CollegeMember WHERE PersonID <> 6 LIMIT 1;
    CALL EditCollegeMemberInfo(6, @TakenCollegeID, NULL);
ROLLBACK;

-- Should fail - John Smith (PersonID 1) is not a College Member
START TRANSACTION;
    CALL EditCollegeMemberInfo(1, 'ALM000010', NULL);
ROLLBACK;

-- Should fail - blank CollegeID
START TRANSACTION;
    CALL EditCollegeMemberInfo(6, '   ', NULL);
ROLLBACK;

-- -------------------------------------------------------------------------------

-- EditStudentInfo: update Major
-- Should succeed - Liam Davis (PersonID 6) is a Student
START TRANSACTION;
    CALL EditStudentInfo(6, 'Computer Science');
    SELECT Major FROM Student WHERE PersonID = 6;
ROLLBACK;

-- Should succeed - clearing Major back to undeclared
START TRANSACTION;
    CALL EditStudentInfo(6, NULL);
    SELECT Major FROM Student WHERE PersonID = 6;  -- expect NULL
ROLLBACK;

-- Should fail - James Harris (PersonID 22) is an Employee, not a Student
START TRANSACTION;
    CALL EditStudentInfo(22, 'Physics');
ROLLBACK;

-- -------------------------------------------------------------------------------

-- EditEmployeeInfo: update OfficeLocation, Extension, PositionTitle
-- Should succeed - Thomas Okafor (PersonID 30) is an Employee
START TRANSACTION;
    CALL EditEmployeeInfo(30, 'ADM-201', '8201', 'Administration');
    SELECT OfficeLocation, Extension, PositionTitle FROM Employee WHERE PersonID = 30;
ROLLBACK;

-- Should succeed - clearing both office and extension together
START TRANSACTION;
    CALL EditEmployeeInfo(30, NULL, NULL, 'Support');
    SELECT OfficeLocation, Extension FROM Employee WHERE PersonID = 30;  -- expect NULL, NULL
ROLLBACK;

-- Should fail - Liam Davis (PersonID 6) is a Student, not an Employee
START TRANSACTION;
    CALL EditEmployeeInfo(6, NULL, NULL, 'Staff');
ROLLBACK;

-- Should fail - extension without an office
START TRANSACTION;
    CALL EditEmployeeInfo(30, NULL, '9999', 'Staff');
ROLLBACK;

-- Should fail - invalid position title
START TRANSACTION;
    CALL EditEmployeeInfo(30, NULL, NULL, 'Custodian');
ROLLBACK;

-- -------------------------------------------------------------------------------

-- SetReviewerPermission: toggle the IsReviewer flag on an existing Employee
-- Should succeed - Thomas Okafor (PersonID 30) is an Employee, not yet a reviewer
START TRANSACTION;
    CALL SetReviewerPermission(30, 1);
    SELECT PersonID, IsReviewer FROM Employee WHERE PersonID = 30;  -- expect 1
ROLLBACK;

-- Should succeed - revoking the flag from an existing reviewer
START TRANSACTION;
    CALL SetReviewerPermission(26, 0);
    SELECT PersonID, IsReviewer FROM Employee WHERE PersonID = 26;  -- expect 0
ROLLBACK;

-- Should fail - Emma Johnson (PersonID 5) is a Student, not an Employee
START TRANSACTION;
    CALL SetReviewerPermission(5, 1);
ROLLBACK;

-- -------------------------------------------------------------------------------

-- GetPosterInfo: contact card for whoever posted a given ad
-- Should succeed - AdID 1 was posted by John Smith, a non-member
CALL GetPosterInfo(1);

-- Should succeed - AdID 2 was posted by Emma Johnson, a Student
CALL GetPosterInfo(2);

-- Should fail - no such ad
CALL GetPosterInfo(9999);

-- -------------------------------------------------------------------------------

-- GetReviewerInfo: contact card for whoever reviewed a given ad
-- Should succeed - AdID 1 was reviewed by James Harris (PersonID 22)
CALL GetReviewerInfo(1);

-- Should succeed - AdID 25 is Pending, so it has no reviewer on record
CALL GetReviewerInfo(25);

-- Should fail - no such ad
CALL GetReviewerInfo(9999);

-- =============================================================================
-- Ad Lifecycle & Review
-- Submission, the review decision, withdrawal, and the views and reports that
-- track an ad's progress through those states.
-- =============================================================================

-- -------------------------------------------------------------------------------

-- vw_ExpiredAds: ads whose posting duration has elapsed
SELECT *
FROM vw_ExpiredAds
ORDER BY DaysOverdue DESC, AdID;

-- -------------------------------------------------------------------------------

-- vw_ReviewQueue: ads awaiting a review decision, oldest first
SELECT *
FROM vw_ReviewQueue
ORDER BY QueuePosition;

-- -------------------------------------------------------------------------------

-- vw_ReviewCountsPerReviewer: approvals and rejections per reviewer
SELECT *
FROM vw_ReviewCountsPerReviewer
ORDER BY TotalReviews DESC, ReviewerName;

-- -------------------------------------------------------------------------------

-- AdsByUserType: every ad tagged with the type of user who posted it
SELECT *
FROM AdsByUserType
ORDER BY UserType, PosterID, AdID;

-- -------------------------------------------------------------------------------

-- vw_AdsByUserTypeAndAdType: pivot of user type against ad type, with totals
SELECT *
FROM vw_AdsByUserTypeAndAdType
ORDER BY RowTotal DESC, UserType;

-- -------------------------------------------------------------------------------

-- SubmitAd: create a new ad in Pending status
-- Should succeed - defaults produce Pending, no reviewer, no post date
START TRANSACTION;
    CALL SubmitAd(3, 'Kayak for Sale', 'Sale', 350, 90, NULL, 'kayak.jpg', @NewAd);
    SELECT * FROM Ad WHERE AdID = @NewAd;
ROLLBACK;

-- Should succeed - explicit duration overrides the default of 14
START TRANSACTION;
    CALL SubmitAd(5, 'Semester-Long Tutoring', 'Tutorship', 300, 200, 90, 'tutor-poster.jpg', @LongAd);
    SELECT AdID, Title, Duration, ReviewStatus FROM Ad WHERE AdID = @LongAd;
ROLLBACK;

-- Should fail - invalid ad type
START TRANSACTION;
    CALL SubmitAd(1, 'Test', 'Rummage', 100, 100, NULL, 'bad-post.jpg', @BadAd);
ROLLBACK;

-- Should fail - no such poster
START TRANSACTION;
    CALL SubmitAd(9999, 'Orphan Ad', 'Sale', 100, 100, NULL, 'bad-post.jpg', @NoPosterAd);
ROLLBACK;

-- Should fail - non-positive dimensions
START TRANSACTION;
    CALL SubmitAd(1, 'Zero Width', 'Sale', 100, 0, NULL, 'bad-post.jpg', @ZeroAd);
ROLLBACK;

-- Should fail - blank image filename
START TRANSACTION;
    CALL SubmitAd(1, 'Missing Image', 'Sale', 100, 0, NULL, '', @NoImageAd);
ROLLBACK;

-- -------------------------------------------------------------------------------

-- GetAdDetails: full detail lookup by AdID list, or every ad if NULL
-- Should succeed - NULL returns every ad
CALL GetAdDetails(NULL);

-- Should succeed - single AdID
CALL GetAdDetails('1');

-- Should succeed - mix of existing and nonexistent AdIDs: 9999 is silently
-- omitted rather than raising, since the list is a filter, not a validation
CALL GetAdDetails('1, 19, 9999, 25');
-- expect exactly 3 rows: AdID 1, 19, 25

-- Should succeed - stray whitespace around list entries is tolerated
CALL GetAdDetails(' 1 ,  19  ');

-- -------------------------------------------------------------------------------

-- ReviewAd: approve, reject, or return an ad to the review queue
-- Should succeed - AdID 25 is Pending; PersonID 22 is a reviewer
START TRANSACTION;
    CALL ReviewAd(25, 'Approved', 22, NULL);
    SELECT AdID, ReviewStatus, ReviewerID, ReviewDate FROM Ad WHERE AdID = 25;
ROLLBACK;

-- Should succeed - rejecting instead, with an explicit review date
START TRANSACTION;
    CALL ReviewAd(25, 'Rejected', 26, '2026-07-20');
    SELECT AdID, ReviewStatus, ReviewerID, ReviewDate FROM Ad WHERE AdID = 25;
ROLLBACK;

-- Should succeed - returning an approved ad to Pending clears reviewer and date
START TRANSACTION;
    CALL ReviewAd(1, 'Pending', 22, NULL);
    SELECT AdID, ReviewStatus, ReviewerID, ReviewDate FROM Ad WHERE AdID = 1;
ROLLBACK;

-- Should fail - PersonID 19 is a student, not a reviewer
START TRANSACTION;
    CALL ReviewAd(25, 'Approved', 19, NULL);
ROLLBACK;

-- Should fail - invalid status
START TRANSACTION;
    CALL ReviewAd(25, 'Deferred', 22, NULL);
ROLLBACK;

-- Should fail - a withdrawn ad can no longer be reviewed
START TRANSACTION;
    CALL WithdrawAd(25, 17, @WithdrawnFirst);
    CALL ReviewAd(25, 'Approved', 22, NULL);
ROLLBACK;

-- -------------------------------------------------------------------------------

-- WithdrawAd: poster pulls their own ad and its message history
-- Should succeed - AdID 1 was posted by PersonID 1 and has messages attached
START TRANSACTION;
    CALL WithdrawAd(1, 1, @Deleted);
    SELECT @Deleted AS MessagesDeleted;
    SELECT ReviewStatus, IsWithdrawn, WithdrawnDate FROM Ad WHERE AdID = 1;
    -- Board postings are deliberately left in place, and now surface for takedown
    SELECT * FROM vw_PendingRemoval WHERE AdID = 1;
ROLLBACK;

-- Should fail - wrong poster
START TRANSACTION;
    CALL WithdrawAd(1, 999, @BadWithdraw);
ROLLBACK;

-- Should fail - withdrawal is one-way
START TRANSACTION;
    CALL WithdrawAd(1, 1, @FirstWithdraw);
    CALL WithdrawAd(1, 1, @SecondWithdraw);
ROLLBACK;

-- Should fail - no such ad
START TRANSACTION;
    CALL WithdrawAd(9999, 1, @NoAdWithdraw);
ROLLBACK;

-- -------------------------------------------------------------------------------

-- DeleteAd: permanently remove an ad, returning its image for cleanup.
-- Moderation action -- authorization is by Reviewer status, not by poster.
-- Should succeed - AdID 19 is Approved but not posted to any board
START TRANSACTION;
    CALL DeleteAd(19, 22, @DelMsgs, @DelImage);
    SELECT @DelMsgs AS MessagesDeleted, @DelImage AS ImageToClean;
    SELECT COUNT(*) AS AdRows FROM Ad WHERE AdID = 19;  -- expect 0
ROLLBACK;

-- Should succeed - unpost first, then delete an ad that was on a board.
-- AdID 1 has messages attached, so MessagesDeleted should be non-zero.
START TRANSACTION;
    CALL UnpostAd(1, 'BLD', 1, 'A');
    CALL DeleteAd(1, 26, @UnpostMsgs, @UnpostImage);
    SELECT @UnpostMsgs AS MessagesDeleted, @UnpostImage AS ImageToClean;
    SELECT COUNT(*) AS AdRows      FROM Ad              WHERE AdID = 1;  -- expect 0
    SELECT COUNT(*) AS MessageRows FROM Messages        WHERE AdID = 1;  -- expect 0
    SELECT COUNT(*) AS PostingRows FROM Ad_Posted_Board WHERE AdID = 1;  -- expect 0
ROLLBACK;

-- Should succeed - a Pending ad with no messages reports zero deleted
START TRANSACTION;
    CALL DeleteAd(25, 28, @PendMsgs, @PendImage);
    SELECT @PendMsgs AS MessagesDeleted;  -- expect 0
ROLLBACK;

-- Should fail - AdID 1 is still posted to a board
START TRANSACTION;
    CALL DeleteAd(1, 22, @PostedMsgs, @PostedImage);
ROLLBACK;

-- Should fail - PersonID 5 is a Student, not a Reviewer; a poster can no
-- longer delete their own ad under this authorization model
START TRANSACTION;
    CALL DeleteAd(19, 5, @NonRevMsgs, @NonRevImage);
ROLLBACK;

-- Should fail - NULL reviewer ID
START TRANSACTION;
    CALL DeleteAd(19, NULL, @NullRevMsgs, @NullRevImage);
ROLLBACK;

-- Should fail - no such ad
START TRANSACTION;
    CALL DeleteAd(9999, 22, @NoAdMsgs, @NoAdImage);
ROLLBACK;

-- Should succeed - deletion is permitted after withdrawal, and is the
-- mechanism by which a withdrawn ad is eventually purged
START TRANSACTION;
    CALL WithdrawAd(19, 15, @WdMsgs);
    CALL DeleteAd(19, 29, @WdDelMsgs, @WdImage);
    SELECT COUNT(*) AS AdRows FROM Ad WHERE AdID = 19;  -- expect 0
ROLLBACK;

-- -------------------------------------------------------------------------------

-- GetNoncompliantPosters: posters with repeated rejections
-- Should succeed - NULL falls back to the default threshold of 2 rejections
CALL GetNoncompliantPosters(NULL);

-- Should succeed - stricter threshold; Amelia White (PersonID 19) has 3
CALL GetNoncompliantPosters(3);

-- Should succeed - threshold above any poster's count, returning no rows
CALL GetNoncompliantPosters(99);

-- -------------------------------------------------------------------------------

-- GetPosterRejectionHistory: every rejected ad for one poster
-- Should succeed - Amelia White (PersonID 19) has three rejected ads
CALL GetPosterRejectionHistory(19);

-- Should succeed - John Smith (PersonID 1) has none, returning no rows
CALL GetPosterRejectionHistory(1);

-- Should fail - no such person
CALL GetPosterRejectionHistory(9999);

-- =============================================================================
-- Board & Posting
-- Board creation and retirement, placing and removing ads, and the space
-- accounting views that report on the result.
-- =============================================================================

-- -------------------------------------------------------------------------------

-- vw_PostedAdsInfo: every ad currently on a board, with its full ad record
SELECT *
FROM vw_PostedAdsInfo
ORDER BY Building, BldgFloor, Slot, AdID;

-- -------------------------------------------------------------------------------

-- vw_BoardSpace: per-board occupancy and remaining space
SELECT *
FROM vw_BoardSpace
ORDER BY
    Building, 
    BldgFloor, 
    Slot;

-- -------------------------------------------------------------------------------

-- vw_BoardSpaceDisplay: the same accounting, formatted and ranked by fullness
SELECT *
FROM vw_BoardSpaceDisplay
ORDER BY FullnessRank;

-- -------------------------------------------------------------------------------

-- vw_PendingPosting: approved ads that have not been placed on a board yet
SELECT *
FROM vw_PendingPosting
ORDER BY ReviewDate, AdID;

-- -------------------------------------------------------------------------------

-- vw_PendingRemoval: ads that should be removed from boards.
SELECT *
FROM vw_PendingRemoval
ORDER BY Building, BldgFloor, Slot, AdID;

-- -------------------------------------------------------------------------------

-- NewBoard: register a new physical board
-- Should succeed - fresh board
START TRANSACTION;
    CALL NewBoard('SCI', 1, 'A', 2200, 1600);
    SELECT * FROM Board WHERE Building = 'SCI';
ROLLBACK;

-- Should fail - duplicate location
START TRANSACTION;
    CALL NewBoard('BLD', 1, 'A', 2000, 1500);
ROLLBACK;

-- Should fail - non-positive dimensions
START TRANSACTION;
    CALL NewBoard('SCI', 2, 'A', 0, 1500);
ROLLBACK;

-- -------------------------------------------------------------------------------

-- RetireBoard: permanently remove a board
-- Should succeed - a freshly created board has nothing posted to it
START TRANSACTION;
    CALL NewBoard('SCI', 1, 'A', 2200, 1600);
    SELECT COUNT(*) AS BoardsBefore FROM Board WHERE Building = 'SCI';  -- expect 1
    CALL RetireBoard('SCI', 1, 'A');
    SELECT COUNT(*) AS BoardsAfter FROM Board WHERE Building = 'SCI';   -- expect 0
ROLLBACK;

-- Should fail - board still populated
START TRANSACTION;
    CALL RetireBoard('BLD', 1, 'A');
ROLLBACK;

-- Should fail - no board at that location
START TRANSACTION;
    CALL RetireBoard('XXX', 9, 'Z');
ROLLBACK;

-- Should succeed - clear the board first, then retire it.
-- NWN-2-A holds AdIDs 15 and 16 in the seed data.
START TRANSACTION;
    CALL UnpostAd(15, 'NWN', 2, 'A');
    CALL UnpostAd(16, 'NWN', 2, 'A');
    SELECT COUNT(*) AS PostingsRemaining FROM Ad_Posted_Board
    WHERE Building = 'NWN' AND BldgFloor = 2 AND Slot = 'A';  -- expect 0
    CALL RetireBoard('NWN', 2, 'A');
    SELECT COUNT(*) AS BoardRows FROM Board
    WHERE Building = 'NWN' AND BldgFloor = 2 AND Slot = 'A';  -- expect 0
ROLLBACK;

-- -------------------------------------------------------------------------------

-- EditBoardDetails: update a board's dimensions and/or location
-- Should succeed - dimensions only, no location change (BLD-1-A holds AdID 1)
START TRANSACTION;
    CALL EditBoardDetails('BLD', 1, 'A', 'BLD', 1, 'A', 2500, 1800);
    SELECT * FROM Board WHERE Building = 'BLD' AND BldgFloor = 1 AND Slot = 'A';
    SELECT COUNT(*) AS StillPosted FROM Ad_Posted_Board
    WHERE Building = 'BLD' AND BldgFloor = 1 AND Slot = 'A';  -- unaffected, expect 1
ROLLBACK;

-- Should succeed - location change; NWN-2-A holds AdID 15 and 16, and the
-- cascade should carry both postings to the new location automatically
START TRANSACTION;
    CALL EditBoardDetails('NWN', 2, 'A', 'NWN', 9, 'Z', 2000, 1500);
    SELECT COUNT(*) AS OldLocationBoardRows FROM Board
    WHERE Building = 'NWN' AND BldgFloor = 2 AND Slot = 'A';  -- expect 0
    SELECT COUNT(*) AS OldLocationPostings FROM Ad_Posted_Board
    WHERE Building = 'NWN' AND BldgFloor = 2 AND Slot = 'A';  -- expect 0
    SELECT AdID, Building, BldgFloor, Slot FROM Ad_Posted_Board
    WHERE AdID IN (15, 16);  -- both should now show NWN-9-Z
ROLLBACK;

-- Should fail - BLD-1-A holds AdID 1 (300x200 = 60,000 cm2); shrinking well below that
START TRANSACTION;
    CALL EditBoardDetails('BLD', 1, 'A', 'BLD', 1, 'A', 10, 10);
ROLLBACK;

-- Should fail - new location already occupied by another real board
START TRANSACTION;
    CALL EditBoardDetails('BLD', 1, 'A', 'NWN', 2, 'A', 2000, 1500);
ROLLBACK;

-- Should fail - no board at the given (old) location
START TRANSACTION;
    CALL EditBoardDetails('XXX', 9, 'Z', 'XXX', 9, 'Z', 2000, 1500);
ROLLBACK;

-- Should fail - non-positive new dimensions
START TRANSACTION;
    CALL EditBoardDetails('BLD', 1, 'A', 'BLD', 1, 'A', 0, 1500);
ROLLBACK;

-- -------------------------------------------------------------------------------

-- PostAd: place an approved ad on a board
-- Should succeed - AdID 19 is Approved but not yet posted anywhere
START TRANSACTION;
    CALL PostAd(19, 'LIB', 1, 'A');
    SELECT * FROM Ad_Posted_Board WHERE AdID = 19;
ROLLBACK;

-- Should succeed - approve a Pending ad, then post it in the same transaction
START TRANSACTION;
    CALL ReviewAd(25, 'Approved', 22, NULL);
    CALL PostAd(25, 'LIB', 1, 'A');
    SELECT * FROM vw_PostedAdsInfo WHERE AdID = 25;
ROLLBACK;

-- Should fail - AdID 25 is Pending without the ReviewAd call above
START TRANSACTION;
    CALL PostAd(25, 'LIB', 1, 'A');
ROLLBACK;

-- Should fail - no board at that location
START TRANSACTION;
    CALL PostAd(19, 'XXX', 9, 'Z');
ROLLBACK;

-- Should fail - a withdrawn ad cannot be posted
START TRANSACTION;
    CALL WithdrawAd(19, 15, @WithdrawnForPost);
    CALL PostAd(19, 'LIB', 1, 'A');
ROLLBACK;

-- -------------------------------------------------------------------------------

-- UnpostAd: take an ad down from one board, or from all of them
-- Should succeed - AdID 1 is posted only to BLD-1-A
START TRANSACTION;
    CALL UnpostAd(1, 'BLD', 1, 'A');
    SELECT COUNT(*) AS PostingsRemaining FROM Ad_Posted_Board WHERE AdID = 1;  -- expect 0
ROLLBACK;

-- Should succeed - AdID 7 is posted to four boards; omitting the location clears all
START TRANSACTION;
    SELECT COUNT(*) AS PostingsBefore FROM Ad_Posted_Board WHERE AdID = 7;  -- expect 4
    CALL UnpostAd(7, NULL, NULL, NULL);
    SELECT COUNT(*) AS PostingsAfter FROM Ad_Posted_Board WHERE AdID = 7;   -- expect 0
ROLLBACK;

-- Should fail - AdID 19 is approved but not posted to any board
START TRANSACTION;
    CALL UnpostAd(19, NULL, NULL, NULL);
ROLLBACK;

-- Should fail - AdID 1 is not posted to that particular board
START TRANSACTION;
    CALL UnpostAd(1, 'NWN', 1, 'A');
ROLLBACK;

-- Should fail - partial board location
START TRANSACTION;
    CALL UnpostAd(1, 'BLD', NULL, NULL);
ROLLBACK;

-- Should fail - no such ad
START TRANSACTION;
    CALL UnpostAd(9999, NULL, NULL, NULL);
ROLLBACK;

-- -------------------------------------------------------------------------------

-- CheckAdFit: report which boards a given ad could fit on
-- Should succeed - AdID 1 is a normal-sized ad
CALL CheckAdFit(1);

-- Should succeed - AdID 33 ('Giant Ad', 3500x2100) fits nowhere
CALL CheckAdFit(33);

-- Should succeed - no such ad returns no rows rather than raising
CALL CheckAdFit(9999);

-- -------------------------------------------------------------------------------

-- GetAdPostings: every board a given ad currently hangs on
-- Should succeed - AdID 7 is posted to four boards
CALL GetAdPostings(7);

-- Should succeed - AdID 19 is approved but unposted, returning no rows
CALL GetAdPostings(19);

-- =============================================================================
-- Messaging
-- The message views, plus sending, retrieving, and deleting the messages
-- exchanged about an ad.
-- =============================================================================

-- -------------------------------------------------------------------------------

-- vw_NumMessagesPerAd: message volume per ad, busiest first
SELECT *
FROM vw_NumMessagesPerAd
ORDER BY NumMessages DESC, AdID;

-- -------------------------------------------------------------------------------

-- vw_MessageCountsPerUser: messages sent and received per person
SELECT *
FROM vw_MessageCountsPerUser
ORDER BY NumSent + NumReceived DESC, PersonID;

-- -------------------------------------------------------------------------------

-- SendMessage: post a message against an ad
-- Approved ad, poster messaging a prospective buyer: should succeed
START TRANSACTION;
    CALL SendMessage(1, 1, 18, 'Is this still available?');
    SELECT SenderID, RecipientID, Content FROM Messages
    WHERE AdID = 1 AND SenderID = 1 AND RecipientID = 18;
ROLLBACK;

-- Pending ad, a reviewer asking the poster a clarifying question: should succeed
START TRANSACTION;
    CALL SendMessage(22, 25, 17, 'Can you confirm the dimensions?');
    SELECT SenderID, RecipientID, Content FROM Messages WHERE AdID = 25;
ROLLBACK;

-- Should fail - poster not involved on either side
START TRANSACTION;
    CALL SendMessage(18, 25, 22, 'hi');
ROLLBACK;

-- Should fail - Pending ad, neither party is a reviewer
START TRANSACTION;
    CALL SendMessage(17, 25, 18, 'hi');
ROLLBACK;

-- Should fail - blank content
START TRANSACTION;
    CALL SendMessage(1, 1, 18, '   ');
ROLLBACK;

-- Should fail - no such ad
START TRANSACTION;
    CALL SendMessage(1, 9999, 18, 'hi');
ROLLBACK;

-- Should fail - a withdrawn ad accepts no further messages
START TRANSACTION;
    CALL WithdrawAd(1, 1, @WithdrawnForMessage);
    CALL SendMessage(1, 1, 18, 'still there?');
ROLLBACK;

-- -------------------------------------------------------------------------------

-- GetAllADMessages: full conversation on one ad, in chronological order
-- Should succeed - AdID 1 has seven messages
CALL GetAllADMessages(1);

-- Should succeed - AdID 25 is Pending with no messages, returning no rows
CALL GetAllADMessages(25);

-- -------------------------------------------------------------------------------

-- DeleteMessage: remove one message by its full primary key
-- Delete one message: should succeed
START TRANSACTION;
    CALL DeleteMessage(5, 1, '2026-06-17 10:30:00');
    SELECT COUNT(*) AS RemainingOnAd1 FROM Messages WHERE AdID = 1;  -- one fewer than before
ROLLBACK;

-- Should fail - no message with that exact key
START TRANSACTION;
    CALL DeleteMessage(999, 1, '2026-06-17 10:30:00');
ROLLBACK;

-- Should fail - right sender and ad, wrong timestamp
START TRANSACTION;
    CALL DeleteMessage(5, 1, '2026-06-17 10:31:00');
ROLLBACK;

-- -------------------------------------------------------------------------------

-- DeleteAdMessages: clear every message attached to one ad
-- Bulk delete every message on an ad: should succeed
START TRANSACTION;
    CALL DeleteAdMessages(1, @BulkDeleted);
    SELECT @BulkDeleted AS MessagesDeleted;
    SELECT COUNT(*) AS RemainingOnAd1 FROM Messages WHERE AdID = 1;  -- expect 0
ROLLBACK;

-- Should succeed - an ad with no messages reports zero deleted
START TRANSACTION;
    CALL DeleteAdMessages(25, @NoneDeleted);
    SELECT @NoneDeleted AS MessagesDeleted;  -- expect 0
ROLLBACK;

-- Should fail - no such ad
START TRANSACTION;
    CALL DeleteAdMessages(9999, @BadDeleted);
ROLLBACK;

-- =============================================================================
-- Lookups & Search
-- Read-only search helpers for finding records by more human-friendly
-- criteria than raw primary keys: poster name, ad title, person name, and
-- message participant name. Every name match here accepts a first name, a
-- last name, or the full "First Last" string; title search is the only
-- partial match, since ad titles are free text.
-- =============================================================================

-- -------------------------------------------------------------------------------

-- SearchAdsByPosterName: find ads by poster first/last/full name
-- Should succeed - last name match finds John Smith's ad
CALL SearchAdsByPosterName('Smith');

-- Should succeed - full name match finds the same result
CALL SearchAdsByPosterName('John Smith');

-- Should succeed - no match returns no rows, not an error
CALL SearchAdsByPosterName('Nonexistent');

-- -------------------------------------------------------------------------------

-- SearchAdsByTitle: partial match on ad title
-- Should succeed - matches every ad with "Sale" in the title
CALL SearchAdsByTitle('Sale');

-- Should succeed - case-insensitivity follows default collation
CALL SearchAdsByTitle('sale');

-- Should succeed - no match returns no rows, not an error
CALL SearchAdsByTitle('Nonexistent Title Text');

-- -------------------------------------------------------------------------------

-- SearchPeopleByName: find people by first/last/full name, with role flags
-- Should succeed - John Smith (PersonID 1), a non-member: all role flags 'No'
CALL SearchPeopleByName('Smith');

-- Should succeed - Emma Johnson (PersonID 5): IsStudent and IsCollegeMember 'Yes'
CALL SearchPeopleByName('Johnson');

-- Should succeed - no match returns no rows, not an error
CALL SearchPeopleByName('Nonexistent');

-- -------------------------------------------------------------------------------

-- SearchMessagesBySenderOrRecipientName: a person's own messages, by the
-- other party's name
-- Should succeed - John Smith (PersonID 1) searching for 'Johnson' finds his
-- conversation with Emma Johnson on AdID 1
CALL SearchMessagesBySenderOrRecipientName(1, 'Johnson');

-- Should succeed - same conversation, found from the other side
CALL SearchMessagesBySenderOrRecipientName(5, 'Smith');

-- Should succeed - a real name, but the searcher wasn't part of that
-- conversation, so it's correctly excluded rather than raising
CALL SearchMessagesBySenderOrRecipientName(30, 'Johnson');

-- Should fail - no such person
CALL SearchMessagesBySenderOrRecipientName(9999, 'Johnson');