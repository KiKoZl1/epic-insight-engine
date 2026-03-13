# Tools Catalog

Catálogo operacional de todas as tools expostas ao usuário/admin.

## 1. Hubs de ferramentas
Hubs declarados no frontend:
- `analyticsTools`
- `thumbTools`
- `widgetKit`

(fonte: `src/tool-hubs/registry.ts:4`)

## 2. Matriz completa de tools
| Hub | Tool ID | Rota | Requer Auth | Tool Code (Commerce) | Custo padrão | Execução |
|---|---|---|---|---|---|---|
| Analytics | island-analytics | `/app` | sim | n/a | n/a | frontend + APIs discover |
| Analytics | island-lookup | `/app/island-lookup` | sim | n/a | n/a | `discover-island-lookup*` |
| Analytics | reports | `/reports` | não | n/a | n/a | dados públicos |
| Thumb | generate | `/app/thumb-tools/generate` | sim | `surprise_gen` | 15 | `tgis-generate` via commerce |
| Thumb | edit-studio | `/app/thumb-tools/edit-studio` | sim | `edit_studio` | 4 | `tgis-edit-studio` via commerce |
| Thumb | camera-control | `/app/thumb-tools/camera-control` | sim | `camera_control` | 3 | `tgis-camera-control` via commerce |
| Thumb | layer-decomposition | `/app/thumb-tools/layer-decomposition` | sim | `layer_decomposition` | 8 | `tgis-layer-decompose` via commerce |
| WidgetKit | psd-umg | `/app/widgetkit/psd-umg` | sim | `psd_to_umg` | 2 | `client_local` (sem dispatch tgis) |
| WidgetKit | umg-verse | `/app/widgetkit/umg-verse` | sim | `umg_to_verse` | 2 | `client_local` (sem dispatch tgis) |

Evidência:
- Rotas/hubs/toolCode/requiresAuth. (fonte: `src/tool-hubs/registry.ts:24`)
- Custos padrão. (fonte: `src/lib/commerce/toolCosts.ts:11`)
- Mapping toolCode->função backend para tools remotas. (fonte: `supabase/functions/commerce/index.ts:36`)
- WidgetKit client_local. (fonte: `supabase/functions/commerce/index.ts:761`)

## 3. Regras de auth no frontend
- Subtools sensíveis usam prompt de autenticação quando anônimo.

Evidência:
- `requiresAuth: true` em tools protegidas. (fonte: `src/tool-hubs/registry.ts:62`)
- e2e garante prompt em anônimo ao clicar Generate. (fonte: `e2e/tool-hubs.spec.ts:15`)

## 4. Regras de cobrança
### 4.1 Como custo é calculado
- Front usa catálogo com fallback local (`DEFAULT_TOOL_COSTS`) e cache em localStorage.
- Front consulta `/functions/v1/commerce/catalog/tool-costs` para custos atuais.

Evidência:
- fallback costs e cache TTL. (fonte: `src/lib/commerce/toolCosts.ts:11`, `src/lib/commerce/toolCosts.ts:30`)
- endpoint de catálogo. (fonte: `src/lib/commerce/toolCosts.ts:91`)

### 4.2 Execução cobrada
- Front envia `Idempotency-Key` e `x-device-fingerprint-hash`.
- Backend debita créditos (`commerce_debit_tool_credits`).
- Falhas qualificáveis podem auto-reverter operação.

Evidência:
- headers idempotência/fingerprint. (fonte: `src/lib/commerce/client.ts:56`)
- débito RPC. (fonte: `supabase/functions/commerce/index.ts:735`)
- auto-reversal. (fonte: `supabase/functions/commerce/index.ts:818`)

## 5. Endpoints de execução relacionados
### 5.1 Endpoints de usuário
- `POST /functions/v1/commerce/tools/execute`
- `POST /functions/v1/commerce/tools/reverse`
- `GET /functions/v1/commerce/me/credits`
- `GET /functions/v1/commerce/me/credits/summary`
- `GET /functions/v1/commerce/me/ledger`
- `GET /functions/v1/commerce/me/usage-summary`

Evidência: `supabase/functions/commerce/index.ts:1567`.

### 5.2 Endpoints de administração financeira
- `GET /functions/v1/commerce/admin/user-lookup`
- `GET /functions/v1/commerce/admin/user/{userId}`
- `POST /functions/v1/commerce/admin/credits/grant`
- `POST /functions/v1/commerce/admin/credits/debit`
- `POST /functions/v1/commerce/admin/user/{userId}/abuse-review`
- `POST /functions/v1/commerce/admin/user/{userId}/suspend`

Evidência: `supabase/functions/commerce/index.ts:1662`.

## 6. Onde manter cada parte
### Frontend UX de tools
- `src/tool-hubs/registry.ts`
- `src/navigation/config.ts`
- `src/pages/thumb-tools/*`
- `src/pages/widgetkit/*`

### Regras de custos e cobrança
- `src/lib/commerce/toolCosts.ts`
- `src/lib/commerce/client.ts`
- `supabase/functions/commerce/index.ts`

### Regras server-side de tool code
- `supabase/functions/_shared/commerceTools.ts`

## 7. Checklist quando adicionar uma nova tool
1. Adicionar nova route/página em `src/App.tsx` e/ou hub.
2. Adicionar item no `src/tool-hubs/registry.ts`.
3. Adicionar `toolCode` em tipos/constantes de custos.
4. Definir custo padrão e chave de config.
5. Implementar dispatch no commerce backend (ou marcar `client_local`).
6. Ajustar UI de créditos/ledger se necessário.
7. Atualizar e2e (`e2e/tool-hubs.spec.ts`) e docs.

Evidência base:
- Estrutura atual de tool lifecycle. (fonte: `src/tool-hubs/registry.ts:24`, `src/lib/commerce/toolCosts.ts:20`, `supabase/functions/commerce/index.ts:717`)
