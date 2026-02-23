
-- =============================================================================
-- ACTIVIDAD FORMATIVA SEMANA 7 - PRY2206 Programación de Bases de Datos
-- =============================================================================

-- PASO 1: 

CREATE OR REPLACE TYPE t_multas_especialidad AS VARRAY(7) OF NUMBER(6);
/

-- =============================================================================
-- PASO 2: 
-- =============================================================================

CREATE OR REPLACE PACKAGE PKG_CLINICA_MAXSALUD AS

    -- Variable pública para almacenar el valor de la multa calculada
    v_monto_multa       NUMBER(8);

    -- Variable pública para almacenar el porcentaje/valor de descuento 3ra edad
    v_descto_3ra_edad   NUMBER(8);

    -- Función pública: retorna el valor de descuento para pacientes > 70 años
    -- Parámetros:

    FUNCTION f_descto_3ra_edad(
        p_edad  IN NUMBER,
        p_monto IN NUMBER
    ) RETURN NUMBER;

END PKG_CLINICA_MAXSALUD;
/

-- =============================================================================
-- PASO 3:
-- =============================================================================

CREATE OR REPLACE PACKAGE BODY PKG_CLINICA_MAXSALUD AS

    -- Implementación de la función de descuento para pacientes > 70 años
    FUNCTION f_descto_3ra_edad(
        p_edad  IN NUMBER,
        p_monto IN NUMBER
    ) RETURN NUMBER IS

        v_porcentaje    NUMBER(5,2) := 0;  -- Porcentaje de descuento desde tabla
        v_valor_descto  NUMBER(8)   := 0;  -- Valor monetario del descuento

    BEGIN
        -- Solo aplica para pacientes mayores a 70 años
        IF p_edad > 70 THEN
            -- Obtener el porcentaje de descuento según rango de edad
            -- en la tabla PORC_DESCTO_3RA_EDAD
            SELECT porcentaje_descto
            INTO   v_porcentaje
            FROM   PORC_DESCTO_3RA_EDAD
            WHERE  p_edad > anno_ini
              AND  p_edad <= anno_ter;

            -- Calcular el valor monetario del descuento
            v_valor_descto := ROUND(p_monto * v_porcentaje / 100, 0);
        END IF;

        -- Retornar el valor del descuento (0 si no aplica)
        RETURN v_valor_descto;

    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            -- Si la edad no cae en ningún rango, no se aplica descuento
            RETURN 0;
        WHEN OTHERS THEN
            RETURN 0;
    END f_descto_3ra_edad;

END PKG_CLINICA_MAXSALUD;
/

-- =============================================================================
-- PASO 4:
-- =============================================================================

CREATE OR REPLACE FUNCTION f_get_especialidad(
    p_ate_id IN ATENCION.ate_id%TYPE
) RETURN VARCHAR2 IS

    v_especialidad  ESPECIALIDAD.nombre%TYPE;

BEGIN
    -- Consultar la especialidad a través de la atención -> médico -> especialidad
    SELECT E.nombre
    INTO   v_especialidad
    FROM   ATENCION A
    JOIN   MEDICO   M ON M.med_run = A.med_run
    JOIN   ESPECIALIDAD E ON E.esp_id = M.esp_id
    WHERE  A.ate_id = p_ate_id;

    RETURN v_especialidad;

EXCEPTION
    WHEN NO_DATA_FOUND THEN
        RETURN 'Sin Especialidad';
    WHEN OTHERS THEN
        RETURN 'Error';
END f_get_especialidad;
/

-- =============================================================================
-- PASO 5: 
-- =============================================================================

CREATE OR REPLACE PROCEDURE sp_genera_pago_moroso AS

    -- -------------------------------------------------------------------
    -- Declaración del VARRAY con multas por día de atraso según Tabla 1:
    -- Índice 1: Medicina General   -> $1.200
    -- Índice 2: Traumatología      -> $1.300
    -- Índice 3: Neurología y Ped.  -> $1.700
    -- Índice 4: Oftalmología       -> $1.900
    -- Índice 5: Geriatría          -> $1.100
    -- Índice 6: Ginecología y Gast -> $2.000
    -- Índice 7: Dermatología       -> $2.300
    -- -------------------------------------------------------------------
    
    v_multas    t_multas_especialidad := t_multas_especialidad(1200, 1300, 1700, 1900, 1100, 2000, 2300);

    -- Variable para el índice del VARRAY según la especialidad
    v_idx_varray        NUMBER(1);

    -- Variables para datos del cursor
    v_pac_run           PACIENTE.pac_run%TYPE;
    v_pac_dv            PACIENTE.dv_run%TYPE;
    v_pac_nombre        VARCHAR2(50);
    v_ate_id            ATENCION.ate_id%TYPE;
    v_fecha_venc        DATE;
    v_fecha_pago        DATE;
    v_dias_morosidad    NUMBER(3);
    v_especialidad      VARCHAR2(30);
    v_esp_id            NUMBER(3);
    v_costo_atencion    NUMBER(8);
    v_fecha_nacimiento  DATE;
    v_edad_atencion     NUMBER(3);
    v_descuento         NUMBER(8);
    v_observacion       VARCHAR2(100);

    -- -------------------------------------------------------------------
    -- CURSOR: Obtiene todas las atenciones pagadas fuera de plazo
    -- durante el AÑO ANTERIOR al año de ejecución del procedimiento.
    -- Se usa EXTRACT(YEAR FROM ...) para obtener el año en forma dinámica
    -- Se ordena por fecha_venc_pago ASC y apellido paterno ASC
    -- -------------------------------------------------------------------
    
    CURSOR cur_morosos IS
        SELECT
            P.pac_run,
            P.dv_run,
            P.pnombre || ' ' || P.snombre || ' ' || P.apaterno || ' ' || P.amaterno AS pac_nombre,
            A.ate_id,
            PA.fecha_venc_pago,
            PA.fecha_pago,
            (PA.fecha_pago - PA.fecha_venc_pago)    AS dias_morosidad,
            M.esp_id,
            A.costo                                  AS costo_atencion,
            P.fecha_nacimiento,
            A.fecha_atencion
        FROM   PAGO_ATENCION PA
        JOIN   ATENCION      A  ON A.ate_id  = PA.ate_id
        JOIN   PACIENTE      P  ON P.pac_run = A.pac_run
        JOIN   MEDICO        M  ON M.med_run = A.med_run
        WHERE  PA.fecha_pago > PA.fecha_venc_pago
          -- Filtrar año anterior al año de ejecución (dinámico)
          AND  EXTRACT(YEAR FROM PA.fecha_venc_pago) = EXTRACT(YEAR FROM SYSDATE) - 1
        ORDER BY PA.fecha_venc_pago ASC,
                 P.apaterno         ASC;

BEGIN

    -- -------------------------------------------------------------------
    -- Truncar la tabla PAGO_MOROSO antes de poblarla
    -- Se utiliza EXECUTE IMMEDIATE para ejecutar DDL dentro de PL/SQL
    -- -------------------------------------------------------------------
    
    EXECUTE IMMEDIATE 'TRUNCATE TABLE PAGO_MOROSO';

    -- -------------------------------------------------------------------
    -- Iterar sobre cada atención morosa del año anterior
    -- -------------------------------------------------------------------
    
    FOR rec IN cur_morosos LOOP

        -- Obtener la especialidad usando la Función Almacenada f_get_especialidad
        v_especialidad   := f_get_especialidad(rec.ate_id);
        v_esp_id         := rec.esp_id;
        v_dias_morosidad := rec.dias_morosidad;
        v_costo_atencion := rec.costo_atencion;

        -- -------------------------------------------------------------------
        -- Multas según Tabla 1 del enunciado:
        --   Medicina General        -> idx 1 -> $1.200
        --   Traumatología           -> idx 2 -> $1.300
        --   Neurología y Pediatría  -> idx 3 -> $1.700
        --   Oftalmología            -> idx 4 -> $1.900
        --   Geriatría               -> idx 5 -> $1.100
        --   Ginecología y Gastro.   -> idx 6 -> $2.000
        --   Dermatología            -> idx 7 -> $2.300
        -- -------------------------------------------------------------------
        
        IF v_esp_id = 700 THEN
            -- Medicina General
            v_idx_varray := 1;
        ELSIF v_esp_id = 100 THEN
            -- Traumatología
            v_idx_varray := 2;
        ELSIF v_esp_id = 300 OR v_esp_id = 600 THEN
            -- Neurología y Pediatría (comparten multa)
            v_idx_varray := 3;
        ELSIF v_esp_id = 500 THEN
            -- Oftalmología
            v_idx_varray := 4;
        ELSIF v_esp_id = 400 THEN
            -- Geriatría
            v_idx_varray := 5;
        ELSIF v_esp_id = 800 OR v_esp_id = 200 THEN
            -- Ginecología y Gastroenterología (comparten multa)
            v_idx_varray := 6;
        ELSIF v_esp_id = 900 THEN
            -- Dermatología
            v_idx_varray := 7;
        ELSE
            -- Especialidad no contemplada: multa por defecto Medicina General
            v_idx_varray := 1;
        END IF;

        -- -------------------------------------------------------------------
        -- Calcular el monto de la multa:
        -- Multa = días de morosidad * valor_multa_por_día (del VARRAY)
        -- Se asigna al mismo tiempo a la variable pública del Package
        -- -------------------------------------------------------------------
        
        PKG_CLINICA_MAXSALUD.v_monto_multa := v_dias_morosidad * v_multas(v_idx_varray);

        -- -------------------------------------------------------------------
        -- Calcular la edad del paciente a la fecha de la atención médica
        -- Usando MONTHS_BETWEEN para obtener años exactos a la fecha de atención
        -- -------------------------------------------------------------------
        
        v_edad_atencion := TRUNC(MONTHS_BETWEEN(rec.fecha_atencion, rec.fecha_nacimiento) / 12);

        -- -------------------------------------------------------------------
        -- Verificar si aplica descuento por 3ra edad (más de 70 años)
        -- Se usa la función pública del Package
        -- -------------------------------------------------------------------
        
        IF v_edad_atencion > 70 THEN
            -- Llamar a la función del Package para obtener el valor del descuento
            v_descuento := PKG_CLINICA_MAXSALUD.f_descto_3ra_edad(
                               v_edad_atencion,
                               PKG_CLINICA_MAXSALUD.v_monto_multa
                           );

            -- Asignar descuento a la variable pública del Package
            PKG_CLINICA_MAXSALUD.v_descto_3ra_edad := v_descuento;

            -- Aplicar descuento al monto de la multa
            PKG_CLINICA_MAXSALUD.v_monto_multa := PKG_CLINICA_MAXSALUD.v_monto_multa - v_descuento;

            -- Construir observación indicando el descuento aplicado
            v_observacion := 'Paciente tenia ' || v_edad_atencion ||
                             ' a la fecha de atención. Se aplicó descuento paciente mayor a 70 años';
        ELSE
            -- No aplica descuento
            PKG_CLINICA_MAXSALUD.v_descto_3ra_edad := 0;
            v_observacion := NULL;
        END IF;

        -- -------------------------------------------------------------------
        -- Insertar registro en la tabla PAGO_MOROSO
        -- -------------------------------------------------------------------
        INSERT INTO PAGO_MOROSO (
            pac_run,
            pac_dv_run,
            pac_nombre,
            ate_id,
            fecha_venc_pago,
            fecha_pago,
            dias_morosidad,
            especialidad_atencion,
            costo_atencion,
            monto_multa,
            observacion
        ) VALUES (
            rec.pac_run,
            rec.dv_run,
            rec.pac_nombre,
            rec.ate_id,
            rec.fecha_venc_pago,
            rec.fecha_pago,
            v_dias_morosidad,
            v_especialidad,
            v_costo_atencion,
            PKG_CLINICA_MAXSALUD.v_monto_multa,
            v_observacion
        );

    END LOOP;

    -- Confirmar transacción
    COMMIT;

    DBMS_OUTPUT.PUT_LINE('Proceso finalizado correctamente.');
    DBMS_OUTPUT.PUT_LINE('Registros insertados en PAGO_MOROSO: ' ||
                         TO_CHAR(SQL%ROWCOUNT));

EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        DBMS_OUTPUT.PUT_LINE('Error en sp_genera_pago_moroso: ' || SQLERRM);
        RAISE;
END sp_genera_pago_moroso;
/

-- =============================================================================
-- PASO 6: EJECUCIÓN DEL PROCEDIMIENTO
-- =============================================================================

SET SERVEROUTPUT ON;

BEGIN
    sp_genera_pago_moroso;
END;
/

-- =============================================================================
-- PASO 7: CONSULTA DE VERIFICACIÓN
-- =============================================================================

SELECT
    pac_run,
    pac_dv_run,
    pac_nombre,
    ate_id,
    TO_CHAR(fecha_venc_pago, 'DD/MM/YYYY') AS fecha_venc_pago,
    TO_CHAR(fecha_pago,      'DD/MM/YYYY') AS fecha_pago,
    dias_morosidad,
    especialidad_atencion,
    costo_atencion,
    monto_multa,
    observacion
FROM  PAGO_MOROSO
ORDER BY fecha_venc_pago ASC,
         pac_nombre      ASC;
         