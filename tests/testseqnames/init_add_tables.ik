set add table (id=1, set id=1, origin=1, fully qualified name = 'public.table1', comment='accounts table');
set add table (id=2, set id=1, origin=1, fully qualified name = 'public.table2', key='table2_id_key');
set add table (id=3, set id=1, origin=1, fully qualified name = 'public.table3');
set add sequence (set id = 1, origin = 1, id = 1, fully qualified name = 'public."Evil Spacey Sequence Name"');

set add sequence (set id = 1, origin = 1, id = 2, fully qualified name = '"Studly Spacey Schema"."user"');

set add sequence (set id = 1, origin = 1, id = 3, fully qualified name = '"Schema.name"."a.periodic.sequence"');
