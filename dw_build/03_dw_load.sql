BEGIN;

-- ============================ DIM TEMPO ==============================
-- Calendario continuo cobrindo todo o periodo dos dados (2016-2018).
-- + membro "Nao informado" (sk_tempo = 0) para pedidos sem data de entrega.
INSERT INTO dw.dim_tempo
    (sk_tempo, data_completa, ano, mes, nome_mes, trimestre, dia, dia_semana, nome_dia_semana, fim_de_semana)
SELECT
    to_char(d, 'YYYYMMDD')::int,
    d::date,
    extract(year    from d)::int,
    extract(month   from d)::int,
    CASE extract(month from d)
        WHEN 1 THEN 'Janeiro'  WHEN 2 THEN 'Fevereiro' WHEN 3 THEN 'Marco'
        WHEN 4 THEN 'Abril'    WHEN 5 THEN 'Maio'      WHEN 6 THEN 'Junho'
        WHEN 7 THEN 'Julho'    WHEN 8 THEN 'Agosto'    WHEN 9 THEN 'Setembro'
        WHEN 10 THEN 'Outubro' WHEN 11 THEN 'Novembro' WHEN 12 THEN 'Dezembro'
    END,
    extract(quarter from d)::int,
    extract(day     from d)::int,
    extract(isodow  from d)::int,
    CASE extract(isodow from d)
        WHEN 1 THEN 'Segunda' WHEN 2 THEN 'Terca'  WHEN 3 THEN 'Quarta'
        WHEN 4 THEN 'Quinta'  WHEN 5 THEN 'Sexta'  WHEN 6 THEN 'Sabado'
        WHEN 7 THEN 'Domingo'
    END,
    extract(isodow from d) IN (6, 7)
FROM generate_series('2016-01-01'::date, '2018-12-31'::date, interval '1 day') AS g(d);

INSERT INTO dw.dim_tempo (sk_tempo, data_completa, nome_mes, nome_dia_semana)
VALUES (0, NULL, 'Nao informado', 'Nao informado');

-- ========================== DIM CATEGORIA ===========================
-- Categorias distintas dos produtos + traducao para ingles.
INSERT INTO dw.dim_categoria (categoria_pt, categoria_en)
SELECT DISTINCT
    trim(p.product_category_name),
    t.product_category_name_english
FROM repositorio.products p
LEFT JOIN repositorio.category_translation t
       ON trim(p.product_category_name) = trim(t.product_category_name)
WHERE p.product_category_name IS NOT NULL
  AND trim(p.product_category_name) <> '';

-- membro "Nao informado" para produtos sem categoria
INSERT INTO dw.dim_categoria (categoria_pt, categoria_en)
VALUES ('sem_categoria', 'no_category');

-- =========================== DIM PRODUTO ============================
-- snowflake: cada produto aponta para sua categoria (sk_categoria).
INSERT INTO dw.dim_produto
    (product_id, sk_categoria, peso_g, comprimento_cm, altura_cm, largura_cm, qtd_fotos)
SELECT
    p.product_id,
    COALESCE(c.sk_categoria, sc.sk_categoria),                 -- nulo -> "sem_categoria"
    NULLIF(p.product_weight_g, '')::numeric::int,
    NULLIF(p.product_length_cm, '')::numeric::int,
    NULLIF(p.product_height_cm, '')::numeric::int,
    NULLIF(p.product_width_cm, '')::numeric::int,
    NULLIF(p.product_photos_qty, '')::numeric::int
FROM repositorio.products p
LEFT JOIN dw.dim_categoria c  ON trim(p.product_category_name) = c.categoria_pt
CROSS JOIN (SELECT sk_categoria FROM dw.dim_categoria WHERE categoria_pt = 'sem_categoria') sc;

-- =========================== DIM CLIENTE ============================
INSERT INTO dw.dim_cliente (customer_id, customer_unique_id, cidade, estado, cep)
SELECT
    customer_id,
    customer_unique_id,
    upper(trim(customer_city)),                                -- padronizacao
    upper(trim(customer_state)),
    customer_zip_code_prefix
FROM repositorio.customers;

-- ========================== DIM VENDEDOR ============================
INSERT INTO dw.dim_vendedor (seller_id, cidade, estado, cep)
SELECT
    seller_id,
    upper(trim(seller_city)),
    upper(trim(seller_state)),
    seller_zip_code_prefix
FROM repositorio.sellers;

-- ========================= DIM PAGAMENTO ===========================
-- Combinacoes distintas de (tipo, parcelas).
INSERT INTO dw.dim_pagamento (payment_type, payment_installments)
SELECT DISTINCT
    payment_type,
    NULLIF(payment_installments, '')::int
FROM repositorio.order_payments;

-- membro "Nao informado" para pedidos sem registro de pagamento
INSERT INTO dw.dim_pagamento (payment_type, payment_installments)
VALUES ('nao_informado', NULL);

-- ============================ FATO VENDAS ===========================
-- Grao: 1 item de pedido. Resolve as FKs juntando as chaves naturais
-- as dimensoes ja carregadas.
WITH o AS (   -- ETL das datas dos pedidos (texto -> timestamp), uma unica vez
    SELECT
        order_id,
        customer_id,
        order_status,
        NULLIF(order_purchase_timestamp, '')::timestamp      AS dt_compra,
        NULLIF(order_delivered_customer_date, '')::timestamp AS dt_entrega
    FROM repositorio.orders
),
pg AS (       -- pagamento PRINCIPAL de cada pedido (sequencia = 1) evita fan-out
    SELECT
        order_id,
        payment_type,
        NULLIF(payment_installments, '')::int AS inst
    FROM repositorio.order_payments
    WHERE payment_sequential = '1'
)
INSERT INTO dw.fato_vendas
    (order_id, order_item_id, order_status,
     sk_cliente, sk_vendedor, sk_produto, sk_pagamento,
     sk_data_compra, sk_data_entrega,
     price, freight_value, dias_entrega)
SELECT
    oi.order_id,
    oi.order_item_id::int,
    o.order_status,
    dc.sk_cliente,
    dv.sk_vendedor,
    dp.sk_produto,
    COALESCE(dpg.sk_pagamento, pg_ni.sk_pagamento),                 -- nulo -> "nao_informado"
    COALESCE(to_char(o.dt_compra,  'YYYYMMDD')::int, 0),            -- nulo -> membro 0
    COALESCE(to_char(o.dt_entrega, 'YYYYMMDD')::int, 0),
    NULLIF(oi.price, '')::numeric,
    NULLIF(oi.freight_value, '')::numeric,
    (o.dt_entrega::date - o.dt_compra::date)                       -- dias entre compra e entrega
FROM repositorio.order_items oi
JOIN o                  ON oi.order_id  = o.order_id
LEFT JOIN dw.dim_cliente  dc  ON o.customer_id  = dc.customer_id
LEFT JOIN dw.dim_vendedor dv  ON oi.seller_id   = dv.seller_id
LEFT JOIN dw.dim_produto  dp  ON oi.product_id  = dp.product_id
LEFT JOIN pg              ON oi.order_id = pg.order_id
LEFT JOIN dw.dim_pagamento dpg
       ON dpg.payment_type = pg.payment_type
      AND dpg.payment_installments IS NOT DISTINCT FROM pg.inst
CROSS JOIN (SELECT sk_pagamento FROM dw.dim_pagamento WHERE payment_type = 'nao_informado') pg_ni;

COMMIT;

-- ===================== CONFERENCIA PoS-CARGA ========================
SELECT 'dim_tempo'     AS tabela, count(*) FROM dw.dim_tempo
UNION ALL SELECT 'dim_categoria', count(*) FROM dw.dim_categoria
UNION ALL SELECT 'dim_produto',   count(*) FROM dw.dim_produto
UNION ALL SELECT 'dim_cliente',   count(*) FROM dw.dim_cliente
UNION ALL SELECT 'dim_vendedor',  count(*) FROM dw.dim_vendedor
UNION ALL SELECT 'dim_pagamento', count(*) FROM dw.dim_pagamento
UNION ALL SELECT 'fato_vendas',   count(*) FROM dw.fato_vendas;
