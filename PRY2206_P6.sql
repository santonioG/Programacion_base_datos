
-- ===============================================================================
-- SECCIÓN 1
-- ===============================================================================

CREATE OR REPLACE PACKAGE pkg_excepciones_gastos_comunes AS
    -- Excepción: Departamento no existe
    ex_departamento_no_existe EXCEPTION;
    PRAGMA EXCEPTION_INIT(ex_departamento_no_existe, -20001);
    
    -- Excepción: Período inválido
    ex_periodo_invalido EXCEPTION;
    PRAGMA EXCEPTION_INIT(ex_periodo_invalido, -20002);
    
    -- Excepción: Valor UF inválido
    ex_valor_uf_invalido EXCEPTION;
    PRAGMA EXCEPTION_INIT(ex_valor_uf_invalido, -20003);
    
    -- Excepción: Error en actualización
    ex_error_actualizacion EXCEPTION;
    PRAGMA EXCEPTION_INIT(ex_error_actualizacion, -20004);
    
    -- Excepción: Datos inconsistentes
    ex_datos_inconsistentes EXCEPTION;
    PRAGMA EXCEPTION_INIT(ex_datos_inconsistentes, -20005);
END pkg_excepciones_gastos_comunes;
/

SHOW ERRORS;

-- ===============================================================================
-- SECCIÓN 2: FUNCIÓN - Validar Período (mes y año)
-- ===============================================================================

CREATE OR REPLACE FUNCTION fn_validar_periodo(
    p_mes IN NUMBER,
    p_anno IN NUMBER
) RETURN BOOLEAN
IS
    v_periodo_valido BOOLEAN := TRUE;
BEGIN
    -- Validar rango de mes (1-12)
    IF p_mes < 1 OR p_mes > 12 THEN
        RAISE_APPLICATION_ERROR(-20002, 
            'Mes invalido (' || p_mes || '). Debe estar entre 1 y 12');
    END IF;
    
    -- Validar rango de año razonable
    IF p_anno < 2020 OR p_anno > 2100 THEN
        RAISE_APPLICATION_ERROR(-20002, 
            'Anio invalido (' || p_anno || '). Debe estar entre 2020 y 2100');
    END IF;
    
    RETURN TRUE;
    
EXCEPTION
    WHEN OTHERS THEN
        RETURN FALSE;
END fn_validar_periodo;
/

SHOW ERRORS;

-- ===============================================================================
-- SECCIÓN 3: FUNCIÓN - Contar Meses Sin Pago
-- ===============================================================================

CREATE OR REPLACE FUNCTION fn_contar_meses_sin_pago(
    p_id_edif IN NUMBER,
    p_nro_depto IN NUMBER,
    p_periodo_inicial IN NUMBER,
    p_meses_a_verificar IN NUMBER DEFAULT 2
) RETURN NUMBER
IS
    v_meses_sin_pago NUMBER := 0;
    v_periodo_actual NUMBER;
    v_mes NUMBER;
    v_anno NUMBER;
    v_count_pagos NUMBER;
BEGIN
    -- Extraer mes y año del período (formato YYYYMM)
    v_anno := TRUNC(p_periodo_inicial / 100);
    v_mes := MOD(p_periodo_inicial, 100);
    
    -- Verificar hacia atrás los últimos N meses
    FOR i IN 1..p_meses_a_verificar LOOP
        -- Retroceder un mes
        v_mes := v_mes - 1;
        
        -- Si el mes es 0, pasar a diciembre del año anterior
        IF v_mes < 1 THEN
            v_mes := 12;
            v_anno := v_anno - 1;
        END IF;
        
        -- Construir período en formato YYYYMM
        v_periodo_actual := v_anno * 100 + v_mes;
        
        -- Contar si existe pago para ese período
        BEGIN
            SELECT COUNT(*)
            INTO v_count_pagos
            FROM PAGO_GASTO_COMUN
            WHERE anno_mes_pcgc = v_periodo_actual
              AND id_edif = p_id_edif
              AND nro_depto = p_nro_depto;
            
            IF v_count_pagos = 0 THEN
                v_meses_sin_pago := v_meses_sin_pago + 1;
            ELSE
                -- Si encontró un pago, dejar de buscar
                EXIT;
            END IF;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                v_meses_sin_pago := v_meses_sin_pago + 1;
        END;
    END LOOP;
    
    RETURN v_meses_sin_pago;
    
EXCEPTION
    WHEN OTHERS THEN
        RETURN 0;
END fn_contar_meses_sin_pago;
/

SHOW ERRORS;

-- ===============================================================================
-- SECCIÓN 4: PROCEDIMIENTO - Insertar Registro de Moroso
-- ===============================================================================

CREATE OR REPLACE PROCEDURE sp_insertar_moroso_v2(
    -- Parámetros IN (10)
    p_anno_mes_pcgc       IN NUMBER,
    p_id_edif             IN NUMBER,
    p_nombre_edif         IN VARCHAR2,
    p_run_administrador   IN VARCHAR2,
    p_nombre_administrador IN VARCHAR2,
    p_nro_depto           IN NUMBER,
    p_run_responsable     IN VARCHAR2,
    p_nombre_responsable  IN VARCHAR2,
    p_valor_multa         IN NUMBER,
    p_observacion         IN VARCHAR2,
    -- Parámetros OUT (2)
    p_resultado           OUT VARCHAR2,
    p_id_insertado        OUT NUMBER,
    -- Parámetro IN OUT (1)
    p_contador_inserciones IN OUT NUMBER
) AS
    v_existe NUMBER := 0;
BEGIN
    -- Verificar si ya existe el registro
    BEGIN
        SELECT COUNT(*)
        INTO v_existe
        FROM GASTO_COMUN_PAGO_CERO
        WHERE anno_mes_pcgc = p_anno_mes_pcgc
          AND id_edif = p_id_edif
          AND nro_depto = p_nro_depto;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            v_existe := 0;
    END;
    
    IF v_existe > 0 THEN
        p_resultado := 'ERROR_DUPLICADO';
        p_id_insertado := -1;
        RETURN;
    END IF;
    
    -- Validar que la multa sea positiva
    IF p_valor_multa <= 0 THEN
        RAISE_APPLICATION_ERROR(-20003, 'Valor de multa debe ser mayor a cero');
    END IF;
    
    -- Insertar el registro
    INSERT INTO GASTO_COMUN_PAGO_CERO (
        anno_mes_pcgc,
        id_edif,
        nombre_edif,
        run_administrador,
        nombre_admnistrador,
        nro_depto,
        run_responsable_pago_gc,
        nombre_responsable_pago_gc,
        valor_multa_pago_cero,
        observacion
    ) VALUES (
        p_anno_mes_pcgc,
        p_id_edif,
        p_nombre_edif,
        p_run_administrador,
        p_nombre_administrador,
        p_nro_depto,
        p_run_responsable,
        p_nombre_responsable,
        p_valor_multa,
        p_observacion
    );
    
    -- Incrementar contador (IN OUT)
    p_contador_inserciones := p_contador_inserciones + 1;
    
    -- Establecer valores de salida (OUT)
    p_resultado := 'OK';
    p_id_insertado := p_contador_inserciones;
    
    COMMIT;
    
EXCEPTION
    WHEN DUP_VAL_ON_INDEX THEN
        ROLLBACK;
        p_resultado := 'ERROR_DUPLICADO';
        p_id_insertado := -1;
        
    WHEN OTHERS THEN
        ROLLBACK;
        p_resultado := 'ERROR';
        p_id_insertado := -1;
        RAISE;
END sp_insertar_moroso_v2;
/

SHOW ERRORS;

-- ===============================================================================
-- SECCIÓN 5: PROCEDIMIENTO PRINCIPAL - Procesar Morosos y Multas
-- ===============================================================================

CREATE OR REPLACE PROCEDURE sp_procesar_morosos_y_multas_v2(
    -- Parámetros IN (3)
    p_mes   IN NUMBER,
    p_anno  IN NUMBER,
    p_valor_uf IN NUMBER,
    -- Parámetros OUT (3)
    p_total_morosos          OUT NUMBER,
    p_total_multas_aplicadas OUT NUMBER,
    p_mensaje_resultado      OUT VARCHAR2,
    -- Parámetro IN OUT (1)
    p_log_ejecucion          IN OUT VARCHAR2
) AS
    -- Variables para almacenar datos del cursor
    v_id_edif NUMBER;
    v_nro_depto NUMBER;
    v_nombre_edif VARCHAR2(50);
    v_run_administrador VARCHAR2(20);
    v_nombre_administrador VARCHAR2(100);
    v_numrun_rpgc NUMBER;
    v_run_responsable VARCHAR2(20);
    v_nombre_responsable VARCHAR2(100);
    
    -- Variables de proceso
    v_anno_mes_actual NUMBER;
    v_meses_sin_pago NUMBER;
    v_valor_multa NUMBER;
    v_observacion VARCHAR2(80);
    v_periodo_valido BOOLEAN;
    
    -- Contadores
    v_total_morosos NUMBER := 0;
    v_total_multas NUMBER := 0;
    v_contador_inserciones NUMBER := 0;
    v_errores NUMBER := 0;
    
    -- Variables para llamar al procedimiento de inserción
    v_resultado_insert VARCHAR2(50);
    v_id_insert NUMBER;
    
    -- Cursor para departamentos
    CURSOR c_departamentos IS
        SELECT 
            d.id_edif,
            d.nro_depto,
            e.nombre_edif,
            a.numrun_adm,
            a.dvrun_adm,
            TRIM(a.pnombre_adm || ' ' || 
                 NVL(a.snombre_adm, '') || ' ' || 
                 a.appaterno_adm || ' ' || 
                 NVL(a.apmaterno_adm, '')) AS nombre_administrador,
            gc.numrun_rpgc,
            TRIM(r.pnombre_rpgc || ' ' || 
                 NVL(r.snombre_rpgc, '') || ' ' || 
                 r.appaterno_rpgc || ' ' || 
                 NVL(r.apmaterno_rpgc, '')) AS nombre_responsable,
            r.dvrun_rpgc
        FROM DEPARTAMENTO d
        INNER JOIN EDIFICIO e ON d.id_edif = e.id_edif
        INNER JOIN ADMINISTRADOR a ON e.numrun_adm = a.numrun_adm
        INNER JOIN GASTO_COMUN gc ON d.id_edif = gc.id_edif 
                                  AND d.nro_depto = gc.nro_depto
        INNER JOIN RESPONSABLE_PAGO_GASTO_COMUN r ON gc.numrun_rpgc = r.numrun_rpgc
        WHERE gc.anno_mes_pcgc = (
            SELECT MAX(anno_mes_pcgc) 
            FROM GASTO_COMUN 
            WHERE id_edif = d.id_edif 
              AND nro_depto = d.nro_depto
        )
        ORDER BY e.nombre_edif, d.nro_depto;
    
BEGIN
    -- ???????????????????????????????????????????????????????????????????????????
    -- FASE 1: VALIDACIONES INICIALES
    -- ???????????????????????????????????????????????????????????????????????????
    
    DBMS_OUTPUT.PUT_LINE('????????????????????????????????????????????????????????');
    DBMS_OUTPUT.PUT_LINE('SISTEMA DE CONTROL DE GASTOS COMUNES Y MULTAS');
    DBMS_OUTPUT.PUT_LINE('????????????????????????????????????????????????????????');
    DBMS_OUTPUT.PUT_LINE(' ');
    
    p_log_ejecucion := p_log_ejecucion || CHR(10) || 
                       'Inicio: ' || TO_CHAR(SYSDATE, 'DD/MM/YYYY HH24:MI:SS');
    
    -- Validar período usando la función
    v_periodo_valido := fn_validar_periodo(p_mes, p_anno);
    
    IF NOT v_periodo_valido THEN
        RAISE_APPLICATION_ERROR(-20002, 'Periodo invalido');
    END IF;
    
    -- Validar valor UF
    IF p_valor_uf IS NULL OR p_valor_uf <= 0 THEN
        RAISE_APPLICATION_ERROR(-20003, 
            'Valor UF invalido: ' || NVL(TO_CHAR(p_valor_uf), 'NULL'));
    END IF;
    
    -- Construir período en formato YYYYMM
    v_anno_mes_actual := p_anno * 100 + p_mes;
    
    DBMS_OUTPUT.PUT_LINE('Periodo a procesar: ' || v_anno_mes_actual);
    DBMS_OUTPUT.PUT_LINE('Valor UF: $' || TO_CHAR(p_valor_uf, '999,999'));
    DBMS_OUTPUT.PUT_LINE(' ');
    
    p_log_ejecucion := p_log_ejecucion || CHR(10) || 
                       'Periodo: ' || v_anno_mes_actual || 
                       ' | UF: $' || TO_CHAR(p_valor_uf, '999,999');
    
    -- ???????????????????????????????????????????????????????????????????????????
    -- FASE 2: LIMPIAR TABLA DE MOROSOS DEL PERÍODO
    -- ???????????????????????????????????????????????????????????????????????????
    
    DELETE FROM GASTO_COMUN_PAGO_CERO 
    WHERE anno_mes_pcgc = v_anno_mes_actual;
    
    COMMIT;
    
    DBMS_OUTPUT.PUT_LINE('Tabla GASTO_COMUN_PAGO_CERO limpiada');
    DBMS_OUTPUT.PUT_LINE(' ');
    DBMS_OUTPUT.PUT_LINE('????????????????????????????????????????????????????????');
    DBMS_OUTPUT.PUT_LINE('PROCESANDO DEPARTAMENTOS...');
    DBMS_OUTPUT.PUT_LINE('????????????????????????????????????????????????????????');
    DBMS_OUTPUT.PUT_LINE(' ');
    
    -- ???????????????????????????????????????????????????????????????????????????
    -- FASE 3: PROCESAR CADA DEPARTAMENTO
    -- ???????????????????????????????????????????????????????????????????????????
    
    FOR rec IN c_departamentos LOOP
        BEGIN
            -- Copiar valores a variables locales
            v_id_edif := rec.id_edif;
            v_nro_depto := rec.nro_depto;
            v_nombre_edif := rec.nombre_edif;
            v_numrun_rpgc := rec.numrun_rpgc;
            v_nombre_administrador := rec.nombre_administrador;
            v_nombre_responsable := rec.nombre_responsable;
            
            -- Formatear RUN administrador
            v_run_administrador := rec.numrun_adm || '-' || rec.dvrun_adm;
            
            -- Formatear RUN responsable
            v_run_responsable := rec.numrun_rpgc || '-' || rec.dvrun_rpgc;
            
            -- Contar meses sin pago usando la función
            v_meses_sin_pago := fn_contar_meses_sin_pago(
                p_id_edif => v_id_edif,
                p_nro_depto => v_nro_depto,
                p_periodo_inicial => v_anno_mes_actual,
                p_meses_a_verificar => 2
            );
            
            -- ???????????????????????????????????????????????????????????????????
            -- SI HAY MOROSIDAD, APLICAR REGLAS DE NEGOCIO
            -- ???????????????????????????????????????????????????????????????????
            
            IF v_meses_sin_pago > 0 THEN
                
                -- CASO A: 1 mes de atraso
                IF v_meses_sin_pago = 1 THEN
                    v_valor_multa := 2 * p_valor_uf;
                    v_observacion := 'AVISO: Corte de combustible y agua si no regulariza';
                
                -- CASO B: 2 o más meses de atraso
                ELSE
                    v_valor_multa := 4 * p_valor_uf;
                    v_observacion := 'CORTE PROGRAMADO: Suspension efectiva proximo mes';
                END IF;
                
                -- ???????????????????????????????????????????????????????????????
                -- INSERTAR REGISTRO DE MOROSO
                -- ???????????????????????????????????????????????????????????????
                
                sp_insertar_moroso_v2(
                    p_anno_mes_pcgc       => v_anno_mes_actual,
                    p_id_edif             => v_id_edif,
                    p_nombre_edif         => v_nombre_edif,
                    p_run_administrador   => v_run_administrador,
                    p_nombre_administrador => v_nombre_administrador,
                    p_nro_depto           => v_nro_depto,
                    p_run_responsable     => v_run_responsable,
                    p_nombre_responsable  => v_nombre_responsable,
                    p_valor_multa         => v_valor_multa,
                    p_observacion         => v_observacion,
                    p_resultado           => v_resultado_insert,
                    p_id_insertado        => v_id_insert,
                    p_contador_inserciones => v_contador_inserciones
                );
                
                IF v_resultado_insert = 'OK' THEN
                    
                    -- Actualizar tabla GASTO_COMUN con la multa
                    BEGIN
                        UPDATE GASTO_COMUN
                        SET multa_gc = v_valor_multa
                        WHERE anno_mes_pcgc = v_anno_mes_actual
                          AND id_edif = v_id_edif
                          AND nro_depto = v_nro_depto;
                        
                        -- Si no existe el registro, crearlo
                        IF SQL%ROWCOUNT = 0 THEN
                            INSERT INTO GASTO_COMUN (
                                anno_mes_pcgc,
                                id_edif,
                                nro_depto,
                                fecha_desde_gc,
                                fecha_hasta_gc,
                                prorrateado_gc,
                                fondo_reserva_gc,
                                agua_individual_gc,
                                combustible_individual_gc,
                                multa_gc,
                                monto_total_gc,
                                fecha_pago_gc,
                                id_epago,
                                numrun_rpgc
                            ) VALUES (
                                v_anno_mes_actual,
                                v_id_edif,
                                v_nro_depto,
                                TRUNC(SYSDATE, 'MM'),
                                LAST_DAY(SYSDATE),
                                50000,
                                0,
                                0,
                                0,
                                v_valor_multa,
                                50000 + v_valor_multa,
                                LAST_DAY(SYSDATE),
                                3,
                                v_numrun_rpgc
                            );
                        END IF;
                        
                        COMMIT;
                    EXCEPTION
                        WHEN OTHERS THEN
                            DBMS_OUTPUT.PUT_LINE('  Error al actualizar GASTO_COMUN: ' || 
                                               SQLERRM);
                            ROLLBACK;
                    END;
                    
                    -- Incrementar contadores
                    v_total_morosos := v_total_morosos + 1;
                    v_total_multas := v_total_multas + v_valor_multa;
                    
                    DBMS_OUTPUT.PUT_LINE(
                        'Moroso #' || v_total_morosos || ': ' || 
                        v_nombre_edif || ' - Depto ' || v_nro_depto || 
                        ' | Multa: $' || TO_CHAR(v_valor_multa, '999,999') ||
                        ' (' || v_meses_sin_pago || ' meses)'
                    );
                END IF;
            END IF;
            
        EXCEPTION
            WHEN OTHERS THEN
                v_errores := v_errores + 1;
                DBMS_OUTPUT.PUT_LINE(
                    'Error en depto ' || v_nro_depto || ': ' || SQLERRM
                );
        END;
    END LOOP;
    
    -- ???????????????????????????????????????????????????????????????????????????
    -- FASE 4: ESTABLECER RESULTADOS (Parámetros OUT)
    -- ???????????????????????????????????????????????????????????????????????????
    
    p_total_morosos := v_total_morosos;
    p_total_multas_aplicadas := v_total_multas;
    
    IF v_total_morosos = 0 THEN
        p_mensaje_resultado := 'COMPLETADO: No se detectaron morosos';
    ELSIF v_errores = 0 THEN
        p_mensaje_resultado := 'EXITOSO: ' || v_total_morosos || ' morosos procesados';
    ELSE
        p_mensaje_resultado := 'COMPLETADO CON ADVERTENCIAS: ' || 
                              v_total_morosos || ' morosos, ' || 
                              v_errores || ' errores';
    END IF;
    
    p_log_ejecucion := p_log_ejecucion || CHR(10) || 
                       'Fin: ' || TO_CHAR(SYSDATE, 'DD/MM/YYYY HH24:MI:SS') || CHR(10) ||
                       'Total morosos: ' || v_total_morosos || CHR(10) ||
                       'Total multas: $' || TO_CHAR(v_total_multas, '999,999,999') || CHR(10) ||
                       'Errores: ' || v_errores;
    
    DBMS_OUTPUT.PUT_LINE(' ');
    DBMS_OUTPUT.PUT_LINE('????????????????????????????????????????????????????????');
    DBMS_OUTPUT.PUT_LINE('PROCESO FINALIZADO');
    DBMS_OUTPUT.PUT_LINE('????????????????????????????????????????????????????????');
    DBMS_OUTPUT.PUT_LINE('Total morosos detectados: ' || v_total_morosos);
    DBMS_OUTPUT.PUT_LINE('Total multas aplicadas: $' || 
                        TO_CHAR(v_total_multas, '999,999,999'));
    DBMS_OUTPUT.PUT_LINE('Errores: ' || v_errores);
    DBMS_OUTPUT.PUT_LINE('????????????????????????????????????????????????????????');
    
EXCEPTION
    WHEN pkg_excepciones_gastos_comunes.ex_periodo_invalido THEN
        ROLLBACK;
        p_total_morosos := 0;
        p_total_multas_aplicadas := 0;
        p_mensaje_resultado := 'ERROR: Periodo invalido';
        p_log_ejecucion := p_log_ejecucion || CHR(10) || 'ERROR: Periodo invalido';
        DBMS_OUTPUT.PUT_LINE('ERROR: Periodo invalido');
        
    WHEN pkg_excepciones_gastos_comunes.ex_valor_uf_invalido THEN
        ROLLBACK;
        p_total_morosos := 0;
        p_total_multas_aplicadas := 0;
        p_mensaje_resultado := 'ERROR: Valor UF invalido';
        p_log_ejecucion := p_log_ejecucion || CHR(10) || 'ERROR: Valor UF invalido';
        DBMS_OUTPUT.PUT_LINE('ERROR: Valor UF invalido');
        
    WHEN OTHERS THEN
        ROLLBACK;
        p_total_morosos := 0;
        p_total_multas_aplicadas := 0;
        p_mensaje_resultado := 'ERROR: ' || SQLERRM;
        p_log_ejecucion := p_log_ejecucion || CHR(10) || 'ERROR: ' || SQLERRM;
        DBMS_OUTPUT.PUT_LINE('ERROR CRITICO: ' || SQLERRM);
        RAISE;
END sp_procesar_morosos_y_multas_v2;
/

SHOW ERRORS;


SET SERVEROUTPUT ON SIZE 1000000;

DECLARE
    v_total_morosos NUMBER;
    v_total_multas NUMBER;
    v_mensaje VARCHAR2(500);
    v_log VARCHAR2(4000) := 'LOG DE EJECUCION:';
BEGIN
    -- Ejecutar procedimiento principal
    sp_procesar_morosos_y_multas_v2(
        p_mes                    => 5,
        p_anno                   => 2025,
        p_valor_uf               => 29509,
        p_total_morosos          => v_total_morosos,
        p_total_multas_aplicadas => v_total_multas,
        p_mensaje_resultado      => v_mensaje,
        p_log_ejecucion          => v_log
    );
    
    DBMS_OUTPUT.PUT_LINE(' ');
    DBMS_OUTPUT.PUT_LINE('????????????????????????????????????????????????????????');
    DBMS_OUTPUT.PUT_LINE('RESULTADOS DE PARAMETROS OUT/IN OUT');
    DBMS_OUTPUT.PUT_LINE('????????????????????????????????????????????????????????');
    DBMS_OUTPUT.PUT_LINE('Total morosos (OUT): ' || v_total_morosos);
    DBMS_OUTPUT.PUT_LINE('Total multas (OUT): $' || TO_CHAR(v_total_multas, '999,999,999'));
    DBMS_OUTPUT.PUT_LINE('Mensaje (OUT): ' || v_mensaje);
    DBMS_OUTPUT.PUT_LINE(' ');
    DBMS_OUTPUT.PUT_LINE('LOG completo (IN OUT):');
    DBMS_OUTPUT.PUT_LINE(v_log);
    DBMS_OUTPUT.PUT_LINE('????????????????????????????????????????????????????????');
    
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('ERROR EN LA PRUEBA: ' || SQLERRM);
        ROLLBACK;
END;
/


