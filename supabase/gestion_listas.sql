-- Gestión de opciones desplegables del módulo de aseguramiento y MIPE.
-- Ejecutar una vez en Supabase SQL Editor.
begin;

create or replace function public.gestionar_opciones_listas_admin(
  p_identificacion text,
  p_password text,
  p_catalogo text,
  p_operacion text,
  p_valor text default null,
  p_id bigint default null,
  p_activo boolean default null
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_nombre text := nullif(btrim(p_valor), '');
  v_id bigint;
  v_resultado jsonb;
begin
  if not exists (
    select 1 from public.persona
    where identificacion::text = p_identificacion
      and password::text = p_password
      and upper(trim(admin::text)) = 'S'
  ) then
    raise exception 'Credenciales de administrador invalidas';
  end if;

  if p_operacion = 'listar' then
    case p_catalogo
      when 'semanas' then
        select coalesce(jsonb_agg(jsonb_build_object('id',id,'valor',numero::text,'activo',activo) order by numero), '[]'::jsonb) into v_resultado from public.aseguramiento_semanas;
      when 'productos' then
        select coalesce(jsonb_agg(jsonb_build_object('id',id,'valor',nombre,'activo',activo) order by lower(nombre)), '[]'::jsonb) into v_resultado from public.aseguramiento_productos;
      when 'proveedores' then
        select coalesce(jsonb_agg(jsonb_build_object('id',id,'valor',nombre,'activo',activo) order by lower(nombre)), '[]'::jsonb) into v_resultado from public.aseguramiento_proveedores;
      when 'presentaciones' then
        select coalesce(jsonb_agg(jsonb_build_object('id',id,'valor',nombre,'activo',activo) order by lower(nombre)), '[]'::jsonb) into v_resultado from public.aseguramiento_presentaciones;
      when 'colores' then
        select coalesce(jsonb_agg(jsonb_build_object('id',id,'valor',nombre,'activo',activo) order by lower(nombre)), '[]'::jsonb) into v_resultado from public.aseguramiento_colores;
      when 'formulas_c' then
        select coalesce(jsonb_agg(jsonb_build_object('id',id,'valor',nombre,'activo',activo) order by lower(nombre)), '[]'::jsonb) into v_resultado from public.aseguramiento_formulas_c;
      when 'categorias_toxicologicas' then
        select coalesce(jsonb_agg(jsonb_build_object('id',id,'valor',nombre,'activo',activo) order by lower(nombre)), '[]'::jsonb) into v_resultado from public.aseguramiento_categorias_toxicologicas;
      when 'tipos_mipe' then
        select coalesce(jsonb_agg(jsonb_build_object('id',id,'valor',nombre,'activo',activo) order by lower(nombre)), '[]'::jsonb) into v_resultado from public.mipe_tipos;
      when 'direcciones_mipe' then
        select coalesce(jsonb_agg(jsonb_build_object('id',id,'valor',nombre,'activo',activo) order by lower(nombre)), '[]'::jsonb) into v_resultado from public.mipe_direcciones;
      when 'grupos_mipe' then
        select coalesce(jsonb_agg(jsonb_build_object('id',id,'valor',nombre,'activo',activo) order by lower(nombre)), '[]'::jsonb) into v_resultado from public.mipe_grupos;
      else raise exception 'Lista no permitida';
    end case;
    return v_resultado;
  end if;

  if p_operacion = 'agregar' then
    if v_nombre is null then raise exception 'Escribe el nombre de la opción'; end if;
    if length(v_nombre) > 100 then raise exception 'La opción no puede superar 100 caracteres'; end if;
    case p_catalogo
      when 'semanas' then
        if v_nombre !~ '^[0-9]{1,2}$' then raise exception 'La semana debe ser un número entre 1 y 52'; end if;
        insert into public.aseguramiento_semanas(numero) values(v_nombre::integer)
        on conflict(numero) do update set activo=true returning id into v_id;
      when 'productos' then insert into public.aseguramiento_productos(nombre) values(v_nombre) on conflict(nombre) do update set activo=true returning id into v_id;
      when 'proveedores' then insert into public.aseguramiento_proveedores(nombre) values(v_nombre) on conflict(nombre) do update set activo=true returning id into v_id;
      when 'presentaciones' then insert into public.aseguramiento_presentaciones(nombre) values(v_nombre) on conflict(nombre) do update set activo=true returning id into v_id;
      when 'colores' then insert into public.aseguramiento_colores(nombre) values(v_nombre) on conflict(nombre) do update set activo=true returning id into v_id;
      when 'formulas_c' then insert into public.aseguramiento_formulas_c(nombre) values(v_nombre) on conflict(nombre) do update set activo=true returning id into v_id;
      when 'categorias_toxicologicas' then insert into public.aseguramiento_categorias_toxicologicas(nombre) values(v_nombre) on conflict(nombre) do update set activo=true returning id into v_id;
      when 'tipos_mipe' then insert into public.mipe_tipos(nombre) values(v_nombre) on conflict(nombre) do update set activo=true returning id into v_id;
      when 'direcciones_mipe' then insert into public.mipe_direcciones(nombre) values(v_nombre) on conflict(nombre) do update set activo=true returning id into v_id;
      when 'grupos_mipe' then insert into public.mipe_grupos(nombre) values(v_nombre) on conflict(nombre) do update set activo=true returning id into v_id;
      else raise exception 'Lista no permitida';
    end case;
    return jsonb_build_object('ok', true, 'id', v_id);
  end if;

  if p_operacion = 'estado' then
    if p_id is null or p_activo is null then raise exception 'Falta el estado de la opción'; end if;
    case p_catalogo
      when 'semanas' then update public.aseguramiento_semanas set activo=p_activo where id=p_id returning id into v_id;
      when 'productos' then update public.aseguramiento_productos set activo=p_activo where id=p_id returning id into v_id;
      when 'proveedores' then update public.aseguramiento_proveedores set activo=p_activo where id=p_id returning id into v_id;
      when 'presentaciones' then update public.aseguramiento_presentaciones set activo=p_activo where id=p_id returning id into v_id;
      when 'colores' then update public.aseguramiento_colores set activo=p_activo where id=p_id returning id into v_id;
      when 'formulas_c' then update public.aseguramiento_formulas_c set activo=p_activo where id=p_id returning id into v_id;
      when 'categorias_toxicologicas' then update public.aseguramiento_categorias_toxicologicas set activo=p_activo where id=p_id returning id into v_id;
      when 'tipos_mipe' then update public.mipe_tipos set activo=p_activo where id=p_id returning id into v_id;
      when 'direcciones_mipe' then update public.mipe_direcciones set activo=p_activo where id=p_id returning id into v_id;
      when 'grupos_mipe' then update public.mipe_grupos set activo=p_activo where id=p_id returning id into v_id;
      else raise exception 'Lista no permitida';
    end case;
    if v_id is null then raise exception 'No se encontró la opción'; end if;
    return jsonb_build_object('ok', true, 'id', v_id, 'activo', p_activo);
  end if;

  if p_operacion = 'editar' then
    if p_id is null or v_nombre is null then raise exception 'Falta el valor para actualizar'; end if;
    case p_catalogo
      when 'semanas' then
        if v_nombre !~ '^[0-9]{1,2}$' then raise exception 'La semana debe ser un número entre 1 y 52'; end if;
        update public.aseguramiento_semanas set numero=v_nombre::integer where id=p_id returning id into v_id;
      when 'productos' then update public.aseguramiento_productos set nombre=v_nombre where id=p_id returning id into v_id;
      when 'proveedores' then update public.aseguramiento_proveedores set nombre=v_nombre where id=p_id returning id into v_id;
      when 'presentaciones' then update public.aseguramiento_presentaciones set nombre=v_nombre where id=p_id returning id into v_id;
      when 'colores' then update public.aseguramiento_colores set nombre=v_nombre where id=p_id returning id into v_id;
      when 'formulas_c' then update public.aseguramiento_formulas_c set nombre=v_nombre where id=p_id returning id into v_id;
      when 'categorias_toxicologicas' then update public.aseguramiento_categorias_toxicologicas set nombre=v_nombre where id=p_id returning id into v_id;
      when 'tipos_mipe' then update public.mipe_tipos set nombre=v_nombre where id=p_id returning id into v_id;
      when 'direcciones_mipe' then update public.mipe_direcciones set nombre=v_nombre where id=p_id returning id into v_id;
      when 'grupos_mipe' then update public.mipe_grupos set nombre=v_nombre where id=p_id returning id into v_id;
      else raise exception 'Lista no permitida';
    end case;
    if v_id is null then raise exception 'No se encontró la opción'; end if;
    return jsonb_build_object('ok', true, 'id', v_id);
  end if;

  if p_operacion = 'eliminar' then
    if p_id is null then raise exception 'Falta la opción para eliminar'; end if;
    case p_catalogo
      when 'semanas' then delete from public.aseguramiento_semanas where id=p_id returning id into v_id;
      when 'productos' then delete from public.aseguramiento_productos where id=p_id returning id into v_id;
      when 'proveedores' then delete from public.aseguramiento_proveedores where id=p_id returning id into v_id;
      when 'presentaciones' then delete from public.aseguramiento_presentaciones where id=p_id returning id into v_id;
      when 'colores' then delete from public.aseguramiento_colores where id=p_id returning id into v_id;
      when 'formulas_c' then delete from public.aseguramiento_formulas_c where id=p_id returning id into v_id;
      when 'categorias_toxicologicas' then delete from public.aseguramiento_categorias_toxicologicas where id=p_id returning id into v_id;
      when 'tipos_mipe' then delete from public.mipe_tipos where id=p_id returning id into v_id;
      when 'direcciones_mipe' then delete from public.mipe_direcciones where id=p_id returning id into v_id;
      when 'grupos_mipe' then delete from public.mipe_grupos where id=p_id returning id into v_id;
      else raise exception 'Lista no permitida';
    end case;
    if v_id is null then raise exception 'No se encontró la opción'; end if;
    return jsonb_build_object('ok', true, 'id', v_id);
  end if;

  raise exception 'Operación no permitida';
end;
$$;

revoke all on function public.gestionar_opciones_listas_admin(text,text,text,text,text,bigint,boolean) from public;
grant execute on function public.gestionar_opciones_listas_admin(text,text,text,text,text,bigint,boolean) to anon, authenticated;

notify pgrst, 'reload schema';

commit;
