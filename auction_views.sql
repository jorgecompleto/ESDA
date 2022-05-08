USE AdventureWorks2019

GO

CREATE OR ALTER VIEW Auction.RevenueSubtotal
AS
(
    SELECT  top (30) StoreID, StateProvinceID, StateProvinceCode,CountryRegionCode, City, AddressID, sum(SubTotal) as Revenue

FROM (
SELECT SC.CustomerID, StoreID, BusinessEntityID, PB.AddressID, PA.City, PA.StateProvinceID, PSP.CountryRegionCode, PSP.StateProvinceCode, SOH.SubTotal
FROM Sales.Customer AS SC
LEFT JOIN Person.BusinessEntityAddress AS PB
ON SC.StoreID = PB.BusinessEntityID
LEFT JOIN Person.Address AS PA
ON PA.AddressID = PB.AddressID
LEFT JOIN Person.StateProvince AS PSP
ON PSP.StateProvinceID = PA.StateProvinceID
LEFT JOIN Sales.SalesOrderHeader AS SOH
ON SC.CustomerID = SOH.CustomerID
WHERE SC.StoreID IS NOT NULL) a

WHERE CountryRegionCode = 'US'
GROUP BY StoreID, City, AddressID, StateProvinceID, StateProvinceCode, CountryRegionCode
ORDER BY sum(SubTotal) desc

)

GO

CREATE OR ALTER VIEW Auction.ProductGrossMargin
AS(
        SELECT a.*, b.ListPrice, (b.ListPrice - a.StandardCost) AS GrossMargin
        FROM Production.ProductCostHistory as a 
        LEFT JOIN Production.ProductListPriceHistory as b 
        ON (
            a.ProductID = b.ProductID
            AND a.StartDate = b.StartDate)
    )


GO

CREATE OR ALTER VIEW Auction.ProductAvgGrossMargin
AS(
   SELECT ProductID, AVG(GrossMargin) AS GrossMargin
    FROM Auction.ProductGrossMargin
    GROUP BY ProductID)

GO

CREATE OR ALTER VIEW Auction.OrderGrossMargin
AS (
SELECT A.*, B.GrossMargin, (a.OrderQty * B.GrossMargin) AS TotalGrossMargin, D.StoreID AS StoreID

FROM Sales.SalesOrderDetail AS A 
LEFT JOIN Auction.ProductAvgGrossMargin AS B 
ON (A.ProductID = B.ProductID)
LEFT JOIN Sales.SalesOrderHeader AS C
ON (A.SalesOrderID = C.SalesOrderID)
LEFT JOIN Sales.Customer AS D 
ON (C.CustomerID = D.CustomerID)    
)

GO

CREATE OR ALTER VIEW Auction.StoreGrossMargin
AS (
    SELECT A.StoreID, SUM(A.TotalGrossMargin) AS GrossMargin, C.City, D.CountryRegionCode, D.StateProvinceCode, D.StateProvinceID
    FROM Auction.OrderGrossMargin AS A 
    LEFT JOIN Person.BusinessEntityAddress AS B 
    ON A.StoreID = B.BusinessEntityID
    LEFT JOIN Person.Address AS C
    ON C.AddressID = B.AddressID
    LEFT JOIN Person.StateProvince AS D
    ON D.StateProvinceID = C.StateProvinceID

    GROUP BY StoreID, City, CountryRegionCode, D.StateProvinceID, StateProvinceCode
    HAVING CountryRegionCode = 'US'
    --ORDER BY GrossMargin DESC

)

GO

CREATE OR ALTER VIEW Auction.StoreNetMargin
AS(

    SELECT A.*, B.TaxRate, (A.GrossMargin * (1- (B.TaxRate / 100))) AS NetMargin
    FROM Auction.StoreGrossMargin AS A 
    LEFT JOIN Sales.SalesTaxRate AS B 
    ON (A.StateProvinceID = B.StateProvinceID)
)

GO

SELECT City, SUM(NetMargin) AS NetMargin_per_City

FROM Auction.StoreNetMargin
GROUP BY City
ORDER by Sum(NetMargin) DESC
