

# Surprise Radar -- Reestruturacao Completa da Plataforma

## Resumo

Transformar a aplicacao atual "FN Analytics" na plataforma "Surprise Radar" com tres areas distintas (publica, cliente, admin), novo sistema de identidade visual baseado na brand guide fornecida, e um mini-CMS para publicacao de reports semanais.

---

## Fase 1: Identidade Visual e Rebrand

### 1.1 Paleta de cores (baseada na brand guide)

Atualizar `src/index.css` com a nova paleta:

```text
Preto:    #000000 (base, sidebar, backgrounds)
Branco:   #FFFFFF (texto, cards)
Amarelo:  #FFFF29 (primary / CTA / destaques)
Rosa:     #FF087A (accent / insights / alertas)
Azul:     #0040FF (secondary actions / chips)
Roxo:     #6408C8 (tabs / categorias)
Vermelho: #FF392B (destructive / decliners)
```

Dark mode: fundo preto (#000000), cards em cinza escuro (#111111), texto branco.
Light mode: fundo branco, cards brancos, texto preto.

### 1.2 Tipografia

Substituir Inter + Space Grotesk por:
- **Mafinest** (destaques/headings) -- como fonte custom, mas como fallback usaremos uma fonte similar disponivel no Google Fonts ou manteremos Space Grotesk para headings com estilo bold
- **Figerona** (textos/body) -- fallback para Inter ou similar
- Como fontes custom exigem arquivos .woff2, usaremos as mais proximas disponiveis: manter **Space Grotesk** para headings e **Inter** para body, ajustando pesos e estilos para refletir a energia da brand

### 1.3 Nome e Branding

- Trocar todas as referencias "FN Analytics" para "Surprise Radar"
- Tagline: "Weekly Discovery Intelligence for Fortnite UGC"
- Sidebar: logo + "Surprise Radar"
- Footer: "Surprise Radar" + links

---

## Fase 2: Estrutura de Rotas e Permissoes

### 2.1 Nova arvore de rotas

```text
/                         Home publica
/reports                  Lista de reports publicados (publica)
/reports/:slug            Pagina publica de um report
/auth                     Login/Signup

/app                      Dashboard do cliente (auth required)
/app/island-lookup        Lookup por codigo (ja existe)
/app/csv-analytics        Upload ZIP/CSV (rota atual /app com projects)
/app/history              Historico de relatorios do cliente

/admin                    Overview admin (role required)
/admin/reports            Lista de reports (draft/published)
/admin/reports/:id/edit   Editor do report (mini CMS)
```

### 2.2 Sistema de roles

Adicionar coluna `role` na tabela `profiles`:

```text
ALTER TABLE profiles ADD COLUMN role TEXT DEFAULT 'client';
```

Valores: `admin`, `editor`, `client`

### 2.3 Componentes de gate

- `ProtectedRoute` (ja existe): requer auth
- `AdminRoute` (novo): requer auth + role = admin ou editor
- `useAuth` atualizado para expor `role` do perfil

---

## Fase 3: Tabela CMS -- `weekly_reports`

### 3.1 Schema

```text
weekly_reports
  id                UUID PK DEFAULT gen_random_uuid()
  discover_report_id UUID NULL (FK para discover_reports.id)
  week_key          TEXT NOT NULL (ex: 2026-W06)
  date_from         DATE NOT NULL
  date_to           DATE NOT NULL
  status            TEXT DEFAULT 'draft' (draft | published | archived)
  public_slug       TEXT UNIQUE (ex: 2026-w06)
  title_public      TEXT
  subtitle_public   TEXT
  editor_note       TEXT (markdown)
  kpis_json         JSONB DEFAULT '{}'
  rankings_json     JSONB DEFAULT '{}'
  sections_json     JSONB DEFAULT '[]'
  ai_sections_json  JSONB DEFAULT '{}'
  editor_sections_json JSONB DEFAULT '{}'
  published_at      TIMESTAMPTZ NULL
  created_at        TIMESTAMPTZ DEFAULT now()
  updated_at        TIMESTAMPTZ DEFAULT now()
```

### 3.2 RLS

- SELECT publico para `status = 'published'` (sem auth)
- SELECT completo para admin/editor (via role check)
- INSERT/UPDATE/DELETE apenas service_role e admins

---

## Fase 4: Area Publica

### 4.1 Home (`/`)

Redesign com a identidade Surprise Radar:
- Hero section com fundo escuro, acentos amarelo/rosa
- CTA "Ver report desta semana" linkando para o ultimo published
- Cards das 3 ferramentas
- Footer com branding

### 4.2 Lista de Reports (`/reports`)

- Grid de cards com os reports publicados
- Cada card: titulo, semana, data, KPIs resumidos
- Sem auth necessario

### 4.3 Pagina do Report (`/reports/:slug`)

- Layout publico (sem sidebar)
- Header com titulo, periodo, nota editorial
- Todas as 13 secoes do report (reutilizar componentes existentes)
- Logica: se `editor_sections_json[sectionN]` existe, usa; senao usa `ai_sections_json[sectionN]`
- Botoes: compartilhar, copiar link

---

## Fase 5: Admin Panel

### 5.1 Overview (`/admin`)

- Status do job atual (fase, progresso, contadores)
- Botao "Gerar Report Agora"
- Lista dos ultimos reports com status

### 5.2 Lista de Reports (`/admin/reports`)

- Tabela com todos os reports (draft/published)
- Acoes: editar, preview, publicar/despublicar

### 5.3 Editor (`/admin/reports/:id/edit`)

- Campos: titulo publico, subtitulo, nota editorial
- Para cada secao (1-13): textarea com texto da IA + campo editavel
- Botao "Publicar" que seta status=published e gera public_slug
- Botao "Regenerar IA" por secao (chama discover-report-ai)

---

## Fase 6: Integracao Pipeline para CMS

Atualizar o mode "finalize" do `discover-collector`:
- Apos finalizar o `discover_reports`, criar/atualizar um `weekly_reports` como draft
- Copiar `platform_kpis` para `kpis_json`
- Copiar `computed_rankings` para `rankings_json`
- Copiar `ai_narratives` para `ai_sections_json`
- Gerar `public_slug` automaticamente (ex: `2026-w06`)
- Gerar `title_public` automaticamente (ex: "Fortnite Discovery - Semana 6/2026")

---

## Fase 7: Reorganizacao de Rotas Existentes

### Mover funcionalidades atuais

- `/app` (atual Island Analytics / projects) migra para `/app/csv-analytics`
- `/app/discover-trends` migra para `/admin` (apenas admin gera reports)
- `/app/discover-trends/:reportId` (visualizacao) e reutilizado em `/reports/:slug` (publico) e `/admin/reports/:id/edit` (admin)

---

## Detalhes Tecnicos

### Arquivos a criar

```text
src/components/AdminRoute.tsx
src/components/PublicLayout.tsx
src/components/AdminLayout.tsx
src/pages/public/Home.tsx
src/pages/public/ReportsList.tsx
src/pages/public/ReportView.tsx
src/pages/admin/AdminOverview.tsx
src/pages/admin/AdminReportsList.tsx
src/pages/admin/AdminReportEditor.tsx
src/pages/app/ClientHistory.tsx
```

### Arquivos a modificar

```text
src/App.tsx                    -- novas rotas
src/index.css                  -- nova paleta
src/components/AppSidebar.tsx  -- rebrand + ajustar links
src/components/AppLayout.tsx   -- manter para /app
src/hooks/useAuth.tsx          -- adicionar role
src/pages/Index.tsx            -- substituir por nova Home
src/pages/DiscoverTrendsReport.tsx -- extrair componentes reutilizaveis
supabase/functions/discover-collector/index.ts -- criar weekly_reports no finalize
```

### Migracao SQL

1. `ALTER TABLE profiles ADD COLUMN role TEXT DEFAULT 'client'`
2. `CREATE TABLE weekly_reports (...)`
3. RLS policies para weekly_reports
4. Setar seu usuario como admin: `UPDATE profiles SET role = 'admin' WHERE user_id = '...'`

---

## Ordem de Execucao

1. **SQL**: Criar `weekly_reports` + adicionar `role` em `profiles`
2. **CSS**: Nova paleta de cores (rebrand visual)
3. **Auth**: Atualizar `useAuth` com role, criar `AdminRoute`
4. **Rotas**: Reestruturar `App.tsx` com as 3 areas
5. **Home publica**: Nova landing page Surprise Radar
6. **Reports publicos**: `/reports` e `/reports/:slug`
7. **Admin**: Overview + lista + editor
8. **Pipeline**: Integracao do finalize com `weekly_reports`
9. **Sidebar/Header**: Rebrand completo

---

## Resultado Esperado

- Plataforma com identidade propria "Surprise Radar"
- Reports semanais publicaveis como paginas publicas (SEO)
- Admin pode editar/revisar antes de publicar
- Clientes acessam ferramentas (lookup, CSV) sem ver admin
- Paleta vibrante: preto/amarelo/rosa conforme brand guide
- Pipeline existente inalterado, apenas com output adicional para o CMS

