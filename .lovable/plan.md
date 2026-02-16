

# Enriquecimento do Relatorio Semanal: Novos Dados, Metricas e Visual

## Resumo

Com base na auditoria completa dos dados disponiveis (274k ilhas no cache, 192k registros de metadata com versoes/ratings/SAC, 83k segmentos de exposicao em 104 paineis, 30+ tags, split UEFN/FNC), existem pelo menos **8 novas secoes/metricas** que podem ser criadas sem nenhuma chamada adicional de API -- usando puramente dados que ja estao no banco mas nao sao aproveitados.

---

## Dados Disponiveis Mas Nao Utilizados

| Fonte | Campo | Volume | Status Atual |
|-------|-------|--------|-------------|
| `discover_link_metadata` | `version` (numero de atualizacoes) | 66.878 ilhas | **Nao usado** |
| `discover_link_metadata` | `ratings` (classificacao etaria) | 66.746 ilhas | **Nao usado** |
| `discover_link_metadata` | `support_code` (SAC creator) | 66.520 ilhas | **Nao usado** |
| `discover_link_metadata` | `max_players` / `min_players` | 66.591 ilhas | **Nao usado** |
| `discover_link_metadata` | `tagline` / `introduction` | 66.639 ilhas | **Nao usado** |
| `discover_islands_cache` | `published_at_epic` / `updated_at_epic` | 67.180 ilhas | **Nao usado no report** |
| `discover_islands_cache` | `suppressed_streak` / `reported_streak` | 274k ilhas | Usado parcialmente |
| `discover_report_islands` | `created_in` (UEFN vs FNC) | 52k por report | **Nao usado** |
| `discover_report_islands` | `tags` (array completo) | 52k por report | Usado so no NLP |
| Exposure | `feature_tags` nos segmentos | 83k segmentos | **Nao usado** |
| Exposure | Panel presence duration vs metrics correlation | 3.515 ilhas expostas | **Nao cruzado** |

---

## Novas Secoes Propostas

### Secao 20: Multi-Panel Presence (Ilhas Multi-Painel)
**Sua ideia**: "Mostrar ilhas que mais entraram em tags/paineis diferentes"

- **Metrica**: Contar em quantos paineis DISTINTOS cada ilha apareceu nos ultimos 7 dias
- **RPC**: Query nos `discovery_exposure_presence_segments` agrupando por `link_code` e contando `DISTINCT panel_name`
- **Ranking**: Top 10 ilhas com maior diversidade de paineis
- **Insight**: Ilhas que o algoritmo da Epic distribui em multiplas categorias = alta versatilidade
- **Visual**: Ranking com barra + badge mostrando os nomes dos paineis

### Secao 21: Panel Loyalty (Residentes de Painel)
**Sua ideia**: "Mostrar ilhas que mais ficaram na mesma tag/painel"

- **Metrica**: Total de minutos expostos em um UNICO painel (max duration em um so painel)
- **RPC**: Query nos segmentos somando duracao por ilha+painel, pegando o maior
- **Ranking**: Top 10 ilhas com maior permanencia em um unico painel
- **Insight**: "Residentes" do painel = ilhas que dominam uma categoria

### Secao 22: Most Updated Islands (Ilhas Mais Atualizadas)
**Sua ideia**: "Top ilhas que mais foram atualizadas/versions diferentes"

- **Dados**: Ja temos `mostUpdatedIslandsThisWeek` no rankings_json (campo existe mas nao e exibido!)
- **Tambem**: Campo `version` no `discover_link_metadata` (13.7k ilhas com v1, 9.1k com v2, etc.)
- **RPC**: Cruzar ilhas do report com metadata para pegar version + updated_at_epic
- **Ranking**: Top 10 ilhas com maior numero de versao (mais iteracoes do criador)
- **KPI**: Media de versoes do ecossistema, % de ilhas com 5+ versoes

### Secao 23: Rookie Creators (Novos Criadores em Destaque)
**Sua ideia**: "Top novos criadores que mostraram destaque"

- **Metrica**: Criadores cuja `first_seen_at` no cache e desta semana, ranqueados por melhor ilha
- **RPC**: Filtrar ilhas do report onde `creator_code` aparece pela primeira vez, agregar por criador
- **Ranking**: Top 10 rookies por plays, CCU, ou retention da melhor ilha
- **KPI**: Total de novos criadores, media de plays de rookies vs veteranos

### Secao 24: Player Capacity Analysis (Analise por Capacidade)
- **Dados**: `max_players` disponivel para 66k ilhas (16 players e o mais comum com 19k ilhas)
- **Metrica**: Performance media por faixa de max_players (Solo, Duo, Squad 4, Party 8-16, Massive 20+)
- **Visual**: Grafico de barras com plays/retention por faixa de capacidade
- **Insight**: "Mapas para 16 jogadores tem 2.3x mais retention que mapas solo"

### Secao 25: UEFN vs Fortnite Creative (Ferramenta de Criacao)
- **Dados**: `created_in` ja coletado (40k UEFN vs 12k FNC no W06)
- **Metricas**: Plays, retention, CCU, stickiness comparados entre as duas ferramentas
- **Visual**: Dois cards lado a lado comparando metricas medias
- **Insight**: "Ilhas UEFN tem 1.5x mais retention D7 que FNC"

---

## Enriquecimentos em Secoes Existentes

### Secao 19 (Exposure) - Efficiency Score
- **Novo**: Cruzar minutos de exposicao no Discovery com plays reais
- **Metrica**: "Exposure Efficiency" = plays / minutos_expostos
- **Insight**: Quais ilhas convertem melhor a visibilidade em jogadores reais

### Secao 2 (Trending) - Tag Velocity
- **Novo**: Alem do NLP nos titulos, analisar quais TAGS oficiais estao crescendo
- **Dados**: 30+ tags com contagem (just for fun: 17.5k, pvp: 13.2k, free for all: 13k)
- **Visual**: Adicionar "Tags em Alta" ao lado do "Trends por Plays"

### Secao 7 (Creators) - SAC Coverage
- **Dados**: `support_code` disponivel para 66.5k ilhas
- **KPI**: % de criadores ativos com codigo SAC (Support-a-Creator)

### Secao 15 (Category & Tags) - Tag Cloud Visual
- **Melhoria visual**: Substituir ranking simples por word cloud interativo ou treemap

---

## Melhorias Visuais

### 1. Island Cards com Imagem
- Temos `image_url` para 66.874 ilhas
- Nos rankings, mostrar thumbnail da ilha ao lado do nome
- Torna o report muito mais visual e profissional

### 2. Sparkline Mini-Charts nos KPIs
- Adicionar mini graficos de linha nos KPI cards mostrando tendencia dos ultimos dias
- Usando dados de probe_date que ja temos

### 3. Gradientes e Glassmorphism nas Secoes
- Headers de secao com gradiente sutil baseado na cor da secao
- Cards com efeito glass para profundidade visual
- Separadores animados entre secoes

### 4. Badges de Destaque
- Ilhas no top 3 de qualquer ranking recebem badges visuais (ouro, prata, bronze)
- Tags coloridas por genero nos rankings

### 5. Comparativo Visual Side-by-Side
- Para secoes como UEFN vs FNC, usar layout de "versus" com barras espelhadas
- Estilo infografico de comparacao

---

## Plano Tecnico de Implementacao

### Fase 1: Novos RPCs SQL (3 novas funcoes)

```text
report_finalize_exposure_analysis(p_report_id, p_days)
  - Multi-panel count per island
  - Panel loyalty (max duration single panel)
  - Exposure efficiency (plays / exposure minutes)

report_finalize_tool_split(p_report_id)
  - UEFN vs FNC metrics comparison
  - Avg plays, retention, CCU by created_in

report_finalize_rookies(p_report_id)
  - New creators this week
  - Best performing rookies with their top island
```

### Fase 2: Atualizar Collector/Rebuild
- Adicionar chamadas dos novos RPCs no `Promise.all` do finalize
- Salvar resultados em `rankings_json` com chaves novas
- Enriquecer dados com `version` e `max_players` do link_metadata

### Fase 3: Atualizar AI Prompt
- Adicionar descricoes das novas secoes (20-25) no prompt
- Incluir dados dos novos RPCs no payload enviado para a IA

### Fase 4: Frontend - Novas Secoes
- Adicionar secoes 20-25 no `ReportView.tsx`
- Implementar componente `IslandCard` com thumbnail
- Implementar componente `ComparisonChart` para UEFN vs FNC
- Adicionar i18n keys para todas as novas secoes

### Fase 5: Melhorias Visuais
- Redesign dos section headers com gradientes
- Thumbnails nos rankings (RankingTable com prop `showImage`)
- Badges visuais (ouro/prata/bronze)
- Glassmorphism nos cards

### Fase 6: Exibir Dados Ja Existentes Mas Nao Mostrados
- `mostUpdatedIslandsThisWeek` ja existe no rankings_json mas nao tem UI
- Adicionar imediatamente ao report

---

## Prioridade de Impacto

| Prioridade | Item | Esforco |
|-----------|------|---------|
| P0 | Mostrar `mostUpdatedIslandsThisWeek` (ja existe, so falta UI) | Baixo |
| P0 | Island thumbnails nos rankings (image_url ja existe) | Medio |
| P1 | Rookie Creators (secao 23) | Medio |
| P1 | UEFN vs FNC (secao 25) | Medio |
| P1 | Multi-Panel Presence (secao 20) | Medio |
| P2 | Panel Loyalty (secao 21) | Medio |
| P2 | Player Capacity Analysis (secao 24) | Medio |
| P2 | Exposure Efficiency cross-reference | Alto |
| P3 | Melhorias visuais (gradientes, glass, badges) | Medio |
| P3 | Tag Cloud / Treemap visual | Medio |

