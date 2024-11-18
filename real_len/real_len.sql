CREATE FUNCTION dbo.REAL_LEN(@Input VARCHAR(MAX))
RETURNS INT
AS
BEGIN
	DECLARE @Length INT
	-- Validate input
	IF @Input IS NULL
		BEGIN
			RETURN @Length
		END

	-- Replace spaces with '.' to get an accurate character count
	SET @Input = REPLACE(@Input, ' ', '.')
	SET @Length = LEN(@Input)
	RETURN @Length
END

-- Before
SELECT LEN('This is a string                         ') [string_length]
--string_length
--16

-- After
SELECT dbo.REAL_LEN('This is a string                         ') [string_length]
--string_length
--41
