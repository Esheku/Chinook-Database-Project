-- Top-Selling Artists: Identify artists with the highest sales and analyze their sales trends over time.

CREATE TEMP TABLE ArtistSales AS 
    SELECT strftime('%Y-%m', i.InvoiceDate) AS SalesMonth, a.Name AS ArtistName, SUM(i.Total) AS MonthlySales
    FROM artists a
    LEFT JOIN albums ab ON a.ArtistId = ab.ArtistId 
    LEFT JOIN tracks t ON ab.AlbumId = t.AlbumId 
    LEFT JOIN invoice_items ii ON t.TrackId = ii.TrackId
    LEFT JOIN invoices i ON ii.InvoiceId = i.InvoiceId 
    WHERE i.InvoiceDate IS NOT NULL
    GROUP BY SalesMonth, a.Name

-- Top Selling Artist
SELECT ArtistName, sum(MonthlySales) as TotalSales
FROM ArtistSales
group by ArtistName
order by TotalSales desc Limit 5;

--Top artist sales trend
SELECT SalesMonth, ArtistName, MonthlySales
FROM ArtistSales 
WHERE ArtistName IN ("Iron Maiden", "U2", "Lost", "Led Zeppelin", "Metallica")
ORDER BY SalesMonth asc, MonthlySales desc

-- Customer Purchase Patterns: Segment customers based on purchase behavior 

WITH CustomerTable AS (
    SELECT
        FirstName || ' ' || LastName AS Name,
        MIN(strftime('%Y-%m-%d', i.InvoiceDate)) AS EarliestPurchase,
        MAX(strftime('%Y-%m-%d', i.InvoiceDate)) AS LastPurchase,
        COUNT(i.InvoiceID) AS PurchaseFrequency,
        SUM(i.Total) AS TotalSpent,
        c.Country
    FROM customers c 
    LEFT JOIN invoices i ON c.CustomerId = i.CustomerId 
    LEFT JOIN invoice_items ii ON i.InvoiceId = ii.InvoiceId 
    GROUP BY Name
),
CustomerRFM AS (
    SELECT 
        Name, 
        LastPurchase, 
        PurchaseFrequency, 
        TotalSpent, 
        Country,
        strftime('%J', '2013-12-31') - strftime('%J', LastPurchase) AS DateDiff,
        -- Recency score calculation
        CASE 
            WHEN strftime('%J', '2013-12-31') - strftime('%J', LastPurchase) <= 30 THEN 5
            WHEN strftime('%J', '2013-12-31') - strftime('%J', LastPurchase) <= 90 THEN 4
            WHEN strftime('%J', '2013-12-31') - strftime('%J', LastPurchase) <= 180 THEN 3
            WHEN strftime('%J', '2013-12-31') - strftime('%J', LastPurchase) <= 350 THEN 2
            ELSE 1
        END AS RecencyScore,
        -- Monetary score calculation
        CASE
            WHEN TotalSpent > 800 THEN 5
            WHEN TotalSpent >= 500 THEN 4
            WHEN TotalSpent >= 300 THEN 3
            WHEN TotalSpent >= 100 THEN 2
            ELSE 1
        END AS MoneyScore
    FROM CustomerTable
)
-- -- identify key characteristics of high-value customers.
SELECT Name, RecencyScore, MoneyScore, (RecencyScore * 0.7 + MoneyScore * 0.3) AS RM_Score, Country
FROM CustomerRFM
ORDER BY RM_Score DESC 


-- Genre Popularity: Determine the most popular music genres 

SELECT g.Name GenreName, SUM(i.Total) TotalSales, sum(ii.Quantity) QuantityPurchased 
FROM invoices i 
LEFT JOIN invoice_items ii ON i.InvoiceId = ii.InvoiceId 
LEFT JOIN tracks t ON ii.TrackId = t.TrackId 
LEFT JOIN genres g ON t.GenreId = g.GenreId
GROUP BY g.Name 
ORDER BY TotalSales DESC

-- analyze the change in genre popularity over different time periods.
WITH GenreSales AS (
    SELECT 
        strftime('%Y', i.InvoiceDate) AS SalesYear,
        g.Name AS GenreName,
        SUM(i.Total) TotalSales
    FROM invoices i
    LEFT JOIN invoice_items ii ON i.InvoiceId = ii.InvoiceId
    LEFT JOIN tracks t ON ii.TrackId = t.TrackId
    LEFT JOIN genres g ON t.GenreId = g.GenreId
    GROUP BY SalesYear, GenreName
),
YoY_Variance as(
	SELECT SalesYear, GenreName, TotalSales,
	LAG(TotalSales) OVER (PARTITION BY GenreName ORDER BY SalesYear) AS PreviousYearSales,
	CASE 
		WHEN LAG(TotalSales) OVER (PARTITION BY GenreName ORDER BY SalesYear) IS NOT NULL 
		THEN ROUND(
		((TotalSales-LAG(TotalSales) OVER (PARTITION BY GenreName ORDER BY SalesYear))
		/LAG(TotalSales) OVER (PARTITION BY GenreName ORDER BY SalesYear))*100,2
		) 
		ELSE NULL
	END AS YOYVariance
	FROM GenreSales
)
SELECT SalesYear, GenreName, TotalSales, PreviousYearSales, YOYVariance || '%'
FROM YoY_Variance
ORDER BY GenreName, SalesYear;

-- Sales Over Time: 
-- Analyze monthly 
WITH MonthlySales AS (
    SELECT 
        strftime('%Y-%m', i.InvoiceDate) AS SalesMonth,
        SUM(i.Total) TotalSales
    FROM invoices i
    GROUP BY SalesMonth
),
MoM_Variance as(
	SELECT SalesMonth, TotalSales,
	LAG(TotalSales) OVER(order by SalesMonth) AS PreviousMonthSales,
	CASE 
		WHEN LAG(TotalSales) OVER(order by SalesMonth) IS NOT NULL 
		THEN ROUND(
		((TotalSales-LAG(TotalSales) OVER(order by SalesMonth))
		/LAG(TotalSales) OVER(order by SalesMonth))*100,2
		) 
		ELSE NULL
	END AS MoMVariance
	FROM MonthlySales
)
SELECT SalesMonth, TotalSales, PreviousMonthSales, MoMVariance || '%'
FROM MoM_Variance
ORDER BY SalesMonth;

--yearly sales trends 
WITH YearlySales AS (
    SELECT 
        strftime('%Y', i.InvoiceDate) AS SalesYear,
        SUM(i.Total) TotalSales
    FROM invoices i
    GROUP BY SalesYear
),
YoY_Variance as(
	SELECT SalesYear, TotalSales,
	LAG(TotalSales) OVER(order by SalesYear) AS PreviousYearSales,
	CASE 
		WHEN LAG(TotalSales) OVER(order by SalesYear) IS NOT NULL 
		THEN ROUND(
		((TotalSales-LAG(TotalSales) OVER(order by SalesYear))
		/LAG(TotalSales) OVER(order by SalesYear))*100,2
		) 
		ELSE NULL
	END AS YoYVariance
	FROM YearlySales
)
SELECT SalesYear, TotalSales, PreviousYearSales, YoYVariance || '%'
FROM YoY_Variance
ORDER BY SalesYear;


--including seasonal effects and significant sales events.

    SELECT 
        strftime('%m', i.InvoiceDate) AS Month,
        SUM(i.Total) TotalSales,
        AVG(SUM(i.Total)) OVER() AvgSales,
        CASE 		
        	WHEN SUM(i.Total) > AVG(SUM(i.Total)) OVER() THEN 'Above Average'
        	ELSE 'Below Average'
        END AS Seasonality    
    FROM invoices i
    GROUP BY Month

    --Calculate the lifetime value of customers based on their purchase history
    -- Customer Lifetime Value (CLV) : average purchase value, purchase frequerncy, customer lifespan
    
WITH metrics AS(
    SELECT FirstName || ' ' || LastName AS Name,
    	SUM(i.Total) TotalSpent,
    	ROUND(SUM(i.Total)/COUNT(i.InvoiceID), 2) AvgPurchaseValue,
    	COUNT(i.InvoiceID)/COUNT(DISTINCT i.CustomerId) AvgPurchaseFrequency,
    	(CAST(strftime('%Y', MAX(i.InvoiceDate)) - strftime('%Y', MIN(i.InvoiceDate)) AS INTEGER) * 12) +
    	(CAST(strftime('%m', MAX(i.InvoiceDate)) - strftime('%m', MIN(i.InvoiceDate)) AS INTEGER))
    	/COUNT(DISTINCT i.CustomerId) AvgActiveMonths
	FROM customers c
    LEFT JOIN invoices i ON c.CustomerId = i.CustomerId 
    GROUP BY Name
)
SELECT	
	Name,
	'$'||TotalSpent as TotalSpent,
	AvgPurchaseFrequency,
	'$'||AvgPurchaseValue as AvgPurchaseValue,
	AvgActiveMonths,
	'$'||(AvgPurchaseFrequency * AvgPurchaseValue * AvgActiveMonths) CustomerLifeValue
FROM metrics
ORDER BY CustomerLifeValue Desc;