USE projest;

/* A tabela uso_rh contém dados de horário de início e fim das tarefas. Como o dado relevante é o tempo efetivamente gasto,
foi criada uma VIEW que será utilizada várias vezes e que retorna a diferença entre o tempo de início de e fim da tarefa para
ser utilizado nas demais consultas */

CREATE OR REPLACE VIEW horas_rh AS
SELECT 	id_uso_rh,
		id_pessoa,
		id_tarefa,
        id_projeto,
        DATE(hora_inicio) AS data_rh,
        ROUND(TIME_TO_SEC(TIMEDIFF(hora_fim, hora_inicio))/3600,2) AS tempo_rh
	FROM uso_rh;

/* O histórico de uso de recursos pode ser útil na estimativa de consumo em projetos futuros.
A consulta abaixo retorna a quantidade de horas consumida em cada projeto e em cada tipo de cargo*/

SELECT
	c.nome AS cargo,
    h.id_projeto AS projeto,
    SUM(h.tempo_rh) AS horas_trabalhadas
FROM horas_rh AS h								-- utilização da VIEW criada anteriormente
	INNER JOIN pessoas AS p						-- relacionamento com a tabela 'pessoas' para buscar o cargo
    ON h.id_pessoa = p.id_pessoa
    
	INNER JOIN cargos AS c						-- relacionamento com tabela 'cargos' onde
												-- é possível buscar o cargo de quem realizou a tarefa
	ON p.id_cargo = c.id_cargo
    
GROUP BY projeto, cargo
ORDER BY projeto;


/* Os colaboradores dos projetos são remunerados por hora.
Mensalmente é necessário levantar a quantidade de horas trabalhadas por cada um deles para
encaminhar os processo de pagamento.
Esta consulta retorna a quantidade de horas trabalhadas e o valor total devido por colaborador no mês de março/2023 */

SELECT 
	h.id_pessoa,
    CONCAT (p.nome, " ", p.sobrenome) AS pessoa,
    c.nome AS cargo,
    SUM(tempo_rh) AS horas_trabalhadas,
    c.valor_hora AS valor_hora,
    ROUND(SUM(tempo_rh) * c.valor_hora,2) AS valor_total_periodo
    
FROM horas_rh AS h							-- utilização da VIEW criada anteriormente
INNER JOIN pessoas AS p
ON p.id_pessoa = h.id_pessoa

INNER JOIN cargos AS c
ON c.id_cargo = p.id_cargo

WHERE data_rh BETWEEN '2023-03-01' AND '2023-03-31'
GROUP BY id_pessoa
ORDER BY 6 DESC;

/* É importante ter um panorama sobre a quantidade de projetos que cada gerente
está responsável para melhor distribuir o trabalho.
Esta consulta retorna uma listagem de gerentes de projeto e quantos projetos estão gerenciando */

SELECT DISTINCT gerente, qt_projetos
FROM
(
SELECT
	/*pr.nome AS projeto,*/
    CONCAT (p.nome, " ", p.sobrenome) AS gerente,
    COUNT(*) OVER (PARTITION BY pr.id_gerente) AS qt_projetos	-- função de janela para subtotalizar os projetos de cada gerente

FROM projetos AS pr

INNER JOIN pessoas AS p
ON p.id_pessoa = pr.id_gerente
) AS sub;

/* Os projetos devem ser acompanhados periodicamente para um bom controle do andamento, consumo de recursos
e se estão dentro do orçamento previsto. Estas informações permitem tomar ações preventivas para mitigar eventuais
prejuízos e potencializar ganhos
A consulta retornará uma listagem de projetos, seus valores originalmente orçados, o perecentual de sua execução (andamento),
os custos com Recursos Físicos e Recursos Humanos e verifica se estão dentro do previsto no orçamento até o momento */

WITH totais_rh AS			-- definição de uma CTE que totaliza os valores totais segmentados por projeto e cargo
(
SELECT *, ROUND(sub1.horas_cargo * sub1.valor_hora,2) AS valor_total
FROM(
	SELECT
		h.id_projeto AS projeto,
		c.nome AS cargo,
		SUM(h.tempo_rh) OVER (PARTITION BY h.id_projeto, c.id_cargo) AS horas_cargo,
		c.valor_hora
	FROM horas_rh AS h
		INNER JOIN pessoas AS p
		ON h.id_pessoa = p.id_pessoa
		
		INNER JOIN cargos AS c
		ON p.id_cargo = c.id_cargo) AS sub1
GROUP BY sub1.projeto, sub1.cargo
),

totais_rf AS		-- outra CTE que resume os valores totais por classe de recurso físico e por projeto
(    
SELECT *, ROUND(sub2.quantidade * sub2.custo_unitario,2) AS custo_total
FROM (
	SELECT
		u.id_projeto AS projeto,
		r.nome as recurso,
		SUM(u.quantidade) OVER (PARTITION BY u.id_projeto, u.id_rf) AS quantidade,
		r.unidade AS un,
		r.custo_unitario AS custo_unitario
	FROM uso_rf as u

	INNER JOIN recursos_fisicos AS r
	ON r.id_rf = u.id_rf) AS sub2
GROUP BY sub2.projeto, sub2.recurso
)

SELECT									-- a consulta principal irá resumir os dados dos projetos
	p.id_projeto AS id_projeto,
    p.nome AS projeto,
    p.valor_orcado AS valor_orcado,
    p.andamento AS andamento,
    custos_gerais.valores_rf AS custos_rf,
    custos_gerais.valores_rh AS custos_rh,
    custos_gerais.valores_rf + custos_gerais.valores_rh AS custos_totais,
    CASE			-- cláusula CASE vai comparar o percentual do valor gasto em relação ao orçamento e compará-lo
					-- ao andamento do projeto também em termos percentuais
		WHEN (custos_gerais.valores_rf + custos_gerais.valores_rh)/p.valor_orcado > p.andamento THEN "ORÇAMENTO ESTOURADO"
        ELSE "DENTRO DO ORÇAMENTO" END AS situacao_projeto
FROM projetos AS p

INNER JOIN 				-- relacionamento da consulta principal com outras duas consultas também relacionadas.
						-- que totalizam os valores de Recursos Humanos e Recursos Físicos em uma só tabela
						-- e as une para agreagar à consulta principal
(
SELECT
	f.projeto AS projeto,
	SUM(f.custo_total) AS valores_rf,
    h.valores_rh
FROM totais_rf AS f
	LEFT JOIN
		(
		SELECT
			h.projeto AS projeto,
			SUM(h.valor_total) AS valores_rh
		FROM totais_rh AS h
		GROUP BY 1
		) AS h
	ON h.projeto = f.projeto
GROUP BY 1)
	AS custos_gerais
ON custos_gerais.projeto = p.id_projeto
ORDER BY 1;

/* Para analisar os processo de trabalho das equipes é relevante entender quais tarefas
demandam mais esforço por parte das pessoas.
Esta consulta retorna a listagem de tarefas e o tempo consumido pelos membros da equipe nas mesmas */

SELECT
    t.nome,
    SUM(tempo_rh) AS tempo_consumido
FROM horas_rh as h
INNER JOIN tarefas AS t
ON t.id_tarefa = h.id_tarefa
GROUP BY h.id_tarefa
ORDER BY 2 DESC;