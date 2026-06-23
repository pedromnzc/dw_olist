# Trabalho BI — Data Warehouse Olist (Modelo Estrela)

Projeto acadêmico de construção de um **Data Warehouse dimensional** (modelo
estrela) no **PostgreSQL** a partir do dataset público de e-commerce da **Olist**,
com posterior análise no **Power BI**.

Todo o DW é reconstruível do zero com 5 scripts SQL em `dw_build/`, executados em
ordem — sem dependência de notebooks ou de qualquer estado manual.

## Pipeline em 4 etapas

| Etapa | Onde | O que faz |
|---|---|---|
| 1. Repositório | schema `repositorio` | Importa os 9 CSVs, uma tabela por arquivo, tudo como `text` (dado bruto). |
| 2. ETL | script `03` | Converte tipos (texto→número/data), padroniza, trata nulos. |
| 3. Data Warehouse | schema `dw` | Modelo estrela tipado, com PKs e FKs. |
| 4. Data Mart | schema `datamart_vendas` | View analítica achatada, pronta para o BI. |

## Modelo dimensional

- **Fato:** `dw.fato_vendas` — **grão = 1 item de pedido** (`order_id` + `order_item_id`).
- **Dimensões (6):** `dim_tempo`, `dim_cliente`, `dim_vendedor`, `dim_produto`,
  `dim_categoria`, `dim_pagamento`.

### Conceitos avançados aplicados (4)

| Conceito | Onde |
|---|---|
| Dimensão tempo | `dim_tempo` (calendário gerado) |
| Role-playing | `dim_tempo` referenciada 2x na fato: `sk_data_compra` e `sk_data_entrega` |
| Snowflake (parcial) | `dim_produto` → `dim_categoria` |
| Dimensão degenerada | `order_id` / `order_item_id` guardados na fato, sem dimensão própria |

## Como executar

Pré-requisito: **PostgreSQL 14+** e **pgAdmin 4**.

Siga o passo a passo detalhado em **[`dw_build/GUIA_pgAdmin.md`](dw_build/GUIA_pgAdmin.md)**.

Resumo da ordem dos scripts:

```
00_setup.sql  →  01_repositorio.sql (+ import dos CSVs)  →  02_dw_ddl.sql  →  03_dw_load.sql  →  04_datamart.sql
```

## Estrutura do repositório

```
.
├── README.md
├── dw_build/                 # scripts SQL do pipeline (executar em ordem)
│   ├── 00_setup.sql          # cria os 3 schemas
│   ├── 01_repositorio.sql    # tabelas brutas (text) + instruções de import
│   ├── 02_dw_ddl.sql         # DDL do modelo estrela (PK/FK)
│   ├── 03_dw_load.sql        # ETL + carga das dimensões e da fato
│   ├── 04_datamart.sql       # view analítica do data mart
│   └── GUIA_pgAdmin.md       # passo a passo na interface do pgAdmin
└── datasets/raw/             # CSVs originais da Olist (fonte dos dados)
```

## Fonte dos dados

Brazilian E-Commerce Public Dataset by Olist — disponível no Kaggle:
https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce
