import { useEffect, useMemo, useState } from "react";
import { Link } from "react-router-dom";
import { ArrowRight, ChevronRight } from "lucide-react";
import { useTranslation } from "react-i18next";
import { useAuth } from "@/hooks/useAuth";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { PlatformBrand } from "@/components/brand/PlatformBrand";
import { AuthGateDialog } from "@/components/navigation/AuthGateDialog";
import { getVisibleToolCategories, isNavItemProtectedForAccess } from "@/navigation/config";
import { resolveNavItemIcon } from "@/navigation/iconMap";
import { NavAccessState } from "@/navigation/types";
import { cn } from "@/lib/utils";
import {
  Carousel,
  CarouselContent,
  CarouselItem,
  CarouselNext,
  CarouselPrevious,
  type CarouselApi,
} from "@/components/ui/carousel";

const CAROUSEL_AUTOPLAY_MS = 5200;

function usePrefersReducedMotion() {
  const [prefersReducedMotion, setPrefersReducedMotion] = useState(false);

  useEffect(() => {
    if (typeof window === "undefined") return;
    const mediaQuery = window.matchMedia("(prefers-reduced-motion: reduce)");
    const onChange = (event: MediaQueryListEvent) => setPrefersReducedMotion(event.matches);

    setPrefersReducedMotion(mediaQuery.matches);
    mediaQuery.addEventListener("change", onChange);
    return () => mediaQuery.removeEventListener("change", onChange);
  }, []);

  return prefersReducedMotion;
}

function getCategoryTheme(categoryId: string) {
  if (categoryId === "discover") {
    return {
      shell: "from-primary/24 via-primary/6 to-background",
      badge: "border-primary/35 bg-primary/14 text-primary",
    };
  }
  if (categoryId === "analyticsTools") {
    return {
      shell: "from-sky-500/22 via-sky-500/6 to-background",
      badge: "border-sky-400/35 bg-sky-400/12 text-sky-300",
    };
  }
  if (categoryId === "thumbTools") {
    return {
      shell: "from-orange-500/24 via-orange-500/6 to-background",
      badge: "border-orange-400/35 bg-orange-400/12 text-orange-300",
    };
  }
  return {
    shell: "from-emerald-500/22 via-emerald-500/6 to-background",
    badge: "border-emerald-400/35 bg-emerald-400/12 text-emerald-300",
  };
}

export default function Home() {
  const { t } = useTranslation();
  const { user, isAdmin, isEditor } = useAuth();
  const [authGate, setAuthGate] = useState<{ open: boolean; label?: string }>({ open: false });
  const [carouselApi, setCarouselApi] = useState<CarouselApi>();
  const [carouselIndex, setCarouselIndex] = useState(0);
  const [isCarouselPaused, setIsCarouselPaused] = useState(false);
  const prefersReducedMotion = usePrefersReducedMotion();

  const access = useMemo<NavAccessState>(
    () => ({
      isAuthenticated: Boolean(user),
      isAdmin,
      isEditor,
    }),
    [isAdmin, isEditor, user],
  );

  const categories = useMemo(() => getVisibleToolCategories("public", access), [access]);
  const featuredTools = useMemo(() => categories.flatMap((category) => category.items.map((item) => ({ category, item }))), [categories]);

  const steps = useMemo(
    () => [
      { id: "discover", title: t("home.stepDiscoverTitle"), desc: t("home.stepDiscoverDesc") },
      { id: "build", title: t("home.stepBuildTitle"), desc: t("home.stepBuildDesc") },
      { id: "ship", title: t("home.stepShipTitle"), desc: t("home.stepShipDesc") },
    ],
    [t],
  );

  useEffect(() => {
    if (!carouselApi) return;

    const onSelect = () => setCarouselIndex(carouselApi.selectedScrollSnap());
    onSelect();
    carouselApi.on("select", onSelect);
    carouselApi.on("reInit", onSelect);

    return () => {
      carouselApi.off("select", onSelect);
      carouselApi.off("reInit", onSelect);
    };
  }, [carouselApi]);

  useEffect(() => {
    if (!carouselApi || prefersReducedMotion || isCarouselPaused || categories.length <= 1) return;

    const interval = window.setInterval(() => {
      const nextIndex = (carouselApi.selectedScrollSnap() + 1) % categories.length;
      carouselApi.scrollTo(nextIndex);
    }, CAROUSEL_AUTOPLAY_MS);

    return () => window.clearInterval(interval);
  }, [carouselApi, categories.length, isCarouselPaused, prefersReducedMotion]);

  const openAuthGateForLabel = (label: string) => setAuthGate({ open: true, label });

  return (
    <>
      <section className="relative overflow-hidden border-b border-border/60">
        <div className="pointer-events-none absolute inset-0 bg-[radial-gradient(circle_at_20%_20%,rgba(255,127,0,0.18),transparent_45%),radial-gradient(circle_at_85%_12%,rgba(56,189,248,0.14),transparent_35%),linear-gradient(180deg,rgba(8,14,24,0.95)_0%,rgba(8,14,24,0.82)_60%,rgba(8,14,24,0.6)_100%)]" />
        <div className="pointer-events-none absolute inset-0 bg-[linear-gradient(rgba(255,255,255,0.02)_1px,transparent_1px),linear-gradient(90deg,rgba(255,255,255,0.02)_1px,transparent_1px)] bg-[size:48px_48px]" />

        <div className="relative mx-auto grid max-w-7xl gap-8 px-6 py-16 md:grid-cols-[1.08fr_0.92fr] md:py-20">
          <div className="space-y-7">
            <span className="inline-flex items-center rounded-full border border-primary/30 bg-primary/12 px-4 py-1.5 text-[11px] uppercase tracking-[0.16em] text-primary">
              {t("home.badge")}
            </span>

            <div className="space-y-4">
              <h1 className="max-w-3xl font-display text-4xl font-bold leading-[1.05] tracking-tight text-foreground sm:text-5xl lg:text-6xl">
                {t("home.title")} <span className="text-primary">{t("home.titleHighlight")}</span>
              </h1>
              <p className="max-w-2xl text-base leading-relaxed text-muted-foreground md:text-lg">{t("home.subtitle")}</p>
            </div>

            <div className="flex flex-wrap items-center gap-3">
              <Button size="lg" asChild>
                <Link to="/discover" className="gap-2">
                  {t("home.ctaPrimary")}
                  <ArrowRight className="h-4 w-4" />
                </Link>
              </Button>
              <Button size="lg" variant="outline" asChild>
                <Link to="/tools/analytics">{t("home.ctaSecondary")}</Link>
              </Button>
            </div>

            <div className="flex flex-wrap items-center gap-2 text-xs text-muted-foreground">
              <span className="rounded-full border border-border/70 bg-background/45 px-3 py-1">{t("home.heroStatOne")}</span>
              <span className="rounded-full border border-border/70 bg-background/45 px-3 py-1">{t("home.heroStatTwo")}</span>
              <span className="rounded-full border border-border/70 bg-background/45 px-3 py-1">{t("home.heroStatThree")}</span>
            </div>
          </div>

          <Card className="relative border-border/70 bg-background/55 backdrop-blur">
            <div className="pointer-events-none absolute -right-16 -top-16 h-44 w-44 rounded-full bg-primary/22 blur-3xl" />
            <CardHeader className="relative space-y-2">
              <span className="text-xs uppercase tracking-[0.16em] text-primary">{t("home.liveDeskTitle")}</span>
              <CardTitle className="font-display text-2xl leading-tight">{t("home.liveDeskSubtitle")}</CardTitle>
              <CardDescription>{t("home.liveDeskDescription")}</CardDescription>
            </CardHeader>
            <CardContent className="relative space-y-3">
              {categories.map((category) => {
                const Icon = resolveNavItemIcon(category.hubItem.icon || category.icon);
                return (
                  <Link
                    key={`hero-${category.id}`}
                    to={category.hubPublicRoute}
                    className="group flex items-center justify-between rounded-xl border border-border/70 bg-background/45 px-3 py-2.5 transition-colors hover:border-primary/35 hover:bg-primary/8"
                  >
                    <span className="flex items-center gap-2 text-sm font-medium">
                      {Icon ? <Icon className="h-4 w-4 text-primary" /> : null}
                      {t(category.labelKey)}
                    </span>
                    <ChevronRight className="h-4 w-4 text-muted-foreground transition-transform group-hover:translate-x-0.5" />
                  </Link>
                );
              })}
            </CardContent>
          </Card>
        </div>
      </section>

      <section className="mx-auto max-w-7xl px-6 py-12">
        <div className="mb-5 flex items-end justify-between gap-4">
          <div>
            <h2 className="font-display text-3xl font-bold tracking-tight">{t("home.carouselTitle")}</h2>
            <p className="text-sm text-muted-foreground">{t("home.carouselSubtitle")}</p>
          </div>
          <span className="hidden text-xs uppercase tracking-[0.14em] text-muted-foreground md:inline-flex">
            {categories.length} {t("common.tools")}
          </span>
        </div>

        <div
          className="rounded-3xl border border-border/70 bg-card/35 p-4 md:p-5"
          onMouseEnter={() => setIsCarouselPaused(true)}
          onMouseLeave={() => setIsCarouselPaused(false)}
          onFocusCapture={() => setIsCarouselPaused(true)}
          onBlurCapture={(event) => {
            if (!event.currentTarget.contains(event.relatedTarget as Node | null)) {
              setIsCarouselPaused(false);
            }
          }}
        >
          <Carousel opts={{ align: "start", loop: true }} setApi={setCarouselApi}>
            <CarouselContent>
              {categories.map((category, index) => {
                const Icon = resolveNavItemIcon(category.hubItem.icon || category.icon);
                const theme = getCategoryTheme(category.id);
                const tools = (category.items.length > 0 ? category.items : [category.hubItem]).slice(0, 4);

                return (
                  <CarouselItem key={`slide-${category.id}`}>
                    <article className={cn("relative overflow-hidden rounded-2xl border border-border/70 bg-gradient-to-br p-6 md:p-8", theme.shell)}>
                      <div className="pointer-events-none absolute -right-20 top-0 h-52 w-52 rounded-full bg-white/10 blur-3xl" />

                      <div className="relative grid gap-6 md:grid-cols-[1.15fr_0.85fr] md:gap-8">
                        <div className="space-y-4">
                          <span className={cn("inline-flex items-center gap-2 rounded-full border px-3 py-1 text-[11px] uppercase tracking-[0.15em]", theme.badge)}>
                            {Icon ? <Icon className="h-3.5 w-3.5" /> : null}
                            {t("home.slideBadge")}
                          </span>

                          <div className="space-y-2">
                            <h3 className="font-display text-3xl font-bold leading-tight tracking-tight">{t(category.labelKey)}</h3>
                            {category.descriptionKey ? (
                              <p className="max-w-xl text-sm leading-relaxed text-muted-foreground md:text-base">{t(category.descriptionKey)}</p>
                            ) : null}
                          </div>

                          <div className="flex flex-wrap items-center gap-3">
                            <Button asChild>
                              <Link to={category.hubPublicRoute} className="gap-2">
                                {t("home.slideCta")}
                                <ChevronRight className="h-4 w-4" />
                              </Link>
                            </Button>
                            <span className="text-xs uppercase tracking-[0.14em] text-muted-foreground">
                              {t("home.carouselMeta", { index: index + 1, total: categories.length })}
                            </span>
                          </div>
                        </div>

                        <div className="space-y-2 rounded-xl border border-border/65 bg-background/55 p-3">
                          <p className="px-1 text-[11px] uppercase tracking-[0.16em] text-muted-foreground">{t("home.slideToolsTitle")}</p>
                          {tools.map((tool) => {
                            const isProtected = isNavItemProtectedForAccess(tool, access);
                            const ToolIcon = resolveNavItemIcon(tool.icon || category.icon);

                            if (isProtected) {
                              return (
                                <button
                                  key={`${category.id}-${tool.id}`}
                                  type="button"
                                  onClick={() => openAuthGateForLabel(t(tool.labelKey))}
                                  className="group flex w-full items-center justify-between rounded-lg border border-border/70 bg-background/55 px-3 py-2 text-left transition-colors hover:border-primary/35 hover:bg-primary/8 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
                                >
                                  <span className="flex items-center gap-2 text-sm font-medium text-foreground/95">
                                    {ToolIcon ? <ToolIcon className="h-3.5 w-3.5 text-primary" /> : null}
                                    {t(tool.labelKey)}
                                  </span>
                                  <span className="text-[11px] uppercase tracking-[0.13em] text-muted-foreground">{t("home.toolsListCtaProtected")}</span>
                                </button>
                              );
                            }

                            return (
                              <Link
                                key={`${category.id}-${tool.id}`}
                                to={tool.to}
                                className="group flex items-center justify-between rounded-lg border border-border/70 bg-background/55 px-3 py-2 transition-colors hover:border-primary/35 hover:bg-primary/8 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
                              >
                                <span className="flex items-center gap-2 text-sm font-medium text-foreground/95">
                                  {ToolIcon ? <ToolIcon className="h-3.5 w-3.5 text-primary" /> : null}
                                  {t(tool.labelKey)}
                                </span>
                                <span className="text-[11px] uppercase tracking-[0.13em] text-muted-foreground">{t("home.toolsListCtaPublic")}</span>
                              </Link>
                            );
                          })}
                        </div>
                      </div>
                    </article>
                  </CarouselItem>
                );
              })}
            </CarouselContent>
            <CarouselPrevious className="left-2 top-2 h-9 w-9 translate-y-0 border-border/70 bg-background/95 md:left-auto md:right-14" />
            <CarouselNext className="right-2 top-2 h-9 w-9 translate-y-0 border-border/70 bg-background/95" />
          </Carousel>

          <div className="mt-4 flex items-center justify-center gap-2" role="tablist" aria-label={t("home.carouselDotsAria")}>
            {categories.map((category, index) => (
              <button
                key={`dot-${category.id}`}
                type="button"
                onClick={() => carouselApi?.scrollTo(index)}
                className={`h-2.5 rounded-full transition-all ${
                  carouselIndex === index ? "w-8 bg-primary" : "w-2.5 bg-muted-foreground/40 hover:bg-muted-foreground/70"
                }`}
                aria-label={t("home.carouselDot", { index: index + 1 })}
                aria-current={carouselIndex === index}
              />
            ))}
          </div>
        </div>
      </section>

      <section className="mx-auto max-w-7xl px-6 py-6">
        <div className="mb-5 space-y-1">
          <h2 className="font-display text-2xl font-bold tracking-tight md:text-3xl">{t("home.workflowTitle")}</h2>
          <p className="text-sm text-muted-foreground">{t("home.workflowSubtitle")}</p>
        </div>

        <div className="grid gap-4 md:grid-cols-3">
          {steps.map((step, index) => (
            <Card key={step.id} className="relative border-border/70 bg-card/22">
              <div className="pointer-events-none absolute left-0 top-0 h-1 w-full rounded-t-lg bg-gradient-to-r from-primary/70 via-primary/20 to-transparent" />
              <CardHeader className="space-y-2">
                <span className="inline-flex w-fit rounded-full border border-primary/28 bg-primary/10 px-2 py-1 text-[11px] uppercase tracking-[0.12em] text-primary">
                  {t("home.stepLabel", { index: index + 1 })}
                </span>
                <CardTitle className="text-lg">{step.title}</CardTitle>
                <CardDescription>{step.desc}</CardDescription>
              </CardHeader>
            </Card>
          ))}
        </div>
      </section>

      <section className="mx-auto max-w-7xl px-6 py-12">
        <div className="mb-5 space-y-1">
          <h2 className="font-display text-2xl font-bold tracking-tight md:text-3xl">{t("home.hubGridTitle")}</h2>
          <p className="text-sm text-muted-foreground">{t("home.hubGridSubtitle")}</p>
        </div>

        <div className="grid gap-4 md:grid-cols-2 xl:grid-cols-4">
          {categories.map((category) => {
            const Icon = resolveNavItemIcon(category.hubItem.icon || category.icon);
            const theme = getCategoryTheme(category.id);
            return (
              <Card key={`category-${category.id}`} className="h-full border-border/70 bg-card/28">
                <CardHeader className="space-y-3">
                  <div className="flex items-center justify-between">
                    <span className={cn("inline-flex rounded-lg border p-2", theme.badge)}>
                      {Icon ? <Icon className="h-4 w-4" /> : null}
                    </span>
                    <Button asChild variant="ghost" size="sm" className="h-8 px-2 text-xs">
                      <Link to={category.hubPublicRoute}>{t("home.hubCardOpenHub")}</Link>
                    </Button>
                  </div>
                  <CardTitle className="text-xl">{t(category.labelKey)}</CardTitle>
                  {category.descriptionKey ? <CardDescription>{t(category.descriptionKey)}</CardDescription> : null}
                </CardHeader>
                <CardContent className="space-y-2">
                  {(category.items.length > 0 ? category.items : [category.hubItem]).slice(0, 3).map((tool) => (
                    <p key={`${category.id}-${tool.id}`} className="rounded-md border border-border/65 bg-background/45 px-2.5 py-1.5 text-sm text-foreground/90">
                      {t(tool.labelKey)}
                    </p>
                  ))}
                </CardContent>
              </Card>
            );
          })}
        </div>
      </section>

      <section className="mx-auto max-w-7xl px-6 pb-20">
        <div className="rounded-3xl border border-primary/25 bg-gradient-to-br from-primary/16 via-primary/7 to-background p-7 md:p-10">
          <div className="flex flex-col gap-6 md:flex-row md:items-end md:justify-between">
            <div className="space-y-3">
              <PlatformBrand />
              <h2 className="font-display text-2xl font-bold tracking-tight">{t("home.ctaSectionTitle")}</h2>
              <p className="max-w-2xl text-sm text-muted-foreground">{t("home.ctaSectionDesc")}</p>
              <a href="https://www.surpriseugc.com/" target="_blank" rel="noreferrer" className="inline-flex text-sm text-primary hover:underline">
                {t("brand.poweredBy")}
              </a>
              <p className="text-xs text-muted-foreground">{t("home.poweredByLine")}</p>
            </div>
            <Button size="lg" asChild>
              <Link to="/auth" className="gap-2">
                {t("home.ctaSectionBtn")}
                <ArrowRight className="h-4 w-4" />
              </Link>
            </Button>
          </div>
        </div>
      </section>

      <AuthGateDialog
        open={authGate.open}
        onOpenChange={(open) => setAuthGate((prev) => ({ ...prev, open }))}
        featureLabel={authGate.label}
      />
    </>
  );
}
