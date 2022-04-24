--------------------------------------------------------------------------------
-- A Work Project, presented as part of the requirements for the course
-- Managing Relational & Non-Relational Databases 
-- 
-- Post-Graduation in Enterprise Data Science & Analytics from the 
-- NOVA – Information Management School
-- 
-- RELATIONAL DATA: 
-- STOCK CLEARANCE & BRICK AND MORTAR STORES
--
-- Francisco Costa, 20181393
-- João Gouveia, 20181399
-- Nuno Rocha, 20181407
-- Pedro Rivera, 20181411
--
--------------------------------------------------------------------------------
--
-- auction.sql Script
--
--------------------------------------------------------------------------------
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
USE [AdventureWorks]
GO
--------------------------------------------------------------------------------
-- SCHEMA CONFIGURATION
--------------------------------------------------------------------------------
-- Create the Schema if it does not exist
--------------------------------------------------------------------------------
IF NOT EXISTS (SELECT DB_NAME() AS dbname WHERE SCHEMA_ID('Auction') IS NOT NULL)
	BEGIN
	IF NOT EXISTS (SELECT TOP(1) * FROM sys.schemas WHERE name='Auction')
	-- Create the Schema
		BEGIN
			PRINT 'The Schema Auction is missing, so it will be created with all the required tables.';
			EXEC sp_executesql N'CREATE SCHEMA Auction AUTHORIZATION dbo';
		END
	END
GO

IF (OBJECT_ID('Auction.ProductBid') IS NOT NULL)
BEGIN 
	DROP TABLE [Auction].[ProductBid]
END
GO

IF (OBJECT_ID('Auction.Product') IS NOT NULL)
BEGIN
	DROP TABLE [Auction].[Product]
END
GO

IF (OBJECT_ID('Auction.ThresholdsConfig') IS NOT NULL)
BEGIN
	DROP TABLE [Auction].[ThresholdsConfig]
END
GO

--------------------------------------------------------------------------------
-- TABLE CREATION
--------------------------------------------------------------------------------
-- Table Auction.Product
--------------------------------------------------------------------------------
BEGIN
	CREATE TABLE [Auction].[Product]
	(
		[AuctionProductID] [int] NOT NULL IDENTITY PRIMARY KEY,
		[ProductID] [int] NOT NULL,
		[ExpireDate] [datetime] NULL,
		[AuctionStatus] [bit] NOT NULL,
		[Removed] [bit] NULL,
		[InitialBidPrice] [money] NULL,
		[InitialListPrice] [money] NULL,
		[StandardCost] [money] NULL
	) ON [PRIMARY]

	ALTER TABLE [Auction].[Product]  WITH CHECK ADD  CONSTRAINT [FK_ProductAuction_Product] FOREIGN KEY([ProductID])
	REFERENCES [Production].[Product] ([ProductID])

	ALTER TABLE [Auction].[Product] ADD CONSTRAINT [DF_ProductAuction_AuctionStatus] DEFAULT ((1)) FOR [AuctionStatus]

	ALTER TABLE [Auction].[Product] ADD CONSTRAINT [DF_ProductAuction_Removed] DEFAULT ((0)) FOR [Removed]

	PRINT 'The Table Product was created on the Auction Schema.';
END

--------------------------------------------------------------------------------
-- Table Auction.ProductBid
--------------------------------------------------------------------------------
BEGIN
	CREATE TABLE [Auction].[ProductBid]
	(
		[AuctionProductID] [int] NOT NULL,
		[ProductID] [int] NULL,
		[CustomerID] [int] NULL,
		[BidAmmount] [money] NULL,
		[BidTimestamp] [datetime] NOT NULL
	) ON [PRIMARY]

	ALTER TABLE [Auction].[ProductBid]  WITH CHECK ADD CONSTRAINT [FK_ProductAuctionBid_Customer] FOREIGN KEY([CustomerID])
	REFERENCES [Sales].[Customer] ([CustomerID])

	ALTER TABLE [Auction].[ProductBid]  WITH CHECK ADD  CONSTRAINT [FK_ProductAuctionBid_Product] FOREIGN KEY([AuctionProductID])
	REFERENCES [Auction].[Product] ([AuctionProductID])

	PRINT 'The Table ProductBid was created on the Auction Schema.';
END

--------------------------------------------------------------------------------
-- Table Auction.ConfigParameters
--------------------------------------------------------------------------------
BEGIN
	CREATE TABLE [Auction].[ThresholdsConfig]
	(
		[Setting] [varchar](50) NOT NULL,
		[Value] [sql_variant] NOT NULL
	) ON [PRIMARY]

	PRINT 'The Table ThresholdsConfig was created with the default settings on the Auction Schema.';

	-- Pre populate the setting MinIncreaseBid
	INSERT INTO [Auction].[ThresholdsConfig] ([Setting], [Value]) VALUES ('MinIncreaseBid', CAST(0.05 as money))

	-- Pre populate the setting MaxBidLimit as a percentage relative to the initial product listed price
	INSERT INTO [Auction].[ThresholdsConfig] ([Setting], [Value]) VALUES ('MaxBidLimit', CAST(1.0 as real))
END
GO

--------------------------------------------------------------------------------
-- STORED PROCEDURES
--------------------------------------------------------------------------------
-- uspAddProductToAuction
--------------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE [Auction].[uspAddProductToAuction]
(
	@ProductID int,
	@ExpireDate datetime = NULL,
	@InitialBidPrice money = NULL
)
AS
-- Variable to store current timestamp
DECLARE @CurrentTimestamp datetime2 = GETDATE();
-- Variables to store aux values from [Production].[Product]
DECLARE @P_ProductID int = NULL;
DECLARE @SellStartDate datetime = NULL;
DECLARE @SellEndDate datetime = NULL;
DECLARE @DiscontinuedDate datetime = NULL;
DECLARE @ProductSubcategoryID int = NULL
DECLARE @MakeFlag bit = NULL;
-- Variables to store aux values from [Production].[ProductListPriceHistory]
DECLARE @InitialListPrice money = NULL;
DECLARE @ActualListPrice money = NULL;
DECLARE @Min_InitialBidPrice money = NULL;
DECLARE @Max_InitialBidPrice money = NULL;
-- Variables to store aux values from [Production].[ProductCostHistory]
DECLARE @ActualStandardCost money = NULL;
BEGIN TRY
	SELECT  @P_ProductID = [ProductID],
			 @SellStartDate = [SellStartDate],
			  @SellEndDate = [SellEndDate],
			   @DiscontinuedDate = [DiscontinuedDate],
			    @ProductSubcategoryID = [ProductSubcategoryID],
			     @MakeFlag = [MakeFlag]
	FROM
	(
	SELECT [ProductID],
			[SellStartDate],
			 [SellEndDate],
			  [DiscontinuedDate],
				[ProductSubcategoryID],
				 [MakeFlag]
	FROM [Production].[Product]
	WHERE [ProductID] = @ProductID
	) AS p_p

	-- Check if the @ProductID exists
	IF @P_ProductID IS NULL
		BEGIN
			DECLARE @errormessage1 VARCHAR(150) = 'Error uspAddProductToAuction@ProductID: The submitted @ProductID does not exist.';
			THROW 50001, @errormessage1, 0;
		END

	-- Check if the @ProductID is already being auctioned
	ELSE IF EXISTS (
					SELECT [ProductID]
					FROM [Auction].[Product]
					WHERE [ProductID] = @ProductID 
						AND [AuctionStatus] = 1
					) 
		BEGIN
			DECLARE @errormessage2 VARCHAR(150) = 'Error uspAddProductToAuction@ProductID: There is already an active auction for the submitted @ProductID.';
			THROW 50002, @errormessage2, 0;
		END

	-- Check if the @ProductID is from a valid category (Product category different than Accessories and non-null)
	ELSE IF @ProductSubcategoryID IS NULL OR 
		(
			(
				SELECT p_pc.[Name] 
				FROM [Production].[ProductSubcategory] AS p_ps
				INNER JOIN [Production].[ProductCategory] AS p_pc
				ON p_ps.[ProductCategoryID] = p_pc.[ProductCategoryID]
				WHERE p_ps.[ProductSubcategoryID] = @ProductSubcategoryID
			) = N'Accessories'
		)
		BEGIN
			DECLARE @errormessage3 VARCHAR(150) = CONCAT('Error uspAddProductToAuction: The product with the ID ', CONVERT(varchar(10), @ProductID), ' is not from a valid Category.');
			THROW 50003, @errormessage3, 0;
		END
	ELSE
		BEGIN
		-- Set the default value for the @ExpireDate
		SET @ExpireDate = COALESCE(@ExpireDate, DATEADD(WEEK,1,GETDATE()));
		BEGIN
		IF NOT(@ExpireDate BETWEEN CONVERT(datetime, CONCAT(YEAR(@CurrentTimestamp),'1117'), 112) AND CONVERT(datetime, CONCAT(YEAR(@CurrentTimestamp),'1207'), 112))
			BEGIN
				DECLARE @errormessage4 VARCHAR(200) = 'Error uspAddProductToAuction@ExpireDate: The @ExpireDate can only be placed in the last 2 weeks of November + 1 week margin for the current year.';
				THROW 50004, @errormessage4, 0;
			END
		ELSE
			BEGIN
				-- Get the minimum and maximum values for the @InitialBidPrice (considering the @CurrentTimestamp when invoked)
				SELECT @ActualListPrice = [ListPrice] 
					FROM
					(
						SELECT TOP(1) p_plph.[ListPrice] 
						FROM [Production].[ProductListPriceHistory] AS p_plph
						WHERE p_plph.[ProductID] = @ProductID
							AND (@CurrentTimestamp BETWEEN COALESCE(p_plph.[StartDate], CONVERT(datetime, '20110101', 112)) AND COALESCE(p_plph.[EndDate], CONVERT(datetime, '99991231', 112)))
						ORDER BY p_plph.[StartDate] DESC
					) AS temp_ActualListPrice

				SELECT @InitialListPrice = [ListPrice] 
					FROM
					(
						SELECT TOP(1)  p_plph.[ListPrice] 
						FROM [Production].[ProductListPriceHistory] AS  p_plph
						WHERE  p_plph.[ProductID] = @ProductID
						ORDER BY [StartDate] ASC
					) AS temp_InitialListPrice
				
				-- Set the initial bid price based on the @MakeFlag property
				SELECT @Min_InitialBidPrice = [Min_InitialBidPrice], 
						@Max_InitialBidPrice = [Max_InitialBidPrice]
				FROM 
				( 
					SELECT
						CASE WHEN @MakeFlag = 0 
							THEN @ActualListPrice*0.75
							ELSE @ActualListPrice*0.5
						END AS [Min_InitialBidPrice],
						@ActualListPrice AS [Max_InitialBidPrice]
				) AS temp_BidPrice;

				BEGIN
					-- Check if the @InitialBidPrice is in the valid range
					-- Cannot be lower than the minimum bid price
					IF @InitialBidPrice < @Min_InitialBidPrice
					BEGIN
						DECLARE @errormessage5 VARCHAR(150) = CONCAT('Error uspAddProductToAuction@InitialBidPrice: The submitted @InitialBidPrice must be greater than ', CAST(@Min_InitialBidPrice AS VARCHAR(30)),'.');
						THROW 50005, @errormessage5, 0;
					END
					-- Cannot be higher than the maximum bid price
					ELSE IF @InitialBidPrice > @Max_InitialBidPrice
						BEGIN
							DECLARE @errormessage6 VARCHAR(150) = CONCAT('Error uspAddProductToAuction@InitialBidPrice: The submitted @InitialBidPrice must be less than the list price of ', CAST(@Max_InitialBidPrice AS VARCHAR(30)),'.');
							THROW 50006, @errormessage6, 0;
						END
					ELSE
						BEGIN
							-- If the @InitialBidPrice was not defined then use the default value @Min_InitialBidPrice
							SET @InitialBidPrice = COALESCE(@InitialBidPrice, @Min_InitialBidPrice);

							-- Get the @ProductID actual standard cost (considering the @CurrentTimestamp)
							SELECT @ActualStandardCost = [StandardCost] 
							FROM
							(
								SELECT p_pch.[StandardCost] 
								FROM [Production].[ProductCostHistory] AS p_pch
								WHERE p_pch.[ProductID] = @ProductID
									AND (@CurrentTimestamp BETWEEN p_pch.[StartDate] 
									AND COALESCE(p_pch.[EndDate], CONVERT(datetime, '99991231', 112)))
							) AS sc

							-- Check for further Functional Specification requisites
							-- @ProductID is being commercialized (considering the @CurrentTimestamp)
							BEGIN
							IF (@CurrentTimestamp < @SellStartDate) OR (@SellEndDate IS NOT NULL AND @CurrentTimestamp > @SellEndDate) OR (@DiscontinuedDate IS NOT NULL AND @CurrentTimestamp > @DiscontinuedDate)
								BEGIN
									DECLARE @errormessage7 VARCHAR(150) = CONCAT('Error uspAddProductToAuction: The product with the ID ',  CONVERT(varchar(10), @ProductID),' is not currently being commercialized @', CONVERT(char(10), @CurrentTimestamp,126), '.');
									THROW 50007, @errormessage7, 0;
								END

							-- @ProductID costs more than 50$
							ELSE IF @ActualStandardCost <= 50
								BEGIN
									DECLARE @errormessage8 VARCHAR(150) = CONCAT('Error uspAddProductToAuction: The product with the ID ', CONVERT(varchar(10), @ProductID), ' does not have a cost over 50$ to be eligible for auction.');
									THROW 50008, @errormessage8, 0;
								END

							-- Check if the product is available on the inventory
							ELSE IF NOT EXISTS (SELECT [ProductID]
										FROM [Production].[ProductInventory]
										WHERE [ProductID] = @ProductID
											AND (@CurrentTimestamp > [ModifiedDate])
											AND [Quantity] >= 1)
								BEGIN
									DECLARE @errormessage9 VARCHAR(150) = CONCAT('Error uspAddProductToAuction: The product with the ID ', CONVERT(varchar(10), @ProductID), ' is not available on the inventory @', CONVERT(char(10), @CurrentTimestamp,126), '.');
									THROW 50009, @errormessage9, 0;
								END	
							END
						END
				END
			END
		END
	END
BEGIN
	BEGIN TRANSACTION
		-- Add @ProductID to auction
		INSERT INTO [Auction].[Product] 
		(
			[ProductID],
			 [ExpireDate],
			  [InitialBidPrice],
			    [InitialListPrice],
				 [StandardCost] 
		)
		VALUES 
		(
			@ProductID,
			 @ExpireDate,
			  @InitialBidPrice,
			    @InitialListPrice, 
				 @ActualStandardCost
		);
	COMMIT TRANSACTION
END
RETURN
END TRY
BEGIN CATCH
	IF @@TRANCOUNT > 0
		BEGIN 
			ROLLBACK TRANSACTION
		END
	ELSE
		BEGIN
			PRINT ERROR_MESSAGE();
		END
END CATCH
GO

--------------------------------------------------------------------------------
-- uspTryBidProduct
--------------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE [Auction].[uspTryBidProduct]
(
	@ProductID int,
	@CustomerID int,
	@BidAmmount money = NULL
)
AS
-- Variable to store current timestamp
DECLARE @BidTimestamp datetime2 = GETDATE();
-- Variables to store aux values from [Auction].[ThresholdsConfig]
DECLARE @MinIncreaseBid money = NULL;
DECLARE @MaxBidLimit real = NULL;
-- Variables to store aux values from [Auction].[Product]
DECLARE @AuctionProductID int = NULL;
DECLARE @BidProductID int = NULL;
DECLARE @ExpireDate datetime = NULL;
DECLARE @InitialBidPrice money = NULL;
DECLARE @InitialListPrice money = NULL;
-- Variables to store aux values from [Auction].[ProductBid]
DECLARE @LatestBid money = NULL;
DECLARE @Update bit = 0;
BEGIN TRY
	-- Store the details for @ProductID auction in the aux variables
	SELECT @AuctionProductID = [AuctionProductID],
			@BidProductID = [ProductID],
			 @ExpireDate = [ExpireDate],
			  @InitialBidPrice = [InitialBidPrice],
			   @InitialListPrice = [InitialListPrice]
	FROM
	(
	SELECT [AuctionProductID], 
			[ProductID],
			 [ExpireDate],
			  [InitialBidPrice],
			   [InitialListPrice]
	FROM [Auction].[Product]
	WHERE [ProductID] = @ProductID
		AND [AuctionStatus] = 1
	) AS temp_Bid

	BEGIN
	-- Check if the @ProductID is being auctioned
	IF @BidProductID IS NULL
		BEGIN
			DECLARE @errormessage1 VARCHAR(150) = 'Error uspTryBidProduct@ProductID: The submitted @ProductID is not currently being auctioned.';
			THROW 50101, @errormessage1, 0;
		END
	ELSE
		BEGIN
		-- Check if the @CustomerID is valid
		IF NOT EXISTS (
			SELECT [CustomerID] 
			FROM [Sales].[Customer] 
			WHERE [CustomerID] = @CustomerID
			)
			BEGIN
				DECLARE @errormessage2 VARCHAR(150) = 'Error uspTryBidProduct@CustomerID: The submitted @CustomerID does not exist.';
				THROW 50102, @errormessage2, 0;
			END
		ELSE
			BEGIN
			-- Check if the auction has expired for the specified @ProductID
			IF (@BidTimestamp > @ExpireDate)
				BEGIN
					DECLARE @errormessage3 VARCHAR(150) = CONCAT('Error uspTryBidProduct: The Auction for the product with the ID ', CONVERT(varchar(10), @ProductID), ' has expired.');
					THROW 50103, @errormessage3, 0;
				END
			ELSE
				BEGIN
					-- Check if there is already a bid made on the product (it does not matter if it was not done by the current customer)
					SELECT @LatestBid = [BidAmmount]
					FROM
					(
					SELECT TOP(1) [BidAmmount]
					FROM [Auction].[ProductBid]
					WHERE [ProductID] = @ProductID
						AND [AuctionProductID] = @AuctionProductID
					ORDER BY [BidAmmount] DESC
					) AS lbid

					-- Verify the bid value against the configuration parameters in the ThresholdConfig table
					SELECT @MinIncreaseBid = CAST([Value] as money) 
					FROM (SELECT [Value] FROM [Auction].[ThresholdsConfig] 
					WHERE [Setting] = N'MinIncreaseBid') as q_thresh;

					SELECT @MaxBidLimit = CAST([Value] as real) 
					FROM (SELECT [Value] FROM [Auction].[ThresholdsConfig] 
					WHERE [Setting] = N'MaxBidLimit') as q_thresh;
					
					-- If the bid ammount is not specified (@BidAmmount = NULL) increase the bid by the minimum threshold (@MinIncreaseBid)
					IF @BidAmmount IS NULL 
						BEGIN
						SET @BidAmmount = COALESCE(@LatestBid + @MinIncreaseBid, @InitialBidPrice);
						END
					BEGIN

					-- Check if the @BidAmmount is within range
					IF(@BidAmmount > ROUND(@InitialBidPrice + (@MaxBidLimit * @InitialListPrice), 1) + @MinIncreaseBid)
						BEGIN
							DECLARE @errormessage4 VARCHAR(150) = 'Error uspTryBidProduct@BidAmount: The @BidAmount should not exceed the maximum limit threshold.';
							THROW 50104, @errormessage4, 0;
						END

					-- Check if the Maximum Bid Limit (@MaxBidLimit) was reached (and flag the @Update variable)
					ELSE IF (
						@BidAmmount BETWEEN ROUND(@InitialBidPrice + (@MaxBidLimit * @InitialListPrice), 1) - @MinIncreaseBid 
						AND ROUND(@InitialBidPrice + (@MaxBidLimit * @InitialListPrice), 1) + @MinIncreaseBid
						)
						BEGIN
							-- Flag the @Update variable to end the auction
							SET @Update = 1;
						END

					-- Check if there is a minimum increase for @BidAmmount
					ELSE IF @BidAmmount < (COALESCE(@LatestBid + @MinIncreaseBid, @InitialBidPrice))
						BEGIN
							DECLARE @errormessage5 VARCHAR(150) = CONCAT('Error uspTryBidProduct@BidAmount: The @BidAmount must respect the minimum increase bid of ', CONVERT(varchar(10), @MinIncreaseBid), '.');
							THROW 50105, @errormessage5, 0;
						END
					END
				END
			END
		END
	END
BEGIN
	BEGIN TRANSACTION
		-- Bid on behalf of @CustomerID
		INSERT INTO [Auction].[ProductBid] 
		(
			[AuctionProductID],
			 [ProductID],
			  [CustomerID],
			   [BidAmmount],
			    [BidTimestamp]
		)
		VALUES 
		(
			@AuctionProductID,
			 @ProductID,
			  @CustomerID,
			   @BidAmmount,
			    @BidTimestamp
		);
		-- End auction for @ProductID if the MaxBidLimit was reached (@Update = 1)
		IF @Update = 1
			BEGIN
				UPDATE [Auction].[Product]
				SET [AuctionStatus] = 0
				WHERE [ProductID] = @BidProductID
					AND [AuctionStatus] = 1;
			END
	COMMIT TRANSACTION
END
RETURN
END TRY
BEGIN CATCH
	IF @@TRANCOUNT > 0
		BEGIN 
			ROLLBACK TRANSACTION
		END
	ELSE
		BEGIN
			PRINT ERROR_MESSAGE();
		END
END CATCH
GO

--------------------------------------------------------------------------------
-- uspRemoveProductFromAuction
--------------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE [Auction].[uspRemoveProductFromAuction]
(
	@ProductID int
)
AS
BEGIN TRY
	BEGIN
		-- Check if there is any active auction (AuctionStatus = 1) for the specified ProductID
		IF NOT EXISTS (
			SELECT [ProductID] 
			FROM [Auction].[Product] 
			WHERE [ProductID] = @ProductID AND [AuctionStatus] = 1
			)
			BEGIN
				DECLARE @errormessage1 VARCHAR(150) = 'Error uspRemoveProductFromAuction@ProductID: The submitted @ProductID is not currently being auctioned.';
				THROW 50201, @errormessage1, 0;
			END
		END
		BEGIN
			BEGIN TRANSACTION
				-- Disable the auction (AuctionStatus = 0) and flag it as cancelled (Removed = 1)
				UPDATE [Auction].[Product]
				SET [AuctionStatus] = 0,
					[Removed] = 1
				WHERE [ProductID] = @ProductID AND [AuctionStatus] = 1;
			COMMIT TRANSACTION
	END
	RETURN
END TRY
BEGIN CATCH
	IF @@TRANCOUNT > 0
		BEGIN 
			ROLLBACK TRANSACTION
		END
	ELSE
		BEGIN
			PRINT ERROR_MESSAGE();
		END
END CATCH
GO

--------------------------------------------------------------------------------
-- uspSearchForAuctionBasedOnProductName
--------------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE [Auction].[uspSearchForAuctionBasedOnProductName]
(
	@Productname nvarchar(50),
	@StartingOffSet int = 0,
	@NumberOfRows int = 2147483647
)
AS
-- Default Parameters
-- @StartingOffSet: No offset (default is 0)
-- @NumberOfRows: All rows (default is 2147483647 which represents the maximum value for a integer type)

-- Apply a wildcard search for @Productname based on its character count.
-- Disable the wildcard search for a character count that contains less than 3 characters.
-- Returns all rows if the previous condition is applicable.
WITH temp_AucProd AS 
	(
		SELECT  a_p.[ProductID],
				 [Name],
				  [ProductNumber],
				   [Color],
				    [Size],
					 [SizeUnitMeasureCode],
					  [WeightUnitMeasureCode],
					   [Weight],
					    [Style],
						 [ProductSubcategoryID],
						  [ProductModelID],
							cbid.CurrentBid,
								CASE
								WHEN a_p.[Removed] = 1 THEN 'Canceled Auction'
								WHEN a_p.[AuctionStatus] = 0 THEN 'Closed Auction'
								ELSE 'Active Auction'
								END AS AuctionStatus
		FROM [Auction].[Product] AS a_p
		LEFT JOIN [Production].[Product] AS p_p
		ON a_p.ProductID = p_p.[ProductID]
		LEFT JOIN 
			(
			-- Get the current bid
			SELECT 
				[AuctionProductID]
				,MAX([BidAmmount]) AS CurrentBid
			FROM [Auction].[ProductBid]
			GROUP BY [AuctionProductID]
			) AS cbid
		ON a_p.[AuctionProductID] = cbid.[AuctionProductID]
		-- Apply wildcard search if character count of @Productname is greater or equal than 3
		WHERE (LEN(@Productname) < 3) OR ([Name] LIKE N'%' + @Productname + '%')
	),
		-- Total number of entries ignoring @StartingOffset and @NumberOfRows
		TotalCount AS (
						SELECT COUNT([ProductID]) AS TotalCount 
						FROM temp_AucProd
						)
SELECT *
FROM temp_AucProd, TotalCount
ORDER BY [ProductID]
OFFSET @StartingOffSet ROWS
FETCH NEXT @NumberOfRows ROWS ONLY;
BEGIN
	-- Display a warning to inform that wildcard search was not applied (due to @Productname character count).
	IF LEN(@Productname) < 3
		BEGIN
			PRINT N'All results were returned. Wildcard search are not acceptable for @Productname with less than 3 characters.'
		END
	END
GO

--------------------------------------------------------------------------------
-- uspListBidsOffersHistory
--------------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE [Auction].[uspListBidsOffersHistory]
(
	@CustomerID int,
	@StartTime datetime,
	@EndTime datetime,
	@Active bit = 1
)
AS
BEGIN TRY
	BEGIN
	-- Check if there are any bids from CustomerID
	IF NOT EXISTS (
		SELECT [CustomerID] 
		FROM [Auction].[ProductBid] 
		WHERE [CustomerID] = @CustomerID
		)
		BEGIN
			DECLARE @errormessage1 VARCHAR(150) = 'Error uspListBidsOffersHistory@CustomerID: The submitted @CustomerID did not make any bid.';
			THROW 50401, @errormessage1, 0;
		END
	-- Check for a valid time range (@EndTime > @StartTime)
	ELSE IF @EndTime <= @StartTime
		BEGIN
			DECLARE @errormessage2 VARCHAR(150) = 'Error uspListBidsOffersHistory@StartTime & @EndTime: The @EndTime must be greater than the @StartTime.';
			THROW 50402, @errormessage2, 0;
		END
	ELSE
		BEGIN
			-- Return customer bid history sorted by date (BidTimestamp)
			-- @Active = 1 returns active auctions
			-- @Active = 0 returns all auctions
			SELECT  a_pb.[AuctionProductID],
					 a_pb.[ProductID],
					  [CustomerID],
					   [BidAmmount],
					    [BidTimestamp],
						CASE
							WHEN a_p.[Removed] = 1 THEN 'Canceled Auction'
							WHEN a_p.[AuctionStatus] = 0 THEN 'Closed Auction'
						ELSE 'Active Auction'
						END AS AuctionStatus
			FROM [Auction].[ProductBid] as a_pb
			LEFT JOIN [Auction].[Product] as a_p
			ON a_pb.[AuctionProductID] = a_p.[AuctionProductID]
			WHERE a_pb.[CustomerID] = @CustomerID AND
				(a_pb.[BidTimestamp] BETWEEN @StartTime AND @EndTime) AND
				(a_p.[AuctionStatus] = @Active OR @Active = 0)
			ORDER BY [BidTimestamp] DESC;
		END
	END
RETURN
END TRY
BEGIN CATCH
	IF @@TRANCOUNT > 0
		BEGIN 
			ROLLBACK TRANSACTION
		END
	ELSE
		BEGIN
			PRINT ERROR_MESSAGE();
		END
END CATCH
GO
--------------------------------------------------------------------------------
-- uspUpdateProductAuctionStatus
--------------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE [Auction].[uspUpdateProductAuctionStatus]
AS
	-- Check for active auctions (AuctionStatus = 1) and close the ones that expired (ExpireDate)
	UPDATE [Auction].[Product]
	SET [AuctionStatus] = 0
	WHERE [AuctionStatus] = 1 
		AND GETDATE() > [ExpireDate];
GO
--------------------------------------------------------------------------------