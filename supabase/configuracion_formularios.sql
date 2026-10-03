create table if not exists public.configuracion_formularios (
  formulario text primary key check (formulario in ('mipe', 'almacen')),
  orden jsonb not null,
  filas jsonb not null default '[]'::jsonb,
  etiquetas jsonb not null default '{}'::jsonb,
  actualizado_por text references public.persona(identificacion),
  actualizado_en timestamptz not null default now()
);

alter table public.configuracion_formularios
  add column if not exists filas jsonb not null default '[]'::jsonb;
alter table public.configuracion_formularios
  add column if not exists etiquetas jsonb not null default '{}'::jsonb;

alter table public.configuracion_formularios enable row level security;
revoke all on table public.configuracion_formularios from public, anon, authenticated;

create or replace function public.obtener_ordenes_formularios()
returns jsonb
language sql
security definer
set search_path = public, pg_temp
as $$
  select coalesce(jsonb_object_agg(formulario, orden), '{}'::jsonb)
  from public.configuracion_formularios;
$$;

create or replace function public.obtener_configuracion_formularios()
returns jsonb
language sql
security definer
set search_path = public, pg_temp
as $$
  select coalesce(
    jsonb_object_agg(
      formulario,
      jsonb_build_object('orden', orden, 'filas', filas, 'etiquetas', etiquetas)
    ),
    '{}'::jsonb
  )
  from public.configuracion_formularios;
$$;

create or replace function public.guardar_orden_formulario(
  p_identificacion text,
  p_password text,
  p_formulario text,
  p_orden jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_campos text[];
  v_cantidad_validos integer;
begin
  if not exists (
    select 1
    from public.persona
    where identificacion = p_identificacion
      and password = p_password
      and upper(trim(coalesce(admin::text, 'N'))) = 'S'
  ) then
    raise exception 'Solo un administrador puede cambiar el orden de los formularios';
  end if;

  v_campos := case p_formulario
    when 'mipe' then array[
      'bloque', 'bombero', 'jefe_mipe', 'semana', 'dia', 'temperatura',
      'humedad', 'tipo', 'direccion', 'productos', 'volumen_cama',
      'numero_camas', 'grupos_fumigadores', 'equipo', 'ire',
      'administrador_autoriza', 'firma_registra', 'firma_autoriza'
    ]
    when 'almacen' then array[
      'semana', 'nombre_producto', 'casa_comercial', 'presentacion',
      'total_unidades', 'lote', 'cantidad', 'formula_c',
      'categoria_toxicologica', 'fecha_vencimiento', 'estado_etiqueta',
      'estado_tapa', 'sellos', 'puntos_extraccion', 'cumplimiento',
      'color', 'otro_color', 'ph', 'densidad', 'observaciones',
      'administrador_autoriza', 'firma_asegura', 'firma_autoriza'
    ]
    else null
  end;
  if v_campos is null or jsonb_typeof(p_orden) <> 'array'
     or jsonb_array_length(p_orden) <> cardinality(v_campos) then
    raise exception 'Formulario u orden no válidos';
  end if;

  select count(distinct campo)
  into v_cantidad_validos
  from jsonb_array_elements_text(p_orden) as elemento(campo)
  where campo = any(v_campos);

  if v_cantidad_validos <> cardinality(v_campos) then
    raise exception 'La lista debe incluir cada bloque del formulario una sola vez';
  end if;

  insert into public.configuracion_formularios(
    formulario, orden, actualizado_por, actualizado_en
  )
  values (p_formulario, p_orden, p_identificacion, now())
  on conflict (formulario) do update
    set orden = excluded.orden,
        actualizado_por = excluded.actualizado_por,
        actualizado_en = now();

  return jsonb_build_object('ok', true);
end;
$$;

create or replace function public.guardar_configuracion_formulario(
  p_identificacion text,
  p_password text,
  p_formulario text,
  p_orden jsonb,
  p_filas jsonb,
  p_etiquetas jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_campos text[];
  v_etiquetas_campos text[];
  v_cantidad_validos integer;
  v_etiquetas_validas integer;
  v_orden_filas jsonb;
begin
  if not exists (
    select 1
    from public.persona
    where identificacion = p_identificacion
      and password = p_password
      and upper(trim(coalesce(admin::text, 'N'))) = 'S'
  ) then
    raise exception 'Solo un administrador puede cambiar los formularios';
  end if;

  v_campos := case p_formulario
    when 'mipe' then array[
      'bloque', 'bombero', 'jefe_mipe', 'semana', 'dia', 'temperatura',
      'humedad', 'tipo', 'direccion', 'productos', 'volumen_cama',
      'numero_camas', 'grupos_fumigadores', 'equipo', 'ire',
      'administrador_autoriza', 'firma_registra', 'firma_autoriza'
    ]
    when 'almacen' then array[
      'semana', 'nombre_producto', 'casa_comercial', 'presentacion',
      'total_unidades', 'lote', 'cantidad', 'formula_c',
      'categoria_toxicologica', 'fecha_vencimiento', 'estado_etiqueta',
      'estado_tapa', 'sellos', 'puntos_extraccion', 'cumplimiento',
      'color', 'otro_color', 'ph', 'densidad', 'observaciones',
      'administrador_autoriza', 'firma_asegura', 'firma_autoriza'
    ]
    else null
  end;
  v_etiquetas_campos := v_campos || case p_formulario
    when 'mipe' then array[
      'producto_item_nombre', 'producto_item_dosis',
      'producto_item_categoria', 'producto_item_blanco'
    ]
    else array[]::text[]
  end;

  if v_campos is null or jsonb_typeof(p_orden) <> 'array'
     or jsonb_array_length(p_orden) <> cardinality(v_campos) then
    raise exception 'Formulario u orden no válidos';
  end if;

  select count(distinct campo)
  into v_cantidad_validos
  from jsonb_array_elements_text(p_orden) as elemento(campo)
  where campo = any(v_campos);

  if v_cantidad_validos <> cardinality(v_campos) then
    raise exception 'El orden debe incluir cada campo una sola vez';
  end if;

  if jsonb_typeof(p_filas) <> 'array' or jsonb_array_length(p_filas) = 0 then
    raise exception 'La distribución de filas no es válida';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(p_filas) as fila(campos)
    where jsonb_typeof(fila.campos) <> 'array'
       or jsonb_array_length(fila.campos) < 1
       or jsonb_array_length(fila.campos) > 2
  ) then
    raise exception 'Cada fila debe contener uno o dos campos';
  end if;

  select jsonb_agg(campo.nombre order by fila.posicion, campo.posicion)
  into v_orden_filas
  from jsonb_array_elements(p_filas) with ordinality as fila(campos, posicion)
  cross join lateral jsonb_array_elements_text(fila.campos)
    with ordinality as campo(nombre, posicion);

  if v_orden_filas <> p_orden then
    raise exception 'El orden y las filas no coinciden';
  end if;

  if jsonb_typeof(coalesce(p_etiquetas, '{}'::jsonb)) <> 'object' then
    raise exception 'Las etiquetas no tienen un formato válido';
  end if;

  select count(*)
  into v_etiquetas_validas
  from jsonb_each_text(coalesce(p_etiquetas, '{}'::jsonb)) as etiqueta(campo, nombre)
  where campo = any(v_etiquetas_campos)
    and length(trim(nombre)) between 1 and 80;

  if v_etiquetas_validas <> jsonb_object_length(coalesce(p_etiquetas, '{}'::jsonb)) then
    raise exception 'Cada etiqueta debe pertenecer a un campo y tener entre 1 y 80 caracteres';
  end if;

  insert into public.configuracion_formularios(
    formulario, orden, filas, etiquetas, actualizado_por, actualizado_en
  )
  values (
    p_formulario,
    p_orden,
    p_filas,
    coalesce(p_etiquetas, '{}'::jsonb),
    p_identificacion,
    now()
  )
  on conflict (formulario) do update
    set orden = excluded.orden,
      filas = excluded.filas,
        etiquetas = excluded.etiquetas,
        actualizado_por = excluded.actualizado_por,
        actualizado_en = now();

  return jsonb_build_object('ok', true);
end;
$$;

revoke all on function public.obtener_ordenes_formularios() from public;
revoke all on function public.obtener_configuracion_formularios() from public;
revoke all on function public.guardar_orden_formulario(text, text, text, jsonb) from public;
revoke all on function public.guardar_configuracion_formulario(text, text, text, jsonb, jsonb, jsonb) from public;
grant execute on function public.obtener_ordenes_formularios() to anon, authenticated;
grant execute on function public.obtener_configuracion_formularios() to anon, authenticated;
grant execute on function public.guardar_orden_formulario(text, text, text, jsonb) to anon, authenticated;
grant execute on function public.guardar_configuracion_formulario(text, text, text, jsonb, jsonb, jsonb) to anon, authenticated;
