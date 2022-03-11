CREATE TABLE [Control].[ChangeTracking] (
    [ChangeTrackingKey] INT           IDENTITY (1, 1) NOT NULL,
    [Change]            VARCHAR (50)  NOT NULL,
    [ChangeDate]        DATETIME2 (7) CONSTRAINT [df_ChangeDate] DEFAULT (getdate()) NOT NULL,
    CONSTRAINT [pk_ChangeTracking] PRIMARY KEY CLUSTERED ([ChangeTrackingKey] ASC),
    CONSTRAINT [uniqueChange] UNIQUE NONCLUSTERED ([Change] ASC)
);

