
-- VARIABLE BIND: ingresar el año a procesar de forma paramétrica
VARIABLE v_anio_proceso NUMBER;

-- Asignación del año actual para el procesamiento
BEGIN
    :v_anio_proceso := EXTRACT(YEAR FROM SYSDATE);
END;
/

-- Mostrar el año que se va a procesar
SET SERVEROUTPUT ON SIZE UNLIMITED;
PROMPT ======================================================================
PROMPT PROCESO DE CÁLCULO DE APORTES SBIF
PROMPT Año a procesar: 
SELECT :v_anio_proceso AS "AÑO_PROCESAMIENTO" FROM DUAL;
PROMPT ======================================================================

DECLARE
    /***************************************************************************
     * SECCIÓN 1: DECLARACIÓN DE VARIABLES Y TIPOS DE DATOS
     ***************************************************************************/
    
    -- VARRAY: Almacena los códigos de tipos de transacción válidos (Avance y Súper Avance)
    TYPE t_tipos_transaccion IS VARRAY(2) OF NUMBER(4);
    v_tipos_transac t_tipos_transaccion := t_tipos_transaccion(102, 103);
    
    -- REGISTRO PL/SQL: Estructura para almacenar información de resumen temporal
    TYPE t_resumen_mes IS RECORD (
        mes_anno         VARCHAR2(6),
        tipo_transaccion VARCHAR2(40),
        monto_total      NUMBER := 0,
        aporte_total     NUMBER := 0,
        contador_trans   NUMBER := 0
    );
    
    -- Variable de tipo registro para acumular datos
    v_resumen_temp t_resumen_mes;
    
    -- Variables para cálculos de aporte SBIF
    v_porcentaje_aporte  NUMBER(2);
    v_aporte_calculado   NUMBER(10);
    v_mes_anno          VARCHAR2(6);
    
    -- Contadores para control de transacciones
    v_total_registros   NUMBER := 0;
    v_contador_procesos NUMBER := 0;
    v_registros_detalle NUMBER := 0;
    v_registros_resumen NUMBER := 0;
    
    -- Variables auxiliares
    v_nombre_tipo_tran  VARCHAR2(40);
    v_run_completo      VARCHAR2(15);
    
    /***************************************************************************
     * SECCIÓN 2: EXCEPCIÓN DEFINIDA POR EL USUARIO
     ***************************************************************************/
    
    -- EXCEPCIÓN PERSONALIZADA: Se lanza cuando no hay datos a procesar
    ex_no_hay_transacciones EXCEPTION;
    
    /***************************************************************************
     * SECCIÓN 3: CURSORES EXPLÍCITOS
     ***************************************************************************/
    
    -- Obtiene todas las transacciones de Avances y Súper Avances
    CURSOR c_transacciones_sbif IS
        SELECT 
            c.numrun,
            c.dvrun,
            ttc.nro_tarjeta,
            ttc.nro_transaccion,
            ttc.fecha_transaccion,
            ttt.nombre_tptran_tarjeta AS tipo_transaccion,
            ttc.monto_total_transaccion,
            ttc.cod_tptran_tarjeta,
            TO_CHAR(ttc.fecha_transaccion, 'MMYYYY') AS mes_anno_trans
        FROM 
            TRANSACCION_TARJETA_CLIENTE ttc
            INNER JOIN TARJETA_CLIENTE tc ON ttc.nro_tarjeta = tc.nro_tarjeta
            INNER JOIN CLIENTE c ON tc.numrun = c.numrun
            INNER JOIN TIPO_TRANSACCION_TARJETA ttt ON ttc.cod_tptran_tarjeta = ttt.cod_tptran_tarjeta
        WHERE 
            -- Filtra solo transacciones del año a procesar
            EXTRACT(YEAR FROM ttc.fecha_transaccion) = :v_anio_proceso
            AND ttc.cod_tptran_tarjeta IN (102, 103)  -- Solo Avances y Súper Avances
        ORDER BY 
            ttc.fecha_transaccion ASC,
            c.numrun ASC;
    
    -- Obtiene el porcentaje de aporte según el monto de la transacción
    CURSOR c_porcentaje_aporte(p_monto_total NUMBER) IS
        SELECT porc_aporte_sbif
        FROM TRAMO_APORTE_SBIF
        WHERE p_monto_total >= tramo_inf_av_sav 
          AND p_monto_total <= tramo_sup_av_sav;
    
    -- Variable para almacenar el registro del cursor principal
    v_transaccion c_transacciones_sbif%ROWTYPE;

BEGIN
    /***************************************************************************
     * SECCIÓN 4: INICIO DEL PROCESO
     ***************************************************************************/
    
    DBMS_OUTPUT.PUT_LINE('======================================================================');
    DBMS_OUTPUT.PUT_LINE('INICIANDO PROCESO DE CÁLCULO DE APORTES SBIF');
    DBMS_OUTPUT.PUT_LINE('Fecha de ejecución: ' || TO_CHAR(SYSDATE, 'DD/MM/YYYY HH24:MI:SS'));
    DBMS_OUTPUT.PUT_LINE('Año a procesar: ' || :v_anio_proceso);
    DBMS_OUTPUT.PUT_LINE('======================================================================');
    DBMS_OUTPUT.PUT_LINE('');
    
    /***************************************************************************
     * SECCIÓN 5: TRUNCADO DE TABLAS
     * Se eliminan datos previos para garantizar que el proceso sea repetible
     ***************************************************************************/
    
    DBMS_OUTPUT.PUT_LINE('Paso 1: Limpiando tablas de resultados...');
    
    -- Truncar tabla de detalle de aportes
    EXECUTE IMMEDIATE 'TRUNCATE TABLE DETALLE_APORTE_SBIF';
    DBMS_OUTPUT.PUT_LINE('  Tabla DETALLE_APORTE_SBIF truncada correctamente');
    
    -- Truncar tabla de resumen de aportes
    EXECUTE IMMEDIATE 'TRUNCATE TABLE RESUMEN_APORTE_SBIF';
    DBMS_OUTPUT.PUT_LINE('  Tabla RESUMEN_APORTE_SBIF truncada correctamente');
    DBMS_OUTPUT.PUT_LINE('');
    
    /***************************************************************************
     * SECCIÓN 6: CONTEO INICIAL DE REGISTROS A PROCESAR
     ***************************************************************************/
    
    DBMS_OUTPUT.PUT_LINE('Paso 2: Contando transacciones a procesar...');
    
    -- Contar total de transacciones que se procesarán
    SELECT COUNT(*)
    INTO v_total_registros
    FROM TRANSACCION_TARJETA_CLIENTE
    WHERE EXTRACT(YEAR FROM fecha_transaccion) = :v_anio_proceso
      AND cod_tptran_tarjeta IN (102, 103);
    
    DBMS_OUTPUT.PUT_LINE('  Total de transacciones encontradas: ' || v_total_registros);
    DBMS_OUTPUT.PUT_LINE('');
    
    -- EXCEPCIÓN DEFINIDA POR USUARIO: Validar que existan registros a procesar
    IF v_total_registros = 0 THEN
        RAISE ex_no_hay_transacciones;
    END IF;
    
    /***************************************************************************
     * SECCIÓN 7: PROCESAMIENTO PRINCIPAL CON CURSOR
     ***************************************************************************/
    
    DBMS_OUTPUT.PUT_LINE('Paso 3: Procesando transacciones...');
    
    -- Abrir cursor principal
    OPEN c_transacciones_sbif;
    
    -- Bucle LOOP para recorrer todas las transacciones
    LOOP
        -- Obtener siguiente registro del cursor
        FETCH c_transacciones_sbif INTO v_transaccion;
        
        -- Salir del bucle cuando no hay más registros
        EXIT WHEN c_transacciones_sbif%NOTFOUND;
        
        -- Incrementar contador de registros procesados
        v_contador_procesos := v_contador_procesos + 1;
        
        /***********************************************************************
         * SECCIÓN 7.1: CÁLCULO DEL APORTE SBIF
         * Se determina el porcentaje según el tramo y se calcula el aporte
         ***********************************************************************/
        
        -- Inicializar porcentaje en 0
        v_porcentaje_aporte := 0;
        
        -- Abrir cursor con parámetro para obtener el porcentaje de aporte
        OPEN c_porcentaje_aporte(v_transaccion.monto_total_transaccion);
        FETCH c_porcentaje_aporte INTO v_porcentaje_aporte;
        
        -- Manejar caso cuando no se encuentra el tramo
        IF c_porcentaje_aporte%NOTFOUND THEN
            v_porcentaje_aporte := 0;  -- Asignar 0% si no está en ningún tramo
        END IF;
        
        CLOSE c_porcentaje_aporte;
        
        -- Calcular el aporte aplicando el porcentaje
        -- Fórmula: (monto_total * porcentaje) / 100
        v_aporte_calculado := ROUND((v_transaccion.monto_total_transaccion * v_porcentaje_aporte) / 100);
        
        -- Construir RUN completo concatenando número y dígito verificador
        v_run_completo := v_transaccion.numrun || '-' || v_transaccion.dvrun;
        
        /***********************************************************************
         * SECCIÓN 7.2: INSERCIÓN EN TABLA DETALLE_APORTE_SBIF
         ***********************************************************************/
        
        INSERT INTO DETALLE_APORTE_SBIF (
            numrun,
            dvrun,
            nro_tarjeta,
            nro_transaccion,
            fecha_transaccion,
            tipo_transaccion,
            monto_transaccion,
            aporte_sbif
        ) VALUES (
            v_transaccion.numrun,
            v_transaccion.dvrun,
            v_transaccion.nro_tarjeta,
            v_transaccion.nro_transaccion,
            v_transaccion.fecha_transaccion,
            v_transaccion.tipo_transaccion,
            v_transaccion.monto_total_transaccion,
            v_aporte_calculado
        );
        
        v_registros_detalle := v_registros_detalle + 1;
        
        /***********************************************************************
         * SECCIÓN 7.3: ACUMULACIÓN PARA RESUMEN (usando REGISTRO PL/SQL)
         ***********************************************************************/
        
        -- Preparar mes_anno en formato MMYYYY
        v_mes_anno := v_transaccion.mes_anno_trans;
        
        -- ESTRUCTURA DE CONTROL: Verificar si ya existe registro de resumen para este mes y tipo
        BEGIN
            -- Intentar actualizar registro existente
            UPDATE RESUMEN_APORTE_SBIF
            SET monto_total_transacciones = monto_total_transacciones + v_transaccion.monto_total_transaccion,
                aporte_total_abif = aporte_total_abif + v_aporte_calculado
            WHERE mes_anno = v_mes_anno
              AND tipo_transaccion = v_transaccion.tipo_transaccion;
            
            -- OPERADOR LÓGICO: Si no se actualizó ningún registro, insertar uno nuevo
            IF SQL%ROWCOUNT = 0 THEN
                INSERT INTO RESUMEN_APORTE_SBIF (
                    mes_anno,
                    tipo_transaccion,
                    monto_total_transacciones,
                    aporte_total_abif
                ) VALUES (
                    v_mes_anno,
                    v_transaccion.tipo_transaccion,
                    v_transaccion.monto_total_transaccion,
                    v_aporte_calculado
                );
                v_registros_resumen := v_registros_resumen + 1;
            END IF;
        END;
        
        -- Mostrar progreso cada 10 registros
        IF MOD(v_contador_procesos, 10) = 0 THEN
            DBMS_OUTPUT.PUT_LINE('  Procesados: ' || v_contador_procesos || ' de ' || v_total_registros);
        END IF;
        
    END LOOP;
    
    -- Cerrar cursor principal
    CLOSE c_transacciones_sbif;
    
    DBMS_OUTPUT.PUT_LINE('  ? Total procesado: ' || v_contador_procesos || ' transacciones');
    DBMS_OUTPUT.PUT_LINE('');
    
    /***************************************************************************
     * SECCIÓN 8: VALIDACIÓN FINAL Y CONTROL DE TRANSACCIONES
     ***************************************************************************/
    
    DBMS_OUTPUT.PUT_LINE('Paso 4: Validando resultados...');
    
    -- OPERADORES DE COMPARACIÓN: Verificar que se procesaron todos los registros
    IF v_contador_procesos = v_total_registros THEN
        DBMS_OUTPUT.PUT_LINE('  ? Validación exitosa: Todos los registros fueron procesados');
        DBMS_OUTPUT.PUT_LINE('  ? Registros en DETALLE_APORTE_SBIF: ' || v_registros_detalle);
        DBMS_OUTPUT.PUT_LINE('  ? Registros en RESUMEN_APORTE_SBIF: ' || v_registros_resumen);
        DBMS_OUTPUT.PUT_LINE('');
        
        -- COMMIT: Confirmar todas las transacciones
        COMMIT;
        DBMS_OUTPUT.PUT_LINE('??? PROCESO COMPLETADO EXITOSAMENTE ???');
        DBMS_OUTPUT.PUT_LINE('Todas las transacciones han sido confirmadas (COMMIT)');
        
    ELSE
        -- OPERADORES LÓGICOS: Si no coinciden los contadores, hay un error
        DBMS_OUTPUT.PUT_LINE('  ? ERROR: No coincide el número de registros procesados');
        DBMS_OUTPUT.PUT_LINE('    Esperados: ' || v_total_registros);
        DBMS_OUTPUT.PUT_LINE('    Procesados: ' || v_contador_procesos);
        
        -- ROLLBACK: Revertir cambios en caso de inconsistencia
        ROLLBACK;
        DBMS_OUTPUT.PUT_LINE('??? TRANSACCIONES REVERTIDAS (ROLLBACK) ???');
    END IF;
    
    DBMS_OUTPUT.PUT_LINE('======================================================================');
    
/*******************************************************************************
 * SECCIÓN 9: MANEJO DE EXCEPCIONES
 *******************************************************************************/
    
EXCEPTION
    -- EXCEPCIÓN DEFINIDA POR USUARIO: No hay transacciones para procesar
    WHEN ex_no_hay_transacciones THEN
        DBMS_OUTPUT.PUT_LINE('');
        DBMS_OUTPUT.PUT_LINE('!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!');
        DBMS_OUTPUT.PUT_LINE('EXCEPCIÓN DEFINIDA POR USUARIO: ex_no_hay_transacciones');
        DBMS_OUTPUT.PUT_LINE('!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!');
        DBMS_OUTPUT.PUT_LINE('No se encontraron transacciones de Avances o Súper Avances');
        DBMS_OUTPUT.PUT_LINE('para el año: ' || :v_anio_proceso);
        DBMS_OUTPUT.PUT_LINE('Verifique que existan datos en TRANSACCION_TARJETA_CLIENTE');
        DBMS_OUTPUT.PUT_LINE('con cod_tptran_tarjeta = 102 o 103');
        DBMS_OUTPUT.PUT_LINE('!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!');
        ROLLBACK;
    
    -- EXCEPCIÓN PREDEFINIDA: Demasiadas filas retornadas
    WHEN TOO_MANY_ROWS THEN
        DBMS_OUTPUT.PUT_LINE('');
        DBMS_OUTPUT.PUT_LINE('!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!');
        DBMS_OUTPUT.PUT_LINE('EXCEPCIÓN PREDEFINIDA: TOO_MANY_ROWS');
        DBMS_OUTPUT.PUT_LINE('!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!');
        DBMS_OUTPUT.PUT_LINE('ERROR: Una consulta SELECT INTO retornó más de una fila');
        DBMS_OUTPUT.PUT_LINE('Código de error: ' || SQLCODE);
        DBMS_OUTPUT.PUT_LINE('Mensaje: ' || SQLERRM);
        DBMS_OUTPUT.PUT_LINE('!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!');
        ROLLBACK;
        
    -- EXCEPCIÓN PREDEFINIDA: No se encontraron datos
    WHEN NO_DATA_FOUND THEN
        DBMS_OUTPUT.PUT_LINE('');
        DBMS_OUTPUT.PUT_LINE('!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!');
        DBMS_OUTPUT.PUT_LINE('EXCEPCIÓN PREDEFINIDA: NO_DATA_FOUND');
        DBMS_OUTPUT.PUT_LINE('!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!');
        DBMS_OUTPUT.PUT_LINE('ERROR: No se encontraron datos en una consulta SELECT INTO');
        DBMS_OUTPUT.PUT_LINE('Verifique que las tablas contengan la información necesaria');
        DBMS_OUTPUT.PUT_LINE('Código de error: ' || SQLCODE);
        DBMS_OUTPUT.PUT_LINE('Mensaje: ' || SQLERRM);
        DBMS_OUTPUT.PUT_LINE('!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!');
        ROLLBACK;
    
    -- EXCEPCIÓN NO PREDEFINIDA: Cualquier otro error
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('');
        DBMS_OUTPUT.PUT_LINE('!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!');
        DBMS_OUTPUT.PUT_LINE('EXCEPCIÓN NO PREDEFINIDA: Error inesperado del sistema');
        DBMS_OUTPUT.PUT_LINE('!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!');
        DBMS_OUTPUT.PUT_LINE('Ha ocurrido un error no controlado durante el proceso');
        DBMS_OUTPUT.PUT_LINE('Código de error Oracle: ' || SQLCODE);
        DBMS_OUTPUT.PUT_LINE('Mensaje de error: ' || SQLERRM);
        DBMS_OUTPUT.PUT_LINE('Contacte al administrador del sistema');
        DBMS_OUTPUT.PUT_LINE('!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!');
        -- Cerrar cursores si están abiertos
        IF c_transacciones_sbif%ISOPEN THEN
            CLOSE c_transacciones_sbif;
        END IF;
        ROLLBACK;
        
END;
/

-- Verificar resultados finales
 --======================================================================
 --RESULTADOS DEL PROCESO
 --======================================================================

 --Tabla DETALLE_APORTE_SBIF (primeros 20 registros):
SELECT * FROM DETALLE_APORTE_SBIF WHERE ROWNUM <= 20 ORDER BY fecha_transaccion, numrun;

-- Tabla RESUMEN_APORTE_SBIF (todos los registros):
SELECT * FROM RESUMEN_APORTE_SBIF ORDER BY mes_anno, tipo_transaccion;


