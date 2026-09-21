create or replace function public.get_database_storage_usage()
returns table (used_bytes bigint)
language sql
security definer
set search_path = public
as $$
  select pg_database_size(current_database())::bigint;
$$;

grant execute on function public.get_database_storage_usage() to anon, authenticated;