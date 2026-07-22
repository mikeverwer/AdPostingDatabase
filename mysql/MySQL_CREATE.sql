-- Creates Database and Tables

/*
List of Incompatibilities with MS SQL Server

- Auto-increment for Primary Keys uses AUTO_INCREMENT syntax in MySQL, rather than
	the IDENTITY([start], [increment]) syntax used in MS SQL Server.
- Setting the current date as a default for a DATE column can be done directly with
	CURRENT_DATE in MySQL. MS SQL Server's GETDATE() returns a DATETIME instead, so
	it must be cast to a DATE type first before it can be used the same way.
- MySQL does not use the GO command that MS SQL Server relies on to separate
	statements into batches; MySQL statements are separated by semicolons alone.
	Multi-statement objects like stored procedures instead require temporarily
	changing the DELIMITER, so that semicolons inside the procedure body are not
	mistaken for the end of the CREATE statement itself.
- MySQL's TEXT datatype is the standard, fully supported way to store large amounts
	of text, with no deprecation concerns. MS SQL Server instead recommends
	VARCHAR(MAX) for this purpose; TEXT is syntactically valid there but deprecated.
- The TRIGGER defined on the Person table in the MS SQL Server version is not
	needed here, because MySQL places no equivalent restriction on this schema's
	foreign keys. Both Messages (with a Sender and a Recipient, each a foreign key
	referencing Person) and Ad (with a Poster and a Reviewer) reference the same
	table twice, and MySQL allows every one of these foreign keys to carry its own
	ON DELETE clause independently. MS SQL Server disallows this: when multiple
	foreign keys referencing the same table could each fire a cascading action, it
	permits only one of them to carry an ON DELETE clause, to avoid ambiguous or
	cyclical delete paths. In the MS SQL Server version this meant that, without
	manual intervention, only one of Sender/Recipient (for example) could cascade,
	and since nearly every sender is also eventually a recipient, this effectively
	prevented the deletion of any person from the database. MySQL's more permissive
	handling means ON DELETE CASCADE and ON DELETE SET NULL can be declared
	directly on every relevant foreign key here, so no equivalent trigger is
	required.
- MySQL automatically creates an index on every foreign key column when the
	constraint is added, so no equivalent explicit indexing section is needed
	here. MS SQL Server does not do this, which is why the MSSQL script includes
	a dedicated Foreign Key Indexes section after the Foreign Keys section.
- MySQL supports ON DELETE RESTRICT directly. MS SQL Server has no equivalent
	keyword and uses NO ACTION instead; the two behave identically here, since
	neither engine defers foreign key constraint checking.
*/

CREATE DATABASE AdPostingDB;
USE AdPostingDB;

-- =============================================================================
-- Tables
-- Primary keys, UNIQUE, and CHECK constraints are declared here.
-- Foreign keys are declared afterward, once every table exists 
-- 	(see the Foreign Keys section below).
-- =============================================================================
CREATE TABLE Person (
    PersonID 	INT AUTO_INCREMENT  NOT NULL,
    FirstName	VARCHAR(50) 	    NOT NULL,
    LastName	VARCHAR(50)		    NOT NULL,
    Phone		CHAR(10)		    NULL,   -- Assumes standard 10-digit, unformatted, North American, no extensions
    Email 		VARCHAR(50)         NOT NULL,
    -- Constraints
    PRIMARY KEY (PersonID),
    CONSTRAINT uq_person_email UNIQUE (Email)
);

CREATE TABLE CollegeMember (
    PersonID 	INT                 NOT NULL,
    CollegeID 	CHAR(9)     	    NOT NULL,
    Department 	VARCHAR(50)         NULL,	-- Staff and Support may not have an academic department (eg: custodian)
	-- Constraints 
    PRIMARY KEY (PersonID),
    CONSTRAINT uq_collegemember_collegeid UNIQUE (CollegeID)
);

CREATE TABLE Student (
    PersonID 	INT                 NOT NULL,
    Major 		VARCHAR(60)			NULL,	-- A student may not have declared a mojor yet
	-- Constraints 
    PRIMARY KEY (PersonID)
);

CREATE TABLE Employee (
    PersonID 		INT             NOT NULL,
    OfficeLocation 	VARCHAR(15)	    NULL, 	-- Some employees may not have an office, some may share an office.
    Extension 		VARCHAR(6) 		NULL,   -- internal line extension; NULL if the employee has no office (see OfficeLocation)
    PositionTitle	VARCHAR(20)		NOT NULL,
    IsReviewer 		BIT 			NOT NULL    DEFAULT (0),
	-- Constraints 
    PRIMARY KEY (PersonID),
    CONSTRAINT chk_employee_positiontitle
        CHECK (PositionTitle IN ('Faculty', 'Administration', 'Staff', 'Support', 'Specialized')),
    CONSTRAINT chk_employee_extension_requires_office
        CHECK (Extension IS NULL OR OfficeLocation IS NOT NULL)
);

CREATE TABLE Ad (
    AdID            INT AUTO_INCREMENT  NOT NULL,
	PosterID 	    INT					NOT NULL,
	ReviewerID 	    INT					NULL,
	Title 		    VARCHAR(128)		NOT NULL,
	AdType 		    VARCHAR(20)			NOT NULL,
	AdLength 	    INT 				NOT NULL,
	AdWidth 	    INT					NOT NULL,
	Duration 	    INT 				NOT NULL	DEFAULT (14),
	PostDate 	    DATE				NULL,
	AdStatus 	    VARCHAR(10) 		NOT NULL	DEFAULT ('Pending'), 
    EnteredPending  DATE                NOT NULL    DEFAULT (CURRENT_DATE),
    ReviewDate      DATE                NULL,
	-- Constraints 	
    PRIMARY KEY (AdID),
    CONSTRAINT chk_ad_type              CHECK (AdType IN ('Tutorship','Rent','Sale','Roommate','Event', 'Service', 'Other')),
    CONSTRAINT chk_ad_status            CHECK (AdStatus IN ('Pending','Approved','Rejected')),
    CONSTRAINT chk_ad_poster_reviewer   CHECK (PosterID <> ReviewerID),
    CONSTRAINT chk_ad_duration_positive CHECK (Duration > 0),
    CONSTRAINT chk_ad_adlength_positive CHECK (AdLength > 0),
    CONSTRAINT chk_ad_adwidth_positive  CHECK (AdWidth > 0),
	CONSTRAINT chk_ad_postdate_requires_approval 
		CHECK (PostDate IS NULL OR AdStatus = 'Approved'),
	CONSTRAINT chk_ad_reviewdate_requires_nonpending
        CHECK (ReviewDate IS NULL OR AdStatus <> 'Pending'),
    CONSTRAINT chk_ad_nonpending_requires_reviewdate
        CHECK (AdStatus = 'Pending' OR ReviewDate IS NOT NULL)  
);

CREATE TABLE Board (
    Building 	    VARCHAR(4)	NOT NULL, 
    BldgFloor 	    INT			NOT NULL,
    Slot 		    CHAR(1)     NOT NULL,
	BoardLength     INT	    	NOT NULL,
    BoardWidth      INT     	NOT NULL,
	-- Constraints 
    PRIMARY KEY (Building, BldgFloor, Slot),
    CONSTRAINT chk_board_length_positive CHECK (BoardLength > 0),
    CONSTRAINT chk_board_width_positive  CHECK (BoardWidth > 0)
);

CREATE TABLE Ad_Posted_Board (
    AdID 		INT 			NOT NULL,
    Building	VARCHAR(4)		NOT NULL,
    BldgFloor 	INT 			NOT NULL,
    Slot		CHAR(1)			NOT NULL,  -- Letter distinguishing multiple boards on the same floor
	-- Constraints 
    PRIMARY KEY (AdID, Building, BldgFloor, Slot)
);

CREATE TABLE Messages (
    SenderID 	INT				NOT NULL,
    AdID 		INT				NOT NULL,
    TimeLogged 	DATETIME 		NOT NULL	DEFAULT (CURRENT_TIMESTAMP),
    RecipientID INT				NOT NULL,
    Content 	TEXT			NOT NULL	DEFAULT (''),
	-- Constraints 
    PRIMARY KEY (SenderID, AdID, TimeLogged)
);

-- ============================================================
-- Foreign Keys
-- Declared here, after every table already exists, so table
-- creation order does not need to satisfy FK dependencies, and
-- every relationship in the schema can be reviewed as one list.
-- ============================================================
ALTER TABLE CollegeMember ADD CONSTRAINT fk_collegemember_person   FOREIGN KEY (PersonID) 
    REFERENCES Person(PersonID)         ON DELETE CASCADE;
ALTER TABLE Student       ADD CONSTRAINT fk_student_collegemember  FOREIGN KEY (PersonID) 
    REFERENCES CollegeMember(PersonID)  ON DELETE CASCADE;
ALTER TABLE Employee      ADD CONSTRAINT fk_employee_collegemember FOREIGN KEY (PersonID) 
    REFERENCES CollegeMember(PersonID)  ON DELETE CASCADE;

ALTER TABLE Ad ADD CONSTRAINT fk_ad_poster   FOREIGN KEY (PosterID)   REFERENCES Person(PersonID)   ON DELETE CASCADE;
ALTER TABLE Ad ADD CONSTRAINT fk_ad_reviewer FOREIGN KEY (ReviewerID) REFERENCES Employee(PersonID) ON DELETE SET NULL;

ALTER TABLE Ad_Posted_Board ADD CONSTRAINT fk_adpostedboard_ad    FOREIGN KEY (AdID) REFERENCES Ad(AdID) ON DELETE CASCADE;
ALTER TABLE Ad_Posted_Board ADD CONSTRAINT fk_adpostedboard_board FOREIGN KEY (Building, BldgFloor, Slot)
	REFERENCES Board(Building, BldgFloor, Slot) ON DELETE CASCADE;

ALTER TABLE Messages ADD CONSTRAINT fk_messages_sender    FOREIGN KEY (SenderID)    REFERENCES Person(PersonID) ON DELETE CASCADE;
ALTER TABLE Messages ADD CONSTRAINT fk_messages_recipient FOREIGN KEY (RecipientID) REFERENCES Person(PersonID) ON DELETE CASCADE;
ALTER TABLE Messages ADD CONSTRAINT fk_messages_ad        FOREIGN KEY (AdID)        REFERENCES Ad(AdID) ON DELETE RESTRICT;
