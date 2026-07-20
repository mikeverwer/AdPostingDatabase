-- Creates Database and Tables

/*
List of Incompatibilities with MySQL

- Auto-increment for Primary Keys uses IDENTITY([start], [increment]) syntax in MS SQL Server, rather
	than AUTO_INCREMENT in MySQL.
- Setting the current date as a default for DATE data type requires calling the GETDATE() method
	and then casting the result as a DATE type since it returns a date with timestamp.
- MySQL does not support the GO command, which is used to separate statements into batches. 
	They are not strictly required, but useful to be able to run the whole script without getting
	dependency errors.
- VARCHAR(MAX) is not compatible with MySQL as a datatype for storing large amounts of text.
	The TEXT datatype is syntactically valid in MS SQL Server,  but is deprecated and not recommended.
- The TRIGGER defined for the Person table is not syntactically valid in MySQL, but the trigger is also
	not required. MS SQL Server does not allow multiple foreign keys, which reference the same table, 
	to each have ON DELETE clauses. 
	This is problematic in our database since in our Messages table, for example, each row has a Sender 
	and Receiver; both are foreign keys referencing the Person table. MS SQL Server does not allow them 
	to have ON DELETE clauses, meaning that only Senders (for example) can have an ON DELETE clause,
	and then Receivers would not be able to be deleted from the DB. However, since nearly all senders are
	also subsequent receivers of messages, this strictness effectively prevents the deletion of any 
	person from the DB. We therefore need to create the trigger to manually script the delete behaviour
	for the Person table.
	MySQL does not have this strictness, and so the trigger is not required.
- MS SQL Server does not automatically create an index on every foreign key column when the constraint is 
	added, so this script includes a dedicated Foreign Key Indexes section after the Foreign Keys section.
	No equivalent explicit indexing section is needed in the MySQL script since foreign key indexes are 
	created automatically.
- MS SQL Server has no RESTRICT keyword for ON DELETE/ON UPDATE referential actions. NO ACTION is used 
	instead, which behaves identically here, since neither engine defers foreign key constraint checking 
	within a statement.
*/

CREATE DATABASE AdPostingDB;
GO

USE AdPostingDB;
GO

-- =============================================================================
-- Tables
-- Primary keys, UNIQUE, and CHECK constraints are declared here.
-- Foreign keys are declared afterward, once every table exists 
-- 	(see the Foreign Keys section below).
-- =============================================================================
CREATE TABLE Person (
	PersonID 	INT IDENTITY(1, 1)	NOT NULL,	
	FirstName 	VARCHAR(50)			NOT NULL,
	LastName 	VARCHAR(50)			NOT NULL,
	Phone 		CHAR(10)			NULL,	-- Assumes standard 10-digit, unformatted, North American, no extensions
	Email 		VARCHAR(50)			NOT NULL,
	-- Constraints 
	PRIMARY KEY (PersonID),
	CONSTRAINT uq_person_email 	UNIQUE(Email)
);
GO

CREATE TABLE CollegeMember (
	PersonID 	INT					NOT NULL,
	CollegeID 	CHAR(9)				NOT NULL,
	Department 	VARCHAR(50)			NULL,	-- Staff and Support may not have an academic department (eg: custodian)
	-- Constraints
	PRIMARY KEY (PersonID),
	CONSTRAINT uq_collegemember_collegeid UNIQUE(CollegeID) 
);
GO

CREATE TABLE Student (
	PersonID 	INT					NOT NULL,
	Major 		VARCHAR(60)			NULL,	-- A student may not have declared a mojor yet
	-- Constraints
	PRIMARY KEY (PersonID)
);
GO

CREATE TABLE Employee (
	PersonID 		INT				NOT NULL,
	OfficeLocation 	VARCHAR(15) 	NULL,   -- Some employees may not have an office, some may share an office.
	Extension 		VARCHAR(6) 		NULL,   -- internal line extension; NULL if the employee has no office (see OfficeLocation)
	StartDate 		DATE 			NOT NULL, 
	PositionTitle 	VARCHAR(20)		NOT NULL,
	IsReviewer 		BIT 			NOT NULL DEFAULT (0),
	-- Constraints
	PRIMARY KEY (PersonID),
	CONSTRAINT chk_employee_positiontitle 
		CHECK(PositionTitle IN ('Faculty', 'Administration', 'Staff', 'Support', 'Specialized')),
    CONSTRAINT chk_employee_extension_requires_office
        CHECK (Extension IS NULL OR OfficeLocation IS NOT NULL)
);
GO

CREATE TABLE Ad (
	AdID 		INT IDENTITY(1,1)	NOT NULL, 
	PosterID 	INT					NOT NULL,
	ReviewerID 	INT					NULL,
	Title 		VARCHAR(128)		NOT NULL,
	AdType 		VARCHAR(20)			NOT NULL,
	AdLength 	INT 				NOT NULL,
	AdWidth 	INT					NOT NULL,
	Duration 	INT 				NOT NULL	DEFAULT (14),
	PostDate 	DATE				NULL,
	AdStatus 	VARCHAR(10) 		NOT NULL	DEFAULT ('Pending'),
	-- Constraints
	PRIMARY KEY (AdID),
	CONSTRAINT chk_ad_type              CHECK (AdType IN ('Tutorship','Rent','Sale','Roommate','Event')),
	CONSTRAINT chk_ad_status            CHECK (AdStatus IN ('Pending','Approved','Rejected')),
	CONSTRAINT chk_ad_poster_reviewer   CHECK (PosterID <> ReviewerID),
    CONSTRAINT chk_ad_duration_positive CHECK (Duration > 0),
    CONSTRAINT chk_ad_adlength_positive CHECK (AdLength > 0),
    CONSTRAINT chk_ad_adwidth_positive  CHECK (AdWidth > 0),
	CONSTRAINT chk_ad_postdate_requires_approval 
		CHECK (PostDate IS NULL OR AdStatus = 'Approved'),
	CONSTRAINT chk_ad_approval_requires_postdate
		CHECK (AdStatus <> 'Approved' OR PostDate IS NOT NULL)
);
GO

CREATE TABLE Board (
	Building 	VARCHAR(4)	NOT NULL,
	BldgFloor 	INT			NOT NULL,
	Slot 		CHAR(1)		NOT NULL,
	BoardLength INT			NOT NULL,
	BoardWidth 	INT			NOT NULL,
	-- Constraints
	PRIMARY KEY (Building, BldgFloor, Slot),
	CONSTRAINT chk_board_length_positive CHECK (BoardLength > 0),
	CONSTRAINT chk_board_width_positive  CHECK (BoardWidth > 0)
);
GO

CREATE TABLE Ad_Posted_Board (
	AdID 		INT			NOT NULL,
	Building 	VARCHAR(4)	NOT NULL,
	BldgFloor 	INT			NOT NULL,
	Slot 		CHAR(1)		NOT NULL,  -- Letter distinguishing multiple boards on the same floor
	-- Constraints
	PRIMARY KEY (AdID, Building, BldgFloor, Slot)
);
GO

CREATE TABLE Messages (
    SenderID 	INT				NOT NULL,
    AdID 		INT				NOT NULL,
    TimeLogged 	DATETIME 		NOT NULL	DEFAULT (CURRENT_TIMESTAMP),
    RecipientID INT				NOT NULL,
    Content 	VARCHAR(MAX)	NOT NULL	DEFAULT (''),
	-- Constraints
    PRIMARY KEY (SenderID, AdID, TimeLogged)
);
GO

-- =============================================================================
-- Foreign Keys
-- Declared here, after every table already exists, so table creation order does 
-- not need to satisfy FK dependencies, and every relationship in the schema can 
-- be reviewed as one list.
-- =============================================================================
ALTER TABLE CollegeMember ADD CONSTRAINT fk_collegemember_person   FOREIGN KEY (PersonID) REFERENCES Person(PersonID);
ALTER TABLE Student       ADD CONSTRAINT fk_student_collegemember  FOREIGN KEY (PersonID) REFERENCES CollegeMember(PersonID);
ALTER TABLE Employee      ADD CONSTRAINT fk_employee_collegemember FOREIGN KEY (PersonID) REFERENCES CollegeMember(PersonID);

ALTER TABLE Ad ADD CONSTRAINT fk_ad_poster   FOREIGN KEY (PosterID)   REFERENCES Person(PersonID);
ALTER TABLE Ad ADD CONSTRAINT fk_ad_reviewer FOREIGN KEY (ReviewerID) REFERENCES Employee(PersonID);

ALTER TABLE Ad_Posted_Board ADD CONSTRAINT fk_adpostedboard_ad    FOREIGN KEY (AdID) REFERENCES Ad(AdID) ON DELETE CASCADE;
ALTER TABLE Ad_Posted_Board ADD CONSTRAINT fk_adpostedboard_board FOREIGN KEY (Building, BldgFloor, Slot)
	REFERENCES Board(Building, BldgFloor, Slot) ON DELETE CASCADE;

ALTER TABLE Messages ADD CONSTRAINT fk_messages_sender    FOREIGN KEY (SenderID)    REFERENCES Person(PersonID);
ALTER TABLE Messages ADD CONSTRAINT fk_messages_recipient FOREIGN KEY (RecipientID) REFERENCES Person(PersonID);
ALTER TABLE Messages ADD CONSTRAINT fk_messages_ad        FOREIGN KEY (AdID)        REFERENCES Ad(AdID) ON DELETE NO ACTION;
-- NOTE: Ad deletion is restricted until messages are deleted to preserve active conversations and user chat history
GO

-- =============================================================================
-- Foreign Key Indexes
-- Declared here, after tables creation and foreign key constraints are defined.
-- MS SQL Server does not automatically create indexes for foreign key columns.
-- These indexes ae valuable for parent-side integrity checks.
-- =============================================================================
CREATE INDEX ix_ad_posterid          ON Ad (PosterID);
CREATE INDEX ix_ad_reviewerid        ON Ad (ReviewerID);
CREATE INDEX ix_messages_adid        ON Messages (AdID);
CREATE INDEX ix_messages_recipientid ON Messages (RecipientID);
CREATE INDEX ix_adpostedboard_board  ON Ad_Posted_Board (Building, BldgFloor, Slot);
GO

-- =============================================================================
-- On Delete Cascading Trigger
-- This trigger is required since SQL Server does not allow multiple FK's to 
-- reference the same table, which needs to be done for the Messages table and 
-- the Ad table. We therefore need to explicitly define how to delete a person 
-- throughout all tables.
-- =============================================================================
CREATE TRIGGER trg_DeletePersonCascade
ON Person
INSTEAD OF DELETE
AS
BEGIN
    DELETE Ad_Posted_Board
    FROM Ad_Posted_Board apb
    JOIN Ad a ON apb.AdID = a.AdID
    WHERE a.PosterID IN (SELECT PersonID FROM deleted);

    DELETE FROM Ad
    WHERE PosterID IN (SELECT PersonID FROM deleted);

    UPDATE Ad
    SET ReviewerID = NULL
    WHERE ReviewerID IN (SELECT PersonID FROM deleted)
      AND PosterID NOT IN (SELECT PersonID FROM deleted);

    DELETE FROM Messages
    WHERE SenderID IN (SELECT PersonID FROM deleted)
       OR RecipientID IN (SELECT PersonID FROM deleted);

    DELETE FROM Student
    WHERE PersonID IN (SELECT PersonID FROM deleted);

    DELETE FROM Employee
    WHERE PersonID IN (SELECT PersonID FROM deleted);

    DELETE FROM CollegeMember
    WHERE PersonID IN (SELECT PersonID FROM deleted);

    DELETE FROM Person
    WHERE PersonID IN (SELECT PersonID FROM deleted);
END
