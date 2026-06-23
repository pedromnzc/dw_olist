CREATE SCHEMA repositorio;      -- camada bruta (staging): dados como texto
CREATE SCHEMA dw;               -- Data Warehouse: modelo estrela tipado
CREATE SCHEMA datamart_vendas;  -- Data Mart: views prontas para o BI

-- Mensagem de conferencia
SELECT 'Schemas criados: repositorio, dw, datamart_vendas' AS status;
