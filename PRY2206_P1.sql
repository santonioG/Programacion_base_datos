
-- Bloque PL/SQL Anónimo - Caso 1: Programa TODOSUMA

DECLARE
    v_nro_cliente     NUMBER;
    v_nombre_cliente  VARCHAR2(200);
    v_tipo_cliente    VARCHAR2(50);
    v_monto_total     NUMBER := 0;
    v_pesos_finales   NUMBER := 0;
BEGIN
    SELECT c.pnombre || ' ' || c.snombre || ' ' || c.appaterno || ' ' || c.apmaterno,
           tc.nombre_tipo_cliente,
           SUM(cc.monto_solicitado)
    INTO v_nombre_cliente, v_tipo_cliente, v_monto_total
    FROM cliente c
    INNER JOIN tipo_cliente tc
        ON c.cod_tipo_cliente = tc.cod_tipo_cliente
    INNER JOIN credito_cliente cc
        ON c.nro_cliente = cc.nro_cliente
    WHERE c.nro_cliente = :nro_cliente
      AND EXTRACT(YEAR FROM cc.fecha_solic_cred) = EXTRACT(YEAR FROM SYSDATE) - 1
    GROUP BY c.pnombre, c.snombre, c.appaterno, c.apmaterno, tc.nombre_tipo_cliente;

    v_pesos_finales := (v_monto_total / 100000) * :pesos_normales;

    IF v_tipo_cliente = 'Trabajadores independientes' THEN
        IF v_monto_total < :tramo1 THEN
            v_pesos_finales := v_pesos_finales + (v_monto_total / 100000) * :pesos_extra1;
        ELSIF v_monto_total BETWEEN :tramo1 AND :tramo2 THEN
            v_pesos_finales := v_pesos_finales + (v_monto_total / 100000) * :pesos_extra2;
        ELSE
            v_pesos_finales := v_pesos_finales + (v_monto_total / 100000) * :pesos_extra3;
        END IF;
    END IF;

    INSERT INTO cliente_todosuma (
        nro_cliente, run_cliente, nombre_cliente, tipo_cliente, monto_solic_creditos, monto_pesos_todosuma
    )
    VALUES (
        :nro_cliente,
        (SELECT numrun || '-' || dvrun FROM cliente WHERE nro_cliente = :nro_cliente),
        v_nombre_cliente,
        v_tipo_cliente,
        v_monto_total,
        v_pesos_finales
    );

    DBMS_OUTPUT.PUT_LINE('Cliente procesado: ' || v_nombre_cliente || ' - Pesos TODOSUMA: ' || v_pesos_finales);
END;
/


-- ANTES DE REPETIR 
DELETE FROM cliente_todosuma WHERE run_cliente = :run_cliente;
COMMIT;

--VERIFICAR RESULTADOS
SELECT * FROM cliente_todosuma;

-- CASO 2

-- Créditos y cuotas pendientes de un cliente específico
SELECT c.nro_cliente,
       c.numrun || '-' || c.dvrun AS run_cliente,
       c.pnombre || ' ' || c.snombre || ' ' || c.appaterno || ' ' || c.apmaterno AS nombre_cliente,
       cc.nro_solic_credito,
       q.nro_cuota,
       q.fecha_venc_cuota,
       q.valor_cuota,
       q.fecha_pago_cuota
FROM cliente c
INNER JOIN credito_cliente cc
    ON c.nro_cliente = cc.nro_cliente
INNER JOIN cuota_credito_cliente q
    ON cc.nro_solic_credito = q.nro_solic_credito
WHERE c.nro_cliente = :nro_cliente
  AND q.fecha_pago_cuota IS NULL   -- cuotas aún no pagadas
ORDER BY q.fecha_venc_cuota;

DECLARE
    v_nro_cliente NUMBER := :nro_cliente;   -- cliente a procesar
    v_motivo      VARCHAR2(200) := :motivo; -- motivo de postergación
BEGIN
    FOR r IN (
        SELECT c.nro_cliente,
               c.numrun || '-' || c.dvrun AS run_cliente,
               c.pnombre || ' ' || c.snombre || ' ' || c.appaterno || ' ' || c.apmaterno AS nombre_cliente,
               cc.nro_solic_credito,
               q.nro_cuota,
               q.fecha_venc_cuota,
               q.valor_cuota
        FROM cliente c
        INNER JOIN credito_cliente cc
            ON c.nro_cliente = cc.nro_cliente
        INNER JOIN cuota_credito_cliente q
            ON cc.nro_solic_credito = q.nro_solic_credito
        WHERE c.nro_cliente = v_nro_cliente
          AND q.fecha_pago_cuota IS NULL
    ) LOOP
        INSERT INTO cliente_postergacion (
            nro_cliente, run_cliente, nombre_cliente,
            nro_solic_credito, nro_cuota,
            fecha_venc_cuota, valor_cuota,
            nueva_fecha_venc, motivo_postergacion
        )
        VALUES (
            r.nro_cliente, r.run_cliente, r.nombre_cliente,
            r.nro_solic_credito, r.nro_cuota,
            r.fecha_venc_cuota, r.valor_cuota,
            ADD_MONTHS(r.fecha_venc_cuota, 3), -- postergar 3 meses
            v_motivo
        );
    END LOOP;

    DBMS_OUTPUT.PUT_LINE('Postergación registrada para cliente ' || v_nro_cliente);
END;
/



