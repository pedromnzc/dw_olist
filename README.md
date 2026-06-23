# Trabalho de BI — Data Warehouse Olist (Modelo Estrela)

Integrantes:

- Pedro Muniz Cherulli
- Mateus Cunha dos Santos

Projeto acadêmico de construção de um **Data Warehouse dimensional** (modelo
estrela) no **PostgreSQL** a partir do dataset público de e-commerce da **Olist**,
com análise final no **Power BI**.

Todo o DW é reconstruível do zero com 5 scripts SQL em `dw_build/`, executados em
ordem — sem dependência de notebooks ou de qualquer estado manual. A importação e
o dashboard no Power BI estão documentados em `bi_build/`.

---

## 1. Tema escolhido

**Vendas de e-commerce.** O projeto analisa o desempenho comercial de um
marketplace brasileiro: quanto se vende, onde se vende, o que se vende e como
isso evolui no tempo. O tema foi escolhido por reunir, num só dataset real,
todos os elementos que justificam um Data Warehouse — alto volume de transações,
múltiplas dimensões de análise (tempo, geografia, produto, pagamento) e métricas
de negócio claras (receita, ticket médio, prazo de entrega).

---

## 2. Fonte dos dados

**Brazilian E-Commerce Public Dataset by Olist**, disponível no Kaggle:
https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce

São **9 arquivos CSV** (~100 mil pedidos reais feitos entre 2016 e 2018),
relacionados entre si por chaves de pedido, cliente, produto e vendedor:

| Arquivo | Conteúdo |
|---|---|
| `olist_customers_dataset.csv` | clientes e localização |
| `olist_geolocation_dataset.csv` | coordenadas por CEP |
| `olist_order_items_dataset.csv` | itens de cada pedido (grão da fato) |
| `olist_order_payments_dataset.csv` | formas e parcelas de pagamento |
| `olist_order_reviews_dataset.csv` | avaliações dos pedidos |
| `olist_orders_dataset.csv` | pedidos e datas (compra, entrega) |
| `olist_products_dataset.csv` | produtos e atributos físicos |
| `olist_sellers_dataset.csv` | vendedores e localização |
| `product_category_name_translation.csv` | tradução das categorias |

Os CSVs originais ficam em `datasets/raw/`.

---

## 3. Problema de negócio

A Olist é um intermediário que conecta pequenos vendedores aos grandes
marketplaces. Os dados nascem espalhados em 9 tabelas operacionais, sem tipagem e
sem um ponto único de consulta — inviável para análise direta. As perguntas de
negócio que o DW precisa responder:

- **Qual a receita total e o ticket médio**, e como evoluem no tempo?
- **Onde estão concentradas as vendas** (estados e cidades de vendedores)?
- **Quais categorias de produto** mais faturam?
- **Como está o crescimento** ano a ano e há sazonalidade (ex.: Black Friday)?
- **Qual o prazo médio de entrega**, um indicador de qualidade logística?

O objetivo é transformar dados transacionais brutos em um modelo analítico que
responda a essas perguntas em segundos, de forma confiável e reprodutível.

---

## 4. Modelo dimensional (explicado)

Adotamos um **modelo estrela**: uma tabela **fato** central, cercada por
**dimensões** que dão contexto às métricas.

### Tabela fato — `dw.fato_vendas`

- **Grão:** 1 linha por **item de pedido** (`order_id` + `order_item_id`). É o
  nível mais detalhado disponível e o que permite somar receita corretamente.
- **Métricas (aditivas):** `price`, `freight_value` e `dias_entrega`.

### Dimensões (6)

| Dimensão | Descreve |
|---|---|
| `dim_tempo` | calendário (ano, mês, trimestre, dia da semana, fim de semana) |
| `dim_cliente` | cliente e sua cidade/estado |
| `dim_vendedor` | vendedor e sua cidade/estado |
| `dim_produto` | produto e atributos físicos |
| `dim_categoria` | categoria do produto (PT/EN) |
| `dim_pagamento` | tipo de pagamento e nº de parcelas |

### Conceitos avançados aplicados (4)

| Conceito | Onde, e por quê |
|---|---|
| **Dimensão tempo** | `dim_tempo` é um calendário gerado, não apenas a data crua — habilita análises por trimestre, dia da semana etc. |
| **Role-playing** | `dim_tempo` é referenciada **2x** pela fato: `sk_data_compra` e `sk_data_entrega`. A mesma dimensão exerce dois papéis. |
| **Snowflake (parcial)** | `dim_produto` → `dim_categoria` é normalizado num floco, evitando repetir o nome da categoria em cada produto. |
| **Dimensão degenerada** | `order_id` / `order_item_id` ficam na própria fato, sem dimensão própria — são identificadores, não atributos analíticos. |

### Saída para o BI

Sobre o modelo estrela existe a view **`datamart_vendas.vw_vendas`**, que achata
fato + dimensões em uma única tabela tipada — o **ponto único de entrada** do
Power BI (detalhes em `bi_build/`).

---

## 5. Principais decisões técnicas

- **Pipeline em camadas, 100% em SQL versionado.** Repositório (bruto) → DW
  (tipado, estrela) → Data Mart (view). Nenhuma transformação acontece em
  notebook ou no Power BI; tudo é reconstruível rodando os 5 scripts em ordem.
- **Ingestão como `text` puro no schema `repositorio`.** Os CSVs entram sem
  conversão de tipo, isolando os dados crus de erros de parsing. A tipagem
  (texto→número/data) acontece só na carga do DW (`03_dw_load.sql`).
- **Chaves substitutas (surrogate keys)** geradas por `IDENTITY` em todas as
  dimensões, desacoplando o DW dos IDs de origem.
- **Membro "Não informado" nas dimensões** para que registros sem data/atributo
  não sumam em `INNER JOIN` — a fato sempre encontra a dimensão.
- **`dim_tempo` com chave inteligente `AAAAMMDD`** (inteiro), que serve de PK
  legível e acelera os joins de data.
- **A view como contrato com o BI.** Enquanto suas colunas não mudarem, o
  relatório segue válido mesmo que o ETL por trás seja reescrito.
- **Modo Importação no Power BI** (não DirectQuery): para ~112 mil linhas é mais
  rápido e o refresh nunca quebra por transformação manual.

---

## 6. Desafios enfrentados

- **Import dos CSVs no pgAdmin.** O `\copy` do psql não funciona no pgAdmin;
  foi preciso usar o **Import/Export gráfico**, com atenção ao **Header = ON**
  (senão a linha de cabeçalho entra como dado e cada tabela ganha 1 linha a mais).
- **Volume da geolocation** (~1 milhão de linhas) exigiu cuidado na carga.
- **Datas e números como texto** na origem: tratados na conversão do `03`, com
  cuidado para nulos e formatos inconsistentes.
- **Role-playing no Power BI:** só uma relação ativa por par de tabelas. A data
  de compra ficou ativa e a de entrega inativa, ativada sob demanda via
  `USERELATIONSHIP`.
- **Nome da tabela ao importar a view:** o Power BI a nomeia como
  `datamart_vendas vw_vendas` (com espaço), o que quebra o DAX — resolvido
  renomeando a tabela para `vw_vendas` (passo obrigatório documentado em
  `bi_build/`).
- **Granularidade da receita:** somar no grão do item evita duplicar valores que
  apareceriam se o cálculo fosse feito no nível do pedido.

---

## 7. Insights encontrados

Do dashboard final (`bi_build/`):

- **Receita total de ~R$ 15,84 milhões** em ~99 mil pedidos únicos, com
  **ticket médio de R$ 160,58**.
- **Forte concentração geográfica:** **São Paulo (SP) responde por ~64,6% da
  receita** dos vendedores (~R$ 10,24 mi) — o marketplace é fortemente
  dependente de um único estado.
- **Cidades líderes de vendedores:** São Paulo, seguida de Ibitinga, Curitiba,
  Rio de Janeiro e Guarulhos.
- **Categorias campeãs em faturamento:** `beleza_saude`, `relogios_presentes`,
  `cama_mesa_banho`, `esporte_lazer` e `informatica_acessorios`.
- **Crescimento expressivo:** a receita cresceu fortemente de 2017 para 2018
  (crescimento medido > 100% no período), indicando expansão acelerada da base.
- **Sazonalidade clara:** há um **pico acentuado no fim de 2017**, compatível com
  a **Black Friday** — evento que merece planejamento logístico e de estoque.

> **Leitura de negócio:** o crescimento é saudável, mas a dependência de SP é um
> risco de concentração. Há oportunidade de expandir a base de vendedores em
> outras regiões e de preparar a operação para os picos sazonais.

---

## Como executar

Pré-requisito: **PostgreSQL 14+** e **pgAdmin 4**.

Siga o passo a passo detalhado em **[`dw_build/README.md`](dw_build/README.md)**
(construção do DW) e depois **[`bi_build/README.md`](bi_build/README.md)**
(importação e dashboard no Power BI).

Ordem dos scripts SQL:

```
00_setup.sql → 01_repositorio.sql (+ import dos CSVs) → 02_dw_ddl.sql → 03_dw_load.sql → 04_datamart.sql
```

---

## Estrutura do repositório

```
.
├── README.md                 # este documento
├── dw_build/                 # construção do Data Warehouse (SQL)
│   ├── 00_setup.sql          # cria os 3 schemas
│   ├── 01_repositorio.sql    # tabelas brutas (text) + instruções de import
│   ├── 02_dw_ddl.sql         # DDL do modelo estrela (PK/FK)
│   ├── 03_dw_load.sql        # ETL + carga das dimensões e da fato
│   ├── 04_datamart.sql       # view analítica do data mart
│   └── README.md             # guia de execução no pgAdmin
├── bi_build/                 # importação e dashboard no Power BI
│   └── olist_vendas.pbix     # arquivo .pbix
│   └── README.md             # passo a passo, KPIs e montagem do dashboard
└── datasets/raw/             # CSVs originais da Olist (fonte dos dados)
```
