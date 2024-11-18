USE LIBRARY;
GO

--A T-SQL user defined function that provides limited string splitting capabilities, 
--mimicking VBA's SPLIT() function.
--I wrote this code as an exercise while taking an intermediate T-SQL course on Udemy.
--Code is presented AS IS, with no guarantee as to its suitability
--for any purpose whatsoever. User assumes all risks associated with running
--this code. 
--(C) 2023 Adiv Abramson

DROP FUNCTION dbo.STRING_PART
GO
CREATE FUNCTION dbo.STRING_PART(
	@Separator VARCHAR(1),
	@Index INT,
	@Expression VARCHAR(MAX)
)
RETURNS VARCHAR(MAX)
AS

BEGIN
 
	-- Can't PRINT error messages because SQL Server complains about
	-- 'side effects'. :-\
	DECLARE @StringPart VARCHAR(MAX) = NULL
	-- Validate inputs
	IF @Separator IS NULL
		BEGIN
			RETURN @StringPart
		END


	-- SQL treats string of spaces like a zero length string.
	IF @Separator NOT LIKE '_'
		BEGIN
			RETURN @StringPart
		END


	-- Validate index into split string 
	IF @Index IS NULL
		BEGIN
			RETURN @StringPart
		END

	IF @Index NOT BETWEEN 1 AND 126
		BEGIN
			RETURN @StringPart
		END

	-- Validate expression
	IF @Expression IS NULL
		BEGIN
			RETURN @StringPart
		END

	-- Expression must not be a zero length string
	IF @Expression = ''
		BEGIN
			RETURN @StringPart
		END
	
	-- Expression must not consist solely of separator characters
	IF REPLACE(@Expression, @Separator, '') = '' 
		BEGIN
			RETURN @StringPart
		END
	
	-- At least one instance of separator must exist in expression
	IF CHARINDEX(@Separator, @Expression) = 0
		BEGIN
			RETURN @StringPart
		END


	-- Count number of occurrences of separator in expression. To
	-- determine the maximum index into the split string, add 1
	-- to the count. For example max index of string 'Harry James Potter'
	-- will be 3 (2 separators + 1).
	DECLARE @MaxIndex TINYINT
	SET @MaxIndex = LEN(@Expression) - LEN(REPLACE(@Expression, @Separator, '')) + 1

	IF @Index > @MaxIndex 
		BEGIN
			RETURN @StringPart
		END

	-- Create table variable using STRING_SPLIT with ordinal column enabled.
	-- This makes selection of desired part of string very easy
	DECLARE @StringParts TABLE (value VARCHAR(MAX), ordinal BIGINT)
	INSERT INTO @StringParts 
	(value, ordinal)

	SELECT 
		value, ordinal
	FROM
		STRING_SPLIT(@Expression, @Separator, 1)

	SELECT @StringPart = (SELECT [value] FROM @StringParts WHERE [ordinal] = @Index)

	RETURN @StringPart

END

-- Usage and testing
SELECT dbo.STRING_PART(' ', 1, 'Harry James Potter') -- returns 'Harry'
SELECT dbo.STRING_PART(' ', 2, 'Harry James Potter') -- returns 'James'
SELECT dbo.STRING_PART(' ', 3, 'Harry James Potter')  -- returns 'Potter'

--Invalid index:
SELECT dbo.STRING_PART(' ', 0, 'Harry James Potter') -- returns NULL
SELECT dbo.STRING_PART(' ', -10, 'Harry James Potter') -- returns NULL
SELECT dbo.STRING_PART(' ', 5, 'Harry James Potter') -- returns NULL

--Separator is zero length string:
SELECT dbo.STRING_PART('', 1, 'Harry James Potter') -- returns NULL

--Separator not found:
SELECT dbo.STRING_PART('$', 2, 'Harry James Potter') -- returns NULL

--Separator more than 1 character:
SELECT dbo.STRING_PART('    ', 0, 'Harry James Potter') -- returns NULL
	
--NULL expression:
SELECT dbo.STRING_PART('$', 1, NULL) 

--Zero length string expression:
SELECT dbo.STRING_PART('$', 2, '') 

--Expression consisting entirely of separator character,
--e.g all ' ' is specified separator 
--or all '$' if '$' is specified separator
SELECT dbo.STRING_PART('$', 2, '$$$$$$$$$') -- returns NULL

--Expression has no separators:
SELECT dbo.STRING_PART(' ', 2, 'HarryJamesPotter') -- returns NULL

-- So a string beginning with one or more separators is valid; just have to
-- provide the correct index
SELECT dbo.STRING_PART('$', 6, '$$$$$ABC$$$$') -- returns 'ABC'
