THIRD CHALLENGE:
Create a stored procedure called oes.transferFunds that
transfers money from one bank account to another bank
account by updating the balance column in the
oes.bank_accounts table. Also, insert the bank transaction
details into oes.bank_transactions table. Define three input
parameters:
- @withdraw_account_id of data type INT
- @deposit_account_id of data type INT
- @transfer_amount of data type DECIMAL(30,2)
Test the stored procedure by transferring $100 from Anna’s
bank account to Bob’s account.

*/
IF OBJECT_ID(N'oes.transferFunds', N'P') IS NOT NULL
	BEGIN
		DROP PROCEDURE  oes.transferFunds
	END

GO
CREATE PROCEDURE  oes.transferFunds
(
	@withdraw_account_id INT,
	@deposit_account_id INT,
	@transfer_amount DECIMAL(30,2)

)
AS

BEGIN
	--Validate withdraw account
	IF @withdraw_account_id IS NULL
		BEGIN
			PRINT 'Invalid withdraw account id.'
			RETURN 1
		END

	IF @withdraw_account_id <= 0
		BEGIN
			PRINT 'Invalid withdraw account id.'
			RETURN 1
		END

	-- Does specified withdraw account exist?
	IF NOT EXISTS(	SELECT 1 
					FROM 
						[oes].[bank_accounts] 
					WHERE 
						[account_id] = @withdraw_account_id
				)
		BEGIN
			PRINT 'Withdraw account id ' 
				  + FORMAT(@withdraw_account_id, 'N0')
				  + ' does not exist.'
			RETURN 1
		END
	
	-- Validate deposit account
	IF @deposit_account_id IS NULL
		BEGIN
			PRINT 'Invalid deposit account id.'
			RETURN 1
		END

	IF @deposit_account_id <= 0
		BEGIN
			PRINT 'Invalid deposit account id.'
			RETURN 1
		END

	-- Does specified deposit account exist?
	IF NOT EXISTS(	SELECT 1 
					FROM 
						[oes].[bank_accounts] 
					WHERE 
						[account_id] = @deposit_account_id
				)
		BEGIN
			PRINT 'Deposit account id ' 
				  + FORMAT(@deposit_account_id, 'N0')
				  + ' does not exist.'
			RETURN 1
		END

	-- Validate transfer amount
	IF @transfer_amount IS NULL
		BEGIN
			PRINT 'Invalid transfer amount.'
			RETURN 1
		END

	IF @transfer_amount <= 0
		BEGIN
			PRINT 'Invalid transfer amount.'
			RETURN
		END

	-- Don't allow transactions where withdraw account and deposit account
	-- are the same
	IF @withdraw_account_id = @deposit_account_id
		BEGIN
			PRINT 'Withdraw account and deposit account are the same. Invalid transaction.'
			RETURN 1
		END

	-- Don't allow withdrawals greater than current balance of 
	-- withdraw account
	DECLARE @withdraw_balance DECIMAL(30,2)
	SET @withdraw_balance = (
								SELECT [balance] 
								FROM
									[oes].[bank_accounts] 
								WHERE 
									[account_id] = @withdraw_account_id
							)


	IF @transfer_amount > @withdraw_balance
		BEGIN
			PRINT 'Transfer amount (' 
				+ FORMAT(@transfer_amount, 'C2') + ')'
				+ ' is greater than the current balance ('
				+ FORMAT(@withdraw_balance, 'C2')  + ')'
				+ ' for account id ' + FORMAT(@withdraw_account_id, 'N0') + '.'
			RETURN 1
		END



	BEGIN TRANSACTION
		BEGIN TRY
			-- Deduct the transfer amount from the withdraw account
			-- balance and increment the deposit account balance
			UPDATE [oes].[bank_accounts]
			SET [balance] -= @transfer_amount
			WHERE [account_id] = @withdraw_account_id

			UPDATE [oes].[bank_accounts]
			SET [balance] += @transfer_amount
			WHERE [account_id] = @deposit_account_id

			-- Record transaction in bank transactions table
			INSERT INTO [oes].[bank_transactions]
			(
				[from_account_id],
				[to_account_id],
				[amount]
			)
			VALUES 
			(
				@withdraw_account_id,
				@deposit_account_id,
				@transfer_amount
			)
		END TRY

		BEGIN CATCH
			DECLARE @err_message VARCHAR(MAX)
			SET @err_message =  ERROR_MESSAGE()
			PRINT @err_message
			ROLLBACK TRANSACTION
			PRINT 'Transaction cancelled.'
			RETURN 1
		END CATCH

	COMMIT TRANSACTION
	PRINT 'Transaction completed.'

	RETURN 0

END;

GO
DECLARE @return_code INT
EXEC @return_code = 
	oes.transferFunds 
		@withdraw_account_id = 1, 
		@deposit_account_id = 2, 
		@transfer_amount = 100
SELECT @return_code [return_code]
--Transaction completed.
--return_code
--0

GO
DECLARE @return_code INT
EXEC @return_code = 
	oes.transferFunds 
		@withdraw_account_id = -3, 
		@deposit_account_id = 2, 
		@transfer_amount = 100
SELECT @return_code [return_code]
--Invalid withdraw account id.
--return_code
--1

GO
DECLARE @return_code INT
EXEC @return_code = 
	oes.transferFunds 
		@withdraw_account_id = 3, 
		@deposit_account_id = 2, 
		@transfer_amount = 9500
SELECT @return_code [return_code]
--Transfer amount ($9,500.00) is greater than the current balance ($2,800.00) for acount id 3.
--return_code
--1

GO
DECLARE @return_code INT
EXEC @return_code = 
	oes.transferFunds 
		@withdraw_account_id = 4, 
		@deposit_account_id = 4, 
		@transfer_amount = 200
SELECT @return_code [return_code]
--Withdraw account and deposit account are the same. Invalid transaction.
--return_code
--1