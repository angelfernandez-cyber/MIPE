-- Acceso temporal para visitantes. Ejecutar en el SQL Editor de Supabase.
begin;

create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;

create schema if not exists private;

create table if not exists private.configuracion_visitante (
  id boolean primary key default true check (id),
  habilitado boolean not null default false,
  puede_insertar boolean not null default false,
  puede_exportar boolean not null default false,
  puede_ver_aspersiones boolean not null default false,
  secreto text not null default encode(extensions.gen_random_bytes(32), 'hex')
);
insert into private.configuracion_visitante (id) values (true) on conflict (id) do nothing;
revoke all on private.configuracion_visitante from public, anon, authenticated;

create table if not exists private.intentos_codigo_visitante (
  ip_hash text primary key,
  inicio_ventana timestamptz not null,
  intentos integer not null default 0
);
revoke all on private.intentos_codigo_visitante from public, anon, authenticated;

create or replace function public.codigo_visitante_admin(p_identificacion text, p_password text)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private, extensions
as $$
declare
  v_secret text;
  v_digest text;
  v_code text;
  v_minute bigint := floor(extract(epoch from clock_timestamp()) / 60)::bigint;
  v_hex24 text;
  v_valor bigint;
begin
  if not exists (
    select 1 from public.persona
    where identificacion::text = p_identificacion
      and password::text = p_password
      and upper(trim(admin::text)) = 'S'
  ) then
    raise exception 'Credenciales de administrador invalidas';
  end if;

  select secreto into v_secret from private.configuracion_visitante where id = true and habilitado;
  if v_secret is null then raise exception 'Acceso de visitantes deshabilitado'; end if;

  v_digest := encode(extensions.hmac(v_minute::text, v_secret, 'sha256'), 'hex');
  v_hex24 := substr(v_digest, 1, 6);
  v_valor := (
      get_byte(decode(substring(v_hex24 from 1 for 2), 'hex'), 0) * 65536 +
      get_byte(decode(substring(v_hex24 from 3 for 2), 'hex'), 0) * 256 +
      get_byte(decode(substring(v_hex24 from 5 for 2), 'hex'), 0)
  ) % 1000000;
  v_code := lpad(v_valor::text, 6, '0');
  return jsonb_build_object('codigo', v_code, 'cambia_en_segundos', 60 - (extract(epoch from clock_timestamp())::integer % 60));
end;
$$;

create or replace function public.validar_codigo_visitante(p_codigo text)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private, extensions
as $$
declare
  v_config private.configuracion_visitante%rowtype;
  v_digest text;
  v_code text;
  v_code_anterior text;
  v_minute bigint := floor(extract(epoch from clock_timestamp()) / 60)::bigint;
  v_lectura text := 'mapa,almacen';
  v_ip text;
  v_ip_hash text;
  v_intentos private.intentos_codigo_visitante%rowtype;
  v_hex24 text;
  v_valor bigint;
begin
  select * into v_config from private.configuracion_visitante where id = true;
  if not found or not v_config.habilitado then raise exception 'Acceso de visitantes deshabilitado'; end if;
  v_ip := split_part(
    coalesce(nullif(current_setting('request.headers', true), '')::jsonb->>'x-forwarded-for', 'desconocido'),
    ',', 1
  );
  v_ip_hash := encode(extensions.digest(v_ip, 'sha256'), 'hex');
  select * into v_intentos from private.intentos_codigo_visitante where ip_hash = v_ip_hash;
  if found and v_intentos.inicio_ventana > clock_timestamp() - interval '10 minutes' and v_intentos.intentos >= 10 then
    return jsonb_build_object('error', 'Demasiados intentos. Espera 10 minutos.');
  end if;

  v_digest := encode(extensions.hmac(v_minute::text, v_config.secreto, 'sha256'), 'hex');
  v_hex24 := substr(v_digest, 1, 6);
  v_valor := (
      get_byte(decode(substring(v_hex24 from 1 for 2), 'hex'), 0) * 65536 +
      get_byte(decode(substring(v_hex24 from 3 for 2), 'hex'), 0) * 256 +
      get_byte(decode(substring(v_hex24 from 5 for 2), 'hex'), 0)
  ) % 1000000;
  v_code := lpad(v_valor::text, 6, '0');

  -- Aceptar también el minuto anterior evita rechazos si el visitante
  -- termina de escribir mientras el código cambia en la pantalla del admin.
  v_digest := encode(extensions.hmac((v_minute - 1)::text, v_config.secreto, 'sha256'), 'hex');
  v_hex24 := substr(v_digest, 1, 6);
  v_valor := (
      get_byte(decode(substring(v_hex24 from 1 for 2), 'hex'), 0) * 65536 +
      get_byte(decode(substring(v_hex24 from 3 for 2), 'hex'), 0) * 256 +
      get_byte(decode(substring(v_hex24 from 5 for 2), 'hex'), 0)
  ) % 1000000;
  v_code_anterior := lpad(v_valor::text, 6, '0');
  if p_codigo is null or p_codigo !~ '^[0-9]{6}$' or (p_codigo <> v_code and p_codigo <> v_code_anterior) then
    insert into private.intentos_codigo_visitante as intentos_previos (ip_hash, inicio_ventana, intentos)
    values (v_ip_hash, clock_timestamp(), 1)
    on conflict (ip_hash) do update set
      inicio_ventana = case when intentos_previos.inicio_ventana <= clock_timestamp() - interval '10 minutes' then clock_timestamp() else intentos_previos.inicio_ventana end,
      intentos = case when intentos_previos.inicio_ventana <= clock_timestamp() - interval '10 minutes' then 1 else intentos_previos.intentos + 1 end;
    return jsonb_build_object('error', 'Codigo invalido o vencido');
  end if;
  delete from private.intentos_codigo_visitante where ip_hash = v_ip_hash;

  if v_config.puede_insertar then v_lectura := v_lectura || ',scanner'; end if;
  if v_config.puede_exportar then v_lectura := v_lectura || ',exportar_excel'; end if;
  if v_config.puede_ver_aspersiones then v_lectura := v_lectura || ',ver_aspersiones'; end if;
  v_lectura := v_lectura || ',' || (select string_agg(n::text, ',' order by n) from generate_series(401,445) n);

  return jsonb_build_object(
    'identificacion', 'VISITANTE', 'nombres', 'Visitante', 'admin', 'N',
    'lectura', v_lectura, 'visitante', true,
    'puede_insertar', v_config.puede_insertar,
    'puede_exportar', v_config.puede_exportar,
    'expira_en', (clock_timestamp() + interval '5 hours')
  );
end;
$$;

-- Postgres no permite cambiar el tipo de retorno con CREATE OR REPLACE.
-- Se elimina solo esta función del módulo de visitantes antes de recrearla.
drop function if exists public.configurar_visitantes_admin(text,text,boolean,boolean,boolean,boolean);

create function public.configurar_visitantes_admin(
  p_identificacion text, p_password text, p_habilitado boolean,
  p_puede_insertar boolean, p_puede_exportar boolean, p_puede_ver_aspersiones boolean
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
begin
  if not exists (
    select 1 from public.persona
    where identificacion::text = p_identificacion
      and password::text = p_password
      and upper(trim(admin::text)) = 'S'
  ) then raise exception 'Credenciales de administrador invalidas'; end if;

  update private.configuracion_visitante set
    habilitado = p_habilitado,
    puede_insertar = p_puede_insertar,
    puede_exportar = p_puede_exportar,
    puede_ver_aspersiones = p_puede_ver_aspersiones
  where id = true;
  return jsonb_build_object('ok', true);
end;
$$;

create or replace function public.obtener_configuracion_visitantes()
returns jsonb
language sql
security definer
set search_path = pg_catalog, private
as $$
  select jsonb_build_object(
    'habilitado', habilitado,
    'puede_insertar', puede_insertar,
    'puede_exportar', puede_exportar,
    'puede_ver_aspersiones', puede_ver_aspersiones
  ) from private.configuracion_visitante where id = true;
$$;

revoke all on function public.codigo_visitante_admin(text,text) from public;
revoke all on function public.validar_codigo_visitante(text) from public;
revoke all on function public.configurar_visitantes_admin(text,text,boolean,boolean,boolean,boolean) from public;
revoke all on function public.obtener_configuracion_visitantes() from public;
grant execute on function public.codigo_visitante_admin(text,text) to anon, authenticated;
grant execute on function public.validar_codigo_visitante(text) to anon, authenticated;
grant execute on function public.configurar_visitantes_admin(text,text,boolean,boolean,boolean,boolean) to anon, authenticated;
grant execute on function public.obtener_configuracion_visitantes() to anon, authenticated;

notify pgrst, 'reload schema';

commit;
