CREATE OR REPLACE VIEW datamart_vendas.vw_vendas AS
SELECT
    -- ---- Dimensoes degeneradas / identificadores ----
    f.order_id,
    f.order_item_id,
    f.order_status,

    -- ---- Metricas ----
    f.price,
    f.freight_value,
    (f.price + COALESCE(f.freight_value, 0)) AS receita_total,
    f.dias_entrega,

    -- ---- Tempo: DATA DA COMPRA (role-playing 1) ----
    tc.data_completa AS data_compra,
    tc.ano           AS ano_compra,
    tc.mes           AS mes_compra,
    tc.nome_mes      AS mes_nome_compra,
    tc.trimestre     AS trimestre_compra,
    tc.nome_dia_semana AS dia_semana_compra,
    tc.fim_de_semana,

    -- ---- Tempo: DATA DA ENTREGA (role-playing 2) ----
    te.data_completa AS data_entrega,
    te.ano           AS ano_entrega,
    te.mes           AS mes_entrega,

    -- ---- Cliente ----
    cli.cidade AS cidade_cliente,
    cli.estado AS estado_cliente,

    -- ---- Vendedor ----
    ven.cidade AS cidade_vendedor,
    ven.estado AS estado_vendedor,

    -- ---- Produto / Categoria (snowflake) ----
    prod.product_id,
    prod.peso_g,
    cat.categoria_pt,
    cat.categoria_en,

    -- ---- Pagamento ----
    pag.payment_type,
    pag.payment_installments
FROM dw.fato_vendas f
LEFT JOIN dw.dim_tempo     tc   ON f.sk_data_compra  = tc.sk_tempo
LEFT JOIN dw.dim_tempo     te   ON f.sk_data_entrega = te.sk_tempo
LEFT JOIN dw.dim_cliente   cli  ON f.sk_cliente      = cli.sk_cliente
LEFT JOIN dw.dim_vendedor  ven  ON f.sk_vendedor     = ven.sk_vendedor
LEFT JOIN dw.dim_produto   prod ON f.sk_produto      = prod.sk_produto
LEFT JOIN dw.dim_categoria cat  ON prod.sk_categoria = cat.sk_categoria
LEFT JOIN dw.dim_pagamento pag  ON f.sk_pagamento    = pag.sk_pagamento;

-- Conferencia: deve retornar o mesmo numero de linhas da fato
SELECT count(*) AS linhas_view FROM datamart_vendas.vw_vendas;

SELECT * FROM datamart_vendas.vw_vendas LIMIT 100;