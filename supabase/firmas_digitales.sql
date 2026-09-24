-- Firmas dibujadas reutilizables por usuario para el módulo de aseguramiento.
create table if not exists public.firmas_usuarios (
  identificacion text primary key references public.persona(identificacion) on delete cascade,
  firma_png_base64 text not null,
  actualizado_en timestamptz not null default now()
);

alter table public.aseguramiento_plaguicidas
  add column if not exists nombre_quien_asegura text,
  add column if not exists nombre_autoriza text,
  add column if not exists identificacion_autoriza text,
  add column if not exists firma_asegura_base64 text,
  add column if not exists firma_autoriza_base64 text;

alter table public.firmas_usuarios enable row level security;
revoke all on table public.firmas_usuarios from public, anon, authenticated;

create or replace function public.guardar_firma_usuario(
  p_identificacion text,
  p_password text,
  p_firma_png_base64 text
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if length(coalesce(p_firma_png_base64, '')) < 20
    or length(p_firma_png_base64) > 300000 then
    raise exception 'La firma está vacía o excede el tamaño permitido';
  end if;

  if not exists (
    select 1 from public.persona
    where identificacion = p_identificacion
      and password = p_password
  ) then
    raise exception 'Usuario o contraseña incorrectos';
  end if;

  insert into public.firmas_usuarios(identificacion, firma_png_base64, actualizado_en)
  values (p_identificacion, p_firma_png_base64, now())
  on conflict (identificacion) do update
    set firma_png_base64 = excluded.firma_png_base64,
        actualizado_en = now();

  return jsonb_build_object('ok', true);
end;
$$;

create or replace function public.obtener_firmas_aseguramiento(
  p_identificacion text,
  p_password text
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_firmas jsonb;
begin
  if not exists (
    select 1 from public.persona
    where identificacion = p_identificacion
      and password = p_password
  ) then
    raise exception 'Usuario o contraseña incorrectos';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'identificacion', p.identificacion,
    'nombres', p.nombres,
    'admin', p.admin,
    'firma_png_base64', f.firma_png_base64,
    'actualizado_en', f.actualizado_en
  ) order by lower(coalesce(p.nombres, ''))), '[]'::jsonb)
  into v_firmas
  from public.persona p
  left join public.firmas_usuarios f on f.identificacion = p.identificacion
  where p.identificacion = p_identificacion
     or upper(trim(coalesce(p.admin::text, 'N'))) = 'S';

  return v_firmas;
end;
$$;

create or replace function public.eliminar_firma_usuario(
  p_identificacion text,
  p_password text
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if not exists (
    select 1 from public.persona
    where identificacion = p_identificacion
      and password = p_password
  ) then
    raise exception 'Usuario o contraseña incorrectos';
  end if;

  delete from public.firmas_usuarios
  where identificacion = p_identificacion;

  return jsonb_build_object('ok', true);
end;
$$;

revoke all on function public.guardar_firma_usuario(text, text, text) from public;
revoke all on function public.obtener_firmas_aseguramiento(text, text) from public;
revoke all on function public.eliminar_firma_usuario(text, text) from public;
grant execute on function public.guardar_firma_usuario(text, text, text) to anon, authenticated;
grant execute on function public.obtener_firmas_aseguramiento(text, text) to anon, authenticated;
grant execute on function public.eliminar_firma_usuario(text, text) to anon, authenticated;

-- Completa automáticamente las firmas al guardar un registro, incluso si
-- el cliente todavía no alcanzó a cargar la copia local de las firmas.
create or replace function public.completar_firmas_aseguramiento()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if nullif(new.firma_asegura_base64, '') is null
     and nullif(new.identificacion_asegura, '') is not null then
    select f.firma_png_base64
      into new.firma_asegura_base64
    from public.firmas_usuarios f
    where f.identificacion = new.identificacion_asegura;
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

drop trigger if exists trg_completar_firmas_aseguramiento
  on public.aseguramiento_plaguicidas;
create trigger trg_completar_firmas_aseguramiento
before insert or update on public.aseguramiento_plaguicidas
for each row execute function public.completar_firmas_aseguramiento();

-- Recupera registros históricos cuando la identificación permite encontrar
-- una firma guardada. Para quien autoriza, solo infiere el ID si el nombre
-- corresponde a un único administrador con firma registrada.
with administradores_por_nombre as (
  select lower(trim(p.nombres)) as nombre_normalizado,
         min(p.identificacion) as identificacion
  from public.persona p
  join public.firmas_usuarios f on f.identificacion = p.identificacion
  where upper(trim(coalesce(p.admin::text, 'N'))) = 'S'
    and nullif(trim(p.nombres), '') is not null
  group by lower(trim(p.nombres))
  having count(*) = 1
)
update public.aseguramiento_plaguicidas a
set identificacion_autoriza = apn.identificacion
from administradores_por_nombre apn
where a.identificacion_autoriza is null
  and lower(trim(coalesce(a.nombre_autoriza, a.autorizacion, ''))) = apn.nombre_normalizado;

update public.aseguramiento_plaguicidas a
set firma_asegura_base64 = f.firma_png_base64
from public.firmas_usuarios f
where a.firma_asegura_base64 is null
  and a.identificacion_asegura = f.identificacion;

update public.aseguramiento_plaguicidas a
set firma_autoriza_base64 = f.firma_png_base64
from public.firmas_usuarios f
where a.firma_autoriza_base64 is null
  and a.identificacion_autoriza = f.identificacion;
