import { useQuery } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import type { IslandPageResponse } from "@/types/discover-island-page";

const DISCOVERY_SURFACE = "CreativeDiscoverySurface_Frontend";

export interface PublicReportRow {
  id: string;
  week_key: string;
  public_slug: string;
  title_public: string | null;
  subtitle_public: string | null;
  date_from: string;
  date_to: string;
  kpis_json: unknown;
  published_at: string | null;
}

export function usePublicReportsQuery() {
  return useQuery({
    queryKey: ["public-reports"],
    queryFn: async () => {
      const { data, error } = await supabase
        .from("weekly_reports")
        .select("*")
        .eq("status", "published")
        .order("date_from", { ascending: false });

      if (error) throw error;
      return (data || []) as PublicReportRow[];
    },
    staleTime: 5 * 60 * 1000,
  });
}

export interface DiscoveryLivePayload {
  premium: unknown[];
  emerging: unknown[];
  pollution: unknown[];
  rails: unknown[];
}

export function useDiscoverLiveQuery(region: string) {
  return useQuery({
    queryKey: ["discover-live", region],
    queryFn: async () => {
      const [premiumRes, emergingRes, pollutionRes, railsRes] = await Promise.all([
        supabase.from("discovery_public_premium_now").select("*").limit(5000),
        supabase.from("discovery_public_emerging_now").select("*").limit(5000),
        supabase.from("discovery_public_pollution_creators_now").select("*").limit(2000),
        supabase.functions.invoke("discover-rails-resolver", {
          body: {
            region,
            surfaceName: DISCOVERY_SURFACE,
            maxPanels: 40,
            maxItemsPerPanel: 60,
            maxChildrenPerCollection: 24,
            includeChildren: true,
          },
        }),
      ]);

      if (premiumRes.error) throw premiumRes.error;
      if (emergingRes.error) throw emergingRes.error;
      if (pollutionRes.error) throw pollutionRes.error;
      if (railsRes.error) throw railsRes.error;

      const railsPayload = railsRes.data as { rails?: unknown[] } | null;

      return {
        premium: premiumRes.data || [],
        emerging: emergingRes.data || [],
        pollution: pollutionRes.data || [],
        rails: Array.isArray(railsPayload?.rails) ? railsPayload.rails : [],
      } as DiscoveryLivePayload;
    },
    refetchInterval: 60_000,
    staleTime: 30_000,
    placeholderData: (prev) => prev,
  });
}

export function useIslandPageQuery(islandCode: string, enabled: boolean) {
  return useQuery({
    queryKey: ["island-page", islandCode],
    queryFn: async () => {
      const { data: payload, error } = await supabase.functions.invoke("discover-island-page", {
        body: { islandCode, region: "NAE", surfaceName: DISCOVERY_SURFACE },
      });
      if (error) throw error;
      if (payload?.error) throw new Error(String(payload.error));
      return payload as IslandPageResponse;
    },
    enabled,
    refetchInterval: 60_000,
    staleTime: 30_000,
    placeholderData: (prev) => prev,
  });
}
