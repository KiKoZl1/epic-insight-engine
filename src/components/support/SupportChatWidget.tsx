import { useMemo, useState } from "react";
import { MessageCircle, X } from "lucide-react";
import { useQuery } from "@tanstack/react-query";
import { useLocation } from "react-router-dom";
import { useTranslation } from "react-i18next";
import { useAuth } from "@/hooks/useAuth";
import { useIsMobile } from "@/hooks/use-mobile";
import { Button } from "@/components/ui/button";
import { Drawer, DrawerContent, DrawerDescription, DrawerHeader, DrawerTitle, DrawerTrigger } from "@/components/ui/drawer";
import { cn } from "@/lib/utils";
import { SupportChat } from "@/components/support/SupportChat";
import { countPendingSupportTickets } from "@/lib/support/client";

export function SupportChatWidget() {
  const { t } = useTranslation();
  const location = useLocation();
  const { user } = useAuth();
  const isMobile = useIsMobile();
  const [open, setOpen] = useState(false);

  const shouldHide = useMemo(() => {
    const path = location.pathname;
    return path.startsWith("/auth") || path.startsWith("/admin");
  }, [location.pathname]);

  const pendingTicketsQuery = useQuery({
    queryKey: ["support_widget_pending_tickets", user?.id || "anon"],
    queryFn: async () => await countPendingSupportTickets(),
    enabled: Boolean(user),
    refetchInterval: 30_000,
    staleTime: 10_000,
  });

  if (!user || shouldHide) return null;

  const trigger = (
    <Button
      size="icon"
      className={cn(
        "group relative h-12 w-12 rounded-full border border-primary/35 bg-background/95 shadow-[0_10px_30px_rgba(0,0,0,0.35)]",
        open && "pointer-events-none opacity-0",
      )}
      aria-label={t("support.widget.open")}
    >
      <MessageCircle className="h-5 w-5 text-primary transition-transform group-hover:scale-105" />
      {(pendingTicketsQuery.data || 0) > 0 ? (
        <span className="absolute -right-0.5 -top-0.5 flex h-3 w-3">
          <span className="absolute inline-flex h-full w-full animate-ping rounded-full bg-amber-400 opacity-75" />
          <span className="relative inline-flex h-3 w-3 rounded-full bg-amber-400" />
        </span>
      ) : null}
    </Button>
  );

  return (
    <div className="fixed bottom-4 right-4 z-40 sm:bottom-6 sm:right-6">
      {isMobile ? (
        <Drawer open={open} onOpenChange={setOpen}>
          <DrawerTrigger asChild>{trigger}</DrawerTrigger>
          <DrawerContent className="max-h-[92vh] px-0 pb-0">
            <DrawerHeader className="px-4 pb-2 pt-4">
              <DrawerTitle>{t("support.widget.title")}</DrawerTitle>
              <DrawerDescription>{t("support.widget.description")}</DrawerDescription>
            </DrawerHeader>
            <div className="px-3 pb-3">
              <SupportChat mode="widget" allowAnonymous={false} className="h-[70vh] min-h-0" />
            </div>
          </DrawerContent>
        </Drawer>
      ) : (
        <>
          {open ? (
            <div className="absolute bottom-16 right-0 z-[96] w-[420px] max-w-[calc(100vw-2rem)]">
              <div className="relative rounded-2xl border border-border/70 bg-background/98 p-3 shadow-[0_20px_60px_rgba(0,0,0,0.45)] backdrop-blur-xl">
                <Button
                  size="icon"
                  variant="ghost"
                  type="button"
                  onClick={() => setOpen(false)}
                  aria-label="Close support chat"
                  className="absolute right-3 top-3 h-8 w-8 rounded-full border border-border/70"
                >
                  <X className="h-4 w-4" />
                </Button>
                <SupportChat mode="widget" allowAnonymous={false} className="h-[min(72vh,680px)] max-h-[calc(100dvh-8rem)] min-h-0" />
              </div>
            </div>
          ) : null}
          <div onClick={() => setOpen((prev) => !prev)}>{trigger}</div>
        </>
      )}
    </div>
  );
}
