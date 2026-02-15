import { useEffect, useMemo, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Loader2, RefreshCw } from "lucide-react";

export default function AdminIntel() {
  const [loading, setLoading] = useState(true);
  const [asOf, setAsOf] = useState<string | null>(null);
  const [premiumCount, setPremiumCount] = useState<number>(0);
  const [emergingCount, setEmergingCount] = useState<number>(0);
  const [pollutionCount, setPollutionCount] = useState<number>(0);
  const [refreshing, setRefreshing] = useState(false);
  const [lastResult, setLastResult] = useState<any>(null);

  async function loadCounts() {
    setLoading(true);
    const [p, e, pol] = await Promise.all([
      (supabase as any).from("discovery_public_premium_now").select("as_of", { count: "exact", head: false }).limit(1),
      (supabase as any).from("discovery_public_emerging_now").select("as_of", { count: "exact", head: false }).limit(1),
      (supabase as any).from("discovery_public_pollution_creators_now").select("as_of", { count: "exact", head: false }).limit(1),
    ]);
    setPremiumCount(p.count || 0);
    setEmergingCount(e.count || 0);
    setPollutionCount(pol.count || 0);
    setAsOf(p.data?.[0]?.as_of || e.data?.[0]?.as_of || pol.data?.[0]?.as_of || null);
    setLoading(false);
  }

  async function refreshNow() {
    setRefreshing(true);
    const { data, error } = await supabase.functions.invoke("discover-exposure-collector", {
      body: { mode: "intel_refresh" },
    });
    if (!error) setLastResult(data);
    await loadCounts();
    setRefreshing(false);
  }

  useEffect(() => {
    loadCounts();
    const t = setInterval(loadCounts, 60_000);
    return () => clearInterval(t);
  }, []);

  const asOfLabel = useMemo(() => {
    if (!asOf) return "—";
    return new Date(asOf).toLocaleString("pt-BR");
  }, [asOf]);

  if (loading) {
    return (
      <div className="flex justify-center py-20">
        <Loader2 className="h-8 w-8 animate-spin text-primary" />
      </div>
    );
  }

  return (
    <div className="px-6 py-10 max-w-6xl mx-auto space-y-6">
      <div className="flex items-start justify-between gap-3">
        <div>
          <h1 className="font-display text-2xl font-bold">Intel</h1>
          <p className="text-muted-foreground mt-1 text-sm">
            Snapshots públicos (Premium Now, Emerging, Pollution). Atualiza via cron a cada 5 min.
          </p>
        </div>
        <Button onClick={refreshNow} disabled={refreshing} className="gap-2">
          {refreshing ? <Loader2 className="h-4 w-4 animate-spin" /> : <RefreshCw className="h-4 w-4" />}
          Refresh agora
        </Button>
      </div>

      <div className="flex flex-wrap gap-2">
        <Badge variant="secondary" className="font-mono">as_of: {asOfLabel}</Badge>
        <Badge variant="secondary" className="font-mono">premium_rows: {premiumCount}</Badge>
        <Badge variant="secondary" className="font-mono">emerging_rows: {emergingCount}</Badge>
        <Badge variant="secondary" className="font-mono">pollution_rows: {pollutionCount}</Badge>
      </div>

      {lastResult && (
        <Card>
          <CardHeader className="pb-3">
            <CardTitle className="text-sm font-medium">Último refresh (resultado)</CardTitle>
          </CardHeader>
          <CardContent>
            <pre className="text-xs whitespace-pre-wrap bg-muted/40 border rounded-md p-3 overflow-auto">
              {JSON.stringify(lastResult, null, 2)}
            </pre>
          </CardContent>
        </Card>
      )}

      <Card>
        <CardHeader className="pb-3">
          <CardTitle className="text-sm font-medium">Notas</CardTitle>
        </CardHeader>
        <CardContent className="text-sm text-muted-foreground space-y-2">
          <p>
            Estes snapshots são publicáveis porque ficam em tabelas dedicadas com RLS permitindo SELECT público, sem expor
            os dados internos de Exposure (ticks/raw/segments).
          </p>
          <p>
            Se quiser limitar abuso, dá para exigir um header/token interno no modo <span className="font-mono">intel_refresh</span>{" "}
            e colocar esse token só no cron. Hoje o refresh é barato (tabelas pequenas), mas é uma melhoria fácil.
          </p>
        </CardContent>
      </Card>
    </div>
  );
}

