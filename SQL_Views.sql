CREATE OR ALTER VIEW Auction.RevenueSubtotal
AS
(
    SELECT  top (30) StoreID, StateProvinceID, CountryRegionCode,City, AddressID, sum(SubTotal) as Revenue

FROM (
SELECT SC.CustomerID, StoreID, BusinessEntityID, PB.AddressID, PA.City, PA.StateProvinceID, PSP.CountryRegionCode, SOH.SubTotal
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
GROUP BY StoreID, City, AddressID, StateProvinceID, CountryRegionCode
ORDER BY sum(SubTotal) desc

)
;

