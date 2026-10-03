
create table if not exists public.historial_permisos_bloques (
  id bigserial primary key,
  identificacion_usuario text not null,
  nombre_usuario text,
  lectura_anterior text,
  lectura_nueva text not null,
  identificacion_autoriza text not null,
  nombre_autoriza text,
  firma_autoriza_base64 text not null,
  creado_en timestamptz not null default now()
);

alter table public.historial_permisos_bloques enable row level security;
revoke all on table public.historial_permisos_bloques from public, anon, authenticated;

create or replace function public.guardar_permisos_bloques_firmado(
  p_identificacion text,
  p_password text,
  p_usuario text,
  p_lectura text,
  p_firma_png_base64 text
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_nombre_admin text;
  v_nombre_usuario text;
  v_lectura_anterior text;
  v_firma text;
  v_usar_predeterminada boolean;
begin
  select nombres
    into v_nombre_admin
  from public.persona
  where identificacion = p_identificacion
    and password = p_password
    and upper(trim(coalesce(admin::text, 'N'))) = 'S';

  if not found then
    raise exception 'Solo un administrador puede cambiar los permisos de bloques';
  end if;

  select nombres, lectura
    into v_nombre_usuario, v_lectura_anterior
  from public.persona
  where identificacion = p_usuario;

  if not found then
    raise exception 'El usuario no existe';
  end if;

  v_firma := nullif(trim(coalesce(p_firma_png_base64, '')), '');

  -- Sin firma enviada: usar la predeterminada solo si está habilitada.
  if v_firma is null then
    select coalesce(pref.usar_firma_predeterminada, true), f.firma_png_base64
      into v_usar_predeterminada, v_firma
    from public.persona p
    left join public.firmas_usuarios f on f.identificacion = p.identificacion
    left join public.preferencias_firma_usuarios pref
      on pref.identificacion = p.identificacion
    where p.identificacion = p_identificacion;

    if not coalesce(v_usar_predeterminada, true) then
      v_firma := null;
    end if;
  end if;

  if v_firma is null then
    raise exception 'Debes firmar para guardar los permisos de bloques';
  end if;

  if length(v_firma) < 20 or length(v_firma) > 300000 then
    raise exception 'La firma está vacía o excede el tamaño permitido';
  end if;

  update public.persona
  set lectura = coalesce(nullif(trim(p_lectura), ''), 'N')
  where identificacion = p_usuario;

  insert into public.historial_permisos_bloques(
    identificacion_usuario,
    nombre_usuario,
    lectura_anterior,
    lectura_nueva,
    identificacion_autoriza,
    nombre_autoriza,
    firma_autoriza_base64
  )
  values (
    p_usuario,
    v_nombre_usuario,
    v_lectura_anterior,
    coalesce(nullif(trim(p_lectura), ''), 'N'),
    p_identificacion,
    v_nombre_admin,
    v_firma
  );

  return jsonb_build_object('ok', true);
end;
$$;

revoke all on function public.guardar_permisos_bloques_firmado(text, text, text, text, text) from public;
grant execute on function public.guardar_permisos_bloques_firmado(text, text, text, text, text) to anon, authenticated;
