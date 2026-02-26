-- ============================================================
-- ACTIVIDAD SUMATIVA S8 - Antonio González
-- ============================================================

-- ============================================================
-- CASO 1: TRIGGER TRG_TOTAL_CONSUMOS
-- ============================================================

CREATE OR REPLACE TRIGGER TRG_TOTAL_CONSUMOS
AFTER INSERT OR UPDATE OR DELETE ON CONSUMO
FOR EACH ROW
DECLARE
    v_count NUMBER;
BEGIN
    IF INSERTING THEN
        SELECT COUNT(*) INTO v_count
        FROM TOTAL_CONSUMOS
        WHERE ID_HUESPED = :NEW.ID_HUESPED;

        IF v_count > 0 THEN
            UPDATE TOTAL_CONSUMOS
            SET MONTO_CONSUMOS = MONTO_CONSUMOS + :NEW.MONTO
            WHERE ID_HUESPED = :NEW.ID_HUESPED;
        ELSE
            INSERT INTO TOTAL_CONSUMOS (ID_HUESPED, MONTO_CONSUMOS)
            VALUES (:NEW.ID_HUESPED, :NEW.MONTO);
        END IF;

    ELSIF UPDATING THEN
        UPDATE TOTAL_CONSUMOS
        SET MONTO_CONSUMOS = MONTO_CONSUMOS - :OLD.MONTO + :NEW.MONTO
        WHERE ID_HUESPED = :NEW.ID_HUESPED;

    ELSIF DELETING THEN
        UPDATE TOTAL_CONSUMOS
        SET MONTO_CONSUMOS = MONTO_CONSUMOS - :OLD.MONTO
        WHERE ID_HUESPED = :OLD.ID_HUESPED;
    END IF;
END TRG_TOTAL_CONSUMOS;
/


-- ============================================================
-- BLOQUE ANÓNIMO DE PRUEBA DEL TRIGGER
-- ============================================================

DECLARE
    v_max_id NUMBER;
BEGIN
    -- Obtener el ID siguiente al último consumo ingresado
    SELECT MAX(ID_CONSUMO) + 1 INTO v_max_id FROM CONSUMO;

    -- 1. INSERT: nuevo consumo para cliente 340006, reserva 1587, monto $150
    INSERT INTO CONSUMO (ID_CONSUMO, ID_RESERVA, ID_HUESPED, MONTO)
    VALUES (v_max_id, 1587, 340006, 150);
    DBMS_OUTPUT.PUT_LINE('INSERT OK. Nuevo ID_CONSUMO: ' || v_max_id);

    -- 2. DELETE: eliminar consumo ID 11473
    DELETE FROM CONSUMO WHERE ID_CONSUMO = 11473;
    DBMS_OUTPUT.PUT_LINE('DELETE OK para ID_CONSUMO 11473');

    -- 3. UPDATE: actualizar monto del consumo 10688 a $95
    UPDATE CONSUMO SET MONTO = 95 WHERE ID_CONSUMO = 10688;
    DBMS_OUTPUT.PUT_LINE('UPDATE OK para ID_CONSUMO 10688');

    COMMIT;
    DBMS_OUTPUT.PUT_LINE('Transacciones completadas y confirmadas.');
END;
/

-- ============================================================
-- CASO 2: PROCESOS DE GESTIÓN DE COBRANZA
-- ============================================================

-- ============================================================
-- 1. PACKAGE PKG_HOTEL
-- ============================================================

CREATE OR REPLACE PACKAGE PKG_HOTEL AS
    -- Variable pública: el procedimiento principal la usa para
    -- recuperar el monto de tours calculado por FN_TOURS
    g_monto_tours NUMBER := 0;

    -- Función: retorna el total en USD de tours del huésped
    -- Si no tiene tours retorna 0
    FUNCTION FN_TOURS(p_id_huesped IN HUESPED.ID_HUESPED%TYPE)
        RETURN NUMBER;
END PKG_HOTEL;
/

CREATE OR REPLACE PACKAGE BODY PKG_HOTEL AS
    FUNCTION FN_TOURS(p_id_huesped IN HUESPED.ID_HUESPED%TYPE)
        RETURN NUMBER
    IS
        v_total NUMBER := 0;
    BEGIN
        SELECT NVL(SUM(t.VALOR_TOUR * ht.NUM_PERSONAS), 0)
        INTO v_total
        FROM HUESPED_TOUR ht
        JOIN TOUR t ON ht.ID_TOUR = t.ID_TOUR
        WHERE ht.ID_HUESPED = p_id_huesped;

        RETURN v_total;
    EXCEPTION
        WHEN OTHERS THEN RETURN 0;
    END FN_TOURS;
END PKG_HOTEL;
/


-- ============================================================
-- 2. FUNCIONES ALMACENADAS
-- ============================================================

CREATE OR REPLACE FUNCTION FN_AGENCIA(p_id_huesped IN HUESPED.ID_HUESPED%TYPE)
    RETURN VARCHAR2
IS
    PRAGMA AUTONOMOUS_TRANSACTION;
    v_nom_agencia AGENCIA.NOM_AGENCIA%TYPE;
    v_id_error    NUMBER;        
    v_msg_error   VARCHAR2(300); 
BEGIN
    SELECT a.NOM_AGENCIA
    INTO v_nom_agencia
    FROM HUESPED h
    JOIN AGENCIA a ON h.ID_AGENCIA = a.ID_AGENCIA
    WHERE h.ID_HUESPED = p_id_huesped;

    RETURN v_nom_agencia;

EXCEPTION
    WHEN NO_DATA_FOUND THEN
        SELECT SQ_ERROR.NEXTVAL INTO v_id_error FROM DUAL;
        v_msg_error := 'ORA-01403: No se ha encontrado ningún dato';
        INSERT INTO REG_ERRORES (ID_ERROR, NOMSUBPROGRAMA, MSG_ERROR)
        VALUES (v_id_error,
                'Error en la función FN_AGENCIA al recuperar la agencia del huesped con id ' || p_id_huesped,
                v_msg_error);
        COMMIT;
        RETURN 'NO REGISTRA AGENCIA';
    WHEN OTHERS THEN
        SELECT SQ_ERROR.NEXTVAL INTO v_id_error FROM DUAL;
        v_msg_error := SQLERRM;
        INSERT INTO REG_ERRORES (ID_ERROR, NOMSUBPROGRAMA, MSG_ERROR)
        VALUES (v_id_error,
                'Error en la función FN_AGENCIA al recuperar la agencia del huesped con id ' || p_id_huesped,
                v_msg_error);
        COMMIT;
        RETURN 'NO REGISTRA AGENCIA';
END FN_AGENCIA;
/


CREATE OR REPLACE FUNCTION FN_CONSUMOS(p_id_huesped IN HUESPED.ID_HUESPED%TYPE)
    RETURN NUMBER
IS
    PRAGMA AUTONOMOUS_TRANSACTION;
    v_monto       NUMBER := 0;
    v_id_error    NUMBER;        
    v_msg_error   VARCHAR2(300); 
BEGIN
    SELECT MONTO_CONSUMOS
    INTO v_monto
    FROM TOTAL_CONSUMOS
    WHERE ID_HUESPED = p_id_huesped;

    RETURN v_monto;

EXCEPTION
    WHEN NO_DATA_FOUND THEN
        SELECT SQ_ERROR.NEXTVAL INTO v_id_error FROM DUAL;
        v_msg_error := 'ORA-01403: No se ha encontrado ningún dato';
        INSERT INTO REG_ERRORES (ID_ERROR, NOMSUBPROGRAMA, MSG_ERROR)
        VALUES (v_id_error,
                'Error en la función FN_CONSUMOS al recuperar los consumos del cliente con Id ' || p_id_huesped,
                v_msg_error);
        COMMIT;
        RETURN 0;
    WHEN OTHERS THEN
        SELECT SQ_ERROR.NEXTVAL INTO v_id_error FROM DUAL;
        v_msg_error := SQLERRM; 
        INSERT INTO REG_ERRORES (ID_ERROR, NOMSUBPROGRAMA, MSG_ERROR)
        VALUES (v_id_error,
                'Error en la función FN_CONSUMOS al recuperar los consumos del cliente con Id ' || p_id_huesped,
                v_msg_error);
        COMMIT;
        RETURN 0;
END FN_CONSUMOS;
/


-- ============================================================
-- 3. PROCEDIMIENTO ALMACENADO PRINCIPAL
-- ============================================================

CREATE OR REPLACE PROCEDURE PRC_COBRO_HUESPEDES(
    p_fecha_proceso IN DATE,
    p_tipo_cambio   IN NUMBER
)
IS
    CURSOR cur_huespedes IS
        SELECT
            h.ID_HUESPED,
            h.APPAT_HUESPED || ' ' || h.APMAT_HUESPED || ' ' || h.NOM_HUESPED AS nombre,
            r.ID_RESERVA,
            r.ESTADIA,
            SUM(hab.VALOR_HABITACION + hab.VALOR_MINIBAR) * r.ESTADIA AS alojamiento_usd,
            COUNT(dr.ID_HABITACION) AS num_habitaciones
        FROM HUESPED h
        JOIN RESERVA r          ON h.ID_HUESPED     = r.ID_HUESPED
        JOIN DETALLE_RESERVA dr ON r.ID_RESERVA     = dr.ID_RESERVA
        JOIN HABITACION hab     ON dr.ID_HABITACION = hab.ID_HABITACION
        WHERE TRUNC(r.INGRESO + r.ESTADIA) = TRUNC(p_fecha_proceso)
        GROUP BY
            h.ID_HUESPED,
            h.APPAT_HUESPED || ' ' || h.APMAT_HUESPED || ' ' || h.NOM_HUESPED,
            r.ID_RESERVA,
            r.ESTADIA;

    v_agencia            DETALLE_DIARIO_HUESPEDES.AGENCIA%TYPE;
    v_consumos_usd       NUMBER := 0;
    v_tours_usd          NUMBER := 0;
    v_valor_personas_usd NUMBER := 0;
    v_subtotal_usd       NUMBER := 0;
    v_pct_dcto_consumos  NUMBER := 0;
    v_dcto_consumos_usd  NUMBER := 0;
    v_dcto_agencia_usd   NUMBER := 0;
    v_total_usd          NUMBER := 0;
    v_filas              NUMBER := 0;

BEGIN
    -- Limpiar tablas antes del proceso (permite re-ejecución limpia)
    DELETE FROM DETALLE_DIARIO_HUESPEDES;
    DELETE FROM REG_ERRORES;
    COMMIT;

    DBMS_OUTPUT.PUT_LINE('=== Inicio proceso fecha: '
        || TO_CHAR(p_fecha_proceso, 'DD/MM/YYYY')
        || ' | Cambio: $' || p_tipo_cambio || ' ===');

    FOR rec IN cur_huespedes LOOP
        BEGIN

            -- 1. Agencia
            v_agencia := FN_AGENCIA(rec.ID_HUESPED);

            -- 2. Valor personas en USD ($35.000 CLP x N habitaciones)
            v_valor_personas_usd := (35000 * rec.num_habitaciones) / p_tipo_cambio;

            -- 3. Consumos en USD
            v_consumos_usd := FN_CONSUMOS(rec.ID_HUESPED);

            -- 4. Tours en USD via Package
            PKG_HOTEL.g_monto_tours := PKG_HOTEL.FN_TOURS(rec.ID_HUESPED);
            v_tours_usd             := PKG_HOTEL.g_monto_tours;

            -- 5. Subtotal en USD
            v_subtotal_usd := rec.alojamiento_usd
                            + v_consumos_usd
                            + v_tours_usd
                            + v_valor_personas_usd;

            -- 6. Descuento consumos por tramo
            BEGIN
                SELECT NVL(pct, 0) INTO v_pct_dcto_consumos
                FROM TRAMOS_CONSUMOS
                WHERE v_consumos_usd BETWEEN VMIN_TRAMO AND VMAX_TRAMO;
            EXCEPTION
                WHEN NO_DATA_FOUND THEN v_pct_dcto_consumos := 0;
                WHEN OTHERS        THEN v_pct_dcto_consumos := 0;
            END;
            v_dcto_consumos_usd := v_consumos_usd * v_pct_dcto_consumos;

            -- 7. Descuento agencia: 12% sobre subtotal solo para VIAJES ALBERTI
            IF UPPER(TRIM(v_agencia)) = 'VIAJES ALBERTI' THEN
                v_dcto_agencia_usd := v_subtotal_usd * 0.12;
            ELSE
                v_dcto_agencia_usd := 0;
            END IF;

            -- 8. Total
            v_total_usd := v_subtotal_usd - v_dcto_consumos_usd - v_dcto_agencia_usd;

            -- 9. Insertar resultado en pesos chilenos redondeados
            INSERT INTO DETALLE_DIARIO_HUESPEDES (
                ID_HUESPED, NOMBRE, AGENCIA,
                ALOJAMIENTO, CONSUMOS, TOURS,
                SUBTOTAL_PAGO, DESCUENTO_CONSUMOS, DESCUENTOS_AGENCIA, TOTAL
            ) VALUES (
                rec.ID_HUESPED,
                rec.nombre,
                v_agencia,
                ROUND(rec.alojamiento_usd     * p_tipo_cambio),
                ROUND(v_consumos_usd          * p_tipo_cambio),
                ROUND(v_tours_usd             * p_tipo_cambio),
                ROUND(v_subtotal_usd          * p_tipo_cambio),
                ROUND(v_dcto_consumos_usd     * p_tipo_cambio),
                ROUND(v_dcto_agencia_usd      * p_tipo_cambio),
                ROUND(v_total_usd             * p_tipo_cambio)
            );

            v_filas := v_filas + 1;
            DBMS_OUTPUT.PUT_LINE('Procesado: ' || rec.ID_HUESPED || ' | ' || rec.nombre);

        EXCEPTION
            WHEN OTHERS THEN
                DBMS_OUTPUT.PUT_LINE('ERROR huesped ' || rec.ID_HUESPED || ': ' || SQLERRM);
        END;
    END LOOP;

    COMMIT;
    DBMS_OUTPUT.PUT_LINE('=== FIN. Huespedes procesados: ' || v_filas || ' ===');

EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('ERROR CRITICO: ' || SQLERRM);
        ROLLBACK;
END PRC_COBRO_HUESPEDES;
/


-- ============================================================
-- EJECUCIÓN DEL PROCEDIMIENTO
-- ============================================================
BEGIN
    PRC_COBRO_HUESPEDES(
        p_fecha_proceso => TO_DATE('18/08/2021', 'DD/MM/YYYY'),
        p_tipo_cambio   => 915
    );
END;
/


-- ============================================================
-- CONSULTAS DE VERIFICACIÓN
-- ============================================================

SELECT * FROM DETALLE_DIARIO_HUESPEDES ORDER BY ID_HUESPED;
SELECT * FROM REG_ERRORES ORDER BY ID_ERROR;

-- Verificar tabla CONSUMO y TOTAL_CONSUMOS post-trigger
SELECT * FROM CONSUMO 
WHERE ID_HUESPED IN (340003, 340004, 340006, 340008, 340009)
ORDER BY ID_HUESPED, ID_CONSUMO;

SELECT * FROM TOTAL_CONSUMOS
WHERE ID_HUESPED IN (340003, 340004, 340006, 340008, 340009)
ORDER BY ID_HUESPED;