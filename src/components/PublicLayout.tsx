import { Outlet, Link } from "react-router-dom";
import { useTranslation } from "react-i18next";
import { TopBar } from "@/components/navigation/TopBar";
import { PlatformBrand } from "@/components/brand/PlatformBrand";
import { BRAND_CANONICAL_URL } from "@/config/brand";

export default function PublicLayout() {
  const { t } = useTranslation();

  return (
    <div className="min-h-screen bg-background flex flex-col">
      <TopBar context="public" />

      <main className="flex-1">
        <Outlet />
      </main>

      <footer className="px-6 py-8 border-t border-border/50">
        <div className="max-w-7xl mx-auto flex flex-col sm:flex-row items-center justify-between gap-4">
          <PlatformBrand iconClassName="h-7 w-7" textClassName="text-sm" />
          <p className="text-xs text-muted-foreground">{t("footer.copyright")}</p>
          <div className="flex flex-wrap items-center justify-center gap-4 text-xs text-muted-foreground">
            <Link to="/reports" className="hover:text-foreground transition-colors">{t("nav.reports")}</Link>
            <Link to="/discover" className="hover:text-foreground transition-colors">{t("nav.discover")}</Link>
            <a href={BRAND_CANONICAL_URL} target="_blank" rel="noreferrer" className="hover:text-foreground transition-colors">
              {t("brand.poweredBy")}
            </a>
          </div>
        </div>
      </footer>
    </div>
  );
}
