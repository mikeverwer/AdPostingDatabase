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
    CALL SubmitAd(3, 'Kayak for Sale', 'Sale', 350, 90, NULL, @NewAd);
    SELECT * FROM Ad WHERE AdID = @NewAd;
ROLLBACK;

-- Should succeed - explicit duration overrides the default of 14
START TRANSACTION;
    CALL SubmitAd(5, 'Semester-Long Tutoring', 'Tutorship', 300, 200, 90, @LongAd);
    SELECT AdID, Title, Duration, ReviewStatus FROM Ad WHERE AdID = @LongAd;
ROLLBACK;

-- Should fail - invalid ad type
START TRANSACTION;
    CALL SubmitAd(1, 'Test', 'Rummage', 100, 100, NULL, @BadAd);
ROLLBACK;

-- Should fail - no such poster
START TRANSACTION;
    CALL SubmitAd(9999, 'Orphan Ad', 'Sale', 100, 100, NULL, @NoPosterAd);
ROLLBACK;

-- Should fail - non-positive dimensions
START TRANSACTION;
    CALL SubmitAd(1, 'Zero Width', 'Sale', 100, 0, NULL, @ZeroAd);
ROLLBACK;

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

-- PostedAdsInfo: every ad currently on a board, with its full ad record
SELECT *
FROM PostedAdsInfo
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
    SELECT * FROM PostedAdsInfo WHERE AdID = 25;
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
