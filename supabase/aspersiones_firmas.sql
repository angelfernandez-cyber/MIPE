-- Firmas del formulario de Mapa de bloques (Registro MIPE):
--   * quien registra (usuario que llena el formulario)
--   * administrador que autoriza
-- Reemplazan a los campos de facilitadores. Misma lógica que almacén.
-- Requiere haber ejecutado supabase/firmas_digitales.sql.

alter table public.aspersiones
  add column if not exists identificacion_registra text,
  add column if not exists firma_registra_base64 text,
  add column if not exists nombre_autoriza text,
  add column if not exists identificacion_autoriza text,
  add column if not exists firma_autoriza_base64 text;

-- Si un registro llega sin firma (por ejemplo, sincronizado sin conexión),
-- se completa con la firma guardada de esa persona.
create or replace function public.completar_firma_aspersion()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if nullif(new.firma_registra_base64, '') is null
     and nullif(new.identificacion_registra, '') is not null then
    select f.firma_png_base64
      into new.firma_registra_base64
    from public.firmas_usuarios f
    where f.identificacion = new.identificacion_registra;
  end if;

  if nullif(new.firma_autoriza_base64, '') is null
     and nullif(new.identificacion_autoriza, '') is not null then
    select f.firma_png_base64
      into new.firma_autoriza_base64
    from public.firmas_usuarios f
    where f.identificacion = new.identificacion_autoriza;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_completar_firma_aspersion on public.aspersiones;
create trigger trg_completar_firma_aspersion
before insert or update on public.aspersiones
for each row execute function public.completar_firma_aspersion();
