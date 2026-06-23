# Importação e Dashboard no Power BI — Data Warehouse Olist

Guia completo para conectar o **Power BI** ao Data Warehouse construído em
`dw_build/`, criar os indicadores e reproduzir o dashboard de vendas. O foco é um
processo **escalável** e **reprodutível**.

O princípio central: **o Power BI nunca lê tabelas brutas nem faz ETL.** Ele
consome **um único ponto de entrada** — a view `datamart_vendas.vw_vendas` — que
já entrega os dados achatados, tipados e prontos. Toda transformação pesada
permanece no banco (SQL versionado), não no relatório. Por isso a importação é
reprodutível: quem rodar os 5 scripts do DW e seguir este guia chega ao mesmo
dashboard.

> **Pré-requisito:** Data Warehouse já reconstruído. Se ainda não fez, rode antes
> os scripts de **[`../dw_build/`](../dw_build/README.md)** na ordem
> `00 → 01 → 02 → 03 → 04`. A última fase precisa estar concluída — a view
> `datamart_vendas.vw_vendas` deve retornar **112.650** linhas.
>
> Visão geral do projeto: **[`../README.md`](../README.md)**.

---

## Visão geral das fases

| Fase | O que faz |
|---|---|
| 1 | Conectar o Power BI ao PostgreSQL e importar a view |
| 2 | **Renomear a tabela para `vw_vendas`** (obrigatório) |
| 3 | Conferir os tipos das colunas |
| 4 | Criar a tabela de calendário (`dCalendario`) |
| 5 | Criar os relacionamentos de tempo (role-playing) |
| 6 | Criar a tabela `_Medidas` e os 11 KPIs |
| 7 | Validar os números contra o DW |
| 8 | Montar o dashboard |

---

## Por que conectar pela view (e não pelas tabelas)

| Abordagem | Problema |
|---|---|
| Importar as 9 tabelas brutas | Joins e tipagem viram trabalho manual no Power Query — frágil e não reprodutível. |
| Importar as 6 dimensões + fato | Funciona, mas exige remontar o modelo estrela dentro do BI. |
| **Importar só `vw_vendas`** | Uma fonte só, já no grão do item de pedido. Mudou a regra de negócio? Altera-se a view em SQL e o relatório acompanha no próximo refresh. |

A view é o **contrato** entre o DW e o BI. Enquanto o nome e as colunas dela não
mudam, o relatório continua válido — mesmo que o ETL por trás seja reescrito.

---

## FASE 1 — Conectar o Power BI ao PostgreSQL

> Necessário **Power BI Desktop**. Na primeira conexão a PostgreSQL ele pode
> pedir para instalar o conector **Npgsql** — aceite e reinicie o Power BI.

1. **Página Inicial → Obter Dados → Mais… → Banco de Dados → PostgreSQL**.
2. Preencha:
   - **Servidor:** `localhost` (ou o host do banco)
   - **Banco de Dados:** `dw_olist`
3. Em **Modo de Conectividade de Dados**, escolha **Importação**
   (ver [Importação vs DirectQuery](#importação-vs-directquery) ao final).
4. Informe usuário/senha do PostgreSQL (ex.: `postgres`). Em **Nível**, deixe
   selecionado o banco `dw_olist` para reaproveitar a credencial.
5. No **Navegador**, abra `dw_olist → datamart_vendas` e marque **apenas**
   `vw_vendas`.
6. Clique em **Transformar Dados** (não em "Carregar") — vamos ajustar antes.

> **Escalabilidade — parametrizar a conexão.** Em **Página Inicial → Gerenciar
> Parâmetros**, crie os parâmetros de texto `pServidor` e `pBanco`. Depois, em
> **Fonte** do Power Query, troque os valores fixos por esses parâmetros. Assim o
> mesmo `.pbix` aponta para `localhost` (dev) ou para o servidor de produção
> mudando só o parâmetro — sem editar a query.

---

## FASE 2 — Renomear a tabela (passo obrigatório)

Ao importar a view, o Power BI nomeia a tabela juntando esquema + nome:
**`datamart_vendas vw_vendas`** (com espaço). Esse espaço quebra as fórmulas DAX
deste guia (obriga aspas e gera erros fáceis de cometer). **Renomeie para
`vw_vendas` antes de prosseguir** — todo o restante do guia assume esse nome.

- Ainda no **editor do Power Query** (FASE 1, passo 6): no painel **Consultas**
  (à esquerda), botão direito na consulta → **Renomear** → digite `vw_vendas`.
- Ou, se já carregou: no painel **Dados** (à direita), botão direito na tabela
  → **Renomear** → `vw_vendas`.

> Sem esse passo, medidas como `SUM ( vw_vendas[receita_total] )` não encontram a
> tabela e retornam erro. **Não pule.**

---

## FASE 3 — Conferir tipos no Power Query

A view já entrega os tipos certos, mas confirme no editor (cada coluna tem um
ícone de tipo no cabeçalho). Ajuste o que estiver divergente:

| Coluna | Tipo esperado |
|---|---|
| `order_id`, `order_status` | Texto |
| `order_item_id` | Número Inteiro |
| `price`, `freight_value`, `receita_total` | Número Decimal |
| `dias_entrega` | Número Inteiro |
| `data_compra`, `data_entrega` | Data |
| `ano_compra`, `mes_compra`, `trimestre_compra`, `ano_entrega`, `mes_entrega` | Número Inteiro |
| `cidade_cliente`, `estado_cliente`, `cidade_vendedor`, `estado_vendedor` | Texto |
| `categoria_pt`, `categoria_en`, `payment_type` | Texto |
| `payment_installments` | Número Inteiro |
| `peso_g` | Número Inteiro |

Quando terminar: **Página Inicial → Fechar e Aplicar**.

---

## FASE 4 — Tabela de calendário (eixo de tempo)

Para análises temporais corretas (hierarquia ano→trimestre→mês, "mesmo período
do ano anterior" etc.) o Power BI precisa de uma **tabela de datas marcada**. A
view traz as datas, mas não uma dimensão de calendário própria — crie uma com DAX.

1. **Modelagem → Nova Tabela** e cole:

   ```dax
   dCalendario =
   ADDCOLUMNS (
       CALENDAR ( DATE ( 2016, 1, 1 ), DATE ( 2018, 12, 31 ) ),
       "Ano",        YEAR ( [Date] ),
       "Mes",        MONTH ( [Date] ),
       "MesNome",    FORMAT ( [Date], "MMM" ),
       "AnoMes",     FORMAT ( [Date], "YYYY-MM" ),
       "Trimestre",  "T" & FORMAT ( [Date], "Q" )
   )
   ```

2. Selecione a tabela `dCalendario` → **Ferramentas de Tabela → Marcar como
   Tabela de Datas** → coluna de data = `Date`.

> O intervalo `2016–2018` cobre os pedidos da Olist. Se o dataset crescer, basta
> alargar o `CALENDAR(...)` — o relatório continua válido.

---

## FASE 5 — Relacionamentos (role-playing)

No modo **Modelo** (ícone à esquerda), ligue o calendário à view:

- `dCalendario[Date]` **1 → \*** `vw_vendas[data_compra]` → deixe **ativo**.
- `dCalendario[Date]` **1 → \*** `vw_vendas[data_entrega]` → ficará **inativo**
  (linha pontilhada). É o esperado: só uma relação ativa por par de tabelas.
  Para analisar por data de entrega, ative-a pontualmente numa medida com
  `USERELATIONSHIP(dCalendario[Date]; vw_vendas[data_entrega])`.

Isso reproduz no BI o **role-playing** que a fato já implementa (a `dim_tempo`
exerce dois papéis: data de compra × data de entrega).

---

## FASE 6 — Tabela de medidas e os 11 KPIs (DAX)

Primeiro crie uma **tabela vazia** só para organizar as medidas (mantém o painel
limpo, separando KPIs dos dados):

1. **Página Inicial → Inserir Dados**.
2. Não digite nada nas células. Em **Nome**, escreva `_Medidas` → **Carregar**.
3. No painel **Dados**, expanda `_Medidas`, botão direito na coluna `Coluna1` →
   **Ocultar** (ou exclua-a depois de criar a primeira medida).

> Use **Inserir Dados**, não `_Medidas = {BLANK()}` via Nova Tabela — a versão
> em DAX falha/gera tabela com coluna indesejada em várias versões do Power BI.

Agora crie as medidas explícitas — sempre prefira medidas a somar colunas direto
no visual. Para cada uma: selecione `_Medidas` → **Nova Medida** → cole:

```dax
-- 1) Total de registros (itens vendidos)
Qtd Itens       = COUNTROWS ( vw_vendas )

-- 2) Total de pedidos distintos
Pedidos Únicos  = DISTINCTCOUNT ( vw_vendas[order_id] )

-- 3) Receita total
Receita Total   = SUM ( vw_vendas[receita_total] )

-- 4) Receita só de produto (sem frete)
Receita Produto = SUM ( vw_vendas[price] )

-- 5) Frete total
Frete Total     = SUM ( vw_vendas[freight_value] )

-- 6) Média — ticket médio por pedido
Ticket Médio    = DIVIDE ( [Receita Total], [Pedidos Únicos] )

-- 7) Média — prazo de entrega em dias
Prazo Médio Entrega = AVERAGE ( vw_vendas[dias_entrega] )

-- 8) Base para crescimento — receita no mesmo período do ano anterior
Receita Ano Anterior =
CALCULATE ( [Receita Total], SAMEPERIODLASTYEAR ( dCalendario[Date] ) )

-- 9) Crescimento ao longo do tempo — variação % YoY
Crescimento Receita % =
DIVIDE ( [Receita Total] - [Receita Ano Anterior], [Receita Ano Anterior] )

-- 10) Participação percentual — % da receita sobre o total (ignora filtros de linha)
% Participação Receita =
DIVIDE ( [Receita Total], CALCULATE ( [Receita Total], ALL ( vw_vendas ) ) )

-- 11) Ranking — posição da categoria por receita
Ranking Receita =
IF (
    HASONEVALUE ( vw_vendas[categoria_pt] ),
    RANKX ( ALL ( vw_vendas[categoria_pt] ), [Receita Total],, DESC )
)
```

> **Formatação:** marque `Crescimento Receita %` e `% Participação Receita` como
> **Porcentagem** (Ferramentas de Medida → Formato), e `Receita Total` /
> `Ticket Médio` / `Frete Total` como **Moeda**.

### Cobertura dos KPIs exigidos (≥ 10)

| # | KPI | Categoria do exemplo |
|---|---|---|
| 1 | Qtd Itens | total de registros |
| 2 | Pedidos Únicos | total de registros |
| 3 | Receita Total | receita total |
| 4 | Receita Produto | receita total |
| 5 | Frete Total | soma |
| 6 | Ticket Médio | média |
| 7 | Prazo Médio Entrega | média |
| 8 | Receita Ano Anterior | série temporal |
| 9 | Crescimento Receita % | crescimento ao longo do tempo |
| 10 | % Participação Receita | participação percentual |
| 11 | Ranking Receita | ranking |

São **11 indicadores**, cobrindo todas as categorias de exemplo pedidas (mínimo 10).

---

## FASE 7 — Validar a importação

Antes de construir visuais, confirme que os números batem com o DW:

| Verificação | Onde conferir | Valor esperado |
|---|---|---|
| Linhas importadas | `Qtd Itens` num cartão | **112.650** |
| `Pedidos Únicos` | cartão | **~98.666** |
| `Receita Total` | cartão | **~R$ 15,8 mi** |
| Datas sem nulos | filtro em `data_compra` | sem branco relevante |

Se `Qtd Itens` ≠ 112.650, a view não foi importada por completo — verifique a
conexão e reexecute **Atualizar**.

---

## FASE 8 — Montagem do dashboard

O dashboard final usa um **tema escuro** com destaque em magenta. São **9 visuais**
em quatro faixas: cartões de KPI no topo, três gráficos de receita por dimensão no
meio, a série temporal abaixo e a tabela de detalhe no rodapé.

```
┌──────────┬──────────┬──────────┬──────────┐  ← faixa de KPIs (4 cartões)
│ Receita  │ Pedidos  │ Ticket   │ % Cresc. │
│ Total    │ Únicos   │ Médio    │ Receita  │
├──────────┴────┬─────┴─────┬────┴──────────┤
│ Rosca:        │ Barras:   │ Barras:       │  ← receita por dimensão
│ estado_vend.  │ categ_pt  │ cidade_vend.  │
├───────────────┴───────────┴───────────────┤
│ Linha: Receita Total por Date (Ano/Mês)   │  ← série temporal
├────────────────────┬──────────────────────┤
│ Tabela: order_id,  │                       │  ← detalhe do pedido
│ order_item_id,     │                       │
│ order_status       │                       │
└────────────────────┴──────────────────────┘
```

### 8.1 Tema escuro

**Exibir → Temas → Escuro** (ou personalizado). Fundo preto e visuais na paleta
magenta/violeta.

### 8.2 Faixa de KPIs — 4 cartões (visual *Cartão*)

Um **Cartão** por medida:

| Cartão | Medida | Valor exibido | Formato |
|---|---|---|---|
| Receita Total | `[Receita Total]` | `$15,84 Mi` | Moeda |
| Pedidos Únicos | `[Pedidos Únicos]` | `99 Mil` | Inteiro |
| Ticket Médio | `[Ticket Médio]` | `$160,58` | Moeda |
| % Crescimento Receita | `[Crescimento Receita %]` | `120%` | Porcentagem |

### 8.3 Receita por dimensão — 3 visuais

Todos usam `[Receita Total]` como valor, variando a dimensão:

| Visual | Tipo | Eixo / Legenda | Valor |
|---|---|---|---|
| Receita Total por `estado_vendedor` | **Rosca** | Legenda = `estado_vendedor` | `[Receita Total]` |
| Receita Total por `categoria_pt` | **Barras horizontais** | Eixo Y = `categoria_pt` | `[Receita Total]` |
| Receita Total por `cidade_vendedor` | **Barras horizontais** | Eixo Y = `cidade_vendedor` | `[Receita Total]` |

> Nas barras, ative **classificação por `Receita Total` (decrescente)** no menu
> "…" do visual — é o que produz o ranking visual (beleza_saude / SAO PAULO no
> topo). A barra de rolagem aparece porque há mais itens do que cabem;
> opcionalmente aplique um **Filtro Top N** para fixar, ex., as 10 maiores.

### 8.4 Série temporal — 1 visual (*Gráfico de linhas*)

| Eixo X | Valor |
|---|---|
| `dCalendario[Date]` (hierarquia Ano/Mês) | `[Receita Total]` |

Usa a `dCalendario` (relacionamento ativo por `data_compra`), por isso o eixo
mostra `jan 2017 → jul 2018`. O pico no fim de 2017 corresponde à Black Friday.

### 8.5 Tabela de detalhe — 1 visual (*Tabela*)

| Colunas |
|---|
| `order_id` · `order_item_id` · `order_status` · ... |

Tabela no grão de item, para auditar linha a linha. `order_id` e `order_item_id`
são as **dimensões degeneradas** da fato; `order_status` permite conferir que os
registros exibidos estão `delivered`...

> **Interatividade:** todos os visuais compartilham o mesmo modelo, então clicar
> num estado na rosca ou numa categoria nas barras **filtra os demais visuais e a
> tabela** automaticamente (cross-filter nativo do Power BI).

---

## Insights do dashboard

- **~R$ 15,84 mi** de receita em **~99 mil pedidos únicos**, com **ticket médio de
  R$ 160,58**.
- **Forte concentração geográfica:** **São Paulo (SP) responde por ~64,6%** da
  receita dos vendedores (~R$ 10,24 mi) — dependência de um único estado.
- **Cidades líderes:** São Paulo, Ibitinga, Curitiba, Rio de Janeiro, Guarulhos.
- **Categorias campeãs:** `beleza_saude`, `relogios_presentes`, `cama_mesa_banho`,
  `esporte_lazer`, `informatica_acessorios`.
- **Crescimento expressivo** de 2017 para 2018, com **pico de Black Friday** no
  fim de 2017 — evento que merece planejamento logístico e de estoque.

---

## Checklist de reprodutibilidade

Qualquer pessoa deve conseguir refazer o relatório do zero seguindo só isto:

- [ ] DW reconstruído (`dw_build/` rodado por completo).
- [ ] `vw_vendas` retorna 112.650 linhas no banco.
- [ ] Power BI conectado via PostgreSQL → **só** `vw_vendas` importada.
- [ ] **Tabela renomeada para `vw_vendas`** (FASE 2 — obrigatório).
- [ ] Tipos conferidos (FASE 3).
- [ ] `dCalendario` criada e marcada como tabela de datas.
- [ ] Relacionamentos de tempo (compra ativo, entrega inativo).
- [ ] Tabela `_Medidas` e os **11 KPIs** criados (≥ 10 exigidos).
- [ ] Validação da FASE 7 bate com o DW.
- [ ] Dashboard montado (4 cartões + rosca + 2 barras + linha + tabela).

---

## Estrutura da pasta

```
bi_build/
├── README.md          # este guia
└── olist_vendas.pbix  # relatório do Power BI (adicione ao concluir)
```

> O `.pbix` é binário e não versiona bem em diff. O que garante a
> reprodutibilidade é este README + os scripts SQL do DW: a partir deles o
> `.pbix` é sempre reconstruível.