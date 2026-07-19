USE AdPostingDB;

-- Insert 25 People
INSERT INTO Person (FirstName, LastName, Phone, Email) VALUES
-- Non-college members (3)
('John', 'Smith', '5551234567', 'john.smith@email.com'),
('Sarah', 'Williams', '5551234568', 'sarah.williams@email.com'),
('Michael', 'Brown', '5551234569', 'michael.brown@email.com'),

-- Students (15)
('Emma', 'Johnson', '5551234570', 'emma.johnson@college.edu'),
('Liam', 'Davis', '5551234571', 'liam.davis@college.edu'),
('Olivia', 'Garcia', '5551234572', 'olivia.garcia@college.edu'),
('Noah', 'Martinez', '5551234573', 'noah.martinez@college.edu'),
('Ava', 'Rodriguez', '5551234574', 'ava.rodriguez@college.edu'),
('Ethan', 'Wilson', '5551234575', 'ethan.wilson@college.edu'),
('Sophia', 'Anderson', '5551234576', 'sophia.anderson@college.edu'),
('Mason', 'Taylor', '5551234577', 'mason.taylor@college.edu'),
('Isabella', 'Thomas', '5551234578', 'isabella.thomas@college.edu'),
('Logan', 'Moore', '5551234579', 'logan.moore@college.edu'),
('Mia', 'Jackson', '5551234580', 'mia.jackson@college.edu'),
('Lucas', 'Martin', '5551234581', 'lucas.martin@college.edu'),
('Charlotte', 'Lee', '5551234582', 'charlotte.lee@college.edu'),
('Aiden', 'Perez', '5551234583', 'aiden.perez@college.edu'),
('Amelia', 'White', '5551234584', 'amelia.white@college.edu'),

-- Employees (7, with 4 as reviewers)
('James', 'Harris', '5551234585', 'james.harris@college.edu'),
('Emily', 'Clark', '5551234586', 'emily.clark@college.edu'),
('Benjamin', 'Lewis', '5551234587', 'benjamin.lewis@college.edu'),
('Grace', 'Walker', '5551234588', 'grace.walker@college.edu'),
('Alexander', 'Hall', '5551234589', 'alexander.hall@college.edu'),
('Chloe', 'Allen', '5551234590', 'chloe.allen@college.edu'),
('Daniel', 'Young', '5551234591', 'daniel.young@college.edu');

-- Insert College Members (22 people: 15 students + 7 employees)
INSERT INTO CollegeMember (PersonID, CollegeID, Department) VALUES
-- Students
(4, 'STU000001', 'Computer Science'),
(5, 'STU000002', 'Engineering'),
(6, 'STU000003', 'Business'),
(7, 'STU000004', 'Computer Science'),
(8, 'STU000005', 'Biology'),
(9, 'STU000006', 'Engineering'),
(10, 'STU000007', 'Psychology'),
(11, 'STU000008', 'Mathematics'),
(12, 'STU000009', 'English'),
(13, 'STU000010', 'Computer Science'),
(14, 'STU000011', 'Chemistry'),
(15, 'STU000012', 'Business'),
(16, 'STU000013', 'History'),
(17, 'STU000014', 'Physics'),
(18, 'STU000015', 'Art'),

-- Employees
(19, 'EMP000001', 'IT Services'),
(20, 'EMP000002', 'Student Affairs'),
(21, 'EMP000003', 'Marketing'),
(22, 'EMP000004', 'Communications'),
(23, 'EMP000005', 'Administration'),
(24, 'EMP000006', 'Facilities'),
(25, 'EMP000007', 'Student Affairs');

-- Insert Students
INSERT INTO Student (PersonID, Major) VALUES
(4, 'Computer Science'),
(5, 'Mechanical Engineering'),
(6, 'Business Administration'),
(7, 'Software Engineering'),
(8, 'Molecular Biology'),
(9, 'Civil Engineering'),
(10, 'Clinical Psychology'),
(11, 'Applied Mathematics'),
(12, 'Creative Writing'),
(13, 'Data Science'),
(14, 'Biochemistry'),
(15, 'Marketing'),
(16, 'World History'),
(17, 'Theoretical Physics'),
(18, 'Graphic Design');

-- Insert Employees (4 are reviewers)
INSERT INTO Employee (PersonID, OfficeLocation, Extension, StartDate, PositionTitle, IsReviewer) VALUES
(19, 'BLD-201', '4201', '2020-05-15', 'Staff', 1),          -- Reviewer
(20, 'BLD-105', '4105', '2019-08-20', 'Faculty', 0),
(21, 'LIB-301', '5301', '2021-03-10', 'Specialized', 0),
(22, 'BLD-210', '4210', '2022-01-05', 'Administration', 0),
(23, 'NWN-220', '6220', '2018-09-12', 'Staff', 1),          -- Reviewer
(24, NULL,      NULL,   '2023-02-28', 'Support', 0),
(25, 'BLD-105', '4106', '2020-11-18', 'Faculty', 1);        -- Reviewer (shares office with PersonID 20)

-- Insert 20 Ads (using PosterID, valid AdType values, valid Ad_Status)
INSERT INTO Ad (PosterID, ReviewerID, Title, AdType, AdLength, AdWidth, Duration, PostDate, AdStatus) VALUES
-- Approved ads (14)
(1, 19, 'Textbook for Sale', 'Sale', 300, 200, 14, '2025-10-15', 'Approved'),
(4, 23, 'Roommate Wanted', 'Roommate', 400, 250, 21, '2025-10-20', 'Approved'),
(5, 19, 'Tutoring Services', 'Tutorship', 350, 220, 14, '2025-10-22', 'Approved'),
(6, 25, 'Campus Event DJ', 'Event', 300, 200, 7, '2025-10-25', 'Approved'),
(7, 25, 'Used Laptop', 'Sale', 300, 200, 14, '2025-10-28', 'Approved'),
(4, 23, 'Study Group Formation', 'Tutorship', 350, 220, 10, '2025-11-01', 'Approved'),
(8, 19, 'Lab Equipment Sale', 'Sale', 400, 250, 14, '2025-11-02', 'Approved'),
(2, 25, 'Bike for Sale', 'Sale', 300, 200, 14, '2025-11-03', 'Approved'),
(9, 25, 'Apartment Sublet', 'Roommate', 400, 250, 30, '2025-11-04', 'Approved'),
(10, 19, 'Guitar Lessons', 'Tutorship', 350, 220, 21, '2025-11-05', 'Approved'),
(11, 23, 'Math Tutor Available', 'Tutorship', 300, 200, 14, '2025-11-06', 'Approved'),
(5, 19, 'Engineering Textbooks', 'Sale', 350, 220, 14, '2025-11-07', 'Approved'),
(12, 25, 'Photography Services', 'Tutorship', 400, 250, 21, '2025-11-08', 'Approved'),
(13, 19, 'Programming Help', 'Tutorship', 300, 200, 14, '2025-11-08', 'Approved'),

-- Pending ads (4)
(14, 23, 'Chemistry Lab Partner', 'Tutorship', 300, 200, 7, NULL, 'Pending'),
(15, NULL, 'Business Books', 'Sale', 350, 220, 14, NULL, 'Pending'),
(3, NULL, 'Car for Sale', 'Sale', 400, 250, 21, NULL, 'Pending'),
(16, NULL, 'History Study Group', 'Tutorship', 300, 200, 10, NULL, 'Pending'),

-- Rejected ads (2)
(17, 19, 'Prohibited Item', 'Sale', 300, 200, 14, NULL, 'Rejected'),
(18, 25, 'Inappropriate Service', 'Tutorship', 350, 220, 14, NULL, 'Rejected'),
(18, 25, 'Giant Ad', 'Tutorship', 3500, 2100, 14, NULL, 'Rejected');

-- Insert 5 Boards
INSERT INTO Board (Building, BldgFloor, Place, BoardLength, BoardWidth) VALUES
('BLD', 1, 'A', 2000, 1500),
('BLD', 1, 'B', 2500, 1875),
('BLD', 2, 'A', 2000, 1500),
('BLD', 3, 'A', 3000, 2250),
('LIB', 1, 'A', 1800, 1350),
('NWN', 1, 'A', 2000, 1500),
('NWN', 2, 'A', 1800, 1350);

-- Post some ads to boards (only approved ads)
INSERT INTO Ad_Posted_Board (AdID, Building, BldgFloor, Place) VALUES
(1, 'BLD', 1, 'A'),
(2, 'BLD', 1, 'B'),
(3, 'BLD', 2, 'A'),
(3, 'LIB', 1, 'A'),
(4, 'BLD', 1, 'A'),
(5, 'BLD', 3, 'A'),
(6, 'LIB', 1, 'A'),
(7, 'BLD', 1, 'A'),
(7, 'BLD', 1, 'B'),
(7, 'BLD', 2, 'A'),
(7, 'BLD', 3, 'A'),
(8, 'BLD', 2, 'A'),
(9, 'BLD', 1, 'A'),
(10, 'BLD', 3, 'A'),
(11, 'LIB', 1, 'A'),
(12, 'BLD', 1, 'B'),
(13, 'BLD', 2, 'A');

-- Insert 24 Messages
INSERT INTO Messages (SenderID, AdID, TimeLogged, RecipientID, Content) VALUES
(4, 1, '2025-10-16 10:30:00', 1, 'Is this textbook still available?'),
(1, 1, '2025-10-16 11:15:00', 4, 'Yes! It is in great condition.'),
(4, 1, '2025-10-16 11:45:00', 1, 'Great, would you take $40 for it?'),
(1, 1, '2025-10-16 12:10:00', 4, 'I can do $45, it includes the solutions manual.'),
(4, 1, '2025-10-16 12:30:00', 1, 'Deal, I can pick it up tomorrow afternoon.'),
(6, 1, '2025-10-17 09:00:00', 1, 'Hi, is this textbook still up for grabs?'),
(1, 1, '2025-10-17 09:20:00', 6, 'Sorry, already sold it to someone else!'),
(5, 2, '2025-10-21 14:20:00', 4, 'I am interested in being your roommate. Can we meet?'),
(6, 3, '2025-10-23 09:45:00', 5, 'What subjects do you tutor?'),
(5, 3, '2025-10-23 16:30:00', 6, 'I tutor Math, Physics, and Engineering courses.'),
(7, 4, '2025-10-26 12:00:00', 6, 'Are you available for a weekend event?'),
(8, 5, '2025-10-29 08:15:00', 7, 'What are the specs on this laptop?'),
(7, 5, '2025-10-29 08:40:00', 8, 'It is a 2022 model, 16GB RAM, 512GB SSD, barely used.'),
(8, 5, '2025-10-29 09:10:00', 7, 'Does the battery still hold a charge well?'),
(7, 5, '2025-10-29 09:25:00', 8, 'Yes, about 6 hours on a full charge.'),
(3, 5, '2025-10-30 14:00:00', 7, 'Would you be willing to ship it to me?'),
(7, 5, '2025-10-30 14:30:00', 3, 'Sorry, local pickup only for this one.'),
(9, 9, '2025-11-05 17:40:00', 9, 'When is the apartment available?'),
(10, 10, '2025-11-06 13:25:00', 10, 'What is your hourly rate for lessons?'),
(11, 7, '2025-11-03 11:50:00', 8, 'Is the lab equipment still for sale?'),
(14, 11, '2025-11-07 10:00:00', 11, 'Do you tutor calculus for first-year engineering students?'),
(11, 11, '2025-11-07 10:20:00', 14, 'Yes, I focus mostly on Calc I and II. When are you looking to start?'),
(14, 11, '2025-11-07 10:35:00', 11, 'This week if possible, I have a midterm coming up.'),
(15, 13, '2025-11-09 16:00:00', 12, 'Are you available to shoot a graduation event in December?');
