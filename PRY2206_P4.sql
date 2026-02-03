


SET SERVEROUTPUT ON SIZE UNLIMITED;

DECLARE
    -- ========================================================================
    -- DECLARACIÓN DE TIPOS Y COLECCIONES
    -- ========================================================================
    
    -- Tipo VARRAY para almacenar los valores de puntos según reglas de negocio
    TYPE t_puntos_array IS VARRAY(4) OF NUMBER;
    v_puntos_valores t_puntos_array := t_puntos_array(250, 300, 550, 700);
    
    -- Registro para almacenar información de transacciones
    TYPE t_transaccion_rec IS RECORD (
        numrun              CLIENTE.NUMRUN%TYPE,
        dvrun               CLIENTE.DVRUN%TYPE,
        nro_tarjeta         TARJETA_CLIENTE.NRO_TARJETA%TYPE,
        nro_transaccion     TRANSACCION_TARJETA_CLIENTE.NRO_TRANSACCION%TYPE,
        fecha_transaccion   TRANSACCION_TARJETA_CLIENTE.FECHA_TRANSACCION%TYPE,
        nombre_tipo_tran    VARCHAR2(100),
        monto_transaccion   TRANSACCION_TARJETA_CLIENTE.MONTO_TRANSACCION%TYPE,
        cod_tipo_cliente    TIPO_CLIENTE.COD_TIPO_CLIENTE%TYPE,
        nombre_tipo_cliente TIPO_CLIENTE.NOMBRE_TIPO_CLIENTE%TYPE
    );
    
    -- Registro para resumen mensual
    TYPE t_resumen_mensual_rec IS RECORD (
        mes_anno                 VARCHAR2(6),
        monto_total_compras      NUMBER := 0,
        total_puntos_compras     NUMBER := 0,
        monto_total_avances      NUMBER := 0,
        total_puntos_avances     NUMBER := 0,
        monto_total_savances     NUMBER := 0,
        total_puntos_savances    NUMBER := 0
    );
    
    -- Tipo para cursor variable (REF CURSOR)
    TYPE t_ref_cursor IS REF CURSOR;
    
    -- ========================================================================
    -- DECLARACIÓN DE VARIABLES PARAMÉTRICAS Y DE CONTROL
    -- ========================================================================
    
    -- Variables paramétricas para rangos de montos (puntos extra)
    v_rango1_inf    NUMBER := 500000;   -- Límite inferior rango 1
    v_rango1_sup    NUMBER := 700000;   -- Límite superior rango 1
    v_rango2_inf    NUMBER := 700001;   -- Límite inferior rango 2
    v_rango2_sup    NUMBER := 900000;   -- Límite superior rango 2
    v_rango3_inf    NUMBER := 900001;   -- Límite inferior rango 3
    
    -- Variable para el año a procesar
    v_anio_proceso  NUMBER := EXTRACT(YEAR FROM SYSDATE) - 1;
    
    -- Variables de cálculo
    v_puntos_base           NUMBER := 0;
    v_puntos_extra          NUMBER := 0;
    v_puntos_totales        NUMBER := 0;
    v_monto_anual_cliente   NUMBER := 0;
    v_tipo_transaccion      VARCHAR2(50); 
    
    -- Variables de control
    v_contador_transac      NUMBER := 0;
    v_contador_clientes     NUMBER := 0;
    
    -- ========================================================================
    -- DECLARACIÓN DE CURSORES
    -- ========================================================================
    
    -- Cursor Variable (REF CURSOR) sin parámetros para lectura general
    cur_transacciones       t_ref_cursor;
    v_transaccion           t_transaccion_rec;
    
    -- Cursor Explícito CON PARÁMETROS para obtener monto anual acumulado por cliente
    CURSOR cur_monto_anual_cliente(
        p_numrun NUMBER,
        p_anio NUMBER
    ) IS
        SELECT 
            NVL(SUM(t.MONTO_TRANSACCION), 0) AS monto_anual_total
        FROM TRANSACCION_TARJETA_CLIENTE t
        INNER JOIN TARJETA_CLIENTE tc ON t.NRO_TARJETA = tc.NRO_TARJETA
        WHERE tc.NUMRUN = p_numrun
          AND EXTRACT(YEAR FROM t.FECHA_TRANSACCION) = p_anio;
    
    -- ========================================================================
    -- FUNCIONES INTERNAS
    -- ========================================================================
    
    -- Función para calcular puntos base (250 puntos por cada $100.000)
    FUNCTION calcular_puntos_base(p_monto NUMBER) RETURN NUMBER IS
        v_puntos NUMBER := 0;
    BEGIN
        IF p_monto IS NULL OR p_monto <= 0 THEN
            RETURN 0;
        END IF;
        -- Utilizar el primer valor del VARRAY
        v_puntos := TRUNC(p_monto / 100000) * v_puntos_valores(1);
        RETURN v_puntos;
    EXCEPTION
        WHEN OTHERS THEN
            RETURN 0;
    END calcular_puntos_base;
    
    -- Función para calcular puntos extra según monto anual y tipo de cliente
    FUNCTION calcular_puntos_extra(
        p_monto_anual NUMBER,
        p_tipo_cliente VARCHAR2,
        p_monto_transaccion NUMBER
    ) RETURN NUMBER IS
        v_puntos_extra NUMBER := 0;
        v_factor_puntos NUMBER := 0;
    BEGIN
        IF p_monto_anual IS NULL OR p_monto_anual <= 0 THEN
            RETURN 0;
        END IF;
        
        IF p_monto_transaccion IS NULL OR p_monto_transaccion <= 0 THEN
            RETURN 0;
        END IF;
        
        -- Solo aplica para "Pensionado/3ra Edad" y "Dueña de Casa"
        IF UPPER(TRIM(p_tipo_cliente)) IN ('PENSIONADO/3RA EDAD', 'DUEÑA DE CASA', 
                                           'PENSIONADO', 'DUENA DE CASA',
                                           'PENSIONADO/3RA. EDAD', 'TERCERA EDAD') THEN
            
            -- Determinar factor de puntos según rango de monto anual
            IF p_monto_anual >= v_rango1_inf AND p_monto_anual <= v_rango1_sup THEN
                -- Rango 1: $500.000 - $700.000 ? +300 puntos (índice 2 del VARRAY)
                v_factor_puntos := v_puntos_valores(2);
                
            ELSIF p_monto_anual >= v_rango2_inf AND p_monto_anual <= v_rango2_sup THEN
                -- Rango 2: $700.001 - $900.000 ? +550 puntos (índice 3 del VARRAY)
                v_factor_puntos := v_puntos_valores(3);
                
            ELSIF p_monto_anual > v_rango3_inf THEN
                -- Rango 3: Más de $900.000 ? +700 puntos (índice 4 del VARRAY)
                v_factor_puntos := v_puntos_valores(4);
            END IF;
            
            -- Calcular puntos extra basados en la transacción actual
            IF v_factor_puntos > 0 THEN
                v_puntos_extra := TRUNC(p_monto_transaccion / 100000) * v_factor_puntos;
            END IF;
        END IF;
        
        RETURN v_puntos_extra;
    EXCEPTION
        WHEN OTHERS THEN
            RETURN 0;
    END calcular_puntos_extra;
    
    -- Función para determinar el tipo de transacción normalizado
    FUNCTION obtener_tipo_transaccion(p_nombre_tipo VARCHAR2) RETURN VARCHAR2 IS
        v_nombre_upper VARCHAR2(100);
    BEGIN
        v_nombre_upper := UPPER(TRIM(NVL(p_nombre_tipo, 'OTRO')));
        
        -- Normalizar el nombre del tipo de transacción
        IF v_nombre_upper LIKE '%COMPRA%' THEN
            RETURN 'COMPRA';
        ELSIF v_nombre_upper LIKE '%SUPER%AVANCE%' OR 
              v_nombre_upper LIKE '%SÚPER%AVANCE%' OR
              v_nombre_upper LIKE '%S%PER%AVANCE%' THEN
            RETURN 'SUPER_AVANCE';
        ELSIF v_nombre_upper LIKE '%AVANCE%' THEN
            RETURN 'AVANCE';
        ELSE
            RETURN 'OTRO';
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            RETURN 'OTRO';
    END obtener_tipo_transaccion;

BEGIN
    -- ========================================================================
    -- INICIALIZACIÓN Y LIMPIEZA DE TABLAS
    -- ========================================================================
    
    DBMS_OUTPUT.PUT_LINE('================================================================================');
    DBMS_OUTPUT.PUT_LINE('PROCESO DE GESTIÓN DE PUNTOS CATB - INICIO');
    DBMS_OUTPUT.PUT_LINE('================================================================================');
    DBMS_OUTPUT.PUT_LINE('Año de proceso: ' || v_anio_proceso);
    DBMS_OUTPUT.PUT_LINE('Fecha de ejecución: ' || TO_CHAR(SYSDATE, 'DD/MM/YYYY HH24:MI:SS'));
    DBMS_OUTPUT.PUT_LINE('');
    
    -- Limpiar tabla de detalles de puntos
    DBMS_OUTPUT.PUT_LINE('Limpiando tabla DETALLE_PUNTOS_TARJETA_CATB...');
    BEGIN
        EXECUTE IMMEDIATE 'TRUNCATE TABLE DETALLE_PUNTOS_TARJETA_CATB';
        DBMS_OUTPUT.PUT_LINE('? Tabla DETALLE_PUNTOS_TARJETA_CATB limpiada correctamente');
    EXCEPTION
        WHEN OTHERS THEN
            DBMS_OUTPUT.PUT_LINE('? Error al limpiar DETALLE_PUNTOS_TARJETA_CATB: ' || SQLERRM);
            RAISE;
    END;
    
    -- Limpiar tabla de resumen de puntos
    DBMS_OUTPUT.PUT_LINE('Limpiando tabla RESUMEN_PUNTOS_TARJETA_CATB...');
    BEGIN
        EXECUTE IMMEDIATE 'TRUNCATE TABLE RESUMEN_PUNTOS_TARJETA_CATB';
        DBMS_OUTPUT.PUT_LINE('? Tabla RESUMEN_PUNTOS_TARJETA_CATB limpiada correctamente');
    EXCEPTION
        WHEN OTHERS THEN
            DBMS_OUTPUT.PUT_LINE('? Error al limpiar RESUMEN_PUNTOS_TARJETA_CATB: ' || SQLERRM);
            RAISE;
    END;
    
    DBMS_OUTPUT.PUT_LINE('');
    
    -- ========================================================================
    -- PROCESAMIENTO DE TRANSACCIONES (CURSOR VARIABLE)
    -- ========================================================================
    
    DBMS_OUTPUT.PUT_LINE('Iniciando procesamiento de transacciones del año ' || v_anio_proceso || '...');
    DBMS_OUTPUT.PUT_LINE('');
    
    -- Abrir cursor variable con consulta de todas las transacciones del año
    OPEN cur_transacciones FOR
        SELECT 
            c.NUMRUN,
            c.DVRUN,
            tc.NRO_TARJETA,
            t.NRO_TRANSACCION,
            t.FECHA_TRANSACCION,
            tpt.NOMBRE_TPTRAN_TARJETA,
            t.MONTO_TRANSACCION,
            tip.COD_TIPO_CLIENTE,
            tip.NOMBRE_TIPO_CLIENTE
        FROM TRANSACCION_TARJETA_CLIENTE t
        INNER JOIN TARJETA_CLIENTE tc ON t.NRO_TARJETA = tc.NRO_TARJETA
        INNER JOIN CLIENTE c ON tc.NUMRUN = c.NUMRUN
        INNER JOIN TIPO_CLIENTE tip ON c.COD_TIPO_CLIENTE = tip.COD_TIPO_CLIENTE
        INNER JOIN TIPO_TRANSACCION_TARJETA tpt ON t.COD_TPTRAN_TARJETA = tpt.COD_TPTRAN_TARJETA
        WHERE EXTRACT(YEAR FROM t.FECHA_TRANSACCION) = v_anio_proceso
        ORDER BY t.FECHA_TRANSACCION ASC, c.NUMRUN ASC, t.NRO_TRANSACCION ASC;
    
    -- Recorrer todas las transacciones
    LOOP
        BEGIN
            -- Fetch de cada transacción en el registro
            FETCH cur_transacciones INTO v_transaccion;
            EXIT WHEN cur_transacciones%NOTFOUND;
            
            v_contador_transac := v_contador_transac + 1;
            
            
            IF v_contador_transac <= 5 THEN
                DBMS_OUTPUT.PUT_LINE('DEBUG Transacción #' || v_contador_transac || 
                                   ' | RUN: ' || v_transaccion.numrun ||
                                   ' | Monto: $' || v_transaccion.monto_transaccion ||
                                   ' | Tipo: ' || SUBSTR(v_transaccion.nombre_tipo_tran, 1, 30));
            END IF;
            
            -- Obtener monto anual acumulado del cliente usando cursor con parámetros
            v_monto_anual_cliente := 0;
            
            OPEN cur_monto_anual_cliente(v_transaccion.numrun, v_anio_proceso);
            FETCH cur_monto_anual_cliente INTO v_monto_anual_cliente;
            CLOSE cur_monto_anual_cliente;
            
            -- Si no se encuentra monto anual, usar 0
            IF v_monto_anual_cliente IS NULL THEN
                v_monto_anual_cliente := 0;
            END IF;
            
            -- ================================================================
            -- CÁLCULO DE PUNTOS
            -- ================================================================
            
            -- Calcular puntos base (aplicable a todos los clientes)
            v_puntos_base := calcular_puntos_base(v_transaccion.monto_transaccion);
            
            -- Calcular puntos extra (solo para tipos específicos de cliente)
            v_puntos_extra := calcular_puntos_extra(
                v_monto_anual_cliente,
                v_transaccion.nombre_tipo_cliente,
                v_transaccion.monto_transaccion
            );
            
            -- Calcular puntos totales
            v_puntos_totales := NVL(v_puntos_base, 0) + NVL(v_puntos_extra, 0);
            
            -- Determinar tipo de transacción normalizado
            v_tipo_transaccion := obtener_tipo_transaccion(v_transaccion.nombre_tipo_tran);
            
            -- Debug: Mostrar cálculo de puntos para las primeras transacciones
            IF v_contador_transac <= 5 THEN
                DBMS_OUTPUT.PUT_LINE('  -> Puntos Base: ' || v_puntos_base || 
                                   ' | Puntos Extra: ' || v_puntos_extra ||
                                   ' | Total: ' || v_puntos_totales ||
                                   ' | Tipo Norm: ' || v_tipo_transaccion);
            END IF;
            
            -- ================================================================
            -- INSERCIÓN EN TABLA DE DETALLE
            -- ================================================================
            
            INSERT INTO DETALLE_PUNTOS_TARJETA_CATB (
                NUMRUN,
                DVRUN,
                NRO_TARJETA,
                NRO_TRANSACCION,
                FECHA_TRANSACCION,
                TIPO_TRANSACCION,
                MONTO_TRANSACCION,
                PUNTOS_ALLTHEBEST
            ) VALUES (
                v_transaccion.numrun,
                v_transaccion.dvrun,
                v_transaccion.nro_tarjeta,
                v_transaccion.nro_transaccion,
                v_transaccion.fecha_transaccion,
                v_tipo_transaccion,
                NVL(v_transaccion.monto_transaccion, 0),
                v_puntos_totales
            );
            
            -- Mostrar progreso cada 100 transacciones
            IF MOD(v_contador_transac, 100) = 0 THEN
                DBMS_OUTPUT.PUT_LINE('Procesadas ' || v_contador_transac || ' transacciones...');
            END IF;
            
        EXCEPTION
            WHEN OTHERS THEN
                DBMS_OUTPUT.PUT_LINE('');
                DBMS_OUTPUT.PUT_LINE('*** ERROR EN TRANSACCIÓN #' || v_contador_transac || ' ***');
                DBMS_OUTPUT.PUT_LINE('RUN: ' || v_transaccion.numrun);
                DBMS_OUTPUT.PUT_LINE('Tarjeta: ' || v_transaccion.nro_tarjeta);
                DBMS_OUTPUT.PUT_LINE('Nro Transacción: ' || v_transaccion.nro_transaccion);
                DBMS_OUTPUT.PUT_LINE('Monto: ' || v_transaccion.monto_transaccion);
                DBMS_OUTPUT.PUT_LINE('Tipo Transacción Original: ' || v_transaccion.nombre_tipo_tran);
                DBMS_OUTPUT.PUT_LINE('Tipo Transacción Normalizado: ' || v_tipo_transaccion);
                DBMS_OUTPUT.PUT_LINE('Error: ' || SQLERRM);
                DBMS_OUTPUT.PUT_LINE('');
                RAISE;
        END;
        
    END LOOP;
    
    -- Cerrar cursor variable
    CLOSE cur_transacciones;
    
    -- Confirmar cambios en tabla de detalle
    COMMIT;
    
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('? Total de transacciones procesadas: ' || v_contador_transac);
    DBMS_OUTPUT.PUT_LINE('? Datos insertados en DETALLE_PUNTOS_TARJETA_CATB correctamente');
    DBMS_OUTPUT.PUT_LINE('');
    
    -- ========================================================================
    --  GENERACIÓN DE RESUMEN MENSUAL 
    -- ========================================================================
    
    DBMS_OUTPUT.PUT_LINE('Generando resumen mensual de puntos...');
    DBMS_OUTPUT.PUT_LINE('');
    
    -- Procesar resumen mensual desde la tabla de detalles ya poblada
    FOR v_mes IN (
        SELECT DISTINCT TO_CHAR(FECHA_TRANSACCION, 'YYYYMM') AS mes_anno
        FROM DETALLE_PUNTOS_TARJETA_CATB
        ORDER BY TO_CHAR(FECHA_TRANSACCION, 'YYYYMM')
    ) LOOP
        
        DECLARE
            v_resumen t_resumen_mensual_rec;
        BEGIN
            v_resumen.mes_anno := v_mes.mes_anno;
            
            -- Calcular totales por tipo de transacción usando CASE
            SELECT 
                NVL(SUM(CASE WHEN TIPO_TRANSACCION = 'COMPRA' THEN MONTO_TRANSACCION ELSE 0 END), 0) AS monto_compras,
                NVL(SUM(CASE WHEN TIPO_TRANSACCION = 'COMPRA' THEN PUNTOS_ALLTHEBEST ELSE 0 END), 0) AS puntos_compras,
                NVL(SUM(CASE WHEN TIPO_TRANSACCION = 'AVANCE' THEN MONTO_TRANSACCION ELSE 0 END), 0) AS monto_avances,
                NVL(SUM(CASE WHEN TIPO_TRANSACCION = 'AVANCE' THEN PUNTOS_ALLTHEBEST ELSE 0 END), 0) AS puntos_avances,
                NVL(SUM(CASE WHEN TIPO_TRANSACCION = 'SUPER_AVANCE' THEN MONTO_TRANSACCION ELSE 0 END), 0) AS monto_savances,
                NVL(SUM(CASE WHEN TIPO_TRANSACCION = 'SUPER_AVANCE' THEN PUNTOS_ALLTHEBEST ELSE 0 END), 0) AS puntos_savances
            INTO 
                v_resumen.monto_total_compras,
                v_resumen.total_puntos_compras,
                v_resumen.monto_total_avances,
                v_resumen.total_puntos_avances,
                v_resumen.monto_total_savances,
                v_resumen.total_puntos_savances
            FROM DETALLE_PUNTOS_TARJETA_CATB
            WHERE TO_CHAR(FECHA_TRANSACCION, 'YYYYMM') = v_mes.mes_anno;
            
            -- Insertar en tabla de resumen
            INSERT INTO RESUMEN_PUNTOS_TARJETA_CATB (
                MES_ANNO,
                MONTO_TOTAL_COMPRAS,
                TOTAL_PUNTOS_COMPRAS,
                MONTO_TOTAL_AVANCES,
                TOTAL_PUNTOS_AVANCES,
                MONTO_TOTAL_SAVANCES,
                TOTAL_PUNTOS_SAVANCES
            ) VALUES (
                v_resumen.mes_anno,
                v_resumen.monto_total_compras,
                v_resumen.total_puntos_compras,
                v_resumen.monto_total_avances,
                v_resumen.total_puntos_avances,
                v_resumen.monto_total_savances,
                v_resumen.total_puntos_savances
            );
            
            DBMS_OUTPUT.PUT_LINE('  Mes ' || v_resumen.mes_anno || 
                               ' | Compras: $' || TO_CHAR(v_resumen.monto_total_compras, '999G999G999') ||
                               ' (' || v_resumen.total_puntos_compras || ' pts) | ' ||
                               'Avances: $' || TO_CHAR(v_resumen.monto_total_avances, '999G999G999') ||
                               ' (' || v_resumen.total_puntos_avances || ' pts)');
        END;
        
    END LOOP;
    
    -- Confirmar cambios en tabla de resumen
    COMMIT;
    
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('? Resumen mensual generado correctamente en RESUMEN_PUNTOS_TARJETA_CATB');
    DBMS_OUTPUT.PUT_LINE('');
    
    -- ========================================================================
    -- ESTADÍSTICAS FINALES
    -- ========================================================================
    
    DECLARE
        v_total_puntos_otorgados NUMBER;
        v_total_monto_transacciones NUMBER;
        v_clientes_unicos NUMBER;
    BEGIN
        -- Calcular estadísticas generales
        SELECT 
            NVL(SUM(PUNTOS_ALLTHEBEST), 0),
            NVL(SUM(MONTO_TRANSACCION), 0),
            COUNT(DISTINCT NUMRUN)
        INTO
            v_total_puntos_otorgados,
            v_total_monto_transacciones,
            v_clientes_unicos
        FROM DETALLE_PUNTOS_TARJETA_CATB;
        
        DBMS_OUTPUT.PUT_LINE('================================================================================');
        DBMS_OUTPUT.PUT_LINE('ESTADÍSTICAS FINALES DEL PROCESO');
        DBMS_OUTPUT.PUT_LINE('================================================================================');
        DBMS_OUTPUT.PUT_LINE('Total de transacciones procesadas: ' || TO_CHAR(v_contador_transac, '999G999G999'));
        DBMS_OUTPUT.PUT_LINE('Total de clientes únicos: ' || TO_CHAR(v_clientes_unicos, '999G999G999'));
        DBMS_OUTPUT.PUT_LINE('Monto total transaccionado: $' || TO_CHAR(v_total_monto_transacciones, '999G999G999G999'));
        DBMS_OUTPUT.PUT_LINE('Total de puntos otorgados: ' || TO_CHAR(v_total_puntos_otorgados, '999G999G999G999'));
        
        IF v_contador_transac > 0 THEN
            DBMS_OUTPUT.PUT_LINE('Promedio puntos por transacción: ' || 
                               ROUND(v_total_puntos_otorgados / v_contador_transac, 2));
        END IF;
        
        DBMS_OUTPUT.PUT_LINE('');
        DBMS_OUTPUT.PUT_LINE('Configuración de puntos utilizada:');
        DBMS_OUTPUT.PUT_LINE('  - Puntos base: ' || v_puntos_valores(1) || ' pts por cada $100.000');
        DBMS_OUTPUT.PUT_LINE('  - Puntos extra Rango 1 ($' || TO_CHAR(v_rango1_inf, '999G999') || 
                           ' - $' || TO_CHAR(v_rango1_sup, '999G999') || '): +' || 
                           v_puntos_valores(2) || ' pts');
        DBMS_OUTPUT.PUT_LINE('  - Puntos extra Rango 2 ($' || TO_CHAR(v_rango2_inf, '999G999') || 
                           ' - $' || TO_CHAR(v_rango2_sup, '999G999') || '): +' || 
                           v_puntos_valores(3) || ' pts');
        DBMS_OUTPUT.PUT_LINE('  - Puntos extra Rango 3 (Más de $' || TO_CHAR(v_rango3_inf, '999G999') || 
                           '): +' || v_puntos_valores(4) || ' pts');
    END;
    
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('================================================================================');
    DBMS_OUTPUT.PUT_LINE('PROCESO FINALIZADO EXITOSAMENTE');
    DBMS_OUTPUT.PUT_LINE('Fecha de finalización: ' || TO_CHAR(SYSDATE, 'DD/MM/YYYY HH24:MI:SS'));
    DBMS_OUTPUT.PUT_LINE('================================================================================');

EXCEPTION
    WHEN OTHERS THEN
        -- Manejo de errores general
        DBMS_OUTPUT.PUT_LINE('');
        DBMS_OUTPUT.PUT_LINE('================================================================================');
        DBMS_OUTPUT.PUT_LINE('ERROR EN EL PROCESO');
        DBMS_OUTPUT.PUT_LINE('================================================================================');
        DBMS_OUTPUT.PUT_LINE('Código de error: ' || SQLCODE);
        DBMS_OUTPUT.PUT_LINE('Mensaje de error: ' || SQLERRM);
        DBMS_OUTPUT.PUT_LINE('Transacciones procesadas hasta el error: ' || v_contador_transac);
        DBMS_OUTPUT.PUT_LINE('');
        
        -- Cerrar cursores si están abiertos
        IF cur_transacciones%ISOPEN THEN
            CLOSE cur_transacciones;
            DBMS_OUTPUT.PUT_LINE('? Cursor de transacciones cerrado');
        END IF;
        
        -- Rollback de cambios
        ROLLBACK;
        DBMS_OUTPUT.PUT_LINE('? Rollback ejecutado - No se guardaron cambios parciales');
        DBMS_OUTPUT.PUT_LINE('');
        
        -- Re-lanzar la excepción
        RAISE;
END;
/

select * from  DETALLE_PUNTOS_TARJETA_CATB




-- ============================================================================
-- PROCESO DE APORTES SBIF
-- ============================================================================


SET SERVEROUTPUT ON SIZE UNLIMITED;

DECLARE
    -- ========================================================================
    -- DECLARACIÓN DE TIPOS Y REGISTROS
    -- ========================================================================
    
    -- Registro para almacenar información de transacciones de avance
    TYPE t_transaccion_avance_rec IS RECORD (
        numrun              CLIENTE.NUMRUN%TYPE,
        dvrun               CLIENTE.DVRUN%TYPE,
        nro_tarjeta         TARJETA_CLIENTE.NRO_TARJETA%TYPE,
        nro_transaccion     TRANSACCION_TARJETA_CLIENTE.NRO_TRANSACCION%TYPE,
        fecha_transaccion   TRANSACCION_TARJETA_CLIENTE.FECHA_TRANSACCION%TYPE,
        monto_transaccion   TRANSACCION_TARJETA_CLIENTE.MONTO_TRANSACCION%TYPE,
        total_cuotas        TRANSACCION_TARJETA_CLIENTE.TOTAL_CUOTAS_TRANSACCION%TYPE,
        monto_total         TRANSACCION_TARJETA_CLIENTE.MONTO_TOTAL_TRANSACCION%TYPE,
        nombre_tipo_tran    TIPO_TRANSACCION_TARJETA.NOMBRE_TPTRAN_TARJETA%TYPE,
        tasa_interes        TIPO_TRANSACCION_TARJETA.TASAINT_TPTRAN_TARJETA%TYPE
    );
    
    -- Registro para el tramo de aporte SBIF
    TYPE t_tramo_sbif_rec IS RECORD (
        tramo_inf           TRAMO_APORTE_SBIF.TRAMO_INF_AV_SAV%TYPE,
        tramo_sup           TRAMO_APORTE_SBIF.TRAMO_SUP_AV_SAV%TYPE,
        porcentaje_aporte   TRAMO_APORTE_SBIF.PORC_APORTE_SBIF%TYPE
    );
    
    -- Registro para resumen mensual
    TYPE t_resumen_mensual_rec IS RECORD (
        mes_anno                VARCHAR2(6),
        tipo_transaccion        VARCHAR2(50),
        monto_total_transac     NUMBER := 0,
        aporte_total            NUMBER := 0
    );
    
    -- ========================================================================
    -- DECLARACIÓN DE VARIABLES DE CONTROL Y PARÁMETROS
    -- ========================================================================
    
    -- Variable dinámica para el año a procesar
    v_anio_proceso          NUMBER := EXTRACT(YEAR FROM SYSDATE);
    
    -- Variables para cálculo de aportes
    v_monto_total_transac   NUMBER := 0;
    v_porcentaje_aporte     NUMBER := 0;
    v_aporte_sbif           NUMBER := 0;
    v_tipo_transaccion      VARCHAR2(50);
    
    -- Variables de control y estadísticas
    v_contador_transac      NUMBER := 0;
    v_contador_avances      NUMBER := 0;
    v_contador_savances     NUMBER := 0;
    v_total_aportes         NUMBER := 0;
    
    -- ========================================================================
    --  DECLARACIÓN DE CURSORES EXPLÍCITOS
    -- ========================================================================
  
    CURSOR cur_transacciones_avance IS
        SELECT 
            c.NUMRUN,
            c.DVRUN,
            tc.NRO_TARJETA,
            t.NRO_TRANSACCION,
            t.FECHA_TRANSACCION,
            t.MONTO_TRANSACCION,
            t.TOTAL_CUOTAS_TRANSACCION,
            t.MONTO_TOTAL_TRANSACCION,
            tpt.NOMBRE_TPTRAN_TARJETA,
            tpt.TASAINT_TPTRAN_TARJETA
        FROM TRANSACCION_TARJETA_CLIENTE t
        INNER JOIN TARJETA_CLIENTE tc ON t.NRO_TARJETA = tc.NRO_TARJETA
        INNER JOIN CLIENTE c ON tc.NUMRUN = c.NUMRUN
        INNER JOIN TIPO_TRANSACCION_TARJETA tpt ON t.COD_TPTRAN_TARJETA = tpt.COD_TPTRAN_TARJETA
        WHERE EXTRACT(YEAR FROM t.FECHA_TRANSACCION) = v_anio_proceso
          AND (UPPER(tpt.NOMBRE_TPTRAN_TARJETA) LIKE '%AVANCE%')
        ORDER BY t.FECHA_TRANSACCION ASC, c.NUMRUN ASC;
    

    CURSOR cur_tramo_aporte(p_monto_total NUMBER) IS
        SELECT 
            TRAMO_INF_AV_SAV,
            TRAMO_SUP_AV_SAV,
            PORC_APORTE_SBIF
        FROM TRAMO_APORTE_SBIF
        WHERE p_monto_total >= TRAMO_INF_AV_SAV
          AND p_monto_total <= TRAMO_SUP_AV_SAV;
    
   -- resumen mensual
    CURSOR cur_resumen_mensual(p_anio NUMBER) IS
        SELECT 
            TO_CHAR(FECHA_TRANSACCION, 'YYYYMM') AS mes_anno,
            TIPO_TRANSACCION,
            SUM(MONTO_TRANSACCION) AS monto_total,
            SUM(APORTE_SBIF) AS aporte_total
        FROM DETALLE_APORTE_SBIF
        WHERE EXTRACT(YEAR FROM FECHA_TRANSACCION) = p_anio
        GROUP BY TO_CHAR(FECHA_TRANSACCION, 'YYYYMM'), TIPO_TRANSACCION
        ORDER BY TO_CHAR(FECHA_TRANSACCION, 'YYYYMM') ASC, TIPO_TRANSACCION ASC;
    
    -- Variables para almacenar registros de cursores
    v_transaccion           t_transaccion_avance_rec;
    v_tramo_sbif            t_tramo_sbif_rec;
    v_resumen               t_resumen_mensual_rec;
    
    -- ========================================================================
    -- FUNCIONES INTERNAS
    -- ========================================================================
    
    FUNCTION calcular_monto_total_transaccion(
        p_monto_base NUMBER,
        p_tasa_interes NUMBER,
        p_cuotas NUMBER
    ) RETURN NUMBER IS
        v_interes_total NUMBER := 0;
        v_monto_total NUMBER := 0;
    BEGIN
        -- Validar parámetros
        IF p_monto_base IS NULL OR p_monto_base <= 0 THEN
            RETURN 0;
        END IF;
        
        IF p_tasa_interes IS NULL OR p_tasa_interes < 0 THEN
            RETURN p_monto_base;
        END IF;
        
        IF p_cuotas IS NULL OR p_cuotas <= 0 THEN
            RETURN p_monto_base;
        END IF;
        
        -- Calcular interés total
        v_interes_total := p_monto_base * (p_tasa_interes / 100);
        
        -- Calcular monto total
        v_monto_total := p_monto_base + v_interes_total;
        
        RETURN v_monto_total;
        
    EXCEPTION
        WHEN OTHERS THEN
            RETURN p_monto_base;
    END calcular_monto_total_transaccion;
    
    -- Función para obtener el porcentaje de aporte según el tramo
    FUNCTION obtener_porcentaje_aporte(p_monto_total NUMBER) RETURN NUMBER IS
        v_porcentaje NUMBER := 0;
        v_encontrado BOOLEAN := FALSE;
    BEGIN
        -- Validar monto
        IF p_monto_total IS NULL OR p_monto_total <= 0 THEN
            RETURN 0;
        END IF;
        
        -- Buscar el tramo correspondiente usando cursor con parámetros
        FOR v_tramo IN cur_tramo_aporte(p_monto_total) LOOP
            v_porcentaje := v_tramo.PORC_APORTE_SBIF;
            v_encontrado := TRUE;
            EXIT; -- Tomar solo el primer tramo que coincida
        END LOOP;
        
        -- Si no se encuentra tramo, usar porcentaje por defecto (0%)
        IF NOT v_encontrado THEN
            DBMS_OUTPUT.PUT_LINE('? ADVERTENCIA: No se encontró tramo para monto $' || 
                               TO_CHAR(p_monto_total, '999G999G999'));
            v_porcentaje := 0;
        END IF;
        
        RETURN v_porcentaje;
        
    EXCEPTION
        WHEN OTHERS THEN
            DBMS_OUTPUT.PUT_LINE('Error al obtener porcentaje de aporte: ' || SQLERRM);
            RETURN 0;
    END obtener_porcentaje_aporte;
    
    -- Función para calcular el aporte a la SBIF
    FUNCTION calcular_aporte_sbif(
        p_monto_total NUMBER,
        p_porcentaje NUMBER
    ) RETURN NUMBER IS
        v_aporte NUMBER := 0;
    BEGIN
        -- Validar parámetros
        IF p_monto_total IS NULL OR p_monto_total <= 0 THEN
            RETURN 0;
        END IF;
        
        IF p_porcentaje IS NULL OR p_porcentaje < 0 THEN
            RETURN 0;
        END IF;
        
        -- Calcular aporte
        v_aporte := p_monto_total * (p_porcentaje / 100);
        
        -- Redondear a 2 decimales
        v_aporte := ROUND(v_aporte, 2);
        
        RETURN v_aporte;
        
    EXCEPTION
        WHEN OTHERS THEN
            RETURN 0;
    END calcular_aporte_sbif;
    
    -- Función para normalizar el tipo de transacción
    FUNCTION normalizar_tipo_transaccion(p_nombre_tipo VARCHAR2) RETURN VARCHAR2 IS
        v_nombre_upper VARCHAR2(100);
    BEGIN
        v_nombre_upper := UPPER(TRIM(NVL(p_nombre_tipo, 'OTRO')));
        
        -- Clasificar según el nombre
        IF v_nombre_upper LIKE '%SUPER%AVANCE%' OR 
           v_nombre_upper LIKE '%SÚPER%AVANCE%' OR
           v_nombre_upper LIKE '%S%PER%AVANCE%' THEN
            RETURN 'SUPER_AVANCE';
        ELSIF v_nombre_upper LIKE '%AVANCE%' THEN
            RETURN 'AVANCE';
        ELSE
            RETURN 'OTRO';
        END IF;
        
    EXCEPTION
        WHEN OTHERS THEN
            RETURN 'OTRO';
    END normalizar_tipo_transaccion;

BEGIN
    -- ========================================================================
    -- INICIALIZACIÓN Y LIMPIEZA DE TABLAS
    -- ========================================================================
    
    DBMS_OUTPUT.PUT_LINE('======================================================');
    DBMS_OUTPUT.PUT_LINE('PROCESO DE CÁLCULO DE APORTES SBIF - INICIO');
    DBMS_OUTPUT.PUT_LINE('======================================================');
    DBMS_OUTPUT.PUT_LINE('Año de proceso: ' || v_anio_proceso);
    DBMS_OUTPUT.PUT_LINE('Fecha de ejecución: ' || TO_CHAR(SYSDATE, 'DD/MM/YYYY HH24:MI:SS'));
    DBMS_OUTPUT.PUT_LINE('Tipo de transacciones: Avances y Súper Avances');
    DBMS_OUTPUT.PUT_LINE('');
    
    -- Limpiar tabla de detalles de aportes SBIF
    DBMS_OUTPUT.PUT_LINE('Limpiando tabla DETALLE_APORTE_SBIF...');
    BEGIN
        EXECUTE IMMEDIATE 'TRUNCATE TABLE DETALLE_APORTE_SBIF';
        DBMS_OUTPUT.PUT_LINE('Tabla DETALLE_APORTE_SBIF limpiada correctamente');
    EXCEPTION
        WHEN OTHERS THEN
            DBMS_OUTPUT.PUT_LINE('Error al limpiar DETALLE_APORTE_SBIF: ' || SQLERRM);
            RAISE;
    END;
    
    -- Limpiar tabla de resumen de aportes SBIF
    DBMS_OUTPUT.PUT_LINE('Limpiando tabla RESUMEN_APORTE_SBIF...');
    BEGIN
        EXECUTE IMMEDIATE 'TRUNCATE TABLE RESUMEN_APORTE_SBIF';
        DBMS_OUTPUT.PUT_LINE('Tabla RESUMEN_APORTE_SBIF limpiada correctamente');
    EXCEPTION
        WHEN OTHERS THEN
            DBMS_OUTPUT.PUT_LINE('Error al limpiar RESUMEN_APORTE_SBIF: ' || SQLERRM);
            RAISE;
    END;
    
    DBMS_OUTPUT.PUT_LINE('');
    
    -- ======================================================
    -- PROCESAMIENTO DE TRANSACCIONES 
    -- ======================================================
    
    DBMS_OUTPUT.PUT_LINE('Iniciando procesamiento de transacciones de avances del año ' || 
                         v_anio_proceso || '...');
    DBMS_OUTPUT.PUT_LINE('');
    
    -- Abrir cursor explícito para todas las transacciones de avance
    OPEN cur_transacciones_avance;
    
    -- Iterar sobre todas las transacciones
    LOOP
        BEGIN
            -- Fetch de cada transacción en el registro
            FETCH cur_transacciones_avance INTO v_transaccion;
            EXIT WHEN cur_transacciones_avance%NOTFOUND;
            
            v_contador_transac := v_contador_transac + 1;
            
            -- =====================================================
            -- CÁLCULO DE MONTO TOTAL Y APORTE 
            -- =====================================================
   
            IF v_transaccion.monto_total IS NOT NULL AND v_transaccion.monto_total > 0 THEN
                v_monto_total_transac := v_transaccion.monto_total;
            ELSE
                v_monto_total_transac := calcular_monto_total_transaccion(
                    v_transaccion.monto_transaccion,
                    v_transaccion.tasa_interes,
                    v_transaccion.total_cuotas
                );
            END IF;
            
            
            -- Usando cursor con parámetros
            v_porcentaje_aporte := obtener_porcentaje_aporte(v_monto_total_transac);
            
            
            IF v_monto_total_transac > 0 AND v_porcentaje_aporte > 0 THEN
                -- Calcular aporte
                v_aporte_sbif := calcular_aporte_sbif(v_monto_total_transac, v_porcentaje_aporte);
            ELSE
                -- Sin aporte si no hay monto o porcentaje
                v_aporte_sbif := 0;
            END IF;
            
            
            v_tipo_transaccion := normalizar_tipo_transaccion(v_transaccion.nombre_tipo_tran);
            
            
            CASE v_tipo_transaccion
                WHEN 'AVANCE' THEN
                    v_contador_avances := v_contador_avances + 1;
                WHEN 'SUPER_AVANCE' THEN
                    v_contador_savances := v_contador_savances + 1;
                ELSE
                    NULL;
            END CASE;
            
            -- Acumular total de aportes
            v_total_aportes := v_total_aportes + v_aporte_sbif;
            
            
            IF v_contador_transac <= 5 THEN
                DBMS_OUTPUT.PUT_LINE('DEBUG Transacción #' || v_contador_transac);
                DBMS_OUTPUT.PUT_LINE('  RUN: ' || v_transaccion.numrun || 
                                   ' | Tarjeta: ' || v_transaccion.nro_tarjeta);
                DBMS_OUTPUT.PUT_LINE('  Tipo: ' || v_tipo_transaccion || 
                                   ' | Monto Base: $' || TO_CHAR(v_transaccion.monto_transaccion, '999G999G999'));
                DBMS_OUTPUT.PUT_LINE('  Tasa Int: ' || v_transaccion.tasa_interes || '%' ||
                                   ' | Cuotas: ' || v_transaccion.total_cuotas);
                DBMS_OUTPUT.PUT_LINE('  Monto Total: $' || TO_CHAR(v_monto_total_transac, '999G999G999') ||
                                   ' | % Aporte: ' || v_porcentaje_aporte || '%');
                DBMS_OUTPUT.PUT_LINE('  Aporte SBIF: $' || TO_CHAR(v_aporte_sbif, '999G999G999'));
                DBMS_OUTPUT.PUT_LINE('');
            END IF;
            
            -- ================================================================
            -- INSERCIÓN EN TABLA DE DETALLE
            -- ================================================================
            
            INSERT INTO DETALLE_APORTE_SBIF (
                NUMRUN,
                DVRUN,
                NRO_TARJETA,
                NRO_TRANSACCION,
                FECHA_TRANSACCION,
                TIPO_TRANSACCION,
                MONTO_TRANSACCION,
                APORTE_SBIF
            ) VALUES (
                v_transaccion.numrun,
                v_transaccion.dvrun,
                v_transaccion.nro_tarjeta,
                v_transaccion.nro_transaccion,
                v_transaccion.fecha_transaccion,
                v_tipo_transaccion,
                v_monto_total_transac,
                v_aporte_sbif
            );
            
            -- Mostrar progreso cada 100 transacciones
            IF MOD(v_contador_transac, 100) = 0 THEN
                DBMS_OUTPUT.PUT_LINE('Procesadas ' || v_contador_transac || ' transacciones...');
            END IF;
            
        EXCEPTION
            WHEN OTHERS THEN
                DBMS_OUTPUT.PUT_LINE('');
                DBMS_OUTPUT.PUT_LINE('*** ERROR EN TRANSACCIÓN #' || v_contador_transac || ' ***');
                DBMS_OUTPUT.PUT_LINE('RUN: ' || v_transaccion.numrun);
                DBMS_OUTPUT.PUT_LINE('Tarjeta: ' || v_transaccion.nro_tarjeta);
                DBMS_OUTPUT.PUT_LINE('Nro Transacción: ' || v_transaccion.nro_transaccion);
                DBMS_OUTPUT.PUT_LINE('Tipo: ' || v_transaccion.nombre_tipo_tran);
                DBMS_OUTPUT.PUT_LINE('Error: ' || SQLERRM);
                DBMS_OUTPUT.PUT_LINE('');
                RAISE;
        END;
        
    END LOOP;
    
    -- Cerrar cursor explícito
    CLOSE cur_transacciones_avance;
    
    -- Confirmar cambios en tabla de detalle
    COMMIT;
    
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('Total de transacciones procesadas: ' || v_contador_transac);
    DBMS_OUTPUT.PUT_LINE('  - Avances: ' || v_contador_avances);
    DBMS_OUTPUT.PUT_LINE('  - Súper Avances: ' || v_contador_savances);
    DBMS_OUTPUT.PUT_LINE('Datos insertados en DETALLE_APORTE_SBIF correctamente');
    DBMS_OUTPUT.PUT_LINE('');
    
    -- ========================================================================
    -- GENERACIÓN DE RESUMEN MENSUAL (CURSOR EXPLÍCITO CON PARÁMETROS)
    -- ========================================================================
    
    DBMS_OUTPUT.PUT_LINE('Generando resumen mensual de aportes SBIF...');
    DBMS_OUTPUT.PUT_LINE('');
    
    -- Abrir cursor con parámetros para obtener resumen mensual
    OPEN cur_resumen_mensual(v_anio_proceso);
    
    LOOP
        FETCH cur_resumen_mensual INTO v_resumen;
        EXIT WHEN cur_resumen_mensual%NOTFOUND;
        
        -- Insertar en tabla de resumen
        INSERT INTO RESUMEN_APORTE_SBIF (
            MES_ANNO,
            TIPO_TRANSACCION,
            MONTO_TOTAL_TRANSACCIONES,
            APORTE_TOTAL_ABIF
        ) VALUES (
            v_resumen.mes_anno,
            v_resumen.tipo_transaccion,
            NVL(v_resumen.monto_total_transac, 0),
            NVL(v_resumen.aporte_total, 0)
        );
        
        -- Mostrar resumen en consola
        DBMS_OUTPUT.PUT_LINE('  Mes ' || v_resumen.mes_anno || 
                           ' | Tipo: ' || RPAD(v_resumen.tipo_transaccion, 15) ||
                           ' | Monto: $' || TO_CHAR(v_resumen.monto_total_transac, '999G999G999G999') ||
                           ' | Aporte: $' || TO_CHAR(v_resumen.aporte_total, '999G999G999'));
        
    END LOOP;
    
    -- Cerrar cursor de resumen
    CLOSE cur_resumen_mensual;
    
    -- Confirmar cambios en tabla de resumen
    COMMIT;
    
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('Resumen mensual generado correctamente en RESUMEN_APORTE_SBIF');
    DBMS_OUTPUT.PUT_LINE('');
    
    -- ========================================================================
    -- ESTADÍSTICAS FINALES Y REPORTES
    -- ========================================================================
    
    DECLARE
        v_total_monto_transac   NUMBER;
        v_total_aporte_calculado NUMBER;
        v_clientes_unicos       NUMBER;
        v_promedio_aporte       NUMBER;
    BEGIN
        -- Calcular estadísticas generales desde la tabla de detalle
        SELECT 
            NVL(SUM(MONTO_TRANSACCION), 0),
            NVL(SUM(APORTE_SBIF), 0),
            COUNT(DISTINCT NUMRUN)
        INTO
            v_total_monto_transac,
            v_total_aporte_calculado,
            v_clientes_unicos
        FROM DETALLE_APORTE_SBIF;
        
        -- Calcular promedio
        IF v_contador_transac > 0 THEN
            v_promedio_aporte := v_total_aporte_calculado / v_contador_transac;
        ELSE
            v_promedio_aporte := 0;
        END IF;
        
        DBMS_OUTPUT.PUT_LINE('================================================================================');
        DBMS_OUTPUT.PUT_LINE('ESTADÍSTICAS FINALES DEL PROCESO');
        DBMS_OUTPUT.PUT_LINE('================================================================================');
        DBMS_OUTPUT.PUT_LINE('');
        DBMS_OUTPUT.PUT_LINE('TRANSACCIONES PROCESADAS:');
        DBMS_OUTPUT.PUT_LINE('  Total de transacciones: ' || TO_CHAR(v_contador_transac, '999G999G999'));
        DBMS_OUTPUT.PUT_LINE('  - Avances: ' || TO_CHAR(v_contador_avances, '999G999G999'));
        DBMS_OUTPUT.PUT_LINE('  - Súper Avances: ' || TO_CHAR(v_contador_savances, '999G999G999'));
        DBMS_OUTPUT.PUT_LINE('  Clientes únicos: ' || TO_CHAR(v_clientes_unicos, '999G999G999'));
        DBMS_OUTPUT.PUT_LINE('');
        
        DBMS_OUTPUT.PUT_LINE('MONTOS Y APORTES:');
        DBMS_OUTPUT.PUT_LINE('  Monto total transaccionado: $' || 
                           TO_CHAR(v_total_monto_transac, '999G999G999G999'));
        DBMS_OUTPUT.PUT_LINE('  Aporte total a SBIF: $' || 
                           TO_CHAR(v_total_aporte_calculado, '999G999G999G999'));
        DBMS_OUTPUT.PUT_LINE('  Promedio de aporte por transacción: $' || 
                           TO_CHAR(ROUND(v_promedio_aporte, 2), '999G999G999'));
        
        IF v_total_monto_transac > 0 THEN
            DBMS_OUTPUT.PUT_LINE('  Porcentaje efectivo de aporte: ' || 
                               ROUND((v_total_aporte_calculado / v_total_monto_transac) * 100, 2) || '%');
        END IF;
        
    END;
    
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('================================================================================');
    DBMS_OUTPUT.PUT_LINE('PROCESO FINALIZADO EXITOSAMENTE');
    DBMS_OUTPUT.PUT_LINE('Fecha de finalización: ' || TO_CHAR(SYSDATE, 'DD/MM/YYYY HH24:MI:SS'));
    DBMS_OUTPUT.PUT_LINE('Datos listos para reportar a la SBIF');
    DBMS_OUTPUT.PUT_LINE('================================================================================');

EXCEPTION
    WHEN OTHERS THEN
        -- Manejo de errores general
        DBMS_OUTPUT.PUT_LINE('');
        DBMS_OUTPUT.PUT_LINE('================================================================================');
        DBMS_OUTPUT.PUT_LINE('ERROR EN EL PROCESO');
        DBMS_OUTPUT.PUT_LINE('================================================================================');
        DBMS_OUTPUT.PUT_LINE('Código de error: ' || SQLCODE);
        DBMS_OUTPUT.PUT_LINE('Mensaje de error: ' || SQLERRM);
        DBMS_OUTPUT.PUT_LINE('Transacciones procesadas hasta el error: ' || v_contador_transac);
        DBMS_OUTPUT.PUT_LINE('');
        
        -- Cerrar cursores si están abiertos
        IF cur_transacciones_avance%ISOPEN THEN
            CLOSE cur_transacciones_avance;
            DBMS_OUTPUT.PUT_LINE('Cursor de transacciones cerrado');
        END IF;
        
        IF cur_resumen_mensual%ISOPEN THEN
            CLOSE cur_resumen_mensual;
            DBMS_OUTPUT.PUT_LINE('Cursor de resumen mensual cerrado');
        END IF;
        
        -- Rollback de cambios
        ROLLBACK;
        DBMS_OUTPUT.PUT_LINE('Rollback ejecutado - No se guardaron cambios parciales');
        DBMS_OUTPUT.PUT_LINE('');
        
        -- Re-lanzar la excepción
        RAISE;
END;
/


SELECT * FROM detalle_aporte_sbif;

SELECT * FROM resumen_aporte_sbif;
