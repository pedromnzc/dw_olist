# Guia de execução no pgAdmin 4

Passo a passo para reconstruir o Data Warehouse do zero usando os scripts da
pasta `dw_build/`. Ordem dos scripts:

`00_setup` → `01_repositorio` (+ import gráfico) → `02_dw_ddl` → `03_dw_load` → `04_datamart`

---

## FASE 0 — Preparar

1. Abra o **pgAdmin 4** e conecte em **Servers → PostgreSQL**.
2. Botão direito em **Databases → Create → Database…** → nome `dw_olist` → **Save**.
3. Selecione o banco `dw_olist` e abra **Tools → Query Tool**.

## FASE 1 — Schemas (`00_setup.sql`)

1. No Query Tool, abra `00_setup.sql` (ícone 📂) e clique **▶ Execute** (F5).
2. Saída esperada: `Schemas criados: repositorio, dw, datamart_vendas`.

> ⚠️ O `00_setup.sql` dá `DROP ... CASCADE`. Rode-o sempre que quiser recomeçar limpo.

## FASE 2 — Repositório: criar tabelas + importar os CSVs

**2a)** Abra `01_repositorio.sql` → **▶ Execute** (cria as 9 tabelas vazias, tudo `text`).

**2b)** Importe cada CSV pela interface (o `\copy` do psql NÃO funciona no pgAdmin):

Para cada tabela em **dw_olist → Schemas → repositorio → Tables**:
1. Botão direito → **Import/Export Data…**
2. Modo **Import**.
3. **Filename:** o `.csv` correspondente em `datasets/raw/`.
4. **Format:** `csv`.
5. Aba **Options:** **Header = ON** ✅ · **Delimiter = `,`**.
6. **OK**.

> 🔴 Atenção ao **Header = ON**. Se ficar desligado, a linha de cabeçalho entra
> como dado e cada tabela fica com 1 linha a mais.

| Tabela | Arquivo |
|---|---|
| customers | olist_customers_dataset.csv |
| geolocation | olist_geolocation_dataset.csv |
| order_items | olist_order_items_dataset.csv |
| order_payments | olist_order_payments_dataset.csv |
| order_reviews | olist_order_reviews_dataset.csv |
| orders | olist_orders_dataset.csv |
| products | olist_products_dataset.csv |
| sellers | olist_sellers_dataset.csv |
| category_translation | product_category_name_translation.csv |

**2c)** Rode a consulta de conferência no fim do `01`. Contagens esperadas:

| tabela | linhas |
|---|---|
| customers | 99.441 |
| geolocation | 1.000.163 |
| order_items | 112.650 |
| order_payments | 103.886 |
| order_reviews | 99.224 |
| orders | 99.441 |
| products | 32.951 |
| sellers | 3.095 |
| category_translation | 71 |

## FASE 3 — Estrutura do DW (`02_dw_ddl.sql`)

Abra `02_dw_ddl.sql` → **▶ Execute**. Cria as 6 dimensões + `fato_vendas` com PKs e FKs.

## FASE 4 — ETL e carga (`03_dw_load.sql`)

Abra `03_dw_load.sql` → **▶ Execute** (arquivo inteiro; está numa transação
`BEGIN…COMMIT`). Contagens esperadas:

| tabela | linhas |
|---|---|
| dim_tempo | 1.096 (+ membro "Não informado") |
| dim_categoria | 74 |
| dim_produto | 32.951 |
| dim_cliente | 99.441 |
| dim_vendedor | 3.095 |
| dim_pagamento | 29 |
| **fato_vendas** | **112.650** |

## FASE 5 — Data Mart (`04_datamart.sql`)

Abra `04_datamart.sql` → **▶ Execute**. Cria a view `datamart_vendas.vw_vendas`
(deve retornar 112.650 linhas) e mostra uma amostra de 100 linhas.

## FASE 6 — Conferir

```sql
SELECT * FROM datamart_vendas.vw_vendas LIMIT 100;
```

Se as linhas vierem com cidade do cliente, categoria do produto, datas de
compra/entrega e tipo de pagamento preenchidos, o DW está pronto para o Power BI.
