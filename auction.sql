-- Selecting the Adventure Works database
USE AdventureWorks2019
GO

-- Creating the Auction Schema
IF NOT EXISTS (SELECT * FROM sys.schemas WHERE name = 'Auction') -- Checking if the Aucion Schema is not already created
    BEGIN
        EXEC ('CREATE SCHEMA [Auction]'); -- Create the Auction Schema
    END

GO -- Select the Auction Schema

IF (EXISTS (SELECT * 
                 FROM sys.TABLES 
                 WHERE name in ('BidInfo', 'ProductInfo', 'ThresholdSet', 'BidDateRange') -- Checking if the tables already exist
                 and schema_id = 10
                ))
BEGIN
    DROP TABLE [Auction].[BidInfo]
    DROP TABLE [Auction].[ProductInfo]
    DROP TABLE [Auction].[ThresholdSet]
    DROP TABLE [Auction].[BidDateRange]
END   

/* Create the tables inside the Auction schema 

TABLE PRODUCT - Save in this table the Products that are going to be up for Auction */

BEGIN
    CREATE TABLE [Auction].[ProductInfo]
    (   [AuctionProductID] [int] NOT NULL IDENTITY PRIMARY KEY,
        [ProductID] [int] NOT NULL FOREIGN KEY REFERENCES [Production].[Product] ([ProductID]),
        [ExpireDate] [datetime] NOT NULL,
        [InitialListPrice] [money] NOT NULL,
        [InitialBidPrice] [money] NOT NULL,
        [Active] [bit] NOT NULL DEFAULT 1,
        [AuctionRemoved] [bit] NOT NULL DEFAULT 0,

    ) ON [PRIMARY]
    
END

-- TABLE BIDINFO - Save in this table every bid made by each Customer for each Product

BEGIN  
    CREATE TABLE [Auction].[BidInfo]
    (   [AuctionProductID] [int] NOT NULL FOREIGN KEY REFERENCES [Auction].[ProductInfo] ([AuctionProductID]),
        [ProductID] [int] NOT NULL FOREIGN KEY REFERENCES [Production].[Product] ([ProductID]),
        [CustomerID] [int] NOT NULL FOREIGN KEY REFERENCES [Sales].[Customer] ([CustomerID]),
        [BidAmount] [money] NOT NULL,
        [BidTime] [datetime] NOT NULL,
    
    ) ON [PRIMARY]

END

-- TABLE THRESHOLDSSET - Contains the predefined thresholds for the mininum bid increase and the maximum bid limit

BEGIN
    CREATE TABLE [Auction].[ThresholdSet]
    (   [Setting] [VARCHAR](70) NOT NULL,
        [BidLimit] [FLOAT] NOT NULL,
    
    ) ON [PRIMARY]

INSERT INTO [Auction].[ThresholdSet] ([Setting], [BidLimit]) VALUES ('MinIncreaseBid', CAST(0.05 AS money))
INSERT INTO [Auction].[ThresholdSet] ([Setting], [BidLimit]) VALUES ('MaxIncreaseLimit', CAST(1 AS real))

END

-- TABLE BIDDATERANGE - Contains the default bidding period when clients can bid for products

BEGIN
    CREATE TABLE [Auction].[BidDateRange]
    (   [Setting] [VARCHAR](70) NOT NULL,
        [Date] DATETIME NOT NULL,
    
    ) ON [PRIMARY]

INSERT INTO [Auction].[BidDateRange] ([Setting], [Date]) VALUES ('StartBidDate', CAST('20221114' AS datetime))
INSERT INTO [Auction].[BidDateRange] ([Setting], [Date]) VALUES ('StopBidDate', CAST('20221127' AS datetime))

END

GO -- Allows the other batch to run

/* STORED PROCEDURES 
uspAddProductToAuction - Store Procedure that adds elegible products for auction */

CREATE OR ALTER PROCEDURE [Auction].[uspAddProductToAuction]
(  
    @ProductID INT = NULL,
    @ExpireDate DATETIME = NULL,
    @InitialBidPrice MONEY = NULL
)

AS

DECLARE @SellEndDate DATETIME = NULL
DECLARE @DiscontinuedDate DATETIME = NULL
DECLARE @MakeFlag BIT = NULL
DECLARE @InitialListPrice MONEY = NULL
DECLARE @MinDefaultBidPrice MONEY = NULL
DECLARE @MaxDefaultBidPrice MONEY = NULL

BEGIN TRY
    SELECT
    @MakeFlag = [MakeFlag],
    @SellEndDate = [SellEndDate],
    @DiscontinuedDate = [DiscontinuedDate],
    @InitialListPrice = [ListPrice]
    FROM (
        SELECT 
        [MakeFlag],
        [SellEndDate],
        [DiscontinuedDate],
        [ListPrice]
        FROM [Production].[Product]
        WHERE [ProductID] = @ProductID
        ) AS [Production_Aux]

-- Check if ProductID is not valid
    IF @ProductID IS NULL
        BEGIN
            DECLARE @errormessage1 VARCHAR(150) = 'Error: ProductID is not valid.';
            THROW 50001, @errormessage1, 0;
        END

-- Check if the ProductsID exists in Production
    ELSE IF NOT EXISTS (
        SELECT [ProductID]
        FROM [Production].[Product]
        WHERE [ProductID] = @ProductID)
            BEGIN
                DECLARE @errormessage2 VARCHAR(150) = 'Error: ProductID does not exist in the catalog.';
                THROW 50002, @errormessage2, 0;
            END

-- Check if ProductID is currently being auctioned
    ELSE IF EXISTS (
        SELECT [ProductID]
        FROM [Auction].[ProductInfo]
        WHERE [ProductID] = @ProductID
        AND [Active] = 1)
            BEGIN
                DECLARE @errormessage3 VARCHAR(150) = 'Error: This product is already being auctioned.';
                THROW 50003, @errormessage3, 0;
            END

    ELSE IF @SellEndDate IS NOT NULL AND @DiscontinuedDate IS NOT NULL
            BEGIN
                DECLARE @errormessage4 VARCHAR(150) = 'Error: This product is not being currently commercialized.';
                THROW 50004, @errormessage4, 0;
            END

    ELSE IF @InitialBidPrice IS NOT NULL AND @InitialBidPrice > @InitialListPrice
            BEGIN 
                DECLARE @errormessage5 VARCHAR(150) = 'Error: The initial bid price must be lower than the list price.';
                THROW 50005, @errormessage5, 0;
            END
    ELSE IF @InitialBidPrice IS NOT NULL AND @InitialBidPrice <= (@InitialListPrice * 0.5)
            BEGIN
                DECLARE @errormessage6 VARCHAR(150) = 'Error: The initial bid price must be higher or equal to the minimum bid price.';
                THROW 50006, @errormessage6, 0;
            END

    ELSE
        BEGIN
            -- Set the default value for the @ExpireDate
            SET @ExpireDate = COALESCE(@ExpireDate, DATEADD(WEEK,1,GETDATE()));
            BEGIN
            --IF NOT(@ExpireDate BETWEEN CONVERT(DATETIME, CONCAT(YEAR(GETDATE()),'1117'), 112) AND CONVERT(datetime, CONCAT(YEAR(GETDATE()),'1207'), 112))
              --  BEGIN
                --    DECLARE @errormessage5 VARCHAR(150) = 'Error: The timeframe of the auction is invalid.';
                  --  THROW 50005, @errormessage5, 0;
                --END
     
            BEGIN
                IF @InitialBidPrice IS NULL
                SELECT @MinDefaultBidPrice = [MinDefaultBidPrice], @MaxDefaultBidPrice = [MaxDefaultBidPrice]
                    FROM (
                    SELECT CASE WHEN @MakeFlag = 0
                    THEN @InitialListPrice * 0.75
                    ELSE @InitialListPrice * 0.5
                    END AS [MinDefaultBidPrice],
                    [ListPrice] AS [MaxDefaultBidPrice]
                    FROM [Production].Product
                    WHERE [ProductID] = @ProductID) AS [DefaultBidPrice]
            END
            END
        END 
            
        BEGIN
            SET @InitialBidPrice = COALESCE(@MinDefaultBidPrice, @MaxDefaultBidPrice, @InitialBidPrice)  -- Colocar exceções de Initial Bid Price           
        END
BEGIN
BEGIN TRANSACTION  [InsertProduct] -- Insert Products into the Auction Product table
    INSERT INTO [Auction].[ProductInfo]
    (
        [ProductID],
        [ExpireDate],
        [InitialBidPrice],
        [InitialListPrice]

    )
    VALUES (
        @ProductID, -- ProductID is a mandatory parameter
        @ExpireDate, -- optional parameter
        @InitialBidPrice, -- optional parameter
        @InitialListPrice -- auxiliar parameter
    );
    --SELECT @@TRANCOUNT AS OpenTransactions
COMMIT TRANSACTION [InsertProduct]
END
END TRY
BEGIN CATCH -- Deal with errors in the transaction
    IF @@TRANCOUNT > 0 -- Check to see if the previous transaction is open
        BEGIN
            ROLLBACK TRANSACTION [InsertProduct] -- Undo all the inserts made by the transaction
        END
    ELSE 
        BEGIN
            PRINT ERROR_MESSAGE() -- Print the error message that is making the Catch block to run if there is no open transactions
        END
END CATCH

GO -- Allows the other batch to run

-- uspTryBidProduct - Store Procedure that adds bids to the BidInfo table

CREATE OR ALTER PROCEDURE [Auction].[uspTryBidProduct]
(
    @ProductID INT,
    @CustomerID INT,
    @BidAmount MONEY = NULL
)

AS

DECLARE @AuctionProductID INT = NULL
DECLARE @BidTimeStamp DATETIME = GETDATE()
DECLARE @ExpireDate DATETIME
DECLARE @Active BIT = NULL
DECLARE @AuctionRemoved BIT = NULL
DECLARE @StartBidDate DATETIME = NULL
DECLARE @StopBidDate DATETIME = NULL
DECLARE @HighestBid FLOAT = NULL
DECLARE @MinIncreaseBid MONEY = NULL
DECLARE @MaxIncreaseLimit REAL = NULL
DECLARE @InitialListPrice MONEY = NULL
DECLARE @InitialBidPrice MONEY = NULL
DECLARE @Flag BIT = NULL

BEGIN TRY
    SELECT @AuctionProductID = [AuctionProductID],
            @ProductID = [ProductID],
            @ExpireDate = [ExpireDate],
            @Active = [Active], 
            @AuctionRemoved = [AuctionRemoved],
            @InitialListPrice = [InitialListPrice],
            @InitialBidPrice = [InitialBidPrice]
            
    FROM(
        SELECT [AuctionProductID], [ProductID], [ExpireDate], [Active], [AuctionRemoved], [InitialListPrice], [InitialBidPrice]

        FROM [Auction].[ProductInfo]
        WHERE [ProductID] = @ProductID
    ) AS [ProductInfoAux] -- Auxiliar table with variables from the table that contains bid Products

    SELECT @StartBidDate = [Date]
    FROM(
        SELECT [Date]
        FROM [Auction].[BidDateRange]
        WHERE [Setting] = 'StartBidDate'
    ) AS [StartBidDateAux] -- Auxiliar table with variables from the table that contains the start and stop bid dates

    SELECT @StopBidDate = [Date]
        FROM(
            SELECT [Date]
            FROM [Auction].[BidDateRange]
            WHERE [Setting] = 'StopBidDate'
        ) AS [StopBidDateAux] -- Auxiliar table with variables from the table that contains the start and stop bid dates

    BEGIN
        IF @AuctionProductID IS NULL 
            BEGIN
                DECLARE @errormessage1 VARCHAR(150) = 'Error: The product is not being auctioned.';
                THROW 51000, @errormessage1, 0;
            END 
        ELSE 
            IF NOT EXISTS (
                SELECT [CustomerID]
                FROM [Sales].Customer
                WHERE [CustomerID] = @CustomerID
            )
                BEGIN
                    DECLARE @errormessage2 VARCHAR(150) = 'Error: The CustomerID is not registered.';
                    THROW 51001, @errormessage2, 0;
                END   
        ELSE IF @BidTimeStamp > @ExpireDate
            BEGIN
                DECLARE @errormessage3 VARCHAR(150) = 'Error: This product auction has already ended.';
                THROW 51002, @errormessage3, 0;
            END
        ELSE IF @Active = 0
            BEGIN
                DECLARE @errormessage4 VARCHAR(150) = 'Error: The product is no longer being auctioned.';
                THROW 51003, @errormessage4, 0;
            END
        ELSE IF @BidTimeStamp NOT BETWEEN @StartBidDate AND @StopBidDate
            BEGIN
                DECLARE @errormessage5 VARCHAR(150) = 'Error: No bids are allowed at this time for this auction.';
                THROW 51004, @errormessage5, 0;
            END 
        ELSE IF @BidAmount IS NOT NULL AND @BidAmount > @InitialListPrice
            BEGIN
                DECLARE @errormessage6 VARCHAR(150) = 'Error: Bid is higher than the list price of the product.';
                THROW 51005, @errormessage6, 0;
            END 

        ELSE 
            BEGIN
                SELECT @HighestBid = [BidAmount]
                FROM (
                    SELECT MAX([BidAmount]) AS [BidAmount]
                    FROM [Auction].[BidInfo]
                    WHERE [ProductID]=@ProductID AND [AuctionProductID] = @AuctionProductID
                ) AS [HighestBidAux]

                SELECT @MinIncreaseBid = [BidLimit]
                FROM (
                    SELECT [BidLimit]
                    FROM [Auction].[ThresholdSet]
                    WHERE [Setting] = 'MinIncreaseBid'
                ) AS [MinIncreaseBidAux]

                SELECT @MaxIncreaseLimit = [BidLimit]
                FROM (
                    SELECT [BidLimit]
                    FROM [Auction].[ThresholdSet]
                    WHERE [Setting] = 'MaxIncreaseLimit'
                ) AS [MinIncreaseBidAux]

                IF @BidAmount IS NULL
                    BEGIN
                        SET @BidAmount = COALESCE(@HighestBid + @MinIncreaseBid, @InitialBidPrice)
                    END
                BEGIN
                    IF @BidAmount < @MinIncreaseBid
                        BEGIN
                            DECLARE @errormessage7 VARCHAR(150) = 'Error: Bid Amount is lower than the minimum increase bid allowed.';
                            THROW 51006, @errormessage7, 0;
                        END

                    ELSE IF @BidAmount > ((@MaxIncreaseLimit * @InitialListPrice) - @MinIncreaseBid)
                        BEGIN
                            SET @Flag = 1
                        END

                    ELSE IF @BidAmount > (@MaxIncreaseLimit * @InitialListPrice)
                        BEGIN
                            DECLARE @errormessage8 VARCHAR(150) = 'Error: Bid Amount is higher than the list price of the product.';
                            THROW 51007, @errormessage8, 0;
                        END
                END
            END
    END  

BEGIN
BEGIN TRANSACTION  [InsertBid]-- Insert Products into the Auction Product table
    INSERT INTO [Auction].[BidInfo]
    (
        [AuctionProductID],
        [ProductID],
        [CustomerID],
        [BidAmount],
        [BidTime]

    )
    VALUES (
        @AuctionProductID, -- Identifies the product that is being bid
        @ProductID, -- ProductID is a mandatory parameter
        @CustomerID,
        @BidAmount, -- optional parameter
        @BidTimeStamp -- auxiliar parameter
    );
    IF @Flag = 1
        BEGIN UPDATE [Auction].ProductInfo
            SET [Active] = 0
            WHERE [ProductID] = @ProductID AND [Active] = 1
        END
COMMIT TRANSACTION [InsertBid]
END
END TRY
BEGIN CATCH -- Deal with errors in the transaction
    IF @@TRANCOUNT > 0 -- Check to see if the previous transaction is open
        BEGIN
            ROLLBACK TRANSACTION [InsertBid] -- Undo all the inserts made by the transaction
        END
    ELSE 
        BEGIN
            PRINT ERROR_MESSAGE() -- Print the error message that is making the Catch block to run if there is no open transactions
        END
END CATCH


-- usp Remove product from auction
GO
CREATE OR ALTER PROCEDURE [Auction].[uspRemoveProductFromAuction]

(   
    @ProductID INT
)
AS
BEGIN TRY
    -- Check if product is currently being actioned
    BEGIN
        IF NOT EXISTS  (SELECT [ProductID] FROM [Auction].[ProductInfo] WHERE [Active] = 1 AND [ProductID] = @ProductID)
            BEGIN
                DECLARE @errormessage0 VARCHAR(100) = 'Error: Product inserted is not currently being auctioned.';
                THROW 52001, @errormessage0, 0;
            END
            BEGIN
                BEGIN TRANSACTION
                    UPDATE [Auction].[ProductInfo]
                    SET [Active] = 0,
                        [AuctionRemoved] = 1
                    WHERE [Active] = 1 AND [ProductID] = @ProductID
                COMMIT TRANSACTION
            END
    END
    RETURN
END TRY
BEGIN CATCH
    IF @@ROWCOUNT > 0
        BEGIN  
            ROLLBACK TRANSACTION
        END
    ELSE    
        BEGIN   
            PRINT ERROR_MESSAGE()
        END
END CATCH
GO

-- uspListBidsOffersHistory - 

CREATE OR ALTER PROCEDURE [Auction].[uspListBidsOffersHistory]
(
    @CustomerID INT,
    @StartTime DATETIME,
    @StopTime DATETIME,
    @Active BIT = 1
)
AS

BEGIN TRY
    BEGIN
        IF NOT EXISTS (
            SELECT @CustomerID
            FROM [Auction].[BidInfo]
            WHERE @CustomerID = [CustomerID]
        )
        BEGIN
            DECLARE @errormessage0 VARCHAR(100) = 'Error: The inserted CustomerID has not made a bid.';
            THROW 53001, @errormessage0, 0;
        END
        
        ELSE IF @StartTime >= @StopTime
            BEGIN
                DECLARE @errormessage1 VARCHAR(100) = 'Error: The inserted StopTime has to be later than the StartTime.';
                THROW 53002, @errormessage1, 0;
            END

        ELSE IF @Active = 1
            BEGIN
                SELECT [CustomerID],
                        a_bi.[ProductID],
                         a_bi.[AuctionProductID],
                          [BidAmount],
                           [BidTime],
                            a_pi.[Active]
                FROM [Auction].[BidInfo] AS a_bi
                INNER JOIN [Auction].[ProductInfo] AS a_pi
                ON a_bi.[AuctionProductID] = a_pi.[AuctionProductID]
                WHERE [CustomerID] = @CustomerID AND ([BidTime] BETWEEN @StartTime AND @StopTime) AND [Active] = 1
            END
        ELSE
            BEGIN
                SELECT [CustomerID],
                        a_bi.[ProductID],
                         a_bi.[AuctionProductID],
                          [BidAmount],
                           [BidTime],
                            a_pi.[Active]
                FROM [Auction].[BidInfo] AS a_bi
                INNER JOIN [Auction].[ProductInfo] AS a_pi
                ON a_bi.[AuctionProductID] = a_pi.[AuctionProductID]
                WHERE [CustomerID] = @CustomerID AND ([BidTime] BETWEEN @StartTime AND @StopTime)
            END
    END
END TRY
BEGIN CATCH -- Deal with errors in the transaction
    IF @@TRANCOUNT > 0 -- Check to see if the previous transaction is open
        BEGIN
            ROLLBACK TRANSACTION [InsertBid] -- Undo all the inserts made by the transaction
        END
    ELSE 
        BEGIN
            PRINT ERROR_MESSAGE() -- Print the error message that is making the Catch block to run if there is no open transactions
        END
END CATCH

GO
-- uspUpdateProductAuctionStatus
CREATE OR ALTER PROCEDURE [Auction].[uspUpdateProductAuctionStatus]
AS
	-- Check for active auctions (Active = 1) and close the ones that have expired
	UPDATE [Auction].[ProductInfo]
	SET [Active] = 0
	WHERE [Active] = 1 
		AND GETDATE() > [ExpireDate];
GO
--------------------------------------------------------------------------------

