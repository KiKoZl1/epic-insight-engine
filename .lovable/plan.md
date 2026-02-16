

# Reforma Completa do Relatorio Semanal

## Problemas Identificados

### 1. Trending Topics usa keywords hardcoded
O array `TREND_KEYWORDS` (linha 81-91 do collector) contem ~50 termos fixos. Nao faz NLP real nos titulos. "Brainrot" nao esta na lista, por isso nao aparece nos trends mesmo sendo dominante.

### 2. Valores sem unidade/contexto
- Tags mostram "333" sem explicar que sao contagem de ilhas com aquela tag
- Ratios mostram "5.37" ou "91.72" sem label explicativo (plays/player, favs/100 players)
- Metricas derivadas nao tem legenda da formula

### 3. Rankings sem filtros de qualidade
- Top Avg Minutes/Player inclui ilhas com 5 jogadores (outliers estatisticos)
- Top Favs Per 100 inclui ilhas com pouquissimos dados
- Nao tem filtro minimo como o relatorio de referencia usa (>=1,000 plays, >=500 uniques, etc.)

### 4. Secoes faltando dados criticos
- Low Performance (secao 8): so mostra contagem, sem top 10 piores, sem tags/generos
- Trending Topics (secao 2): nao detecta temas emergentes reais
- Most Updated: sem contagem de atualizacoes
- Nenhuma secao de Stickiness (plays x minutes x retention)
- Nenhuma separacao UGC vs Epic (global)
- Sem distribuicao de retencao (histograma D1/D7)
- Sem "creators que aparecem em multiplas listas"
- Sem Peak CCU (avg vs max) como blocos separados
- Sem Weekly Growth (breakouts multi-metrica)

### 5. A.I narra coisas que nao estao no relatorio
A narrativa fala de "brainrot" mas os dados visuais nao refletem isso porque trending topics e hardcoded.

---

## Plano de Implementacao

### Fase 1: Corrigir a Engine de Dados (discover-collector finalize)

**1.1 Trending Topics dinamico**
- Remover `TREND_KEYWORDS` hardcoded
- Implementar NLP real: tokenizar titulos, fazer n-gram analysis (1-gram e 2-gram), filtrar stopwords, ranquear por frequencia ponderada por plays
- Output: top 20 termos mais presentes com contagem de ilhas, total plays, total players

**1.2 Filtros de qualidade nos rankings**
- `topAvgMinutesPerPlayer`: filtrar >= 1,000 plays E >= 500 unique players
- `topRetentionD1/D7`: filtrar >= 50 unique players E >= 3 dias de dados
- `topPlaysPerPlayer`: filtrar >= 1,000 plays
- `topFavsPer100`: filtrar >= 100 uniques E >= 10 favorites
- `topRecPer100`: filtrar >= 100 uniques E >= 25 recommendations
- `topFavsPerPlay/topRecsPerPlay`: filtrar >= 1,000 plays
- `topRetentionAdjD1/D7`: filtrar >= 1,000 plays E >= 500 uniques

**1.3 Novos rankings**
- `topPeakCCU_global` (inclui Epic) vs `topPeakCCU_UGC` (ja existe)
- `topAvgPeakCCU_global` e `topAvgPeakCCU_UGC` (media CCU vs pico)
- `topD1Stickiness`: plays x avgMinutes x D1 (global + UGC)
- `topD7Stickiness`: plays x avgMinutes x D7 (global + UGC)
- `topWeeklyGrowth`: ilhas com maior crescimento % multi-metrica (breakouts)
- `topMinutesPerFavorite`: minutos gastos antes de favoritar (minutes/favorites)
- `topCreatorsByFavorites`, `topCreatorsByRecommendations`
- `retentionDistribution`: histograma de D1 e D7 por faixas (0-5%, 5-10%, ... 90-100%)
- `lowPerfTopWorst`: top 10 piores ilhas com tags/categoria
- `lowPerfHistogram`: distribuicao (<50, <100, <500 uniques)
- `activeVsInactive`: contagem de mapas ativos vs inativos com delta WoW
- `creatorsWithActiveVsTotal`: criadores com mapas ativos vs total

**1.4 Enriquecer items dos rankings existentes**
Cada item de ranking passara a incluir:
- `label`: texto formatado com unidade (ex: "520.97 min/player", "71.26%", "+28.25K%")
- `subtitle`: contexto adicional (ex: tag, creator, category)

### Fase 2: Atualizar o Frontend (ReportView.tsx)

**2.1 Corrigir formatacao de valores**
- RankingTable: usar `label` do item quando disponivel (ja suportado)
- Adicionar tooltips explicando cada metrica
- Seção de Tags: mostrar "333 ilhas" em vez de "333"

**2.2 Reestruturar secoes**

O relatorio passara de 14 para ~20 secoes mais completas:

1. **Core Activity** (existente, expandido com active vs inactive, avg maps/creator)
2. **Trending Topics** (corrigido com NLP dinamico)
3. **Player Engagement Volume** (plays, CCU, duracao)
4. **Peak CCU** (nova: global top 10, UGC top 10, avg peak CCU global, avg peak UGC)
5. **New Islands of the Week** (existente)
6. **Retention & Loyalty** (expandido com histograma D1/D7, thresholds >50%)
7. **Creator Performance** (expandido com plays, uniques, minutes, CCU sum, D1, D7)
8. **Map Quality** (com filtros minimos, minutes/favorite, favorites count, recommends count)
9. **Low Performance** (expandido com top 10 piores, histograma, tags)
10. **Plays per Player** (replay frequency, com filtro minimo)
11. **Advocacy Metrics** (favs/100 players, recs/100 players, com filtros)
12. **Efficiency/Conversion** (favs/play, recs/play, minutes/favorite)
13. **Stickiness** (D1 + D7 stickiness global e UGC)
14. **Retention-Adjusted Engagement** (existente, com filtros)
15. **Category & Tags** (existente)
16. **Weekly Growth / Breakouts** (multi-metrica, com % change)
17. **Risers & Decliners** (existente)
18. **Island Lifecycle** (existente)
19. **Discovery Exposure** (existente)

**2.3 Melhorar componentes visuais**
- `RankingTable`: exibir label com unidade, mostrar creator e categoria como subtitulo
- Novo componente `DistributionHistogram` para retencao e low performance
- Novo componente `MetricExplainer`: tooltip/popover que explica a formula da metrica
- Cards de KPI: sempre incluir sufixo/unidade

### Fase 3: Atualizar o Prompt da IA

**3.1 Expandir dados enviados para a IA**
- Incluir todos os novos rankings no prompt
- Incluir distribuicoes de retencao
- Incluir stickiness scores
- Incluir active vs inactive delta

**3.2 Atualizar instrucoes**
- Aumentar de 14 para ~20 secoes
- Instruir a IA a sempre referenciar dados que estao visiveis no relatorio
- Pedir explicacao de formulas e benchmarks quando relevante

---

## Detalhes Tecnicos

### Arquivos que serao modificados:

1. `supabase/functions/discover-collector/index.ts` - Finalize function: novos rankings, NLP trending, filtros de qualidade
2. `supabase/functions/discover-report-ai/index.ts` - Prompt expandido com novos dados e secoes
3. `src/pages/public/ReportView.tsx` - Novas secoes, componentes, formatacao
4. `src/components/discover/RankingTable.tsx` - Suporte a subtitle, melhor formatacao
5. `src/components/discover/DistributionChart.tsx` - Novo componente para histogramas
6. `src/i18n/locales/en.json` e `pt-BR.json` - Novas chaves de traducao

### Migracao de dados
- O relatorio w06 ja existente precisara ser reconstruido (rebuild) apos as mudancas para incluir os novos rankings
- Nenhuma migracao SQL necessaria (os dados ja estao em `discover_report_islands`, so precisam ser calculados de forma diferente)

### Impacto no tamanho do rankings_json
O rankings_json crescera de ~45 chaves para ~60 chaves. O volume de dados por ranking nao muda (top 10-20 items cada). Impacto estimado: +20KB por relatorio, aceitavel.

