CREATE OR ALTER VIEW Auction.RevenueSubtotal
AS
(
SELECT SC.CustomerID, StoreID, BusinessEntityID, PB.AddressID, PA.City, SOH.SubTotal
FROM Sales.Customer AS SC
LEFT JOIN Person.BusinessEntityAddress AS PB
ON SC.StoreID = PB.BusinessEntityID
LEFT JOIN Person.Address AS PA
ON PA.AddressID = PB.AddressID
LEFT JOIN Sales.SalesOrderHeader AS SOH
ON SC.CustomerID = SOH.CustomerID
WHERE SC.StoreID IS NOT NULL
)
