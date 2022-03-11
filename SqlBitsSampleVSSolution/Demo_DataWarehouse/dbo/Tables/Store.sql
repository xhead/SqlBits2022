CREATE TABLE [dbo].[Store] (
    [StoreKey]   INT          IDENTITY (1, 1) NOT NULL,
    [Name]       VARCHAR (50) NOT NULL,
    [Number]     INT          NOT NULL,
    [Address]    VARCHAR (50) NULL,
    [City]       VARCHAR (50) NULL,
    [Region]     VARCHAR (50) NULL,
    [Country]    VARCHAR (50) NULL,
    [PostalCode] VARCHAR (50) NULL,
    CONSTRAINT [pk_Store] PRIMARY KEY CLUSTERED ([StoreKey] ASC)
);

