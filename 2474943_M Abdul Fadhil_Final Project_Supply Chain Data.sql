create database project;
use project;
CREATE TABLE Source_table(
    ShipmentID       VARCHAR(20) NOT NULL UNIQUE,   -- Unique shipment identifier
    OrderID          VARCHAR(20) NOT NULL,          -- Customer order reference
    Warehouse        ENUM('WH-CHN','WH-BLR','WH-PUN') NOT NULL, -- Origin warehouse
    Carrier          ENUM('DHL','FEDEX','BLUE_DART','ECOM_EXP') NOT NULL, -- Logistics provider
    ServiceLevel     ENUM('EXPRESS','STANDARD','ECONOMY') NOT NULL, -- Service type
    ShipDate         DATE NOT NULL,                 -- Shipment date
    DeliveryDate     DATE NOT NULL,                 -- Delivery date
    DistanceKM       DECIMAL(18,2) NOT NULL CHECK (DistanceKM >= 0), -- Distance in KM
    WeightKG         DECIMAL(18,2) NOT NULL CHECK (WeightKG >= 0),   -- Weight in KG
    BaseRatePerKM    DECIMAL(10,2) NOT NULL,        -- Base rate per KM
    FuelSurchargePct DECIMAL(5,2) NOT NULL CHECK (FuelSurchargePct IN (8,10,12,15)), -- Fuel surcharge %
    CODFlag          ENUM('Y','N') NOT NULL,        -- Cash on Delivery flag
    PRIMARY KEY (ShipmentID)
);

DESC Source_table;

SHOW TABLES;

SELECT * 
FROM source;

SET SQL_SAFE_UPDATES = 0;

UPDATE source

SET ShipDate = CASE

    WHEN ShipDate LIKE '%/%' THEN STR_TO_DATE(ShipDate, '%m/%d/%Y')

    WHEN ShipDate LIKE '%-%' THEN STR_TO_DATE(ShipDate, '%d-%m-%Y')

END,

DeliveryDate = CASE

    WHEN DeliveryDate LIKE '%/%' THEN STR_TO_DATE(DeliveryDate, '%m/%d/%Y')

    WHEN DeliveryDate LIKE '%-%' THEN STR_TO_DATE(DeliveryDate, '%d-%m-%Y')

END

WHERE ShipmentID IS NOT NULL;
 
ALTER TABLE source
RENAME COLUMN ï»¿ShipmentID to ShipmentID;

SELECT * 
FROM source;

INSERT INTO Source_table 
SELECT * FROM source;

SELECT * 
FROM Source_table;

CREATE TABLE TargetShipments (
    SurrogateKey INT PRIMARY KEY AUTO_INCREMENT,   -- Sequential PK starting at 60001
    ShipmentID VARCHAR(20) NOT NULL UNIQUE,        -- From source
    OrderID VARCHAR(20) NOT NULL,                  -- From source
    Warehouse ENUM('WH-CHN','WH-BLR','WH-PUN') NOT NULL,
    Carrier ENUM('DHL','FEDEX','BLUE_DART','ECOM_EXP') NOT NULL,
    ServiceLevel ENUM('EXPRESS','STANDARD','ECONOMY') NOT NULL,
    ShipDate DATE NOT NULL,
    DeliveryDate DATE NOT NULL,
    DistanceKM DECIMAL(18,2) NOT NULL,
    WeightKG DECIMAL(18,2) NOT NULL,
    BaseRatePerKM DECIMAL(10,2) NOT NULL,
    FuelSurchargePct DECIMAL(5,2) NOT NULL,
    CODFlag ENUM('Y','N') NOT NULL,
    TransitDays INT NOT NULL,
    RateMultiplier DECIMAL(5,2) NOT NULL,
    LinehaulCost DECIMAL(18,2) NOT NULL,
    FuelSurcharge DECIMAL(18,2) NOT NULL,
    CODFee DECIMAL(18,2) NOT NULL,
    TotalFreight DECIMAL(18,2) NOT NULL,
    SLA_MET ENUM('Y','N') NOT NULL
) AUTO_INCREMENT=60001;
 
DESC TargetShipments;

INSERT INTO TargetShipments (
    ShipmentID, OrderID, Warehouse, Carrier, ServiceLevel,
    ShipDate, DeliveryDate, DistanceKM, WeightKG,
    BaseRatePerKM, FuelSurchargePct, CODFlag,
    TransitDays, RateMultiplier, LinehaulCost,
    FuelSurcharge, CODFee, TotalFreight, SLA_MET
)
SELECT
    s.ShipmentID,
    s.OrderID,
    s.Warehouse,
    s.Carrier,
    s.ServiceLevel,
    s.ShipDate,
    s.DeliveryDate,
    s.DistanceKM,
    s.WeightKG,
    s.BaseRatePerKM,
    s.FuelSurchargePct,
    s.CODFlag,
    GREATEST(DATEDIFF(s.DeliveryDate, s.ShipDate), 0) AS TransitDays,
    CASE s.ServiceLevel
        WHEN 'EXPRESS' THEN 1.4
        WHEN 'STANDARD' THEN 1.0
        WHEN 'ECONOMY' THEN 0.8
    END AS RateMultiplier,
    ROUND(s.DistanceKM * s.BaseRatePerKM *
          CASE s.ServiceLevel
              WHEN 'EXPRESS' THEN 1.4
              WHEN 'STANDARD' THEN 1.0
              WHEN 'ECONOMY' THEN 0.8
          END, 2) AS LinehaulCost,
    ROUND(s.DistanceKM * s.BaseRatePerKM *
          CASE s.ServiceLevel
              WHEN 'EXPRESS' THEN 1.4
              WHEN 'STANDARD' THEN 1.0
              WHEN 'ECONOMY' THEN 0.8
          END * s.FuelSurchargePct/100, 2) AS FuelSurcharge,
    CASE s.CODFlag WHEN 'Y' THEN 50 ELSE 0 END AS CODFee,
    ROUND(
        (s.DistanceKM * s.BaseRatePerKM *
         CASE s.ServiceLevel
             WHEN 'EXPRESS' THEN 1.4
             WHEN 'STANDARD' THEN 1.0
             WHEN 'ECONOMY' THEN 0.8
         END)
        + (s.DistanceKM * s.BaseRatePerKM *
           CASE s.ServiceLevel
               WHEN 'EXPRESS' THEN 1.4
               WHEN 'STANDARD' THEN 1.0
               WHEN 'ECONOMY' THEN 0.8
           END * s.FuelSurchargePct/100)
        + CASE s.CODFlag WHEN 'Y' THEN 50 ELSE 0 END, 2
    ) AS TotalFreight,
    CASE
        WHEN s.ServiceLevel='EXPRESS' AND GREATEST(DATEDIFF(s.DeliveryDate, s.ShipDate),0) <= 3 THEN 'Y'
        WHEN s.ServiceLevel='STANDARD' AND GREATEST(DATEDIFF(s.DeliveryDate, s.ShipDate),0) <= 5 THEN 'Y'
        WHEN s.ServiceLevel='ECONOMY' AND GREATEST(DATEDIFF(s.DeliveryDate, s.ShipDate),0) <= 7 THEN 'Y'
        ELSE 'N'
    END AS SLA_MET
FROM Source_table s;
 
SELECT * 
FROM TargetShipments;

-- TC01 Count Check
SELECT (SELECT COUNT(*) FROM Source_table) AS SourceCount,
       (SELECT COUNT(*) FROM TargetShipments) AS TargetCount;

-- TC02 Null Check
SELECT * 
FROM TargetShipments
WHERE ShipmentID IS NULL 
   OR OrderID IS NULL 
   OR ShipDate IS NULL 
   OR DeliveryDate IS NULL;
   
-- TC03 Duplicate Check
SELECT ShipmentID, COUNT(*) AS Occurrence
FROM TargetShipments
GROUP BY ShipmentID
HAVING Occurrence > 1;

-- TC04 Schema Check
DESC Source_table;
DESC TargetShipments;

-- TC05 Surrogate Key Check
SELECT MIN(SurrogateKey) AS StartingValue, 
       MAX(SurrogateKey) AS EndingValue
FROM TargetShipments;

-- TC06 Date Normalization
SELECT ShipmentID
FROM TargetShipments
WHERE ShipDate NOT LIKE '____-__-__'
   OR DeliveryDate NOT LIKE '____-__-__';
   
-- TC07 TransitDays Calculation
SELECT ShipmentID 
FROM TargetShipments 
WHERE TransitDays <> GREATEST(DATEDIFF(DeliveryDate, ShipDate),0);

-- TC08 RateMultiplier Mapping
SELECT ShipmentID
FROM TargetShipments
WHERE (ServiceLevel='EXPRESS' AND RateMultiplier<>1.4)
   OR (ServiceLevel='STANDARD' AND RateMultiplier<>1.0)
   OR (ServiceLevel='ECONOMY' AND RateMultiplier<>0.8);

-- TC09 LinehaulCost Calculation
SELECT ShipmentID
FROM TargetShipments
WHERE LinehaulCost <> ROUND(DistanceKM*BaseRatePerKM*RateMultiplier,2);

-- TC10 FuelSurcharge Calculation
SELECT ShipmentID
FROM TargetShipments
WHERE FuelSurcharge <> ROUND(LinehaulCost*FuelSurchargePct/100,2);

-- TC11 CODFee Rule
SELECT ShipmentID
FROM TargetShipments
WHERE (CODFlag='Y' AND CODFee<>50)
   OR (CODFlag='N' AND CODFee<>0);
   
-- TC12 TotalFreight Calculation
SELECT ShipmentID 
FROM targetshipments 
WHERE TotalFreight <> ROUND(LinehaulCost + FuelSurcharge + CODFee, 2);

-- TC13 SLA_MET Rule
SELECT ShipmentID
FROM TargetShipments
WHERE (ServiceLevel='EXPRESS' AND TransitDays<=3 AND SLA_MET<>'Y')
   OR (ServiceLevel='STANDARD' AND TransitDays<=5 AND SLA_MET<>'Y')
   OR (ServiceLevel='ECONOMY' AND TransitDays<=7 AND SLA_MET<>'Y');

-- TC14 Enum Validation
SELECT ShipmentID
FROM TargetShipments
WHERE Warehouse NOT IN ('WH-CHN','WH-BLR','WH-PUN')
   OR Carrier NOT IN ('DHL','FEDEX','BLUE_DART','ECOM_EXP')
   OR ServiceLevel NOT IN ('EXPRESS','STANDARD','ECONOMY')
   OR CODFlag NOT IN ('Y','N');

-- TC16 Distance Range Check
SELECT ShipmentID, OrderID
FROM TargetShipments
WHERE DistanceKM < 0 OR DistanceKM > 5000;
 
-- TC17 Unique OrderID Check
SELECT OrderID, COUNT(*) AS DuplicateCount
FROM TargetShipments
GROUP BY OrderID
HAVING COUNT(*) > 1;
 
-- TC18 Precision Check
SELECT ShipmentID
FROM TargetShipments
WHERE RateMultiplier NOT LIKE '%.%';
 
-- TC19 Distance/Weight Precision
SELECT ShipmentID
FROM TargetShipments
WHERE DistanceKM <> ROUND(DistanceKM,2)
   OR WeightKG <> ROUND(WeightKG,2);

-- TC20 Delivery Date Range
SELECT ShipmentID
FROM TargetShipments
WHERE DeliveryDate > DATE_ADD(ShipDate, INTERVAL 1 YEAR);

-- TC21 OrderID Consistency
SELECT OrderID
FROM Source_table
WHERE OrderID NOT IN (SELECT OrderID FROM TargetShipments);

-- TC22 Warehouse/Carrier Mapping
SELECT s.ShipmentID 
FROM Source_table s
JOIN TargetShipments t ON s.ShipmentID = t.ShipmentID
WHERE s.Warehouse<>t.Warehouse OR s.Carrier<>t.Carrier;

-- TC23 ServiceLevel Consistency
SELECT s.ShipmentID 
FROM Source_table s
JOIN TargetShipments t ON s.ShipmentID = t.ShipmentID
WHERE s.ServiceLevel<>t.ServiceLevel;

-- TC24 Date Consistency
SELECT s.ShipmentID 
FROM Source_table s
JOIN TargetShipments t ON s.ShipmentID = t.ShipmentID
WHERE s.ShipDate<>t.ShipDate OR s.DeliveryDate<>t.DeliveryDate;

-- TC25 Shipment ID Uniqueness
SELECT ShipmentID, COUNT(*) 
FROM TargetShipments 
GROUP BY ShipmentID 
HAVING COUNT(*) > 1;


-- TC26 – Warehouse Mismatch
UPDATE target_test 
SET Warehouse = 'WH-DEL'
WHERE ShipmentID = 'SH6002';

SELECT shipmentID, Warehouse 
FROM target_test 
WHERE Warehouse NOT IN ('WH-CHN','WH-PUN','WH-BLR')

SELECT ShipmentID, Warehouse 
FROM source_table
EXCEPT
SELECT ShipmentID, Warehouse 
FROM targetShipments; 

-- TC27 – Invalid CODFlag
UPDATE target_test
SET CODFlag = 'A' 
WHERE ShipmentID = 'SH6011';

SELECT ShipmentID, CODFlag
FROM target_test
WHERE CODFlag NOT IN ('Y','N');

SELECT ShipmentID, CODFlag 
FROM source_table
EXCEPT
SELECT ShipmentID, CODFlag 
FROM targetshipments;

-- TC28 – Negative Distance
UPDATE target_test
SET DistanceKM = -50
WHERE ShipmentID = 'SH6020';

SELECT ShipmentID, DistanceKM
FROM target_test
WHERE DistanceKM < 0;

SELECT ShipmentID, DistanceKM
FROM source_table
EXCEPT
SELECT ShipmentID, DistanceKM
FROM targetShipments;

-- TC29 - Date Validation
UPDATE target_test
SET DeliveryDate = '2025-01-01'
WHERE ShipmentID = 'SH6015';

SELECT ShipmentID, OrderID, ShipDate, DeliveryDate
FROM targetshipments
WHERE DeliveryDate < ShipDate;

SELECT ShipmentID, OrderID, DeliveryDate
FROM source_table
EXCEPT
SELECT ShipmentID, OrderID, DeliveryDate
FROM targetshipments;

-- TC30 - Negative Weight
SELECT ShipmentID, OrderID, WeightKG 
FROM target_test 
EXCEPT 
SELECT ShipmentID, OrderID, WeightKG 
FROM targetshipments;