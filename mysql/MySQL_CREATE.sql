-- CREATING DATABASE AND TABLES SCRIPT -
CREATE DATABASE AdPostingDB;
USE AdPostingDB;

CREATE TABLE Person (
    PersonID 	INT AUTO_INCREMENT 		PRIMARY KEY,
    FirstName	VARCHAR(20) 			NOT NULL,
    LastName	VARCHAR(20)				NOT NULL,
    Phone		VARCHAR(20)				NOT NULL,
    Email 		VARCHAR(40) UNIQUE		NOT NULL
);

CREATE TABLE CollegeMember (
    PersonID 	INT 					PRIMARY KEY,
    CollegeID 	VARCHAR(15) UNIQUE 		NOT NULL,
    Department 	VARCHAR(60)				NOT NULL,
    FOREIGN KEY (PersonID) REFERENCES Person(PersonID) ON DELETE CASCADE
);

CREATE TABLE Student (
    PersonID 	INT 					PRIMARY KEY,
    Major 		VARCHAR(60)				NOT NULL,
    FOREIGN KEY (PersonID) REFERENCES CollegeMember(PersonID) ON DELETE CASCADE
);

CREATE TABLE Employee (
    PersonID 		INT					PRIMARY KEY,
    OfficeLocation 	VARCHAR(100)		NULL,
    StartDate 		DATE				NOT NULL,
    PositionTitle	VARCHAR(20)			NULL,
    IsReviewer 		BIT 				DEFAULT (0),
    
    
    FOREIGN KEY (PersonID) REFERENCES CollegeMember(PersonID) ON DELETE CASCADE
);

CREATE TABLE Board (
    Building 	CHAR(3)					    NOT NULL, 
    BldgFloor 	INT						    NOT NULL,
    Place 		CHAR(1),
	BoardLength INT	CHECK (BoardLength > 0)	NOT NULL,
BoardWidth      INT CHECK (BoardWidth > 0)	NOT NULL,

    PRIMARY KEY (Building, BldgFloor, Place)
);

CREATE TABLE Ad (
    AdID       INT AUTO_INCREMENT 	        PRIMARY KEY,
	Title      VARCHAR(100) 		        NOT NULL,
	AdType     VARCHAR(20)  		        NOT NULL,
	AdLength   INT  CHECK (AdLength > 0)	NOT NULL,
    AdWidth    INT	CHECK (AdWidth > 0)		NOT NULL,
	Duration   INT,
	PostDate   DATE,
	AdStatus   VARCHAR(10)  		        DEFAULT ('Pending'),
	PosterID   INT 					        NOT NULL,      
	ReviewerID INT 					        NULL,  				
    
    CONSTRAINT chk_ad_type
        CHECK (AdType IN ('Tutorship','Rent','Sale','Roommate','Event')),

    CONSTRAINT chk_ad_status
        CHECK (AdStatus IN ('Pending','Approved','Rejected')),
        
	CONSTRAINT chk_poster_vs_reviewer
	    CHECK (ReviewerID <> PosterID),
        
	CONSTRAINT chk_duration_positive
		CHECK (Duration > 0),
        
  FOREIGN KEY (PosterID)   REFERENCES Person(PersonID)    ON DELETE CASCADE,
  FOREIGN KEY (ReviewerID) REFERENCES Employee(PersonID)  ON DELETE SET NULL
);


-- -------------------------------------------------------------------------------
CREATE TABLE Ad_Posted_Board (
    AdID 		INT 					NOT NULL,
    Building	CHAR(3)					NOT NULL,
    BldgFloor 	INT 					NOT NULL,
    Place		CHAR(1)					NOT NULL,
    PRIMARY KEY (AdID, Building, BldgFloor, Place),
    FOREIGN KEY (AdID) REFERENCES Ad(AdID) ON DELETE CASCADE,
    FOREIGN KEY (Building, BldgFloor, Place) REFERENCES Board(Building, BldgFloor, Place) ON DELETE CASCADE
);
-- ---------------------------------------------------------------------------------



CREATE TABLE Messages (
    TimeLogged		TIMESTAMP 			DEFAULT CURRENT_TIMESTAMP,
    SenderID 		INT					NOT NULL,
    RecipientID 	INT					NOT NULL,
    AdID		 	INT					NOT NULL,
    Content 		TEXT				NOT NULL,
    PRIMARY KEY (SenderID, AdID, TimeLogged),
    FOREIGN KEY (SenderID) 		REFERENCES Person(PersonID) 	ON DELETE CASCADE,
    FOREIGN KEY (RecipientID) 	REFERENCES Person(PersonID)		ON DELETE CASCADE,
    FOREIGN KEY (AdID) 			REFERENCES Ad(AdID)				ON DELETE RESTRICT
);


