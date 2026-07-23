-- =============================================================================
-- SEED_ANCHOR_DATE: 2026-07-21
--
-- Every date and timestamp below is expressed relative to the anchor date above.
-- Run shift_seed_dates.py to slide the whole dataset forward so that it sits
-- near the current date again; the script rewrites this line to the new anchor.
-- Relative spacing between all dates is preserved, so the invariants the seed
-- data is built around (EnteredPending <= ReviewDate <= PostDate, the mix of
-- expired and active postings, message chronology) continue to hold.
-- =============================================================================

USE AdPostingDB;
GO

-- Insert 32 People
-- PersonIDs are assigned by the engine in insert order, so people are grouped
-- into contiguous blocks by specialization: non-college members first, then
-- students, then employees. The explicit PersonID values used in every insert
-- below depend on this ordering.
INSERT INTO Person (FirstName, LastName, Phone, Email) VALUES
-- Non-college members (4)
('John',       'Smith',     '5551234567', 'john.smith@email.com'         ),  -- 1
('Sarah',      'Williams',  '5551234568', 'sarah.williams@email.com'     ),  -- 2
('Michael',    'Brown',     '5551234569', 'michael.brown@email.com'      ),  -- 3
('Rebecca',    'Foster',    '5551234593', 'rebecca.foster@email.com'     ),  -- 4

-- Students (17)
('Emma',       'Johnson',   '5551234570', 'emma.johnson@college.edu'     ),  -- 5
('Liam',       'Davis',     '5551234571', 'liam.davis@college.edu'       ),  -- 6
('Olivia',     'Garcia',    '5551234572', 'olivia.garcia@college.edu'    ),  -- 7
('Noah',       'Martinez',  '5551234573', 'noah.martinez@college.edu'    ),  -- 8
('Ava',        'Rodriguez', '5551234574', 'ava.rodriguez@college.edu'    ),  -- 9
('Ethan',      'Wilson',    '5551234575', 'ethan.wilson@college.edu'     ),  -- 10
('Sophia',     'Anderson',  '5551234576', 'sophia.anderson@college.edu'  ),  -- 11
('Mason',      'Taylor',    '5551234577', 'mason.taylor@college.edu'     ),  -- 12
('Isabella',   'Thomas',    '5551234578', 'isabella.thomas@college.edu'  ),  -- 13
('Logan',      'Moore',     '5551234579', 'logan.moore@college.edu'      ),  -- 14
('Mia',        'Jackson',   '5551234580', 'mia.jackson@college.edu'      ),  -- 15
('Lucas',      'Martin',    '5551234581', 'lucas.martin@college.edu'     ),  -- 16
('Charlotte',  'Lee',       '5551234582', 'charlotte.lee@college.edu'    ),  -- 17
('Aiden',      'Perez',     '5551234583', 'aiden.perez@college.edu'      ),  -- 18
('Amelia',     'White',     '5551234584', 'amelia.white@college.edu'     ),  -- 19
('Nathan',     'Reid',      '5551234594', 'nathan.reid@college.edu'      ),  -- 20
('Priya',      'Nair',      '5551234595', 'priya.nair@college.edu'       ),  -- 21

-- Employees (11, with 4 as reviewers)
('James',      'Harris',    '5551234585', 'james.harris@college.edu'     ),  -- 22
('Emily',      'Clark',     '5551234586', 'emily.clark@college.edu'      ),  -- 23
('Benjamin',   'Lewis',     '5551234587', 'benjamin.lewis@college.edu'   ),  -- 24
('Grace',      'Walker',    '5551234588', 'grace.walker@college.edu'     ),  -- 25
('Alexander',  'Hall',      '5551234589', 'alexander.hall@college.edu'   ),  -- 26
('Chloe',      'Allen',     '5551234590', 'chloe.allen@college.edu'      ),  -- 27
('Daniel',     'Young',     '5551234591', 'daniel.young@college.edu'     ),  -- 28
('Mike',       'Jameson',   '5551234592', 'mike.jameson@college.edu'     ),  -- 29
('Thomas',     'Okafor',    '5551234596', 'thomas.okafor@college.edu'    ),  -- 30
('Helen',      'Vasquez',   '5551234597', 'helen.vasquez@college.edu'    ),  -- 31
('Marcus',     'Bell',      '5551234598', 'marcus.bell@college.edu'      );  -- 32
GO

-- Insert College Members (28 people: 17 students + 11 employees)
INSERT INTO CollegeMember (PersonID, CollegeID, Department) VALUES
-- Students
(5, 'STU000001', 'Computer Science'),
(6, 'STU000002', 'Engineering'),
(7, 'STU000003', 'Business'),
(8, 'STU000004', 'Computer Science'),
(9, 'STU000005', 'Biology'),
(10, 'STU000006', 'Engineering'),
(11, 'STU000007', 'Psychology'),
(12, 'STU000008', 'Mathematics'),
(13, 'STU000009', 'English'),
(14, 'STU000010', 'Computer Science'),
(15, 'STU000011', 'Chemistry'),
(16, 'STU000012', 'Business'),
(17, 'STU000013', 'History'),
(18, 'STU000014', 'Physics'),
(19, 'STU000015', 'Art'),
(20, 'STU000016', 'Music'),
(21, 'STU000017', 'Computer Science'),

-- Employees
(22, 'EMP000001', 'IT Services'),
(23, 'EMP000002', 'Student Affairs'),
(24, 'EMP000003', 'Marketing'),
(25, 'EMP000004', 'Communications'),
(26, 'EMP000005', 'Administration'),
(27, 'EMP000006', 'Facilities'),
(28, 'EMP000007', 'Student Affairs'),
(29, 'EMP000008', 'Student Affairs'),
(30, 'EMP000009', 'Physics'),
(31, 'EMP000010', 'Administration'),
(32, 'EMP000011', 'Facilities');
GO

-- Insert 17 Students
INSERT INTO Student (PersonID, Major) VALUES
(5, 'Computer Science'),
(6, 'Mechanical Engineering'),
(7, 'Business Administration'),
(8, 'Software Engineering'),
(9, 'Molecular Biology'),
(10, 'Civil Engineering'),
(11, 'Clinical Psychology'),
(12, 'Applied Mathematics'),
(13, 'Creative Writing'),
(14, 'Data Science'),
(15, 'Biochemistry'),
(16, 'Marketing'),
(17, 'World History'),
(18, 'Theoretical Physics'),
(19, 'Graphic Design'),
(20, 'Music Performance'),
(21, 'Data Science');
GO

-- Insert 11 Employees (4 are reviewers)
INSERT INTO Employee (PersonID, OfficeLocation, Extension, PositionTitle, IsReviewer) VALUES
(22, 'BLD-201', '4201', 'Staff',          1),  -- Reviewer
(23, 'BLD-105', '4105', 'Faculty',        0),
(24, 'LIB-301', '5301', 'Specialized',    0),
(25, 'BLD-210', '4210', 'Administration', 0),
(26, 'NWN-220', '6220', 'Staff',          1),  -- Reviewer
(27, NULL   ,   NULL  , 'Support',        0),
(28, 'BLD-105', '4106', 'Faculty',        1),  -- Reviewer (shares office with PersonID 23)
(29, 'BLD-205', '5106', 'Administration', 1),  -- Reviewer (no reviews)
(30, 'SCI-310', '7310', 'Faculty',        0),
(31, 'BLD-212', '4212', 'Administration', 0),
(32, 'NWN-105', '6105', 'Support',        0);
GO

-- Insert 36 Ads
-- EnteredPending records when an ad most recently entered Pending status; it is
-- never cleared, so it retains its value after an ad is approved or rejected.
-- ReviewDate is stamped whenever ReviewStatus <> 'Pending'. PostDate is only ever set
-- once an ad is physically placed on a board (see PostAd), and always on or after
-- its ReviewDate. IsWithdrawn/WithdrawnDate are independent of ReviewStatus; every
-- ad in this seed data is un-withdrawn (0, NULL).
INSERT INTO Ad (PosterID, ReviewerID, Title, AdType, AdLength, AdWidth, Duration, PostDate, ReviewStatus, EnteredPending, ReviewDate, IsWithdrawn, WithdrawnDate, ImageFileName) VALUES
-- Approved and posted (18)
(1 , 22,   'Textbook for Sale',              'Sale',      300,   200,   14,  '2026-06-16', 'Approved', '2026-06-14', '2026-06-16', 0, NULL, 'sale-textbook.jpg'),
(5 , 26,   'Roommate Wanted',                'Roommate',  400,   250,   21,  '2026-06-21', 'Approved', '2026-06-19', '2026-06-21', 0, NULL, 'roommate-wanted.jpg'),
(6 , 22,   'Tutoring Services',              'Tutorship', 350,   220,   14,  '2026-06-23', 'Approved', '2026-06-20', '2026-06-23', 0, NULL, 'tutorship-general-services.jpg'),
(7 , 28,   'Campus Event DJ',                'Service',   300,   200,   7,   '2026-06-26', 'Approved', '2026-06-24', '2026-06-26', 0, NULL, 'service-campus-dj.jpg'),
(8 , 28,   'Used Laptop',                    'Sale',      300,   200,   14,  '2026-06-29', 'Approved', '2026-06-27', '2026-06-29', 0, NULL, 'sale-used-laptop.jpg'),
(5 , 26,   'Study Group Formation',          'Tutorship', 350,   220,   10,  '2026-07-03', 'Approved', '2026-07-01', '2026-07-03', 0, NULL, 'tutorship-study-group.jpg'),
(9 , 22,   'Lab Equipment Sale',             'Sale',      400,   250,   14,  '2026-07-04', 'Approved', '2026-06-26', '2026-06-29', 0, NULL, 'sale-lab-equipment.jpg'), -- approved 5 days before it was actually posted
(2 , 28,   'Bike for Sale',                  'Sale',      300,   200,   14,  '2026-07-05', 'Approved', '2026-07-03', '2026-07-05', 0, NULL, 'sale-bike.jpg'),
(10, 28,   'Apartment Sublet',               'Roommate',  400,   250,   30,  '2026-07-06', 'Approved', '2026-07-04', '2026-07-06', 0, NULL, 'roommate-apartment-sublet.jpg'),
(11, 22,   'Guitar Lessons',                 'Tutorship', 350,   220,   21,  '2026-07-07', 'Approved', '2026-07-05', '2026-07-07', 0, NULL, 'tutorship-guitar-lessons.jpg'),
(12, 26,   'Math Tutor Available',           'Tutorship', 300,   200,   14,  '2026-07-08', 'Approved', '2026-07-06', '2026-07-08', 0, NULL, 'tutorship-math-tutor.jpg'),
(6 , 22,   'Engineering Textbooks',          'Sale',      350,   220,   14,  '2026-07-09', 'Approved', '2026-07-07', '2026-07-09', 0, NULL, 'sale-engineering-textbooks.jpg'),
(13, 28,   'Photography Services',           'Service',   400,   250,   21,  '2026-07-10', 'Approved', '2026-07-08', '2026-07-10', 0, NULL, 'service-photography.jpg'),
(30, 22,   'Colloquium: Quantum Matter',     'Event',     400,   300,   14,  '2026-07-11', 'Approved', '2026-07-08', '2026-07-10', 0, NULL, 'event-colloquium-quantum-matter.jpg'),
(31, 26,   'Summer Concert on the Green',    'Event',     500,   350,   21,  '2026-07-12', 'Approved', '2026-07-09', '2026-07-11', 0, NULL, 'event-summer-concert.jpg'),
(23, 28,   'Guest Lecture: Urban Policy',    'Event',     400,   300,   10,  '2026-07-13', 'Approved', '2026-07-10', '2026-07-12', 0, NULL, 'event-guest-lecture-urban-policy.jpg'),
(4 , 22,   'Winter Tires, Set of Four',      'Sale',      300,   200,   14,  '2026-07-14', 'Approved', '2026-07-12', '2026-07-14', 0, NULL, 'sale-winter-tires.jpg'),
(20, 26,   'Piano Accompanist Available',    'Service',   350,   220,   21,  '2026-07-15', 'Approved', '2026-07-13', '2026-07-15', 0, NULL, 'service-piano-accompanist.jpg'),

-- Approved, not yet posted (6)
(14, 22,   'Programming Help',               'Tutorship', 300,   200,   14,  NULL,         'Approved', '2026-07-08', '2026-07-10', 0, NULL, 'tutorship-programming-help.jpg'),
(30, 28,   'Seminar: Science Writing',       'Event',     400,   300,   10,  NULL,         'Approved', '2026-07-13', '2026-07-15', 0, NULL, 'event-seminar-science-writing.jpg'),
(21, 26,   'Statistics Tutoring',            'Tutorship', 300,   200,   14,  NULL,         'Approved', '2026-07-14', '2026-07-16', 0, NULL, 'tutorship-statistics.jpg'),
(15, 22,   'Room in Shared House',           'Rent',      400,   250,   30,  NULL,         'Approved', '2026-07-15', '2026-07-17', 0, NULL, 'rent-room-shared-house.jpg'),
(24, 28,   'Lost and Found Reminder',        'Other',     250,   180,   30,  NULL,         'Approved', '2026-07-16', '2026-07-18', 0, NULL, 'other-lost-and-found.jpg'),
(16, 26,   'Bicycle Repair Service',         'Service',   300,   200,   21,  NULL,         'Approved', '2026-07-17', '2026-07-19', 0, NULL, 'service-bicycle-repair.jpg'),

-- Pending (7)
(17, NULL, 'Chemistry Lab Partner',          'Tutorship', 300,   200,   7,   NULL,         'Pending',  '2026-07-16', NULL,         0, NULL, 'tutorship-chemistry-lab-partner.jpg'),
(18, NULL, 'Business Books',                 'Sale',      350,   220,   14,  NULL,         'Pending',  '2026-07-17', NULL,         0, NULL, 'sale-business-books.jpg'),
(3 , NULL, 'Car for Sale',                   'Sale',      400,   250,   21,  NULL,         'Pending',  '2026-07-18', NULL,         0, NULL, 'sale-car.jpg'),
(19, NULL, 'History Study Group',            'Tutorship', 300,   200,   10,  NULL,         'Pending',  '2026-07-19', NULL,         0, NULL, 'tutorship-history-study-group.jpg'),
(31, NULL, 'Departmental Open House',        'Event',     400,   300,   14,  NULL,         'Pending',  '2026-07-21', NULL,         0, NULL, 'event-departmental-open-house.jpg'),
(27, NULL, 'Carpool to Downtown',            'Other',     250,   180,   21,  NULL,         'Pending',  '2026-07-21', NULL,         0, NULL, 'other-carpool-downtown.jpg'),
(21, NULL, 'Textbook Bundle, CS Courses',    'Sale',      300,   200,   14,  NULL,         'Pending',  '2026-07-21', NULL,         0, NULL, 'sale-textbook-bundle-cs.jpg'),

-- Rejected (5)
(17, 22,   'Prohibited Item',                'Sale',      300,   200,   14,  NULL,         'Rejected', '2026-06-30', '2026-07-02', 0, NULL, 'sale-prohibited-item.jpg'),
(19, 28,   'Inappropriate Service',          'Service',   350,   220,   14,  NULL,         'Rejected', '2026-07-06', '2026-07-08', 0, NULL, 'service-inappropriate.jpg'),
(19, 28,   'Giant Ad',                       'Tutorship', 3500,  2100,  14,  NULL,         'Rejected', '2026-07-07', '2026-07-09', 0, NULL, 'tutorship-giant-ad.jpg'),
(19, 26,   'Unverified Cash Offer',          'Other',     300,   200,   14,  NULL,         'Rejected', '2026-07-12', '2026-07-14', 0, NULL, 'other-unverified-cash-offer.jpg'),
(29, 22,   'Off-Campus Solicitation',        'Other',     300,   200,   14,  NULL,         'Rejected', '2026-07-15', '2026-07-17', 0, NULL, 'other-off-campus-solicitation.jpg');
GO

-- Insert 7 Boards
INSERT INTO Board (Building, BldgFloor, Slot, BoardLength, BoardWidth) VALUES
('BLD', 1, 'A', 2000, 1500),
('BLD', 1, 'B', 2500, 1875),
('BLD', 2, 'A', 2000, 1500),
('BLD', 3, 'A', 3000, 2250),
('LIB', 1, 'A', 1800, 1350),
('NWN', 1, 'A', 2000, 1500),
('NWN', 2, 'A', 1800, 1350);
GO

-- Post ads to boards (26 postings; only approved ads with a PostDate)
INSERT INTO Ad_Posted_Board (AdID, Building, BldgFloor, Slot) VALUES
(1 , 'BLD', 1, 'A'),
(2 , 'BLD', 1, 'B'),
(3 , 'BLD', 2, 'A'),
(3 , 'LIB', 1, 'A'),
(4 , 'BLD', 1, 'A'),
(5 , 'BLD', 3, 'A'),
(6 , 'LIB', 1, 'A'),
(7 , 'BLD', 1, 'A'),
(7 , 'BLD', 1, 'B'),
(7 , 'BLD', 2, 'A'),
(7 , 'BLD', 3, 'A'),
(8 , 'BLD', 2, 'A'),
(9 , 'BLD', 1, 'A'),
(10, 'BLD', 3, 'A'),
(11, 'LIB', 1, 'A'),
(12, 'BLD', 1, 'B'),
(13, 'BLD', 2, 'A'),
(14, 'NWN', 1, 'A'),
(14, 'BLD', 3, 'A'),
(15, 'NWN', 1, 'A'),
(15, 'NWN', 2, 'A'),
(15, 'BLD', 1, 'B'),
(16, 'NWN', 2, 'A'),
(16, 'LIB', 1, 'A'),
(17, 'NWN', 1, 'A'),
(18, 'NWN', 2, 'A');
GO

-- Insert 47 Messages
INSERT INTO Messages (SenderID, AdID, TimeLogged, RecipientID, Content) VALUES
-- Ad 1: Textbook for Sale (poster 1)
(5 , 1 , '2026-06-17 10:30:00', 1 , 'Is this textbook still available?'),
(1 , 1 , '2026-06-17 11:15:00', 5 , 'Yes! It is in great condition.'),
(5 , 1 , '2026-06-17 11:45:00', 1 , 'Great, would you take $40 for it?'),
(1 , 1 , '2026-06-17 12:10:00', 5 , 'I can do $45, it includes the solutions manual.'),
(5 , 1 , '2026-06-17 12:30:00', 1 , 'Deal, I can pick it up tomorrow afternoon.'),
(7 , 1 , '2026-06-18 09:00:00', 1 , 'Hi, is this textbook still up for grabs?'),
(1 , 1 , '2026-06-18 09:20:00', 7 , 'Sorry, already sold it to someone else!'),

-- Ad 2: Roommate Wanted (poster 4 -> 5)
(6 , 2 , '2026-06-22 14:20:00', 5 , 'I am interested in being your roommate. Can we meet?'),
(5 , 2 , '2026-06-22 15:05:00', 6 , 'Sure, are you free Thursday evening?'),

-- Ad 3: Tutoring Services (poster 5 -> 6)
(7 , 3 , '2026-06-24 09:45:00', 6 , 'What subjects do you tutor?'),
(6 , 3 , '2026-06-24 16:30:00', 7 , 'I tutor Math, Physics, and Engineering courses.'),

-- Ad 4: Campus Event DJ (poster 6 -> 7)
(8 , 4 , '2026-06-27 12:00:00', 7 , 'Are you available for a weekend event?'),
(7 , 4 , '2026-06-27 13:15:00', 8 , 'Most weekends in July are open. What date?'),

-- Ad 5: Used Laptop (poster 7 -> 8)
(9 , 5 , '2026-06-30 08:15:00', 8 , 'What are the specs on this laptop?'),
(8 , 5 , '2026-06-30 08:40:00', 9 , 'It is a 2022 model, 16GB RAM, 512GB SSD, barely used.'),
(9 , 5 , '2026-06-30 09:10:00', 8 , 'Does the battery still hold a charge well?'),
(8 , 5 , '2026-06-30 09:25:00', 9 , 'Yes, about 6 hours on a full charge.'),
(3 , 5 , '2026-07-01 14:00:00', 8 , 'Would you be willing to ship it to me?'),
(8 , 5 , '2026-07-01 14:30:00', 3 , 'Sorry, local pickup only for this one.'),

-- Ad 7: Lab Equipment Sale (poster 8 -> 9)
(12, 7 , '2026-07-05 11:50:00', 9 , 'Is the lab equipment still for sale?'),
(9 , 7 , '2026-07-05 13:20:00', 12, 'Yes, most of it. What were you looking for specifically?'),

-- Ad 8: Bike for Sale (poster 2)
(21, 8 , '2026-07-06 10:15:00', 2 , 'What size frame is the bike?'),
(2 , 8 , '2026-07-06 11:00:00', 21, 'It is a 54cm, good for someone around 5 foot 9.'),

-- Ad 9: Apartment Sublet (poster 9 -> 10)
(14, 9 , '2026-07-07 17:40:00', 10, 'When is the apartment available?'),
(20, 9 , '2026-07-08 09:30:00', 10, 'Is the sublet furnished?'),
(10, 9 , '2026-07-08 10:05:00', 20, 'Partially, the bedroom furniture stays.'),

-- Ad 10: Guitar Lessons (poster 10 -> 11)
(17, 10, '2026-07-08 13:25:00', 11, 'What is your hourly rate for lessons?'),
(20, 10, '2026-07-09 15:40:00', 11, 'Do you teach classical or only contemporary?'),

-- Ad 11: Math Tutor Available (poster 11 -> 12)
(15, 11, '2026-07-09 10:00:00', 12, 'Do you tutor calculus for first-year engineering students?'),
(12, 11, '2026-07-09 10:20:00', 15, 'Yes, I focus mostly on Calc I and II. When are you looking to start?'),
(15, 11, '2026-07-09 10:35:00', 12, 'This week if possible, I have a midterm coming up.'),

-- Ad 13: Photography Services (poster 12 -> 13)
(16, 13, '2026-07-11 16:00:00', 13, 'Are you available to shoot a graduation event in December?'),
(13, 13, '2026-07-11 17:20:00', 16, 'December is wide open right now, send me the details.'),

-- Ad 14: Colloquium: Quantum Matter (poster 30, Faculty)
(18, 14, '2026-07-12 09:10:00', 30, 'Is the colloquium open to undergraduates?'),
(30, 14, '2026-07-12 10:45:00', 18, 'Yes, all are welcome. No registration needed.'),
(21, 14, '2026-07-13 14:00:00', 30, 'Will there be a recording posted afterward?'),
(30, 14, '2026-07-13 16:30:00', 21, 'We plan to record it and post the link to the department page.'),

-- Ad 15: Summer Concert on the Green (poster 31, Administration)
(20, 15, '2026-07-13 11:00:00', 31, 'Are student performers still being accepted?'),
(31, 15, '2026-07-13 12:15:00', 20, 'We have two slots left, email me a sample recording.'),
(19, 15, '2026-07-14 18:20:00', 31, 'Is there seating or should we bring blankets?'),
(31, 15, '2026-07-15 08:50:00', 19, 'Bring blankets, it is lawn seating only.'),

-- Ad 16: Guest Lecture: Urban Policy (poster 20 -> 23, Faculty)
(17, 16, '2026-07-14 13:30:00', 23, 'Does the guest lecture count for course credit?'),
(23, 16, '2026-07-14 15:00:00', 17, 'Not for credit, but attendance is noted for the seminar series.'),

-- Ad 17: Winter Tires (poster 27 -> 4, non-member)
(10, 17, '2026-07-15 10:20:00', 4 , 'What size are the tires and how much tread is left?'),
(4 , 17, '2026-07-15 11:40:00', 10, 'They are 205/55R16, roughly 70 percent tread remaining.'),

-- Ad 18: Piano Accompanist Available (poster 28 -> 20)
(30, 18, '2026-07-16 09:00:00', 20, 'Would you be available to accompany a recital in the fall?'),
(20, 18, '2026-07-16 10:30:00', 30, 'Yes, I have availability. What repertoire?');
GO
