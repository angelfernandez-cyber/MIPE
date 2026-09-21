create or replace function public.limpiar_datos_respaldo()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from public.aspersiones
  where true;
  delete from public.aseguramiento_plaguicidas
  where true;
end;
$$;

revoke all on function public.limpiar_datos_respaldo() from public;
grant execute on function public.limpiar_datos_respaldo() to anon, authenticated;
