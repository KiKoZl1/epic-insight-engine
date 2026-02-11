

# 🎮 Fortnite Island Analytics Platform + AI Game Design Analyst

Plataforma SaaS que transforma exports do painel da Epic em relatórios analíticos completos com diagnóstico de game design, plano de ação priorizado, e um **analista de IA especializado** que conversa com o usuário sobre seus dados.

---

## 🏗️ Fase 1 — Fundação (Auth + DB + Estrutura)

### Autenticação via Supabase
- Login/signup com email e senha
- Perfis de usuário com nome e avatar
- Proteção de rotas — apenas logados acessam `/app`

### Banco de Dados (Supabase Postgres)
- Tabelas: `profiles`, `projects`, `uploads`, `reports`, `chat_messages`
- RLS para isolamento por usuário
- Storage bucket para ZIPs originais e PDFs

### Estrutura de Páginas
- **/** — Landing page com CTA
- **/auth** — Login/Signup
- **/app** — Lista de projetos
- **/app/projects/:id** — Projeto + histórico de uploads
- **/app/projects/:id/reports/:reportId** — Dashboard do relatório

---

## 🏗️ Fase 2 — Upload & Motor de Processamento (Client-Side)

### Upload
- Drag & drop do .zip com progresso
- Extração no browser via JSZip
- Parsing dos CSVs via PapaParse

### Dataset Registry (mapeado do export real da Epic)

**Aquisição (7 CSVs)**
- CTR diário, impressões totais, por fontes, por países
- Cliques totais, por fontes, por países, por plataformas

**Engajamento (8+ CSVs)**
- Tempo de jogo ativo (total, por país, por plataforma)
- Pessoas ativas (total, por país, por plataforma)
- Tempo de fila com percentis (p5/p25/média/p75/p95)
- Eventos custom com hash IDs
- Novos vs retornando ao Fortnite

**Retenção (1 CSV)**
- D1 e D7 com % em pt-BR

**Surveys (9 CSVs)**
- Avaliação 1-10 (resumo, trend, detalhado, benchmark)
- Diversão sim/não (resumo, trend, benchmark)
- Dificuldade 1-5 (resumo, trend, benchmark)

**Versões (1 CSV)**
- Releases com timestamps e notas

### Normalização Automática
- `Data`/`Date` → `YYYY-MM-DD`
- Números pt-BR: `191.916` → `191916`, `7,8` → `7.8`
- Percentuais: `14,44%` → `0.1444`
- Colunas localizadas: `Diagnósticos` → `impressions`, etc.
- Eventos: extrair nome limpo do hash
- Log completo + warnings para CSVs ausentes

---

## 🏗️ Fase 3 — Métricas Derivadas & Motor de Diagnóstico

### Métricas Calculadas
- **Funil**: CTR por fonte/país/plataforma
- **Rankings**: Top fontes/países/plataformas
- **Engajamento**: tempo médio por jogo, percentis de sessão
- **Eventos**: conversão entre eventos
- **Retenção**: tendência D1/D7, detecção de queda
- **Trends**: pico do período, queda mês a mês, anomalias

### Motor de Heurísticas (regras base)
- CTR quente vs frio → A/B thumbnail
- Sessão longa + D7 baixo → daily quest, streak
- Dificuldade polarizada → onboarding guiado
- Fila P95 alta → otimizar matchmaking
- D1 em queda → melhorar first-time experience
- Output: lista P0/P1/P2 com evidências

---

## 🏗️ Fase 4 — Dashboard de Relatório (7 Tabs)

### Executive Summary
- KPIs grandes: impressões, cliques, CTR, jogos, tempo/jogo, D1/D7, fila
- Nota executiva por área (Aquisição 7/10, etc.)
- Insights automáticos em bullets
- Action Plan resumido

### Acquisition Tab
- Timeseries impressões e cliques
- CTR ao longo do tempo
- Rankings por fonte, país, plataforma

### Engagement Tab
- Jogos e tempo ativo no tempo
- Breakdown por país e plataforma
- Fila com percentis
- Eventos custom com conversão

### Retention Tab
- D1/D7 ao longo do tempo com alertas
- Novos vs recorrentes
- Ativos vs retidos

### Surveys Tab
- Nota 1-10 com distribuição, trend e benchmark
- Diversão com trend e benchmark
- Dificuldade com polarização e benchmark

### Changelog Impact Tab
- Timeline de versões
- Métricas antes vs depois de cada update

### Action Plan Tab
- "O que está forte" / "O que está fraco" / "O que fazer agora"
- Lista priorizada com evidências e impacto

---

## 🏗️ Fase 5 — 🤖 AI Game Design Analyst (Lovable AI)

### Analista de IA Especializado
Uma IA que recebe **todos os dados parseados do relatório** como contexto e atua como um **analista de game design + dados especializado em ilhas Fortnite**.

### Diagnóstico Gerado por IA
- Ao gerar o relatório, a IA analisa todos os dados e escreve:
  - **Executive Summary narrativo** em linguagem natural (como o exemplo que você mostrou)
  - **Diagnóstico estratégico** contextualizado (não só regras fixas)
  - **Plano de ação detalhado** com prioridades e justificativas baseadas nos dados reais
  - **Notas executivas** com tom de consultor de game design

### Chat Interativo com a IA
- Dentro de cada relatório, um **chat ao vivo** onde o usuário pode perguntar:
  - "Por que meu D7 está caindo?"
  - "O que posso fazer para melhorar CTR no PC?"
  - "Como melhorar meu onboarding?"
  - "Quais métricas devo priorizar agora?"
  - "Compare minha retenção com benchmarks"
- A IA responde com base nos **dados reais do relatório**, não genéricos
- Respostas em markdown com formatação rica
- Histórico de chat salvo por relatório

### Implementação Técnica
- **Lovable AI Gateway** via Supabase Edge Function (backend seguro)
- System prompt especializado com conhecimento de:
  - Métricas de jogos Fortnite Creative
  - Benchmarks típicos do ecossistema
  - Estratégias de game design (meta loops, retention hooks, UX patterns)
  - Análise de funil e diagnóstico de gargalos
- Dados do relatório injetados como contexto a cada chamada
- Streaming de respostas token por token para UX fluida

---

## 🏗️ Fase 6 — Comparações & Export

### Comparação entre Uploads
- Selecionar dois uploads do mesmo projeto
- Dashboard comparativo lado a lado
- Indicadores de melhoria/piora com %
- Verde = melhorou, Vermelho = piorou
- IA pode comentar as diferenças automaticamente

### Export PDF
- Geração client-side do relatório completo (incluindo diagnóstico da IA)
- Download direto do dashboard

### Share Link
- Link público para visualizar relatório sem login
- Toggle de visibilidade

---

## 🏗️ Fase 7 — Polish & Qualidade

### Data Quality
- Seção mostrando CSVs encontrados, datasets identificados, warnings
- Botão "Rebuild Report"
- Log detalhado por upload

### UX
- Design responsivo e dark mode
- Loading states e animações
- Empty states informativos
- Toasts de feedback

---

## 📊 Stack
- **Frontend**: React + TypeScript + Tailwind + Recharts
- **Processamento**: Client-side (JSZip + PapaParse)
- **Backend**: Supabase (Auth, Database, Storage, Edge Functions)
- **IA**: Lovable AI Gateway (Gemini) via Edge Function com streaming
- **PDF**: Geração client-side
- **Charts**: Recharts

