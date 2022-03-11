CREATE view BI.Product as 
select ProductKey,
		Name as [Product],
		Cat as Category,
		Subcat as Subcategory
from dbo.Product