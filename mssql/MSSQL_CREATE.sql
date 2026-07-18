-- Creates Database and Tables

/*
List of Incompatibilities with MySQL

- Auto-increment for Primary Keys uses IDENTITY([start], [increment]) syntax in MS SQL Server, rather
	than AUTO_INCREMENT in MySQL.
- Setting the current date as a default for DATE data type requires calling the GET_DATE() method
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

*/

CREATE DATABASE AdPostingDB;
GO

USE AdPostingDB;
GO

CREATE TABLE Person (
	PersonID INT IDENTITY(1, 1),
	FirstName VARCHAR(20)	NOT NULL,
	LastName VARCHAR(20)	NOT NULL,
	Phone CHAR(10),
	Email VARCHAR(50)		NOT NULL,
	-- Constraints 
	PRIMARY KEY (PersonID),

	CONSTRAINT person_email_unique UNIQUE(Email)
);
GO

CREATE TABLE CollegeMember (
	PersonID INT,
	CollegeID CHAR(9)		NOT NULL,
	Department VARCHAR(20),
	--Constraints
	PRIMARY KEY (PersonID),
	FOREIGN KEY (PersonID) REFERENCES Person(PersonID),

	CONSTRAINT collegeID_unique_cnstr UNIQUE(CollegeID) 
);
GO

CREATE TABLE Student (
	PersonID INT,
	Major VARCHAR(30),
	-- Constraints
	PRIMARY KEY (PersonID),
	FOREIGN KEY (PersonID) REFERENCES CollegeMember(PersonID)
);
GO

CREATE TABLE Employee (
	PersonID INT,
	OfficeLocation VARCHAR(10), -- some people may not have an office, some may share an office. so no constraints
	StartDate DATE NOT NULL DEFAULT (CAST(GETDATE() AS DATE)), -- Only works on MS SQL Server, MySQL `CURRENT_DATE` for getting current date
	PositionTitle VARCHAR(20),
	IsReviewer BIT NOT NULL DEFAULT (0),
	-- Constraints
	PRIMARY KEY (PersonID),
	FOREIGN KEY (PersonID) REFERENCES CollegeMember(PersonID),

	CONSTRAINT chk_pos_title 
		CHECK(PositionTitle IN ('Faculty', 'Administration', 'Staff', 'Support', 'Specialized', NULL)) 
);
GO

CREATE TABLE Ad (
	AdID INT IDENTITY(1,1),
	PosterID INT,
	ReviewerID INT,
	Title VARCHAR(30)					NOT NULL,
	AdType VARCHAR(15)					NOT NULL,
	AdLength INT CHECK (AdLength > 0)	NOT NULL,
	AdWidth INT	CHECK (AdWidth > 0)		NOT NULL,
	Duration INT CHECK (Duration > 0) DEFAULT (14),
	PostDate DATE,
	AdStatus VARCHAR(10) DEFAULT ('Pending'),
	-- Constraints
	PRIMARY KEY (AdID),
	FOREIGN KEY (PosterID) REFERENCES Person(PersonID),
	FOREIGN KEY (ReviewerID) REFERENCES Person(PersonID), 

	CONSTRAINT chk_poster_reviewer CHECK (PosterID <> ReviewerID),

    CONSTRAINT chk_ad_type
        CHECK (AdType IN ('Tutorship','Rent','Sale','Roommate','Event')),

	CONSTRAINT chk_ad_status
        CHECK (AdStatus IN ('Pending','Approved','Rejected'))
);
GO

CREATE TABLE Board (
	Building CHAR(3),
	BldgFloor INT,
	Place CHAR(1),
	BoardLength INT	CHECK (BoardLength > 0)	NOT NULL,
	BoardWidth INT CHECK (BoardWidth > 0)	NOT NULL,
	-- Constraints
	PRIMARY KEY (Building, BldgFloor, Place)
);
GO

CREATE TABLE Ad_Posted_Board (
	AdID INT,
	Building CHAR(3),
	BldgFloor INT,
	Place CHAR(1),
	-- Constraints
	PRIMARY KEY (AdID, Building, BldgFloor, Place),
	FOREIGN KEY (AdID) REFERENCES Ad(AdID)				ON DELETE CASCADE,
	FOREIGN KEY (Building, BldgFloor, Place) 
		REFERENCES Board(Building, BldgFloor, Place)	ON DELETE CASCADE
);
GO

CREATE TABLE Messages (
    SenderID INT,
    AdID INT,
    TimeLogged DATETIME DEFAULT (CURRENT_TIMESTAMP),
    RecipientID INT,
    Content VARCHAR(MAX), -- Will not work on MySQL. TEXT datatype is deprecated in MS SQL Server
    PRIMARY KEY (SenderID, AdID, TimeLogged),
    FOREIGN KEY (SenderID) REFERENCES Person(PersonID),
    FOREIGN KEY (AdID) REFERENCES Ad(AdID) ON DELETE CASCADE,
    FOREIGN KEY (RecipientID) REFERENCES Person(PersonID)
);
GO

-- This trigger is required since SQL Server does not allow multiple FK's to reference the same table,
-- which needs to be done for the Messages table and the Ad table.
-- We therefore need to explicitly define how to delete a person throughout all tables.
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
