
-- ***** CASO 1 ***** --

SET SERVEROUTPUT ON
DECLARE
  -- Cursor: atenciones con pago fuera de plazo en el año anterior
  CURSOR c_atenciones IS
    SELECT a.ate_id,
           p.fecha_venc_pago,
           p.fecha_pago,
           a.pac_run,
           pac.dv_run,
           pac.pnombre || ' ' || pac.apaterno AS pac_nombre,
           pac.fecha_nacimiento,
           e.nombre AS especialidad
    FROM ATENCION a
    JOIN PAGO_ATENCION p ON a.ate_id = p.ate_id
    JOIN PACIENTE pac ON a.pac_run = pac.pac_run
    LEFT JOIN ESPECIALIDAD e ON a.esp_id = e.esp_id
    WHERE p.fecha_pago IS NOT NULL
      AND p.fecha_pago > p.fecha_venc_pago
      AND EXTRACT(YEAR FROM p.fecha_venc_pago) = EXTRACT(YEAR FROM SYSDATE) - 1
    ORDER BY p.fecha_venc_pago ASC, pac.apaterno ASC;

  -- VARRAY de multas por índice (índice 1..8)
  TYPE multa_varray IS VARRAY(8) OF NUMBER;
  multas multa_varray := multa_varray(1200,1300,1700,1900,1100,2000,2300,2300);

  -- Mapeo especialidad -> índice del varray (associative array)
  TYPE t_map IS TABLE OF PLS_INTEGER INDEX BY VARCHAR2(100);
  mapa_especialidad t_map;

  -- Registro para insertar en PAGO_MOROSO
  TYPE pago_rec IS RECORD (
    pac_run            PACIENTE.pac_run%TYPE,
    pac_dv_run         PACIENTE.dv_run%TYPE,
    pac_nombre         VARCHAR2(200),
    ate_id             ATENCION.ate_id%TYPE,
    fecha_venc_pago    PAGO_ATENCION.fecha_venc_pago%TYPE,
    fecha_pago         PAGO_ATENCION.fecha_pago%TYPE,
    dias_morosidad     NUMBER,
    especialidad_at    VARCHAR2(100),
    monto_multa        NUMBER
  );
  v_pago pago_rec;

  v_edad NUMBER;
  v_desc NUMBER;
  v_multa_base NUMBER;
BEGIN
  -- Inicializar mapeo (nombres tal como están en ESPECIALIDAD.nombre)
  mapa_especialidad('Ciruga General') := 1; -- nota: en tu DDL aparece 'Ciruga General' sin tilde
  mapa_especialidad('Ciruga General') := 1;
  mapa_especialidad('Dermatologa') := 1;
  mapa_especialidad('Ortopedia y Traumatologa') := 2;
  mapa_especialidad('Inmunologa') := 3;
  mapa_especialidad('Otorrinolaringologa') := 3;
  mapa_especialidad('Fisiatra') := 4;
  mapa_especialidad('Medicina Interna') := 4;
  mapa_especialidad('Medicina General') := 5;
  mapa_especialidad('Psiquiatra Adultos') := 6;
  mapa_especialidad('Ciruga Digestiva') := 7;
  mapa_especialidad('Reumatolog?a') := 8; -- coincide con tu DDL (carácter especial)
  mapa_especialidad('Reumatologia') := 8;  -- alternativa sin acento

  -- Limpiar tabla destino
  EXECUTE IMMEDIATE 'TRUNCATE TABLE PAGO_MOROSO';

  FOR r IN c_atenciones LOOP
    -- días de mora (entero)
    v_pago.dias_morosidad := TRUNC(r.fecha_pago - r.fecha_venc_pago);

    -- multa base por especialidad (si no existe, 0)
    IF r.especialidad IS NOT NULL AND mapa_especialidad.EXISTS(r.especialidad) THEN
      v_multa_base := multas(mapa_especialidad(r.especialidad));
    ELSE
      v_multa_base := 0;
    END IF;

    -- edad al momento del pago
    v_edad := FLOOR(MONTHS_BETWEEN(r.fecha_pago, r.fecha_nacimiento) / 12);

    -- buscar descuento en PORC_DESCTO_3RA_EDAD (anno_ini, anno_ter, porcentaje_descto)
    BEGIN
      SELECT porcentaje_descto
      INTO v_desc
      FROM PORC_DESCTO_3RA_EDAD d
      WHERE v_edad BETWEEN d.anno_ini AND d.anno_ter;
    EXCEPTION
      WHEN NO_DATA_FOUND THEN
        v_desc := 0;
    END;

    -- calcular monto multa total aplicando descuento
    v_pago.monto_multa := v_pago.dias_morosidad * v_multa_base * (1 - NVL(v_desc,0)/100);

    -- rellenar registro
    v_pago.pac_run := r.pac_run;
    v_pago.pac_dv_run := r.dv_run;
    v_pago.pac_nombre := r.pac_nombre;
    v_pago.ate_id := r.ate_id;
    v_pago.fecha_venc_pago := r.fecha_venc_pago;
    v_pago.fecha_pago := r.fecha_pago;
    v_pago.especialidad_at := r.especialidad;

    -- Insertar en tabla destino
    INSERT INTO PAGO_MOROSO (
      pac_run, pac_dv_run, pac_nombre, ate_id,
      fecha_venc_pago, fecha_pago, dias_morosidad,
      especialidad_atencion, monto_multa
    ) VALUES (
      v_pago.pac_run, v_pago.pac_dv_run, v_pago.pac_nombre, v_pago.ate_id,
      v_pago.fecha_venc_pago, v_pago.fecha_pago, v_pago.dias_morosidad,
      v_pago.especialidad_at, ROUND(v_pago.monto_multa,2)
    );
  END LOOP;

  COMMIT;
  DBMS_OUTPUT.PUT_LINE('Proceso finalizado. Registros insertados en PAGO_MOROSO.');
EXCEPTION
  WHEN OTHERS THEN
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('Error: ' || SQLERRM);
    RAISE;
END;
/

SELECT * FROM pago_moroso;



-- ***** CASO 2 ***** --


SET SERVEROUTPUT ON
DECLARE
  TYPE t_destinaciones IS VARRAY(10) OF VARCHAR2(100);

  TYPE medico_rec IS RECORD (
    run_medico        MEDICO.med_run%TYPE,
    dv_run            MEDICO.dv_run%TYPE,
    nombre_medico     VARCHAR2(200),
    ap_paterno        MEDICO.apaterno%TYPE,
    unidad_nombre     UNIDAD.nombre%TYPE,
    total_aten        NUMBER,
    destinaciones     t_destinaciones,
    correo            VARCHAR2(200)
  );

  v_med medico_rec;

  CURSOR c_medicos IS
    SELECT m.med_run, m.dv_run, m.pnombre || ' ' || m.apaterno AS nombre_medico,
           m.apaterno, u.nombre AS unidad_nombre
    FROM MEDICO m
    LEFT JOIN UNIDAD u ON m.uni_id = u.uni_id
    ORDER BY u.nombre, m.apaterno;

  v_count NUMBER;
  v_dest_str VARCHAR2(1000);
BEGIN
  -- Limpiar tabla destino
  EXECUTE IMMEDIATE 'TRUNCATE TABLE MEDICO_SERVICIO_COMUNIDAD';

  FOR r IN c_medicos LOOP
    v_med.run_medico := r.med_run;
    v_med.dv_run := r.dv_run;
    v_med.nombre_medico := r.nombre_medico;
    v_med.ap_paterno := r.apaterno;
    v_med.unidad_nombre := NVL(r.unidad_nombre,'SIN UNIDAD');

    -- contar atenciones del médico
    SELECT COUNT(*) INTO v_med.total_aten
    FROM ATENCION a
    WHERE a.med_run = r.med_run;

    -- inicializar destinaciones
    v_med.destinaciones := t_destinaciones();

    -- Reglas (ejemplos)
    IF v_med.unidad_nombre LIKE '%Atencion Adulto%' OR v_med.unidad_nombre LIKE '%ATENCION ADULTO%' THEN
      v_med.destinaciones.EXTEND;
      v_med.destinaciones(v_med.destinaciones.COUNT) := 'Atencion Adulto';
    END IF;

    IF v_med.unidad_nombre LIKE '%AMBULATORIA%' OR v_med.unidad_nombre LIKE '%ATENCION AMBULATORIA%' THEN
      v_med.destinaciones.EXTEND;
      v_med.destinaciones(v_med.destinaciones.COUNT) := 'Atencion Ambulatoria';
    END IF;

    IF v_med.unidad_nombre LIKE '%URGENCIA%' OR v_med.unidad_nombre LIKE '%SAPU%' THEN
      IF v_med.total_aten BETWEEN 0 AND 3 THEN
        v_med.destinaciones.EXTEND;
        v_med.destinaciones(v_med.destinaciones.COUNT) := 'Urgencia 0-3 SAPU';
      ELSIF v_med.total_aten > 3 THEN
        v_med.destinaciones.EXTEND;
        v_med.destinaciones(v_med.destinaciones.COUNT) := 'Urgencia >3 SAPU';
      END IF;
    END IF;

    IF v_med.unidad_nombre LIKE '%CIRUG%' OR v_med.unidad_nombre LIKE '%CARDIO%' OR v_med.unidad_nombre LIKE '%ONCO%' THEN
      IF v_med.total_aten BETWEEN 0 AND 3 THEN
        v_med.destinaciones.EXTEND;
        v_med.destinaciones(v_med.destinaciones.COUNT) := 'Hospitales area Salud Publica 0-3';
      ELSIF v_med.total_aten > 3 THEN
        v_med.destinaciones.EXTEND;
        v_med.destinaciones(v_med.destinaciones.COUNT) := 'Hospitales area Salud Publica >3';
      END IF;
    END IF;

    IF v_med.destinaciones.COUNT = 0 THEN
      v_med.destinaciones.EXTEND;
      v_med.destinaciones(1) := 'General';
    END IF;

    -- Construcción correo institucional
    DECLARE
      v_pref_unidad VARCHAR2(2);
      v_ap_part VARCHAR2(2);
      v_run3 VARCHAR2(3);
      v_ap_len NUMBER;
    BEGIN
      v_pref_unidad := LOWER(SUBSTR(REPLACE(v_med.unidad_nombre,' ',''),1,2));
      v_ap_len := NVL(LENGTH(v_med.ap_paterno),0);
      IF v_ap_len >= 3 THEN
        v_ap_part := LOWER(SUBSTR(v_med.ap_paterno, v_ap_len-2, 2));
      ELSIF v_ap_len = 2 THEN
        v_ap_part := LOWER(SUBSTR(v_med.ap_paterno,1,2));
      ELSE
        v_ap_part := LOWER(NVL(v_med.ap_paterno,'x'));
      END IF;
      v_run3 := LPAD(MOD(NVL(v_med.run_medico,0),1000),3,'0');
      v_med.correo := v_pref_unidad || v_ap_part || v_run3 || '@institucion.cl';
    END;

    -- Convertir VARRAY a cadena separada por ';'
    v_dest_str := NULL;
    IF v_med.destinaciones.COUNT > 0 THEN
      FOR i IN 1 .. v_med.destinaciones.COUNT LOOP
        IF v_dest_str IS NULL THEN
          v_dest_str := v_med.destinaciones(i);
        ELSE
          v_dest_str := v_dest_str || ';' || v_med.destinaciones(i);
        END IF;
      END LOOP;
    ELSE
      v_dest_str := 'General';
    END IF;

    -- Insertar en MEDICO_SERVICIO_COMUNIDAD usando la cadena
    INSERT INTO MEDICO_SERVICIO_COMUNIDAD (
      unidad, run_medico, nombre_medico, correo_institucional, total_aten_medicas, destinacion
    ) VALUES (
      v_med.unidad_nombre,
      v_med.run_medico,
      v_med.nombre_medico,
      v_med.correo,
      v_med.total_aten,
      v_dest_str
    );
  END LOOP;

  COMMIT;
  DBMS_OUTPUT.PUT_LINE('Proceso MEDICO_SERVICIO_COMUNIDAD finalizado. Registros insertados.');
EXCEPTION
  WHEN OTHERS THEN
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('Error: ' || SQLERRM);
    RAISE;
END;
/

SELECT * FROM medico_servicio_comunidad;
