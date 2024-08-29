/*
	A T-SQL stored procedure that removes duplicate records from 
	the specified table. 
	Parameters:
		DupeDatabase VARCHAR(100): Name of the database containing the table to be
		                           deduped. If omitted, assumes currently connected
								   database.
		DupeSchema VARCHAR(100): Name of schema to which table belongs, dbo is 
		                         default
		DupeTable VARCHAR(100): Name of the table containing potentially duplicated records.
		DupeFields COLUMNLIST: A list of the table columns which determine duplicate records.
		                       Object has custom datatype since stored procedures don't work
							   with TABLE objects directly. Also, this parameter is READONLY.

	Can't use custom type. Proc won't work when invoked from a different database.
	SQL Server throws error about 'COLUMNLIST clashes with COLUMNLIST', after defining
	a local version of COLUMNLIST in the other database. In truth, it's probably
	not a good user exprience to require creation of a custom type. Will pass
	a comma delimited list of fields from the table to be deduped. Will still
	validate them as before.
	
	Procedure validates specified database name, schema name, table name and fields before 
	attempting to delete records. If all parameters are validated,
	procedure uses ROW_NUMBER() to mark duplicate records. If no records have
	ROW_NUMBER() > 1, there are no duplicate records, based on the column list provided, 
	to delete from specified table. It may be that a different list
	of columns will determine that duplicate records exist.

	Procedure wraps deletion code in a transaction.
	Procedure confirms that after deletion, ROW_NUMBER() returns 1 for all remaining records.
	If duplicates remain, procedure will roll back the transaction and print a message.
	Otherwise the changes to the specified table will be committed.

	Procedure prints confirmation message after records have been deleted indicating which
	fields were used to determine duplicate records, how many duplicate records were deleted,
	and the name of the table containing duplicate records.
*/

USE LIBRARY
GO



DECLARE @ProcName VARCHAR(50) = 'DeDupeTable'
IF OBJECT_ID(@ProcName,'P') IS NOT NULL
	EXECUTE('DROP PROCEDURE ' + @ProcName)

GO

 /* NOT USING CUSTOM TYPE ANYMORE FOR LIST OF FIELDS. USING
    COMMA DELIMITED LIST OF FIELDS GOING FORWARD.
 
   To pass a TVP to a stored procedure, first create a custom TYPE
    of datatype TABLE. Then in the SP definition, include a READONLY
    parameter of the custom TYPE.

GO
DROP TYPE IF EXISTS dbo.COLUMNLIST

GO
CREATE TYPE COLUMNLIST 
AS
TABLE(ColumnName VARCHAR(50));
*/


DROP PROCEDURE IF EXISTS dbo.DeDupeTable

GO
CREATE PROCEDURE dbo.DeDupeTable

	@DupeDatabase VARCHAR(100),
	@DupeSchema VARCHAR(100),
	@DupeTable VARCHAR(100),
	@DupeFields VARCHAR(MAX)

AS

BEGIN
	DECLARE @SQL NVARCHAR(MAX)
	DECLARE @Params NVARCHAR(MAX)
	DECLARE @ReturnVal INT 
	DECLARE @Message VARCHAR(MAX)
	DECLARE @TableFields TABLE (ColumnName VARCHAR(50))

	SET NOCOUNT ON
	/* Use parameterized dynamic SQL statements so we don't 
	   have to rely on @@ROWCOUNT, which we might want to 
	   turn off.
	*/

	/*
	 *********************************************************
				     VALIDATE @Database
	 *********************************************************
	*/
	-- Specified database must exist.
	-- Use name of currently connected database if none specified.
	IF @DupeDatabase IS NULL
		BEGIN
			SET @DupeDatabase = DB_NAME()
		END

	SET @SQL = N'SET @RecordsReturned = '
		+ '(SELECT COUNT(*) FROM master.sys.databases ' 
		+ 'WHERE [name] = @DatabaseName)'

	SET @Params = N'@RecordsReturned INT OUTPUT, @DatabaseName VARCHAR(100)'
	EXECUTE sp_executesql 
			@SQL, 
			@Params, 
			@DatabaseName = @DupeDatabase, 
			@RecordsReturned = @ReturnVal OUTPUT 

	IF @ReturnVal = 0
		BEGIN
			SET @Message = 'Database [' + @DupeDatabase + '] does not exist.'
			GOTO EXIT_EARLY
		END		


	/*
	 *********************************************************
				     VALIDATE @DupeSchema
	 *********************************************************
	*/
	-- Specified schema must exist in specified database.
	-- Use 'dbo' schema if none specified.
	-- Dynamic SQL doesn't allow database names as parameters, I believe.
	SET @SQL = N'SET @RecordsReturned = '
			   + '(SELECT COUNT(*) FROM '
	           + '[' + @DupeDatabase + '].sys.schemas '
			   + 'WHERE [name] = @SchemaName)'

	SET @Params = N'@RecordsReturned INT OUTPUT, @SchemaName VARCHAR(100)'

	EXECUTE sp_executesql 
			@SQL,
			@Params,
			@SchemaName = @DupeSchema,
			@RecordsReturned = @ReturnVal OUTPUT 

	IF @ReturnVal = 0
		BEGIN
			SET @Message = 'Schema [' + @DupeSchema + '] does not exist in '
			+ 'database [' + @DupeDatabase + '].'
			GOTO EXIT_EARLY
		END		

	/*
	 *********************************************************
				     VALIDATE @DupeTable
	 *********************************************************
	*/
	-- Specified table must exist in specified database in
	-- specifed schema.
	IF @DupeTable IS NULL
		BEGIN
			SET @Message = '@DupeTable not specified.'
			GOTO EXIT_EARLY
		END

	SET @SQL = N'SET @RecordsReturned = '
		+ '(SELECT COUNT(*) FROM ' 
		+ '[' + @DupeDatabase + '].INFORMATION_SCHEMA.TABLES '
		+ ' WHERE TABLE_NAME = @TableName '
		+ ' AND TABLE_SCHEMA = @SchemaName '
		+ ' AND TABLE_TYPE = ''BASE TABLE'')'

	--PRINT @SQL

	SET @Params = N'@RecordsReturned INT OUTPUT, @TableName VARCHAR(100), @SchemaName VARCHAR(100)'
	
	EXECUTE sp_executesql 
			@SQL,
			@Params,
			@SchemaName = @DupeSchema,
			@TableName = @DupeTable,
			@RecordsReturned = @ReturnVal OUTPUT 


	IF @ReturnVal = 0
		BEGIN
			SET @Message = 'Table [' + @DupeTable + '] '
			+ 'does not exist in schema [' + @DupeSchema + '] '
			+ 'in database [' +@DupeDatabase + '].'
			GOTO EXIT_EARLY
		END

	/*
	 *********************************************************
				     VALIDATE @DupeSFields
	 *********************************************************
	*/
	/* Specified fields must exist in specified table of specified
	   schema of specified database.
	   #BadColumns temp table will hold any columns in @TableFields
	   that do not exist in specified table.
	   Having trouble calling this SP from another database, due
	   to issues with custom type COLUMNLIST. Now @DupeFields
	   parameter is a string of comma delimited field names.
	   Use STRING_SPLIT() to populate @TableFields and then
	   use the EXCEPT query as before.

	   
	*/
	INSERT INTO @TableFields (ColumnName)
	SELECT VALUE 
	FROM STRING_SPLIT(@DupeFields, ',')


	SET @ReturnVal = (SELECT COUNT(*) FROM @TableFields)
	IF @ReturnVal = 0
		BEGIN
			SET @Message = '@TableFields is empty or not specified.'
			GOTO EXIT_EARLY
		END



	DROP TABLE IF EXISTS #BadColumns;

	CREATE TABLE #BadColumns (ColumnName VARCHAR(50));
	
	-- Use CTEs to create more readable queries.
	-- Subtract the list of fields for the specified table in INFORMATION_SCHEMA.TABLES
	-- from the list of fields in @DupeFields. If there are rows in the result set
	-- that means one or more fields in @DupeFields do not exist in specified table.
	SET @SQL = 
	N'DECLARE @TableFields TABLE (ColumnName VARCHAR(50))
	  INSERT INTO @TableFields (ColumnName)
	  SELECT VALUE 
	  FROM STRING_SPLIT(@DupeFields, '','')' 

	+ ';WITH DupeColumns AS
	(
		SELECT 
			[ColumnName]
		FROM @TableFields
	), TableColumns AS
	(
		SELECT 
			[COLUMN_NAME] [ColumnName]
		FROM 
			[' + @DupeDatabase + '].INFORMATION_SCHEMA.COLUMNS

		WHERE
			TABLE_SCHEMA = @SchemaName
			AND
			TABLE_NAME = @TableName
	), MissingColumns AS
	(
		SELECT 
			[ColumnName]
		FROM
			DupeColumns

		EXCEPT

		SELECT 
			[ColumnName]
		FROM
			TableColumns
	)
	INSERT INTO #BadColumns (ColumnName)
	SELECT 
		[ColumnName]
	FROM 
		MissingColumns'

	SET @Params = N'@DupeFields VARCHAR(MAX),
	                @TableName VARCHAR(100), 
					@SchemaName VARCHAR(100)' 
					
	
	EXECUTE sp_executesql 
			@SQL,
			@Params,
			@DupeFields = @DupeFields,
			@SchemaName = @DupeSchema,
			@TableName = @DupeTable
			
				
	SET @ReturnVal = (SELECT COUNT(*) FROM #BadColumns)

	IF @ReturnVal > 0
		BEGIN
			-- Use SELECT...FOR XML and STUFF() to convert
			-- the rows in #BadColumns to a string of 
			-- comma separated values that can be printed.
			DECLARE @ListOfBadColumns VARCHAR(MAX)

			SET @ListOfBadColumns =  
				(SELECT STUFF((SELECT ',' + [ColumnName]
					FROM #BadColumns
					FOR XML PATH('')) ,1,1,'') AS [BadColumns])

			SET @Message = 'The following columns do not exist in table ' 
				  + '[' + @DupeDatabase + '].'
				  + '[' + @DupeSchema + '.'
			      + '[' + @DupeTable + ']: '
				  + @ListOfBadColumns
			GOTO EXIT_EARLY
		END

	/*
	 *********************************************************
		Use Window function ROW_NUMBER() to determine duplicate
		records in the specified table. Partition the records
		based on fields from @DupeFields. If more than one
		record appears in a given partition, it will have
		a ROW_NUMBER() > 1, which means it's a duplicate
		record that can be deleted.
	 *********************************************************
	*/
	/*
	  	Since we need the count of duplicate records in order to determine what, if
	    any, data to delete, will turn the following dynamic SQL into a parameterized
	    procedure. 
	*/
	DECLARE @PartitionFields VARCHAR(MAX)
	SET @PartitionFields =  
				(SELECT STUFF((SELECT ',' + [ColumnName]
					FROM @TableFields
					FOR XML PATH('')) ,1,1,'') AS [ColumnNames])


	SET @SQL =
	N';WITH AnalyzeData AS
	(
		SELECT *,
			[DuplicateCount] =
			ROW_NUMBER()
			OVER
			(
				PARTITION BY ' + @PartitionFields 
			+ ' ORDER BY ' + @PartitionFields  
			+ ') 
		FROM ' +
		'[' + @DupeDatabase + '].'
		+ '[' + @DupeSchema + '].'
		+ '[' +  @DupeTable + ']'
	    + ')'
	    + 'SELECT @RecordsReturned = COUNT(*)
		  FROM AnalyzeData
		  WHERE [DuplicateCount] > 1'
	--PRINT @SQL
	SET @Params = N'@RecordsReturned INT OUTPUT'

	EXECUTE sp_executesql 
		@SQL,
		@Params,
		@RecordsReturned = @ReturnVal OUTPUT

	IF @ReturnVal > 0
		BEGIN
		-- Use a modified version of the dynamic SQL code above to actually delete
		-- the records. Wrap the statement in a transaction and use TRY/CATCH
		-- to undo any changes if errors occur.
		--------------------------------------------------------------------
		BEGIN TRANSACTION
		BEGIN TRY
			SET @SQL =
			N';WITH AnalyzeData AS
			(
				SELECT *,
					[DuplicateCount] =
					ROW_NUMBER()
					OVER
					(
						PARTITION BY ' + @PartitionFields 
					+ ' ORDER BY ' + @PartitionFields  
					+ ') 
				FROM ' +
				'[' + @DupeDatabase + '].'
				+ '[' + @DupeSchema + '].'
				+ '[' +  @DupeTable + ']'
				+ ')'
				+ 'DELETE FROM AnalyzeData
					WHERE [DuplicateCount] > 1'

			EXECUTE(@SQL)
		END TRY

		BEGIN CATCH
			SET @Message = ERROR_MESSAGE()
			PRINT @Message
			ROLLBACK TRANSACTION

			SET @Message = 'Unable to delete records from table.'
			GOTO EXIT_EARLY
		END CATCH

	COMMIT TRANSACTION
	--------------------------------------------------------------------
			PRINT FORMAT(@ReturnVal, 'N0') + ' records have been deleted.'
		END
	ELSE
		BEGIN
			PRINT 'No duplicate records found. No records will be deleted.'
		END


	RETURN 0

	/*
	 *********************************************************
		Clean up, generate message, and exit for bad inputs
	 *********************************************************
	*/
EXIT_EARLY:
	DROP TABLE IF EXISTS #BadColumns;
	PRINT @Message
	SET NOCOUNT OFF
	RETURN 1

END

/*
  NO LONGER USING CUSTOM TYPE. @DupeFields is now a comma delimited
  list of field names.
 Test SP and test TYPE
 When testing SP with empty @Fields variable:
 DupeFields is empty or not specified.
 Cannot pass NULL for @DupeFields as this generates
 a syntax error.
 DECLARE @Fields COLUMNLIST
 INSERT INTO @Fields(ColumnName)
 VALUES
('City'),
('PostalCode')
--SELECT * FROM @Fields
*/

DECLARE @Return_Val INT

EXECUTE @Return_Val = 
		dbo.DeDupeTable 
		@DupeDatabase = 'DB_Temp', 
		@DupeSchema = 'Hogwarts', 
		@DupeTable = 'City',
		@DupeFields = 'City,PostalCode'

SELECT @Return_Val [SP RETURN CODE]
-- The following result was obtained using dynamic SQL:
--The following columns do not exist in table [City]: FakeField1,FakeField2,FakeField3
-- Sample dynamic SQL generated by SP to determine (but not delete) duplicate records
/*
;WITH CountDuplicates AS
	(
		SELECT *,
			[DuplicateCount] =
			ROW_NUMBER()
			OVER
			(
				PARTITION BY City,PostalCode ORDER BY City,PostalCode) 
		FROM [DB_Temp].[Hogwarts].[City])
	SELECT * FROM CountDuplicates

*/

--SELECT * FROM [DB_Temp].Hogwarts.Customer WHERE [FirstName] = 'Harry'
--SELECT @@ROWCOUNT [ROW_COUNT]
--SELECT * FROM [DB_Temp].INFORMATION_SCHEMA.TABLES

--DECLARE @Result INT

SET @Result = (SELECT 
					COUNT(*) 
               FROM 
					[DB_Temp].INFORMATION_SCHEMA.TABLES 
			   WHERE 
					[TABLE_NAME] = 'ThisTableDoesNotExist')
SELECT @Result [Records Returned]
----------------------------------------------
GO
DECLARE @Result INT
DECLARE @SchemaName VARCHAR(100) = 'Hogwarts'
DECLARE @TableName VARCHAR(100) = 'City'
SET @Result = (
				SELECT COUNT(*) 
				FROM 
					[DB_Temp].INFORMATION_SCHEMA.TABLES  
				WHERE 
					TABLE_NAME = @TableName  
					AND TABLE_SCHEMA = @SchemaName  
					AND TABLE_TYPE = 'BASE TABLE'
					)


SELECT @Result [Records Returned]

--SELECT * FROM [DB_Temp].INFORMATION_SCHEMA.TABLES  

SELECT * FROM [DB_Temp].INFORMATION_SCHEMA.COLUMNS
SELECT DB_NAME()