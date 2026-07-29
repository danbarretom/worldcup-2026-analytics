# Projeto: Análise de Dados — Copa do Mundo 2026

**Documento de escopo e planejamento — preparado para handoff ao Claude Code**

---

## 1. Objetivo do projeto

Portfólio de dados voltado a duas trilhas de contratação: **analista/cientista/engenheiro de dados** (foco principal) e, secundariamente, reforço da trilha **full-stack backend** via pipeline + banco relacional.

Este NÃO é um dashboard genérico de estatística de Copa. É uma **investigação orientada por narrativa**: cada módulo parte de uma observação de quem realmente assistiu ao torneio e testa se o dado confirma, refina ou contradiz essa leitura. Isso é o diferencial competitivo do projeto — é fácil achar portfólio com "top 10 artilheiros"; é raro achar um que testa uma tese futebolística com rigor.

**Critério de priorização acordado:** o objetivo é aumentar as chances de contratação. Empolgação pessoal com o tema é bem-vinda e é o que sustenta o projeto até o fim, mas toda decisão de escopo abaixo foi filtrada por "isso fortalece candidatura?" antes de "isso é interessante?".

---

## 2. Narrativa central

> **"Controle não é sempre resultado — a Copa de 2026 contada pelos dois caminhos até a final."**

Espanha: filosofia de jogo única desde a base, domínio consistente, dificuldade inicial de converter domínio em gol, e a melhor campanha defensiva da história das Copas. Argentina: campanha mais irregular, eficiência com menos posse, decisões no detalhe (experiência, Dibu Martínez, brilho de Messi). A final resume os dois arcos: domínio esmagador (20 finalizações a 0 em determinado trecho) resolvido por 1x0 na prorrogação, com a Argentina ainda criando uma chance clara de empate depois do gol.

---

## 3. Módulos analíticos

Cada módulo tem: pergunta testável, hipótese (a leitura "de olho treinado" do Daniel), dado necessário, status de viabilidade, e prioridade.

### Prioridade 1 — Núcleo do MVP (dado 100% confirmado, alto impacto visual)

**Módulo A — A melhor defesa da história das Copas**

- Pergunta: a Espanha 2026 é estatisticamente a campanha defensiva mais eficiente entre todos os campeões desde que há registro?
- Hipótese: sim, e por número redondo (gols sofridos por jogo), não só percepção.
- Dado: gols sofridos por campeão, todas as Copas — dataset Kaggle (2002–2026) + Wikipedia para anos anteriores.
- Por que é prioridade 1: gráfico único, história forte, zero dependência de dado incerto. Melhor candidato a "hero visual" do projeto.

**Módulo B — Os dois caminhos até a final**

- Pergunta: como as campanhas de Espanha e Argentina se comparam estatisticamente — posse, xG, saldo de gols, jogos revertidos no placar?
- Hipótese: Espanha domina em posse/xG/controle; Argentina vence com menos posse e mais eficiência + capacidade de reverter jogos.
- Dado: confirmado (dataset relacional Kaggle).
- Por que é prioridade 1: comparação direta, visualmente forte (radar chart ou side-by-side), sustenta o resto da narrativa.

**Módulo C — A final: domínio sem prêmio proporcional**

- Pergunta: o volume de finalizações/xG da Espanha na final é coerente com um jogo normalmente decidido por 3+ gols de diferença — e por que terminou 1x0 na prorrogação?
- Hipótese: um modelo simples de "gols esperados pelo volume de chances" mostra a final como estatisticamente atípica.
- Dado: eventos minuto a minuto do dataset Kaggle (confirmar granularidade exata na Fase 1).
- Por que é prioridade 1: é o clímax emocional do projeto, ótimo pra abrir o README.

### Prioridade 2 — Capítulos de apoio (dado confirmado, complexidade menor)

**Módulo D — Domínio sem conversão (largada lenta da Espanha)**

- Pergunta: existe uma curva de melhora de conversão (finalizações→gol) entre fase de grupos e mata-mata?
- Caso-âncora: 0x0 contra Cabo Verde na estreia.
- Dado: confirmado.

**Módulo E — O "gelo" da Inglaterra**

- Pergunta: a agressividade ofensiva da Inglaterra cai mensuravelmente depois de abrir o placar na semifinal contra a Argentina?
- Dado: confirmado, é um caso pontual (1 jogo), rápido de construir. foi amplamente divulgado que a posse de bola da inglaterra entre o gol deles e a virada da argentina foi de apenas 12%.

**Módulo F — A disputa de 3º lugar fora da curva**

- Pergunta: 6x4 é estatisticamente uma anomalia pro padrão histórico de jogos de terceiro lugar?
- Dado: confirmado. Módulo curto, bom "encerramento" da história.

### Prioridade 3 — Stretch goal (depende de validação de fonte)

**Módulo G — Por que a defesa da Espanha funciona (pressão pós-perda de posse)**

- Pergunta: dá pra provar quantitativamente que o "pressing imediato" é o mecanismo por trás do número histórico do Módulo A?
- Dado necessário: métrica tipo PPDA — exige dado de evento com coordenada (Squawka) que ainda não confirmamos disponível pra 2026.
- Decisão: **não entra no MVP**. Se a Squawka se confirmar viável na Fase 1, vira o "capítulo bônus" que eleva o projeto de bom pra excepcional. Se não, o projeto se sustenta perfeitamente sem ele — é reforço, não dependência.

### Menções honrosas (parágrafos curtos no README, não módulos com código dedicado)

Portugal/CR7 em declínio, sucesso do formato de 48 seleções (Cabo Verde, Colômbia, força de casa de México/EUA), Brasil (tratado como nota breve — você mesmo já indicou que esse assunto está maduro pra você, sem pergunta nova a explorar).

---

## 4. Stack técnico

Python e R como dois pilares igualmente centrais — Python cuida de engenharia de dados, R cuida de análise
estatística, e Power BI é a camada de apresentação, os dois lendo do mesmo Postgres:

- **Engenharia de dados:** Python (pandas, SQL via `psycopg2`/SQLAlchemy) — scraping, ETL, schema e carga no
  Postgres.
- **Banco:** PostgreSQL — schema relacional próprio, populado a partir do dataset Kaggle + validação cruzada com football-data.org. Fonte única compartilhada — Python e R leem dele de forma independente, nunca um chamando o outro.
- **Análise estatística:** R (`DBI`/`RPostgres`, `dplyr`, `ggplot2`, `stats` base pra PCA/Mahalanobis/testes de hipótese) — a camada de rigor estatístico de cada módulo, incluindo os gráficos (`ggplot2`).
- **Histórico 2022:** `statsbombpy` (StatsBomb Open Data) só para o recorte comparativo do Módulo C/G (Python, ETL)
- **Apresentação:** Power BI, conectado direto ao Postgres, com visuais de script R embutidos (os gráficos `ggplot2`) ao lado dos visuais nativos. Publicado via "Publish to Web" pra link público gratuito.
- **Stretch:** scraper próprio para Squawka (avaliação de viabilidade na Fase 1, antes de qualquer commit de código pra isso)

\*a sessão de claude code tem liberdade para opinar e modificar esse stack caso entenda que é interessante, sempre focando na ideia de portifolio.

---

## 5. Fontes de dados — checklist de validação (fazer no início da Fase 1)

| Fonte                                     | Papel                                | Status                                                              |
| ----------------------------------------- | ------------------------------------ | ------------------------------------------------------------------- |
| Dataset Kaggle `mominullptr` (relacional) | Base principal                       | A validar estrutura real das tabelas/granularidade de evento        |
| football-data.org                         | Validação cruzada + históricos       | A confirmar cobertura de Copas anteriores no tier grátis            |
| FIFA Match Report Hub                     | Contexto qualitativo pontual         | Confirmado disponível, formato a checar                             |
| StatsBomb Open Data (2022)                | Comparação histórica evento-a-evento | Confirmado disponível via `statsbombpy`                             |
| Squawka                                   | Stretch goal (Módulo G)              | Não validado — checar se formato XML/Opta ainda está ativo pra 2026 |

\*se o claude code souber outra possiveis fontes que sejam mais interessantes com o escopo do trabalho, pode ser incluído.

---

## 6. Fases de execução

**Fase 1 — Fundação (MVP)**

- Validar as fontes da tabela acima
- Modelar e popular o schema PostgreSQL
- Construir Módulos A, B, C (ETL em Python + camada estatística em R, cada um)
- Primeiro relatório Power BI publicado com esses três módulos

**Fase 2 — Corpo da narrativa**

- Módulos D, E, F
- Integração do recorte histórico via StatsBomb 2022
- Refino visual do dashboard

**Fase 3 — Polimento e stretch**

- Avaliação final de viabilidade da Squawka → Módulo G se der certo
- README no mesmo padrão de qualidade do SalesSystem (badges, screenshot/GIF, seção "por que este projeto", link ao vivo)
- Publicação final do Power BI

---

## 7. Notas para a sessão do Claude Code

- Este documento é a fonte de verdade do escopo — a sessão de código deve tratá-lo como equivalente ao `CLAUDE.md` que já existe no SalesSystem: contexto de decisão, não só lista de tarefas. Isso não significa que um claude.md desse projeto não possa ser criado, inclusive deve. Só que esse vai ser o arquivo inicial.
- Prioridade de implementação = ordem das seções 3.1 → 3.2 → 3.3 (Prioridade 1 → 2 → 3), não ordem alfabética dos módulos.
- Qualquer decisão técnica nova tomada durante a implementação (ex: schema final das tabelas, decisão sobre incluir ou não a Squawka) deve ser registrada num changelog, seguindo o mesmo padrão de `CHANGELOG.md` do SalesSystem — isso já provou ser um diferencial forte de portfólio.
- README final do repositório deve ser em **inglês**, seguindo o padrão dos outros projetos no GitHub (`danbarretom`) — este documento de escopo em português é material de planejamento interno, não a documentação pública do projeto.
- Nome de repositório ainda em aberto — sugestão a decidir na Fase 1, depois que o schema e o primeiro módulo estiverem rodando (mais fácil nomear com o projeto já tangível).
- Acessar a pasta C:\Users\danie\Desktop\ADS\ADS 2 S\POO\IdeaProjects\Prova 2\TrabalhoAV3Refatorado ler as documentações e memórias de lá para entender qual o fluxo de trabalho que uso em projetos de portifolio, em especial fluxo de github. Já planejar CI-CD adequado para esse projeto, para podermos trabalhar no mesmo formato que trabalhamos no SalesSystem.

---

## 8. Perguntas em aberto para o início da Fase 1

1. O dataset Kaggle tem granularidade de evento suficiente pro Módulo C, ou só estatística agregada por partida?
2. football-data.org free tier cobre histórico de Copas suficiente pro Módulo A, ou precisa complementar com Wikipedia?
3. O formato Squawka/Opta ainda está ativo e acessível pra Copa 2026?
