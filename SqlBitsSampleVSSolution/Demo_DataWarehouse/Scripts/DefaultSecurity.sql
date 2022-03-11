If Not Exists(Select * From sys.database_principals Where name = 'PowerBI') 
Begin 
	Print 'Creating user [PowerBI]...'
	Create USER [PowerBI]
		With PASSWORD = 'reJ_kcxqn2||g{QzuxnPiH_jmsFT7_&#$!~<j}zjbbuuaRmx'
end
GO

Alter Role [BIReader] Add Member [PowerBI]
Go
