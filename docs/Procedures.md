## Stored Procedures

### Person & Roles
Registering people and managing the roles they hold. Registration is layered: AddNonMember inserts a bare Person, AddCollegeMember wraps it, and AddStudent / AddEmployee wrap that in turn. The Grant/Revoke pairs move an existing person between roles without re-registering them. Also holds the two contact-lookup procedures.

AddNonMember
: Add a person with no college affiliation. Inserts into Person only. Use for members of the public who post ads. This procedure must be called inside a transaction the CALLER controls.
: Signature (engine-agnostic):  
  ```
  AddNonMember(  
    IN  FirstName : string(50)   [required, not null/empty]  
    IN  LastName  : string(50)   [required, not null/empty]  
    IN  Phone     : string(10)   = null [optional]  
    IN  Email     : string(50)   [required, not null/empty; unique]  
    OUT PersonID  : integer      [assigned to the new Person row id]  
  )
  ```

AddCollegeMember
: Add a college member who is neither a student nor an employee. Intended for people who retain a college ID and board privileges without being enrolled or employed; alumni are the motivating case. This procedure must be called inside a transaction the CALLER controls.
: Signature (engine-agnostic):
  ```
  AddCollegeMember(
    IN  FirstName  : string(50)   [required, not null/empty]
    IN  LastName   : string(50)   [required, not null/empty]
    IN  Phone      : string(10)   = null [optional]
    IN  Email      : string(50)   [required, not null/empty; unique]
    IN  CollegeID  : string(9)    [required, not null/empty; unique]
    IN  Department : string(50)   = null [optional]
    OUT PersonID   : integer      [assigned to the new Person row id]
  )
  ```

AddStudent
: Add a student. Inserts Person, CollegeMember, and Student. Department (the student's academic department) and Major are both supplied by the caller; they are related but distinct, and Major may be NULL for a student who has not declared one. This procedure must be called inside a transaction the CALLER controls.
: Signature (engine-agnostic):
  ```
  AddStudent(
    IN  FirstName  : string(50)   [required, not null/empty]
    IN  LastName   : string(50)   [required, not null/empty]
    IN  Phone      : string(10)   = null [optional]
    IN  Email      : string(50)   [required, not null/empty; unique]
    IN  CollegeID  : string(9)    [required, not null/empty; unique]
    IN  Department : string(50)   = null [optional]
    IN  Major      : string(60)   = null [optional]
    OUT PersonID   : integer      [assigned to the new Person row id]
  )
  ```

AddEmployee
: Add an employee. Inserts Person, CollegeMember, and Employee. Extension requires OfficeLocation. This procedure must be called inside a transaction the CALLER controls.
: Signature (engine-agnostic):
  ```
  AddEmployee(
    IN  FirstName      : string(50)   [required, not null/empty]
    IN  LastName       : string(50)   [required, not null/empty]
    IN  Phone          : string(10)   = null [optional]
    IN  Email          : string(50)   [required, not null/empty; unique]
    IN  CollegeID      : string(9)    [required, not null/empty; unique]
    IN  Department     : string(50)   = null [optional]
    IN  OfficeLocation : string(15)   = null [optional]
    IN  Extension      : string(6)    = null [optional; requires OfficeLocation]
    IN  PositionTitle  : string(20)   [required; must be one of: Faculty, Administration, Staff, Support, Specialized]
    IN  IsReviewer     : boolean      = false [optional]
    OUT PersonID       : integer      [assigned to the new Person row id]
  )
  ```

GrantCollegeMemberRole
: Grant a person College Member status (Person -> CollegeMember). Requires the person already exist in Person and not already be a College Member. Use for someone gaining a College ID without yet being a Student or Employee.
: Signature (engine-agnostic):
  ```
  GrantCollegeMemberRole(
    IN  PersonID   : integer      [required]
    IN  CollegeID  : string(9)    [required, not null/empty; unique]
    IN  Department : string(50)   = null [optional]
  )
  ```

RevokeCollegeMemberRole
: Revoke College Member status (deletes the CollegeMember row). Refuses if the person still holds Student or Employee status, since both are structurally dependent on CollegeMember. Revoke those first.
: Signature (engine-agnostic):
  ```
  RevokeCollegeMemberRole(
    IN  PersonID : integer   [required]
  )
  ```

GrantStudentRole
: Grant a person Student status (CollegeMember -> Student). Requires the person already hold College Member status. Does not check Employee status either way, so this is also how a person who already holds Employee status becomes a dual Student/Employee.
: Signature (engine-agnostic):
  ```
  GrantStudentRole(
    IN  PersonID : integer      [required]
    IN  Major    : string(60)   = null [optional]
  )
  ```

RevokeStudentRole
: Revoke Student status (deletes the Student row only; College Member and, if held, Employee status are untouched).
: Signature (engine-agnostic):
  ```
  RevokeStudentRole(
    IN  PersonID : integer   [required]
  )
  ```

GrantEmployeeRole
: Grant a person Employee status (CollegeMember -> Employee). Requires the person already hold College Member status. Does not check Student status either way, so this is also how an existing Student becomes a dual Student/Employee. Not to be confused with SetReviewerPermission, which only flips the IsReviewer flag on an Employee row that already exists.
: Signature (engine-agnostic):
  ```
  GrantEmployeeRole(
    IN  PersonID       : integer      [required]
    IN  OfficeLocation : string(15)   = null [optional]
    IN  Extension      : string(6)    = null [optional; requires OfficeLocation]
    IN  PositionTitle  : string(20)   [required; must be one of: Faculty, Administration, Staff, Support, Specialized]
    IN  IsReviewer     : boolean      = false [optional]
  )
  ```

RevokeEmployeeRole
: Revoke Employee status. Any ad this person has reviewed has its ReviewerID explicitly cleared first, then the Employee row is deleted. College Member and, if held, Student status are untouched. Not to be confused with SetReviewerPermission, which only flips the IsReviewer flag; this removes the Employee row entirely.
: Signature (engine-agnostic):
  ```
  RevokeEmployeeRole(
    IN  PersonID : integer   [required]
  )
  ```

UpdateUserCoreInfo
: Edit a person's core contact info (FirstName, LastName, Phone, Email). Does not touch role-specific fields (Department, Major, OfficeLocation, Extension, PositionTitle) those belong to CollegeMember/Student/Employee and have no editor here.  
: Signature (engine-agnostic):
  ```
  UpdateUserCoreInfo(
    IN  PersonID    integer       [required]
    IN  FirstName   string(50)    [required]
    IN  LastName    string(50)    [required]
    IN  Phone       string(10)    = null [optional]
    IN  Email       string(50)    [required]
  )
  ```

SetReviewerPermission
: Set IsReviewer role for an employee. Only flips the flag on an existing Employee row; see GrantEmployeeRole to create that row in the first place.
: Signature (engine-agnostic):
  ```
  SetReviewerPermission(
    IN  EmpID : integer   [required; must be an employee]
    IN  IsRev : boolean   [required]
  )
  ```

GetPosterInfo
: Show Contact information of the poster of a given ad.
: Signature (engine-agnostic):
  ```
  GetPosterInfo(
    IN  AdID : integer   [required]
  )
  ```

GetReviewerInfo
: Show Contact information of the reviewer of a given ad.
: Signature (engine-agnostic):
  ```
  GetReviewerInfo(
    IN  AdID : integer   [required]
  )
  ```

### Ad Lifecycle & Review
Moving an ad through its states: submission, the review decision, and poster-initiated withdrawal. Also holds the two rejection-history reports, which read the outcome of that review process.

SubmitAd
: Submit a new ad for review. Inserts a new Ad row with ReviewStatus = 'Pending', ReviewerID = NULL, PostDate = NULL, EnteredPending = today, and ReviewDate = NULL. This procedure must be called inside a transaction the CALLER controls.
: Signature (engine-agnostic):
  ```
  SubmitAd(
    IN  PosterID      : integer      [required]
    IN  Title         : string(128)  [required, not null/empty]
    IN  AdType        : string(20)   [required; must be one of: Tutorship, Rent, Sale, Roommate, Event, Service, Other]
    IN  AdLength      : integer      [required; > 0]
    IN  AdWidth       : integer      [required; > 0]
    IN  Duration      : integer      = 14 [optional; > 0]
    IN  ImageFileName : string(255)  [required, not null/empty]
    OUT AdID          : integer      [assigned to the new Ad row id]
  )
  ```

ReviewAd
: Approve or Reject an ad. This procedure must be called inside a transaction the CALLER controls.
: Signature (engine-agnostic):
  ```
  ReviewAd(
    IN  AdID       : integer      [required]
    IN  Status     : string(10)   [required; must be one of: Approved, Rejected, Pending]
    IN  ReviewerID : integer      [required; must be an employee with IsReviewer = 1]
    IN  ReviewDate : date         = null [optional; defaults to today]
  )
  ```

WithdrawAd
: Withdraw an ad. Poster-initiated; sets IsWithdrawn/WithdrawnDate and purges every message on the ad, but does NOT touch ReviewStatus and does NOT remove the ad from any board it is currently posted to. Withdrawal is one-way. This procedure must be called inside a transaction the CALLER controls.
: Signature (engine-agnostic):
  ```
  WithdrawAd(
    IN  AdID                : integer   [required]
    IN  PosterID            : integer   [required; must be the ad's poster]
    OUT DeletedMessageCount : integer   [number of messages deleted]
  )
  ```

DeleteAd
: Permanently delete an ad. Admin-initiated, and distinct from WithdrawAd. Refuses while the ad is still posted to any board. This procedure must be called inside a transaction the CALLER controls.
: Signature (engine-agnostic):
  ```
  DeleteAd(
    IN  AdID                : integer      [required]
    IN  ReviewerID          : integer      [required; must be an employee with IsReviewer = 1]
    OUT DeletedMessageCount : integer      [number of messages deleted]
    OUT ImageFileName       : string(255)  [image file name for cleanup]
  )
  ```

GetNoncompliantPosters
: Procedure to find people who have posted multiple rejected ads.
: Signature (engine-agnostic):
  ```
  GetNoncompliantPosters(
    IN  MinRejections : integer = 2 [optional]
  )
  ```

GetPosterRejectionHistory
: Procedure to find the rejection history of a user (poster).
: Signature (engine-agnostic):
  ```
  GetPosterRejectionHistory(
    IN  PosterID : integer   [required]
  )
  ```

### Board & Posting
Creating and retiring the physical boards, placing approved ads onto them, removing them again, and the two read-only helpers for checking fit and looking up where an ad currently hangs.

NewBoard
: Add a new board. The only real constraint is that the location (Building, BldgFloor, Slot) not already be in use.
: Signature (engine-agnostic):
  ```
  NewBoard(
    IN  Building    : string(4)   [required]
    IN  BldgFloor   : integer     [required]
    IN  Slot        : string(1)   [required]
    IN  BoardLength : integer     [required; > 0]
    IN  BoardWidth  : integer     [required; > 0]
  )
  ```

RetireBoard
: Retire (permanently remove) a board. Refuses if any ad is currently posted there. This procedure must be called inside a transaction the CALLER controls.
: Signature (engine-agnostic):
  ```
  RetireBoard(
    IN  Building  : string(4)   [required]
    IN  BldgFloor : integer     [required]
    IN  Slot      : string(1)   [required]
  )
  ```

PostAd
: Create a procedure to post an ad to a given board. Assumes that the user has confirmed that the ad will fit on the board separately. This procedure must be called inside a transaction the CALLER controls.
: Signature (engine-agnostic):
  ```
  PostAd(
    IN  AdID  : integer      [required; must be approved and not expired/withdrawn]
    IN  Bldg  : string(4)    [required]
    IN  Floor : integer      [required]
    IN  Slot  : string(1)    [required]
  )
  ```

UnpostAd
: Remove an unapproved ad from the Ad_Posted_Board table. If a specific board is given, it will only remove the ad from that board, otherwise it will remove it from all boards it is currently on.
: Signature (engine-agnostic):
  ```
  UnpostAd(
    IN  AdID      : integer      [required]
    IN  Building  : string(4)    = null [optional; required with BldgFloor and Slot]
    IN  BldgFloor : integer      = null [optional; required with Building and Slot]
    IN  Slot      : string(1)    = null [optional; required with Building and BldgFloor]
  )
  ```

CheckAdFit
: Procedure to evaluate if a given ad will fit on each board.
: Signature (engine-agnostic):
  ```
  CheckAdFit(
    IN  AdID : integer   [required]
  )
  ```

GetAdPostings
: Procedure to find all the information and locations of a posted ad.
: Signature (engine-agnostic):
  ```
  GetAdPostings(
    IN  AdID : integer   [required]
  )
  ```

### Messaging
Sending, retrieving, and deleting the messages exchanged about an ad. DeleteAdMessages is also the mechanism WithdrawAd uses to clear fk_messages_ad before flagging an ad as withdrawn.

SendMessage
: Send a message about an ad. The ad's PosterID must be either the sender or the recipient. Messaging is only allowed on an Approved ad, UNLESS the sender or recipient is a reviewer (Employee.IsReviewer = 1). Self-messaging is intentionally allowed. This procedure must be called inside a transaction the CALLER controls.
: Signature (engine-agnostic):
  ```
  SendMessage(
    IN  SenderID    : integer      [required]
    IN  AdID        : integer      [required]
    IN  RecipientID : integer      [required]
    IN  Content     : string(max)  [required, not null/empty]
  )
  ```

GetAllADMessages
: Retrieve all messages about a given ad, showing sender and recipient names, message content, and timestamp.
: Signature (engine-agnostic):
  ```
  GetAllADMessages(
    IN  AdID : integer   [required]
  )
  ```

DeleteMessage
: Delete a single message, identified by its full primary key (SenderID, AdID, TimeLogged). This procedure must be called inside a transaction the CALLER controls.
: Signature (engine-agnostic):
  ```
  DeleteMessage(
    IN  SenderID   : integer   [required]
    IN  AdID       : integer   [required]
    IN  TimeLogged : datetime  [required]
  )
  ```

DeleteAdMessages
: Delete every message attached to a given ad. This is the mechanism WithdrawAd will use to clear fk_messages_ad before deleting the Ad row itself. This procedure must be called inside a transaction the CALLER controls.
: Signature (engine-agnostic):
  ```
  DeleteAdMessages(
    IN  AdID         : integer   [required]
    OUT DeletedCount : integer   [number of messages deleted]
  )
  ```