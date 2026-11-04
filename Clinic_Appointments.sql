/*==================================================
    CREATE DATABASE
==================================================*/

IF DB_ID('Clinic_Appointments') IS NULL
BEGIN
    CREATE DATABASE Clinic_Appointments;
END
GO

USE Clinic_Appointments;
GO

/*==================================================
    DROP TABLES
==================================================*/

DROP TABLE IF EXISTS Appointments;
DROP TABLE IF EXISTS Patients;
DROP TABLE IF EXISTS Departments;
DROP TABLE IF EXISTS InsuranceProviders;
DROP TABLE IF EXISTS Clinic_Appointments_Staging;
GO

/*==================================================
    LOOKUP TABLES
==================================================*/

CREATE TABLE Departments
(
    DepartmentID INT IDENTITY(1,1) PRIMARY KEY,
    DepartmentName VARCHAR(100) UNIQUE NOT NULL
);

CREATE TABLE InsuranceProviders
(
    InsuranceID INT IDENTITY(1,1) PRIMARY KEY,
    InsuranceName VARCHAR(100) UNIQUE NOT NULL
);
GO

/*==================================================
    PATIENTS TABLE
==================================================*/

CREATE TABLE Patients
(
    PatientID VARCHAR(50) PRIMARY KEY,
    PatientName VARCHAR(200),
    Gender VARCHAR(20)
);
GO

/*==================================================
    STAGING TABLE
==================================================*/

CREATE TABLE Clinic_Appointments_Staging
(
    AppointmentID      VARCHAR(50),
    PatientID          VARCHAR(50),
    PatientName        VARCHAR(200),
    Gender             VARCHAR(20),
    BirthDate          VARCHAR(50),
    AppointmentDate    VARCHAR(50),
    AppointmentTime    VARCHAR(20),
    DepartmentName     VARCHAR(100),
    DoctorID           VARCHAR(50),
    VisitType          VARCHAR(50),
    InsuranceName      VARCHAR(100),
    BilledAmount       VARCHAR(50),
    PaidAmount         VARCHAR(50),
    AppointmentStatus  VARCHAR(50),
    PhoneNumber        VARCHAR(50),
    City               VARCHAR(100)
);
GO

/*==================================================
    IMPORT CSV FILE
==================================================*/

BULK INSERT Clinic_Appointments_Staging
FROM 'C:\Users\qwert\OneDrive\Desktop\New folder\Project\Clinic_Appointments\DATA\Clinic_Appointments.csv'
WITH
(
    FORMAT = 'CSV',
    FIRSTROW = 2,
    CODEPAGE = '65001',
    KEEPNULLS
);
GO

/*==================================================
    LOAD DEPARTMENTS
==================================================*/

INSERT INTO Departments (DepartmentName)
SELECT DISTINCT
       LTRIM(RTRIM(DepartmentName))
FROM Clinic_Appointments_Staging
WHERE ISNULL(LTRIM(RTRIM(DepartmentName)), '') <> '';
GO

/*==================================================
    LOAD INSURANCE PROVIDERS
==================================================*/

INSERT INTO InsuranceProviders (InsuranceName)
SELECT DISTINCT
       LTRIM(RTRIM(InsuranceName))
FROM Clinic_Appointments_Staging
WHERE ISNULL(LTRIM(RTRIM(InsuranceName)), '') <> '';
GO

/*==================================================
    LOAD PATIENTS
==================================================*/

INSERT INTO Patients
(
    PatientID,
    PatientName,
    Gender
)
SELECT
    PatientID,
    MAX(PatientName),
    MAX(Gender)
FROM Clinic_Appointments_Staging
WHERE ISNULL(PatientID,'') <> ''
GROUP BY PatientID;
GO

/*==================================================
    FACT TABLE
==================================================*/

CREATE TABLE Appointments
(
    AppointmentID VARCHAR(50) PRIMARY KEY,

    PatientID VARCHAR(50) NOT NULL,
    DepartmentID INT NOT NULL,
    InsuranceID INT NOT NULL,

    AppointmentDate DATE NULL,
    AppointmentTime VARCHAR(20) NULL,

    DoctorID VARCHAR(50) NULL,
    VisitType VARCHAR(50) NULL,

    BilledAmount DECIMAL(18,2) NULL,
    PaidAmount DECIMAL(18,2) NULL,

    AppointmentStatus VARCHAR(50) NULL,
    City VARCHAR(100) NULL,

    CONSTRAINT FK_Appointments_Patient
        FOREIGN KEY (PatientID)
        REFERENCES Patients(PatientID),

    CONSTRAINT FK_Appointments_Department
        FOREIGN KEY (DepartmentID)
        REFERENCES Departments(DepartmentID),

    CONSTRAINT FK_Appointments_Insurance
        FOREIGN KEY (InsuranceID)
        REFERENCES InsuranceProviders(InsuranceID)
);
GO

/*==================================================
    LOAD APPOINTMENTS
==================================================*/

;WITH AppointmentCTE AS
(
    SELECT *,
           ROW_NUMBER() OVER
           (
               PARTITION BY AppointmentID
               ORDER BY AppointmentID
           ) AS RN
    FROM Clinic_Appointments_Staging
)

INSERT INTO Appointments
(
    AppointmentID,
    PatientID,
    DepartmentID,
    InsuranceID,
    AppointmentDate,
    AppointmentTime,
    DoctorID,
    VisitType,
    BilledAmount,
    PaidAmount,
    AppointmentStatus,
    City
)
SELECT
    S.AppointmentID,
    S.PatientID,
    D.DepartmentID,
    I.InsuranceID,

    TRY_CONVERT(DATE, NULLIF(S.AppointmentDate,'')),
    NULLIF(S.AppointmentTime,''),

    NULLIF(S.DoctorID,''),
    NULLIF(S.VisitType,''),

    TRY_CONVERT(DECIMAL(18,2), NULLIF(S.BilledAmount,'')),
    TRY_CONVERT(DECIMAL(18,2), NULLIF(S.PaidAmount,'')),

    NULLIF(S.AppointmentStatus,''),
    NULLIF(S.City,'')

FROM AppointmentCTE S
INNER JOIN Departments D
    ON LTRIM(RTRIM(S.DepartmentName)) = D.DepartmentName

INNER JOIN InsuranceProviders I
    ON LTRIM(RTRIM(S.InsuranceName)) = I.InsuranceName

WHERE S.RN = 1;
GO

/*==================================================
    VALIDATION
==================================================*/

SELECT COUNT(*) AS Patients_Count
FROM Patients;

SELECT COUNT(*) AS Departments_Count
FROM Departments;

SELECT COUNT(*) AS InsuranceProviders_Count
FROM InsuranceProviders;

SELECT COUNT(*) AS Appointments_Count
FROM Appointments;
GO

/*==================================================
    KPI QUERIES
==================================================*/

SELECT COUNT(*) AS TotalAppointments
FROM Appointments;

SELECT COUNT(DISTINCT PatientID) AS TotalPatients
FROM Appointments;

SELECT SUM(BilledAmount) AS TotalBilledAmount
FROM Appointments;

SELECT SUM(PaidAmount) AS TotalPaidAmount
FROM Appointments;

SELECT SUM(BilledAmount - PaidAmount) AS OutstandingBalance
FROM Appointments;

SELECT
ROUND(
    SUM(PaidAmount) * 100.0 /
    NULLIF(SUM(BilledAmount),0)
,2) AS CollectionRate
FROM Appointments;

SELECT
ROUND(
    COUNT(CASE WHEN AppointmentStatus = 'Completed' THEN 1 END)
    * 100.0 / NULLIF(COUNT(*),0)
,2) AS CompletionRate
FROM Appointments;

SELECT
ROUND(
    COUNT(CASE WHEN AppointmentStatus = 'No Show' THEN 1 END)
    * 100.0 / NULLIF(COUNT(*),0)
,2) AS NoShowRate
FROM Appointments;
GO

/*==================================================
    DEPARTMENT ANALYSIS
==================================================*/

SELECT
    D.DepartmentName,
    COUNT(*) AS TotalAppointments
FROM Appointments A
INNER JOIN Departments D
    ON A.DepartmentID = D.DepartmentID
GROUP BY D.DepartmentName
ORDER BY TotalAppointments DESC;
GO

/*==================================================
    INSURANCE ANALYSIS
==================================================*/

SELECT
    I.InsuranceName,
    COUNT(*) AS TotalAppointments
FROM Appointments A
INNER JOIN InsuranceProviders I
    ON A.InsuranceID = I.InsuranceID
GROUP BY I.InsuranceName
ORDER BY TotalAppointments DESC;
GO

/*==================================================
    MONTHLY REVENUE
==================================================*/

SELECT
    YEAR(AppointmentDate) AS YearNo,
    MONTH(AppointmentDate) AS MonthNo,
    SUM(BilledAmount) AS Revenue
FROM Appointments
WHERE AppointmentDate IS NOT NULL
GROUP BY
    YEAR(AppointmentDate),
    MONTH(AppointmentDate)
ORDER BY
    YearNo,
    MonthNo;
GO
/*==================================================
    KPI QUERIES
==================================================*/

-- Total Appointments
SELECT
    COUNT(*) AS TotalAppointments
FROM Appointments;
GO

-- Total Patients
SELECT
    COUNT(DISTINCT PatientID) AS TotalPatients
FROM Appointments;
GO

-- Total Billed Amount
SELECT
    SUM(BilledAmount) AS TotalBilledAmount
FROM Appointments;
GO

-- Total Paid Amount
SELECT
    SUM(PaidAmount) AS TotalPaidAmount
FROM Appointments;
GO

-- Outstanding Balance
SELECT
    SUM(BilledAmount - PaidAmount) AS OutstandingBalance
FROM Appointments;
GO

-- Collection Rate (%)
SELECT
    ROUND(
        SUM(PaidAmount) * 100.0 /
        NULLIF(SUM(BilledAmount), 0)
    ,2) AS CollectionRate
FROM Appointments;
GO

-- Appointment Completion Rate (%)
SELECT
    ROUND(
        COUNT(CASE WHEN AppointmentStatus = 'Completed' THEN 1 END)
        * 100.0 /
        NULLIF(COUNT(*),0)
    ,2) AS CompletionRate
FROM Appointments;
GO

-- No Show Rate (%)
SELECT
    ROUND(
        COUNT(CASE WHEN AppointmentStatus = 'No Show' THEN 1 END)
        * 100.0 /
        NULLIF(COUNT(*),0)
    ,2) AS NoShowRate
FROM Appointments;
GO

-- Cancellation Rate (%)
SELECT
    ROUND(
        COUNT(CASE WHEN AppointmentStatus = 'Cancelled' THEN 1 END)
        * 100.0 /
        NULLIF(COUNT(*),0)
    ,2) AS CancellationRate
FROM Appointments;
GO

-- Average Revenue per Appointment
SELECT
    ROUND(AVG(BilledAmount),2) AS AvgRevenuePerAppointment
FROM Appointments;
GO

-- Average Collected per Appointment
SELECT
    ROUND(AVG(PaidAmount),2) AS AvgCollectedPerAppointment
FROM Appointments;
GO

-- Average Outstanding Balance
SELECT
    ROUND(AVG(BilledAmount - PaidAmount),2) AS AvgOutstandingBalance
FROM Appointments;
GO

-- Returning Patients
SELECT
    COUNT(*) AS ReturningPatients
FROM
(
    SELECT PatientID
    FROM Appointments
    GROUP BY PatientID
    HAVING COUNT(*) > 1
) P;
GO
/*==================================================
    DEPARTMENT ANALYSIS
==================================================*/

-- Appointments by Department
SELECT
    D.DepartmentName,
    COUNT(*) AS TotalAppointments
FROM Appointments A
INNER JOIN Departments D
    ON A.DepartmentID = D.DepartmentID
GROUP BY D.DepartmentName
ORDER BY TotalAppointments DESC;
GO

-- Revenue by Department
SELECT
    D.DepartmentName,
    SUM(A.BilledAmount) AS Revenue
FROM Appointments A
INNER JOIN Departments D
    ON A.DepartmentID = D.DepartmentID
GROUP BY D.DepartmentName
ORDER BY Revenue DESC;
GO

-- Collection Rate by Department
SELECT
    D.DepartmentName,
    ROUND(
        SUM(A.PaidAmount) * 100.0 /
        NULLIF(SUM(A.BilledAmount),0)
    ,2) AS CollectionRate
FROM Appointments A
INNER JOIN Departments D
    ON A.DepartmentID = D.DepartmentID
GROUP BY D.DepartmentName
ORDER BY CollectionRate DESC;
GO

-- Top Department
SELECT TOP 1
    D.DepartmentName,
    COUNT(*) AS TotalAppointments
FROM Appointments A
INNER JOIN Departments D
    ON A.DepartmentID = D.DepartmentID
GROUP BY D.DepartmentName
ORDER BY TotalAppointments DESC;
GO
/*==================================================
    INSURANCE ANALYSIS
==================================================*/

-- Appointments by Insurance Provider
SELECT
    I.InsuranceName,
    COUNT(*) AS TotalAppointments
FROM Appointments A
INNER JOIN InsuranceProviders I
    ON A.InsuranceID = I.InsuranceID
GROUP BY I.InsuranceName
ORDER BY TotalAppointments DESC;
GO

-- Top Insurance Provider
SELECT TOP 1
    I.InsuranceName,
    COUNT(*) AS TotalAppointments
FROM Appointments A
INNER JOIN InsuranceProviders I
    ON A.InsuranceID = I.InsuranceID
GROUP BY I.InsuranceName
ORDER BY TotalAppointments DESC;
GO

-- Revenue by Insurance Provider
SELECT
    I.InsuranceName,
    SUM(A.BilledAmount) AS Revenue
FROM Appointments A
INNER JOIN InsuranceProviders I
    ON A.InsuranceID = I.InsuranceID
GROUP BY I.InsuranceName
ORDER BY Revenue DESC;
GO
/*==================================================
    MONTHLY ANALYSIS
==================================================*/

-- Monthly Revenue Trend
SELECT
    YEAR(AppointmentDate) AS YearNo,
    MONTH(AppointmentDate) AS MonthNo,
    SUM(BilledAmount) AS Revenue
FROM Appointments
WHERE AppointmentDate IS NOT NULL
GROUP BY
    YEAR(AppointmentDate),
    MONTH(AppointmentDate)
ORDER BY
    YearNo,
    MonthNo;
GO

-- Monthly Appointments Trend
SELECT
    YEAR(AppointmentDate) AS YearNo,
    MONTH(AppointmentDate) AS MonthNo,
    COUNT(*) AS TotalAppointments
FROM Appointments
WHERE AppointmentDate IS NOT NULL
GROUP BY
    YEAR(AppointmentDate),
    MONTH(AppointmentDate)
ORDER BY
    YearNo,
    MonthNo;
GO
/*==================================================
    CITY ANALYSIS
==================================================*/

-- Appointments by City
SELECT
    City,
    COUNT(*) AS TotalAppointments
FROM Appointments
GROUP BY City
ORDER BY TotalAppointments DESC;
GO

-- Revenue by City
SELECT
    City,
    SUM(BilledAmount) AS Revenue
FROM Appointments
GROUP BY City
ORDER BY Revenue DESC;
GO