--Alejandro Daniel Montufar Reyes

-- 4. Consultas de Validación
-- Listar todos los clientes con productos en mora

--Esta consulta confirma que el datamart conserva el estado del producto (activo, cerrado, moroso)
--y que puede relacionarse con los clientes mediante las claves presentes en las tablas relacionales.

SELECT DISTINCT dClie.cliente_key,
                CASE
                    WHEN dClie.tipo_cliente = 'I' THEN dClie.nombre_completo
                    WHEN dClie.tipo_cliente = 'J' THEN dClie.razon_social
                    ELSE 'N/A'
                    END              AS Nombre,
                dClie.tipo_cliente   as Tipo_CLiente,
                dProdc.tipo_producto as Tipo_Producto,
                dProdc.estado        as Estado
FROM dim_producto AS dProdc
         JOIN dim_cliente AS dClie ON dClie.cliente_id = dProdc.cliente_id
WHERE dProdc.estado = 'moroso';

-- Calcular el saldo total por tipo de cliente (individual vs jurídico)

--Con esto verificamos que dim_cliente contiene tipo_cliente y que dim_producto incluye
--el saldo de cada producto, permitiendo agregaciones por tipo de cliente.

SELECT dClie.tipo_cliente,
       SUM(dProdc.saldo) AS saldo_total
FROM dim_cliente AS dClie
         JOIN dim_producto AS dProdc ON dClie.cliente_id = dProdc.cliente_id
GROUP BY dClie.tipo_cliente;


-- Mostrar el histórico de clasificaciones de riesgo de un cliente específico (ejecutar el DECLARE junto al SELECT)

--Para ver la evolución de la categoría SIB de un cliente se une la tabla de hechos de evaluaciones
--con las dimensiones de tiempo, clientes y categorías

DECLARE @clienteKey INT = 117; -- Reemplázalo por el cliente deseado

SELECT DISTINCT dimt.fecha,
       dimcat.codigo_categoria AS categoria,
       dimcat.descripcion,
       fr.puntaje
FROM fac_evaluacion_riesgo AS fr
         JOIN dim_tiempo AS dimt ON fr.fecha_key = dimt.fecha_key
         JOIN dim_cliente AS dimc ON fr.cliente_key = dimc.cliente_key
         JOIN dim_categoria_riesgo AS dimcat ON fr.categoria_key = dimcat.categoria_key
WHERE fr.cliente_key = @clienteKey
ORDER BY dimt.fecha;


-- 5. Consulta Compleja de Análisis
--Consulta compleja de análisis (TOP‑10 clientes por saldo total y crecimiento mensual)

--Esta consulta usa una CTE y funciones de ventana para calcular el saldo mensual de cada cliente, su variación
--porcentual y la última clasificación de riesgo. Se gestiona el valor nulo con NULLIF y se formatea el saldo.
-- Los clientes están ordenados por saldo total.

WITH SaldosMensuales AS (
    -- Saldo mensual por cliente (suma de montos por mes)
    SELECT dClie.cliente_key,
           dTie.anio,
           dTie.mes,
           SUM(fTrans.monto)                 AS saldo_mes,
           SUM(SUM(fTrans.monto)) OVER (PARTITION BY dClie.cliente_key
               ORDER BY dTie.anio, dTie.mes) AS saldo_acumulado
    FROM fac_transaccion AS fTrans
             JOIN dim_tiempo AS dTie ON fTrans.fecha_key = dTie.fecha_key
             JOIN dim_cliente AS dClie ON fTrans.cliente_key = dClie.cliente_key
    GROUP BY dClie.cliente_key, dTie.anio, dTie.mes),
     Crecimiento AS (
         -- Calcula el porcentaje de crecimiento mensual usando LAG
         SELECT SldsMen.cliente_key,
                SldsMen.anio,
                SldsMen.mes,
                SldsMen.saldo_mes,
                LAG(SldsMen.saldo_mes)
                    OVER (PARTITION BY SldsMen.cliente_key ORDER BY SldsMen.anio, SldsMen.mes) AS saldo_mes_prev,
                CASE
                    WHEN LAG(SldsMen.saldo_mes)
                             OVER (PARTITION BY SldsMen.cliente_key ORDER BY SldsMen.anio, SldsMen.mes) = 0
                        OR LAG(SldsMen.saldo_mes)
                               OVER (PARTITION BY SldsMen.cliente_key ORDER BY SldsMen.anio, SldsMen.mes) IS NULL
                        THEN NULL
                    ELSE
                        ((SldsMen.saldo_mes - LAG(SldsMen.saldo_mes)
                                                  OVER (PARTITION BY SldsMen.cliente_key ORDER BY SldsMen.anio, SldsMen.mes))
                            / NULLIF(LAG(SldsMen.saldo_mes)
                                         OVER (PARTITION BY SldsMen.cliente_key ORDER BY SldsMen.anio, SldsMen.mes), 0)
                            ) * 100
                    END                                                                        AS crecimiento_pct
         FROM SaldosMensuales AS SldsMen),
     SaldoTotal AS (
         -- Suma total por cliente
         SELECT cliente_key,
                SUM(saldo_mes) AS saldo_total
         FROM SaldosMensuales
         GROUP BY cliente_key),
     RiesgoActual AS (
         -- Última clasificación de riesgo de cada cliente
         SELECT fEval.cliente_key,
                dCatR.codigo_categoria,
                ROW_NUMBER() OVER (PARTITION BY fEval.cliente_key ORDER BY dTie.fecha DESC) AS rn
         FROM fac_evaluacion_riesgo AS fEval
                  JOIN dim_tiempo AS dTie ON fEval.fecha_key = dTie.fecha_key
                  JOIN dim_categoria_riesgo AS dCatR ON fEval.categoria_key = dCatR.categoria_key)

SELECT TOP 10 SldTotal.cliente_key,
              CN.Nombre,
              CAST(SldTotal.saldo_total AS MONEY) AS saldo_total,
              MAX(Crec.crecimiento_pct)           AS mayor_crecimiento_mensual,
              CR.Categoria_Riesgo                 AS categoria_riesgo_actual
FROM SaldoTotal AS SldTotal
         JOIN dim_cliente AS dClie ON SldTotal.cliente_key = dClie.cliente_key
         CROSS APPLY (VALUES (CASE
                                  WHEN dClie.tipo_cliente = 'I' THEN dClie.nombre_completo
                                  WHEN dClie.tipo_cliente = 'J' THEN dClie.razon_social
                                  ELSE 'N/A' END)) AS CN(Nombre)
         LEFT JOIN Crecimiento AS Crec ON SldTotal.cliente_key = Crec.cliente_key
         LEFT JOIN RiesgoActual AS RiesAct ON SldTotal.cliente_key = RiesAct.cliente_key AND RiesAct.rn = 1
         CROSS APPLY (VALUES (CASE
                                  WHEN RiesAct.codigo_categoria = 'A' THEN RiesAct.codigo_categoria
                                  WHEN RiesAct.codigo_categoria = 'B' THEN RiesAct.codigo_categoria
                                  WHEN RiesAct.codigo_categoria = 'C' THEN RiesAct.codigo_categoria
                                  WHEN RiesAct.codigo_categoria = 'D' THEN RiesAct.codigo_categoria
                                  WHEN RiesAct.codigo_categoria = 'E' THEN RiesAct.codigo_categoria
                                  ELSE 'N/A' END)) AS CR(Categoria_Riesgo)
GROUP BY SldTotal.cliente_key, CN.Nombre, SldTotal.saldo_total, CR.Categoria_Riesgo
ORDER BY SldTotal.saldo_total DESC;


--6. Detección de Anomalías
-- Detección de anomalías (posible lavado de dinero)

--Se identifican transacciones de los últimos 30 días cuyo monto supera en 300% el promedio histórico del cliente.
--Las fechas se filtran usando la dimensión de tiempo.

WITH Promedios AS (SELECT fTrans.cliente_key,
                          AVG(fTrans.monto) AS promedio_global
                   FROM fac_transaccion AS fTrans
                   GROUP BY fTrans.cliente_key),
     Transacciones30 AS (SELECT fTrans.transaccion_key,
                                fTrans.cliente_key,
                                fTrans.monto,
                                dTie.fecha
                         FROM fac_transaccion AS fTrans
                                  JOIN dim_tiempo AS dTie ON fTrans.fecha_key = dTie.fecha_key
                         WHERE dTie.fecha >= DATEADD(day, -30, CAST(GETDATE() AS DATE)))
SELECT DISTINCT dClie.cliente_key,
       CN.Nombre,
       Trx30.monto,
       Prom.promedio_global,
       (Trx30.monto / NULLIF(Prom.promedio_global, 0)) * 100 AS porcentaje_respecto_al_promedio
FROM Transacciones30 AS Trx30
         JOIN Promedios AS Prom ON Trx30.cliente_key = Prom.cliente_key
         JOIN dim_cliente AS dClie ON Trx30.cliente_key = dClie.cliente_key
         CROSS APPLY (VALUES (CASE
                                  WHEN dClie.tipo_cliente = 'I' THEN dClie.nombre_completo
                                  WHEN dClie.tipo_cliente = 'J' THEN dClie.razon_social
                                  ELSE 'N/A' END)) AS CN(Nombre)
WHERE Prom.promedio_global > 0
  AND Trx30.monto >= (Prom.promedio_global * 3) -- 300% del promedio
ORDER BY porcentaje_respecto_al_promedio DESC;



--Optimización de Query
--Optimización de la consulta final

--SELECT c.nombre, p.tipo_producto, t.fecha, t.monto
--FROM clientes c, productos p, transacciones t
--WHERE c.cliente_id = p.cliente_id
-- AND p.producto_id = t.producto_id
-- AND t.fecha >= '2024-01-01'
-- AND t.monto > 50000
--ORDER BY t.fecha DESC;

--Se aclara que los nombres de las tablas nunca pueden ir en plural.

SELECT CASE
           WHEN dClie.tipo_cliente = 'I' THEN dClie.nombre_completo
           WHEN dClie.tipo_cliente = 'J' THEN dClie.razon_social
           ELSE dClie.nombre_completo
           END    AS nombre,
       dProd.tipo_producto,
       dTie.fecha AS fecha_transaccion,
       fTrans.monto
FROM fac_transaccion AS fTrans
         JOIN dim_tiempo AS dTie ON fTrans.fecha_key = dTie.fecha_key
         JOIN dim_producto AS dProd ON fTrans.producto_key = dProd.producto_key
         JOIN dim_cliente AS dClie ON fTrans.cliente_key = dClie.cliente_key
WHERE dTie.fecha >= '2024-01-01'
  AND fTrans.monto > 50000
ORDER BY dTie.fecha DESC;


-- Opción A: índice compuesto (general)
CREATE NONCLUSTERED INDEX IX_fac_transaccion_fecha_monto
    ON dbo.fac_transaccion (fecha_key, monto DESC)
    INCLUDE (cliente_key, producto_key, agencia_key);

-- Opción B: si el umbral de monto alto es común, usa índice filtrado
CREATE NONCLUSTERED INDEX IX_fac_transaccion_fecha_monto_50k
    ON dbo.fac_transaccion (fecha_key, monto DESC)
    INCLUDE (cliente_key, producto_key, agencia_key)
    WHERE monto > 50000;

-- Asegura búsqueda por fecha y mapeo a la key
CREATE UNIQUE NONCLUSTERED INDEX UX_dim_tiempo_fecha
    ON dbo.dim_tiempo (fecha)
    INCLUDE (fecha_key, anio, mes, dia);


--Alejandro Daniel Montufar Reyes
