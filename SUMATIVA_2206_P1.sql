-- ============================================
-- Bind de fecha
-- ============================================
VARIABLE b_fecha_proceso VARCHAR2(19);
BEGIN
  :b_fecha_proceso := TO_CHAR(SYSDATE, 'YYYY-MM-DD HH24:MI:SS');
END;
/

-- ============================================
-- Bloque PL/SQL anónimo
-- ============================================
DECLARE
  CURSOR c_emp IS
    SELECT e.id_emp,
           e.numrun_emp,
           e.dvrun_emp,
           e.appaterno_emp,
           e.apmaterno_emp,
           e.pnombre_emp,
           e.snombre_emp,
           e.sueldo_base,
           e.fecha_nac,
           e.fecha_contrato,
           ec.nombre_estado_civil
      FROM empleado e
      JOIN estado_civil ec
        ON ec.id_estado_civil = e.id_estado_civil
     ORDER BY e.id_emp;

  r c_emp%ROWTYPE;

  -- %TYPE
  v_id_emp            empleado.id_emp%TYPE;
  v_numrun_emp        empleado.numrun_emp%TYPE;
  v_dvrun_emp         empleado.dvrun_emp%TYPE;
  v_appaterno         empleado.appaterno_emp%TYPE;
  v_apmaterno         empleado.apmaterno_emp%TYPE;
  v_pnombre           empleado.pnombre_emp%TYPE;
  v_snombre           empleado.snombre_emp%TYPE;
  v_sueldo_base       empleado.sueldo_base%TYPE;
  v_fecha_nac         empleado.fecha_nac%TYPE;
  v_fecha_contrato    empleado.fecha_contrato%TYPE;
  v_estado_civil_nom  estado_civil.nombre_estado_civil%TYPE;

  -- Trabajo
  v_nombre_usuario    VARCHAR2(50);
  v_clave_usuario     VARCHAR2(50);

  v_primera_letra_ec  CHAR(1);
  v_tres_primeras_nom VARCHAR2(3);
  v_largo_pnombre     PLS_INTEGER;
  v_ultimo_dig_sueldo CHAR(1);
  v_dv_run            CHAR(1);
  v_anios_trab        PLS_INTEGER;
  v_flag_x            CHAR(1);

  v_tercer_dig_run     CHAR(1);
  v_anio_nac_mas2      PLS_INTEGER;
  v_tres_ult_sueldo    PLS_INTEGER;
  v_tres_ult_sueldo_m1 PLS_INTEGER;
  v_dos_letras_ap      VARCHAR2(2);

  v_mes_base          VARCHAR2(2);
  v_anio_base         VARCHAR2(4);

  v_total_empleados   PLS_INTEGER := 0;
  v_iteraciones       PLS_INTEGER := 0;

  -- Bind de fecha
  v_fecha_proceso     DATE := TO_DATE(:b_fecha_proceso, 'YYYY-MM-DD HH24:MI:SS');

BEGIN
  -- Truncado con SQL dinámico
  EXECUTE IMMEDIATE 'TRUNCATE TABLE USUARIO_CLAVE';

  -- Total empleados 
  SELECT COUNT(*) INTO v_total_empleados FROM empleado;

  FOR r IN c_emp LOOP
    -- Mapear
    v_id_emp         := r.id_emp;
    v_numrun_emp     := r.numrun_emp;
    v_dvrun_emp      := r.dvrun_emp;
    v_appaterno      := r.appaterno_emp;
    v_apmaterno      := r.apmaterno_emp;
    v_pnombre        := r.pnombre_emp;
    v_snombre        := r.snombre_emp;
    v_sueldo_base    := r.sueldo_base;
    v_fecha_nac      := r.fecha_nac;
    v_fecha_contrato := r.fecha_contrato;
    v_estado_civil_nom := r.nombre_estado_civil;

    -- Validaciones mínimas 
    IF v_pnombre IS NULL
       OR v_appaterno IS NULL
       OR v_numrun_emp IS NULL
       OR v_dvrun_emp IS NULL
       OR v_sueldo_base IS NULL
       OR v_fecha_nac IS NULL
       OR v_fecha_contrato IS NULL
    THEN
      CONTINUE;
    END IF;

    -- Base temporal desde bind
    v_mes_base  := TO_CHAR(v_fecha_proceso, 'MM');
    v_anio_base := TO_CHAR(v_fecha_proceso, 'YYYY');

    -- Nombre de usuario
    v_primera_letra_ec := LOWER(SUBSTR(v_estado_civil_nom, 1, 1));
    v_tres_primeras_nom := UPPER(SUBSTR(v_pnombre, 1, 3));
    v_largo_pnombre := LENGTH(v_pnombre);
    v_ultimo_dig_sueldo := SUBSTR(TO_CHAR(ROUND(v_sueldo_base)), -1, 1);
    v_dv_run := v_dvrun_emp;
    v_anios_trab := FLOOR(MONTHS_BETWEEN(v_fecha_proceso, v_fecha_contrato) / 12);
    v_flag_x := CASE WHEN v_anios_trab < 10 THEN 'X' ELSE NULL END;

    v_nombre_usuario :=
      v_primera_letra_ec ||
      v_tres_primeras_nom ||
      TO_CHAR(v_largo_pnombre) ||
      '*' ||
      v_ultimo_dig_sueldo ||
      v_dv_run ||
      TO_CHAR(v_anios_trab) ||
      NVL(v_flag_x, '');

    -- Clave de usuario
    v_tercer_dig_run     := SUBSTR(TO_CHAR(v_numrun_emp), 3, 1);
    v_anio_nac_mas2      := TO_NUMBER(TO_CHAR(v_fecha_nac, 'YYYY')) + 2;
    v_tres_ult_sueldo    := TO_NUMBER(SUBSTR(TO_CHAR(ROUND(v_sueldo_base)), -3, 3));
    v_tres_ult_sueldo_m1 := v_tres_ult_sueldo - 1;

    v_dos_letras_ap :=
      CASE
        WHEN v_estado_civil_nom IN ('CASADO', 'ACUERDO DE UNION CIVIL')
          THEN LOWER(SUBSTR(v_appaterno, 1, 2))
        WHEN v_estado_civil_nom IN ('DIVORCIADO', 'SOLTERO')
          THEN LOWER(SUBSTR(v_appaterno, 1, 1) || SUBSTR(v_appaterno, -1, 1))
        WHEN v_estado_civil_nom = 'VIUDO'
          THEN LOWER(SUBSTR(v_appaterno, GREATEST(LENGTH(v_appaterno) - 2, 1), 1) ||
                     SUBSTR(v_appaterno, GREATEST(LENGTH(v_appaterno) - 1, 1), 1))
        WHEN v_estado_civil_nom = 'SEPARADO'
          THEN LOWER(SUBSTR(v_appaterno, -2, 2))
        ELSE LOWER(SUBSTR(v_appaterno, 1, 2))
      END;

    v_clave_usuario :=
      v_tercer_dig_run ||
      TO_CHAR(v_anio_nac_mas2) ||
      TO_CHAR(v_tres_ult_sueldo_m1) ||
      v_dos_letras_ap ||
      TO_CHAR(v_id_emp) ||
      v_mes_base || v_anio_base;

    -- Inserción
    INSERT INTO usuario_clave
      (id_emp,
       numrun_emp,
       dvrun_emp,
       nombre_empleado,
       nombre_usuario,
       clave_usuario)
    VALUES
      (v_id_emp,
       v_numrun_emp,
       v_dvrun_emp,
       -- Nombre completo sin dobles espacios
       TRIM(
         REGEXP_REPLACE(
           UPPER(v_pnombre) || ' ' ||
           UPPER(NVL(v_snombre, '')) || ' ' ||
           UPPER(v_appaterno) || ' ' ||
           UPPER(v_apmaterno),
           '\s+', ' '
         )
       ),
       v_nombre_usuario,
       v_clave_usuario);

    v_iteraciones := v_iteraciones + 1;
  END LOOP;

  -- Commit solo si se procesó todo (PL/SQL #3)
  IF v_iteraciones = v_total_empleados THEN
    COMMIT;
  ELSE
    ROLLBACK;
  END IF;

EXCEPTION
  WHEN OTHERS THEN
    ROLLBACK;
    RAISE;
END;
/

-- 1) Crear y poblar el modelo (tu script de creación)
-- 2) Definir bind y ejecutar bloque
VARIABLE b_fecha_proceso DATE;
EXEC :b_fecha_proceso := SYSDATE;

-- 3) Ejecutar el bloque anterior

-- 4) Consultar resultados ordenados
SELECT *
FROM usuario_clave
ORDER BY id_emp ASC;
