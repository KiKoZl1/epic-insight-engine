# UEFN Toolkit Brand and Design Standards

This document is the code-derived visual and interaction reference for UEFN Toolkit.

Purpose:

- Keep future tools and pages visually consistent with current implementation.
- Preserve platform naming, color system, typography, spacing, and navigation behavior.
- Provide a reusable baseline when redesigning or extending the UI.

If behavior cannot be proven in code, it is explicitly marked as not determined.

## 1. Canonical Naming

- Canonical product name: `UEFN Toolkit`.
- Brand name is runtime-configurable from env var `VITE_BRAND_NAME` with fallback `UEFNToolkit`.
- Canonical URL is runtime-configurable from `VITE_CANONICAL_URL` with fallback `https://uefntoolkit.com`.

Evidence:
- Brand normalizer and fallbacks. (source: src/config/brand.ts:1, src/config/brand.ts:2, src/config/brand.ts:16)
- Runtime export constants. (source: src/config/brand.ts:18, src/config/brand.ts:19, src/config/brand.ts:20)

## 2. Design Token System

## 2.1 Global Color Tokens

Core CSS custom properties are defined in `:root` and reused in Tailwind theme mappings:

- Base surfaces: `--background`, `--card`, `--popover`.
- Text layers: `--foreground`, `--muted-foreground`.
- Action colors: `--primary`, `--accent`.
- Feedback colors: `--success`, `--warning`, `--info`, `--destructive`.
- Structural colors: `--border`, `--input`, `--ring`.

Evidence:
- CSS token declarations. (source: src/index.css:8, src/index.css:11, src/index.css:19, src/index.css:33, src/index.css:46, src/index.css:49, src/index.css:56)
- Tailwind token mapping. (source: tailwind.config.ts:22, tailwind.config.ts:27, tailwind.config.ts:39, tailwind.config.ts:55, tailwind.config.ts:63)

## 2.2 Sidebar Tokens

Sidebar has dedicated variables:

- `--sidebar-background`
- `--sidebar-foreground`
- `--sidebar-primary`
- `--sidebar-accent`
- `--sidebar-border`
- `--sidebar-ring`

Evidence:
- CSS token declarations. (source: src/index.css:36, src/index.css:37, src/index.css:38, src/index.css:40, src/index.css:42)
- Tailwind mapping. (source: tailwind.config.ts:71, tailwind.config.ts:74, tailwind.config.ts:76, tailwind.config.ts:78, tailwind.config.ts:79)

## 2.3 Radius and Geometry

- Base radius token is `--radius: 0.625rem`.
- Tailwind derives `lg`, `md`, and `sm` from this token.

Evidence:
- CSS radius token. (source: src/index.css:34)
- Tailwind border radius config. (source: tailwind.config.ts:82)

## 3. Typography Standards

## 3.1 Font Families

- Body/UI font: `Inter`.
- Display/headline font: `Space Grotesk`.

Evidence:
- Google font imports. (source: src/index.css:1)
- Base usage in `body` and headings. (source: src/index.css:147, src/index.css:152)
- Tailwind font aliases (`sans`, `display`). (source: tailwind.config.ts:17)

## 3.2 Title Treatment

Headers for major screens commonly use:

- `font-display`
- tight tracking (`tracking-tight`)
- larger scale (`text-3xl` to `text-4xl` on hub headers)

Evidence:
- Tool hub hero title classes. (source: src/components/tool-hub/ToolHubLayout.tsx:30)
- WidgetKit page title classes. (source: src/pages/widgetkit/PsdToUmgPage.tsx:19, src/pages/widgetkit/UmgToVersePage.tsx:19)
- Brand label style in logo component. (source: src/components/brand/PlatformBrand.tsx:30)

## 4. Navigation and Shell Patterns

## 4.1 Layout Shells

Runtime shell selection:

- Anonymous users use `PublicLayout`.
- Authenticated users use `AppLayout`.
- Admin area uses `AdminLayout` guarded by role.

Evidence:
- Smart shell switching logic. (source: src/components/SmartLayout.tsx:10, src/components/SmartLayout.tsx:20, src/components/SmartLayout.tsx:24)
- App shell top bar and max width wrapper. (source: src/components/AppLayout.tsx:6, src/components/AppLayout.tsx:7, src/components/AppLayout.tsx:9)
- Admin route gating. (source: src/App.tsx:140, src/components/AdminRoute.tsx:5, src/components/AdminRoute.tsx:16)

## 4.2 Top Navigation Interaction Standards

Desktop top bar behavior:

- Sticky blurred header.
- Flyout menus for tool hubs (`analyticsToolsHub`, `thumbToolsHub`, `widgetKitHub`).
- Keyboard support for escape and arrow navigation.
- Context switching button between app/admin when role permits.

Evidence:
- Sticky/blur container classes. (source: src/components/navigation/TopBar.tsx:337)
- Flyout id set. (source: src/components/navigation/TopBar.tsx:46)
- Keyboard handlers. (source: src/components/navigation/TopBar.tsx:380, src/components/navigation/TopBar.tsx:384)
- Context switch state and label. (source: src/components/navigation/TopBar.tsx:144, src/components/navigation/TopBar.tsx:146)

## 4.3 Mobile Navigation Standards

Mobile nav behavior:

- Left-side sheet menu.
- Sectioned nav groups with labels.
- Auth gate prompts when anonymous user taps protected tool entries.
- Language toggle and account actions in bottom section.

Evidence:
- Mobile sheet container. (source: src/components/navigation/MobileTopNav.tsx:43, src/components/navigation/MobileTopNav.tsx:49)
- Section rendering. (source: src/components/navigation/MobileTopNav.tsx:63)
- Auth prompt branch for protected nav items. (source: src/components/navigation/MobileTopNav.tsx:74, src/components/navigation/MobileTopNav.tsx:81)
- Language and account actions. (source: src/components/navigation/MobileTopNav.tsx:159, src/components/navigation/MobileTopNav.tsx:203)

## 5. Tool Hub UI Pattern

All tool hubs share `ToolHubLayout` visual structure.

Pattern:

1. Hero block with gradient card and glow.
2. Tool count badge.
3. Grid of tool cards.
4. Per-card icon, title, description, and optional credit chip.
5. Auth-gated button for anonymous users where applicable.

Evidence:
- Shared hub component. (source: src/components/tool-hub/ToolHubLayout.tsx:16)
- Hero header and glow treatment. (source: src/components/tool-hub/ToolHubLayout.tsx:22, src/components/tool-hub/ToolHubLayout.tsx:23)
- Tool card structure and credit chip. (source: src/components/tool-hub/ToolHubLayout.tsx:41, src/components/tool-hub/ToolHubLayout.tsx:49)
- Auth-gated card branch. (source: src/components/tool-hub/ToolHubLayout.tsx:70, src/components/tool-hub/ToolHubLayout.tsx:75)

## 6. Motion and Transitions

## 6.1 Motion Tokens

Motion duration/easing tokens:

- `--motion-nav-fast: 140ms`
- `--motion-nav-base: 180ms`
- `--motion-nav-slow: 220ms`
- `--ease-nav: cubic-bezier(0.16, 1, 0.3, 1)`

Evidence:
- Motion token declarations. (source: src/index.css:58, src/index.css:61)
- Utility classes using tokens. (source: src/index.css:117, src/index.css:122, src/index.css:127)

## 6.2 Reduced Motion

- When `prefers-reduced-motion: reduce` is active, nav motion durations are collapsed to `1ms`.

Evidence:
- Reduced motion media block. (source: src/index.css:133, src/index.css:135)

## 7. Component-Level Visual Rules

## 7.1 Brand Mark

`PlatformBrand` is the reusable identity component:

- Circular/radar-like icon made from inline SVG.
- Orange-accent border and glow treatment.
- Optional compact mode hides text.

Evidence:
- Component and props. (source: src/components/brand/PlatformBrand.tsx:4, src/components/brand/PlatformBrand.tsx:11)
- Icon frame classes and SVG paths. (source: src/components/brand/PlatformBrand.tsx:16, src/components/brand/PlatformBrand.tsx:21)
- Compact behavior. (source: src/components/brand/PlatformBrand.tsx:29)

## 7.2 Tool Card Behavior

Tool cards use:

- Mild elevation and border on hover.
- Slight translate-up (`hover:-translate-y-0.5`).
- Primary tint icon chip.

Evidence:
- Card hover classes. (source: src/components/tool-hub/ToolHubLayout.tsx:41)
- Icon treatment. (source: src/components/tool-hub/ToolHubLayout.tsx:43)

## 7.3 Credit Visibility Rule

Tool cost chips are shown only when:

- User is authenticated.
- Tool has mapped commerce code.
- Resolved cost is greater than zero.

Evidence:
- Cost resolution and conditional render. (source: src/components/tool-hub/ToolHubLayout.tsx:39, src/components/tool-hub/ToolHubLayout.tsx:49)
- Nav-level tool code mapping. (source: src/lib/commerce/toolCosts.ts:152)

## 8. Public vs Authenticated Experience Standard

- Public tool hubs are discoverable without login.
- Protected tools in public context should trigger auth gate dialog instead of broken navigation.
- Authenticated routes remain under `/app`.

Evidence:
- Public tool hub pages and auth gate wiring. (source: src/pages/tools/PublicToolHubPage.tsx:12, src/pages/tools/PublicToolHubPage.tsx:24, src/pages/tools/PublicToolHubPage.tsx:25)
- Protected app routes. (source: src/App.tsx:116)

## 9. New Tool Page Design Checklist

When creating a new tool page, preserve these baseline rules:

1. Register tool in `src/tool-hubs/registry.ts` with id, route, icon, and `toolCode` if billed. (source: src/tool-hubs/registry.ts:5, src/tool-hubs/registry.ts:55)
2. Add route in `src/App.tsx` under the correct shell and guard. (source: src/App.tsx:116)
3. Add nav entries in `src/navigation/config.ts` when tool must appear in top/mobile nav. (source: src/navigation/config.ts:220)
4. Reuse `ToolHubLayout` for hub-level discoverability. (source: src/pages/WidgetKit.tsx:5)
5. Use `ToolCostBadge`/credit chips from existing commerce UI pattern when tool has non-zero cost. (source: src/components/widgetkit/PsdToUmgTool.tsx:16, src/components/widgetkit/UmgToVerseTool.tsx:14)
6. Keep typography to `font-display` for page titles and `Inter` for body.
7. Use existing color tokens (`primary`, `muted`, `border`) instead of hardcoded hex where possible.

## 10. Brand Governance for Documentation and UI Text

Required:

- Use `UEFN Toolkit` in docs and user-facing platform references.
- Avoid reintroducing legacy naming aliases in docs, metadata, or generated templates.

Evidence:
- Runtime brand source from env/fallback. (source: src/config/brand.ts:1, src/config/brand.ts:18)
- Brand rendered in top nav via `PlatformBrand`. (source: src/components/navigation/TopBar.tsx:340)

## 11. Not Determined From Code

The following are not determined from code:

- Official brand voice guidelines (copywriting tone handbook).
- Marketing visual kit (logos exported for social/print).
- External accessibility compliance policy beyond implemented UI behavior.

These must not be inferred until explicit source artifacts exist in repository.
