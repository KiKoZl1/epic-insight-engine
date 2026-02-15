
# Command Center: Painel Admin Completo com Monitoramento em Tempo Real

## Objetivo

Substituir o `AdminOverview` atual (focado apenas no pipeline semanal de reports) por um **Command Center** completo que mostra todo o estado do sistema em tempo real, com auto-refresh automatico -- sem precisar dar F5.

## Estrutura do Painel (6 Secoes)

O novo dashboard sera organizado em 6 secoes verticais:

### Secao 1: System Health Bar (topo fixo)

Barra horizontal com indicadores semaforo (bolinha verde/amarela/vermelha) para cada subsistema:

```text
[Database: 822MB verde] [Exposure: Running verde] [Metadata: 99.1% verde] [Reports: idle cinza] [Crons: 7/7 verde]
```

- Cada indicador avalia automaticamente:
  - **Database**: conexao OK = verde
  - **Exposure**: pipeline status (running/paused/stopped) com uptime
  - **Metadata**: % preenchido (verde >90%, amarelo >50%, vermelho <50%)
  - **Reports**: fase do ultimo report (idle/running/done)
  - **Crons**: todos ativos = verde, algum inativo = vermelho
- Timestamp "Ultima atualizacao: HH:MM:SS" no canto superior direito

### Secao 2: Database Census

Grid de 8 cards com todos os numeros criticos do banco:

```text
+------------------+------------------+------------------+------------------+
| Total Ilhas      | Reported         | Suprimidas       | Outro Status     |
| 274,063          | 52,641 (19.2%)   | 221,339 (80.8%)  | 83               |
+------------------+------------------+------------------+------------------+
| Com Titulo Cache | Criadores Unicos | Reports Engine   | Weekly Reports   |
| 206 (0.1%)       | 185              | 2                | 1 (0 publicados) |
+------------------+------------------+------------------+------------------+
```

- Cada card com icone, label, valor grande e variacao percentual onde aplicavel
- Cores condicionais (vermelho para "Com Titulo Cache" que esta em 0.1%)

### Secao 3: Metadata Pipeline Monitor (secao mais detalhada)

Card dedicado ao `discover_link_metadata` com 3 subsecoes:

**3a. Barra de Progresso Principal**
```text
Metadata Preenchido: 1,742 / 1,758 (99.1%)
[==================================================] 99.1%
ETA: Concluido | Throughput: calculando...
```

- Barra de progresso grande e visivel
- ETA dinamico calculado pela diferenca entre polls (10s)
- Throughput em ilhas/min (media movel dos ultimos 3 polls)

**3b. Grid de Status Detalhado (7 cards)**
```text
+------------------+------------------+------------------+------------------+
| Total Enfileirado| Com Titulo       | Pendentes s/dados| Com Erro         |
| 1,758            | 1,742 (verde)    | 14 (amarelo)     | 2 (vermelho)     |
+------------------+------------------+------------------+------------------+
| Due Agora        | Locked (proc.)   | Throughput       |
| 0                | 0                | X ilhas/min      |
+------------------+------------------+------------------+------------------+
```

**3c. Analise de Cobertura (Gap Analysis)**
```text
Ilhas no Cache:     274,063
Metadata Enfileirado: 1,758  (0.6% do cache)
Ilhas (island):     1,671
Collections:        87
---
GAP: 272,305 ilhas do cache sem metadata enfileirado
```

- Mostra claramente quantas ilhas do `discover_islands_cache` NAO estao no `discover_link_metadata`
- Botao "Enfileirar Top 5K" para enfileirar as ilhas mais relevantes (por last_week_plays DESC)

**3d. Tipos de Link (mini breakdown)**
```text
Islands: 1,671 | Collections: 87
```

### Secao 4: Exposure Pipeline (resumo compacto)

Resumo inline do que ja existe no AdminExposureHealth (sem duplicar tudo):

```text
+------------------+------------------+------------------+------------------+------------------+
| Status           | Targets          | Ticks (24h)      | OK (24h)         | Failed (24h)     |
| Running          | 8 ativos         | 68               | 66               | 2                |
+------------------+------------------+------------------+------------------+------------------+
```

- Link "Ver detalhes" para /admin/exposure
- Pipeline status (running/paused/stopped) com badge colorido

### Secao 5: Cron Jobs Monitor

Tabela mostrando cada cron job registrado no banco:

```text
| Job Name                                    | Schedule    | Status | Health   |
|---------------------------------------------|-------------|--------|----------|
| orchestrate-minute (Exposure)               | * * * * *   | Ativo  | OK verde |
| discover-collector-orchestrate-minute        | * * * * *   | Ativo  | OK verde |
| discover-links-metadata-orchestrate-minute   | * * * * *   | Ativo  | OK verde |
| discover-exposure-intel-refresh-5min         | */5 * * * * | Ativo  | OK verde |
| raw-cleanup-hourly                           | 5 * * * *   | Ativo  | OK verde |
| maintenance-daily                            | 7 0 * * *   | Ativo  | OK verde |
| discover-collector-weekly-v2                 | 0 6 * * 1   | Ativo  | OK verde |
```

- Badge verde "Ativo" / vermelho "Inativo" baseado no campo `active` do `cron.job`
- 7 crons no total (query real confirmada)

### Secao 6: Weekly Report Pipeline (colapsavel)

Todo o conteudo atual do `AdminOverview` (gerar report, progress bar, logs, telemetria de workers) preservado dentro de um `Collapsible`:

- Botao "Gerar Report"
- Botao "Tick Agora"
- Barra de progresso com fase (catalog/metrics/finalize/ai/done)
- Grid de metricas (throughput, workers, 429s, suppressed, stale requeue)
- Log de eventos em tempo real
- Lista dos ultimos 5 reports

---

## Detalhes Tecnicos

### Arquivos Modificados

1. **`src/pages/admin/AdminOverview.tsx`** -- Reescrita completa
2. **`src/components/AdminSidebar.tsx`** -- Renomear "Overview" para "Command Center", icone `Activity`

### Auto-refresh Strategy

- **Polling a cada 10s**: Database Census + Metadata Pipeline + Cron Jobs
  - Queries leves usando `COUNT(*)` com filtros (todas com indices existentes)
  - Nenhum full table scan
- **Polling a cada 30s**: Exposure resumo (5 cards agregados)
- **Pipeline semanal**: Polling a cada 5s (ja existente, preservado no Collapsible)
- **Throughput do metadata**: Calculado no frontend
  - Armazena `withTitle` anterior no `useRef`
  - A cada poll: `(novo - anterior) / intervalo_em_minutos` = ilhas/min
  - ETA: `(total - withTitle) / throughput` em minutos
  - Se throughput = 0 (nada processando): mostra "Idle" em vez de "Infinito"

### Queries Utilizadas (todas leves)

```text
1. Database Census:
   - SELECT COUNT(*), COUNT(*) FILTER (WHERE last_status='reported'), ... FROM discover_islands_cache
   - SELECT COUNT(*), COUNT(*) FILTER (WHERE published_at IS NOT NULL) FROM weekly_reports
   - SELECT COUNT(*) FROM discover_reports

2. Metadata Pipeline:
   - SELECT COUNT(*), COUNT(*) FILTER (WHERE title IS NOT NULL), 
     COUNT(*) FILTER (WHERE last_error IS NOT NULL AND title IS NULL),
     COUNT(*) FILTER (WHERE title IS NULL AND last_error IS NULL),
     COUNT(*) FILTER (WHERE locked_at IS NOT NULL),
     COUNT(*) FILTER (WHERE next_due_at <= now()),
     COUNT(*) FILTER (WHERE link_code_type='island'),
     COUNT(*) FILTER (WHERE link_code_type='collection')
     FROM discover_link_metadata

3. Exposure resumo:
   - SELECT COUNT(*) FROM discovery_exposure_targets
   - Ticks 24h: COUNT(*) de discovery_exposure_ticks com filtro de data

4. Cron Jobs:
   - SELECT jobname, schedule, active FROM cron.job
```

### Componentes Internos (dentro do AdminOverview)

- `StatCard`: card com icone, label, valor grande, sublabel opcional, cor condicional
- `HealthDot`: bolinha verde/amarela/vermelha com tooltip de status
- `MetadataProgressSection`: barra de progresso + ETA + throughput + gap analysis
- `CronTable`: tabela de cron jobs com badges de status

### Sem Migrations Necessarias

Todas as informacoes ja existem nas tabelas atuais. Nenhuma alteracao no banco.

### Sidebar

```text
De: { title: "Overview", url: "/admin", icon: LayoutDashboard }
Para: { title: "Command Center", url: "/admin", icon: Activity }
```
