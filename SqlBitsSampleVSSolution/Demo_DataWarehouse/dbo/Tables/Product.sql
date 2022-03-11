CREATE TABLE [dbo].[Product] (
    [ProductKey] INT          IDENTITY (1, 1) NOT NULL Primary key,
    [Name]       VARCHAR (50) NOT NULL,
    [Cat]        VARCHAR (50) NOT NULL,
    [Subcat]     VARCHAR (50) NOT NULL,
    [SKU]        VARCHAR (50) NOT NULL
);

