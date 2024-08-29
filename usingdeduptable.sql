USE DB_Temp
GO

DROP TABLE IF EXISTS dbo.PhoneModels
GO
CREATE TABLE dbo.PhoneModels
( 
PhoneID int IDENTITY(1,1) NOT NULL, 
DeviceName varchar(55) NULL, 
RAM INT NULL, 
Price MONEY NULL
 ) 

GO

INSERT INTO dbo.PhoneModels
(
	DeviceName,
	RAM,
	Price
)
VALUES
('iPhone 6', 16, 299),
('Samsung Galaxy 3', 32, 199.99),
('BlackBerry Bold', 8, 495.90),
('iPhone 12 Mini', 64, 699),
('Nokia 1100', 4, 89.95)

SELECT * FROM dbo.PhoneModels
/*
PhoneID     DeviceName                                              RAM         Price
----------- ------------------------------------------------------- ----------- ---------------------
1           iPhone 6                                                16          299.00
2           Samsung Galaxy 3                                        32          199.99
3           BlackBerry Bold                                         8           495.90
4           iPhone 12 Mini                                          64          699.00
5           Nokia 1100                                              4           89.95

(5 rows affected)
*/


-- Insert duplicate rows of data
INSERT INTO dbo.PhoneModels
(
	DeviceName,
	RAM,
	Price
)
VALUES
('iPhone 6', 16, 299),
('Samsung Galaxy 3', 32, 199.99),
('iPhone 12 Mini', 64, 699),
('Nokia 1100', 4, 89.95),
('iPhone 6', 16, 299),
('Samsung Galaxy 3', 32, 199.99),
('BlackBerry Bold', 8, 495.90),
('iPhone 12', 64, 799),
('Nokia 1100', 4, 89.95),
('iPhone 6', 16, 299),
('Samsung Galaxy 3', 32, 199.99),
('BlackBerry Bold', 8, 495.90),
('iPhone 12', 64, 799),
('Nokia 1100', 4, 89.95),
('iPhone 6', 16, 299)

SELECT * 
FROM 
	dbo.PhoneModels
ORDER BY
	[DeviceName], [RAM], [Price]
/*
PhoneID     DeviceName                                              RAM         Price
----------- ------------------------------------------------------- ----------- ---------------------
3           BlackBerry Bold                                         8           495.90
12          BlackBerry Bold                                         8           495.90
17          BlackBerry Bold                                         8           495.90
18          iPhone 12                                               64          799.00
13          iPhone 12                                               64          799.00
4           iPhone 12 Mini                                          64          699.00
8           iPhone 12 Mini                                          64          699.00
6           iPhone 6                                                16          299.00
1           iPhone 6                                                16          299.00
10          iPhone 6                                                16          299.00
15          iPhone 6                                                16          299.00
20          iPhone 6                                                16          299.00
19          Nokia 1100                                              4           89.95
14          Nokia 1100                                              4           89.95
5           Nokia 1100                                              4           89.95
9           Nokia 1100                                              4           89.95
7           Samsung Galaxy 3                                        32          199.99
2           Samsung Galaxy 3                                        32          199.99
11          Samsung Galaxy 3                                        32          199.99
16          Samsung Galaxy 3                                        32          199.99

(20 rows affected)
*/

DECLARE @Return_Val INT

EXECUTE @Return_Val = 
		[LIBRARY].dbo.DeDupeTable 
		@DupeDatabase = 'DB_Temp', 
		@DupeSchema = 'dbo', 
		@DupeTable = 'PhoneModels',
		@DupeFields = 'DeviceName,RAM,Price'

--14 records have been deleted.

SELECT @Return_Val [SP RETURN CODE]

SELECT * 
FROM 
	dbo.PhoneModels
ORDER BY
	[DeviceName], [RAM], [Price]

/*
PhoneID     DeviceName                                              RAM         Price
----------- ------------------------------------------------------- ----------- ---------------------
3           BlackBerry Bold                                         8           495.90
18          iPhone 12                                               64          799.00
4           iPhone 12 Mini                                          64          699.00
6           iPhone 6                                                16          299.00
19          Nokia 1100                                              4           89.95
7           Samsung Galaxy 3                                        32          199.99

(6 rows affected)
*/