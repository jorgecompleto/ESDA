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
                 WHERE name in ('BidInfo', 'ProductInfo', 'ThresholdSet') -- Checking if the tables already exist
                 and schema_id = 10
                ))
BEGIN
    DROP TABLE [Auction].[BidInfo]
    DROP TABLE [Auction].[ProductInfo]
    DROP TABLE [Auction].[ThresholdSet]
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
        [BidValue] [money] NOT NULL,
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
        THROW 50001, @errormessage2, 0;
    END

-- Check if ProductID is currently being auctioned
ELSE IF EXISTS (
    SELECT [ProductID]
    FROM [Auction].[ProductInfo]
    WHERE [ProductID] = @ProductID
    AND [Active] = 1)
    
    BEGIN
        DECLARE @errormessage3 VARCHAR(150) = 'Error: This product is already being auctioned.';
        THROW 50001, @errormessage3, 0;
    END

ELSE IF @SellEndDate IS NOT NULL AND @DiscontinuedDate IS NOT NULL
    BEGIN
        DECLARE @errormessage4 VARCHAR(150) = 'Error: This product is not being currently commercialized.';
        THROW 50001, @errormessage4, 0;
    END

ELSE 
    BEGIN
    -- Set the default value for the @ExpireDate
    SET @ExpireDate = COALESCE(@ExpireDate, DATEADD(WEEK,1,GETDATE())); -- Decidir se mantemos o GETDATE ou a data de 2019
    IF NOT(@ExpireDate BETWEEN CONVERT(DATETIME, CONCAT(YEAR(GETDATE()),'1117'), 112) AND CONVERT(datetime, CONCAT(YEAR(GETDATE()),'1207'), 112))
        BEGIN
            DECLARE @errormessage5 VARCHAR(150) = 'Error: The timeframe of the auction is invalid.';
            THROW 50001, @errormessage5, 0;
        END
    
    ELSE 
        BEGIN
            SELECT 
                CASE WHEN @MakeFlag = 0
                    THEN @InitialListPrice * 0.75
                    ELSE @InitialListPrice * 0.5
                END AS [InitialBidPrice]
                FROM [Production].[Product]
        END
    END



        









    