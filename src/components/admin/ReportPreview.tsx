import { KpiCard } from "@/components/discover/KpiCard";
import { RankingTable } from "@/components/discover/RankingTable";
import { SectionHeader } from "@/components/discover/SectionHeader";
import { AiNarrative } from "@/components/discover/AiNarrative";
import { Activity, BarChart3, Clock, Layers, Map as MapIcon, Play, Sparkles, Star, Target, ThumbsUp, TrendingDown, TrendingUp, UserPlus, Users } from "lucide-react";
import ReactMarkdown from "react-markdown";

interface ReportPreviewProps {
  report: {
    title_public?: string | null;
    subtitle_public?: string | null;
    editor_note?: string | null;
    date_from: string;
    date_to: string;
    week_key: string;
    cover_image_url?: string | null;
    kpis_json?: any;
    rankings_json?: any;
    ai_sections_json?: any;
    editor_sections_json?: any;
  };
  liveEditorSections?: Record<string, string>;
  liveTitlePublic?: string;
  liveSubtitlePublic?: string;
  liveEditorNote?: string;
  liveCoverUrl?: string;
}

function fmt(n: number | null | undefined): string {
  if (n == null) return "-";
  const num = Number(n);
  if (Number.isNaN(num)) return "-";
  if (num >= 1_000_000) return (num / 1_000_000).toFixed(1) + "M";
  if (num >= 1_000) return (num / 1_000).toFixed(1) + "K";
  if (Number.isInteger(num)) return num.toLocaleString("en-US");
  return num.toFixed(2);
}

function pct(n: number | null | undefined): string {
  if (n == null) return "-";
  return (Number(n) * 100).toFixed(1) + "%";
}

const SECTION_TITLES: Record<number, string> = {
  1: "Core Activity Overview",
  2: "Trending Topics",
  3: "Player Engagement Volume",
  4: "Peak CCU",
  5: "New Islands of the Week",
  6: "Retention & Loyalty",
  7: "Creator Performance",
  8: "Map Quality",
  9: "Low Performance Analysis",
  10: "Plays per Player",
  11: "Advocacy Metrics",
  12: "Efficiency & Conversion",
  13: "Stickiness (D1/D7)",
  14: "Retention-Adjusted Engagement",
  15: "Category & Tags",
  16: "Weekly Growth / Breakouts",
  17: "Risers & Decliners",
  18: "Island Lifecycle",
  19: "Discovery Exposure",
  20: "Multi-Panel Presence",
  21: "Panel Loyalty",
  22: "Most Updated Islands",
  23: "Rookie Creators",
  24: "Player Capacity Analysis",
  25: "UEFN vs Fortnite Creative",
  26: "Category & Genre Movement",
  27: "Creator Movement & Ranking Changes",
};

function toTableItems(rows: any[] | undefined | null): any[] {
  if (!Array.isArray(rows)) return [];
  return rows.map((r: any) => ({
    name: r?.name || r?.title || r?.creator || r?.category || r?.panelName || r?.code || r?.linkCode || "N/A",
    code: r?.code || r?.island_code || r?.linkCode || undefined,
    value:
      r?.value ??
      r?.plays ??
      r?.minutesExposed ??
      r?.deltaPlays ??
      r?.pctChange ??
      r?.rankChange ??
      r?.avgRank ??
      0,
    image_url: r?.image_url || r?.imageUrl || undefined,
  }));
}

function sectionIcon(section: number) {
  if (section === 2) return TrendingUp;
  if (section === 4) return BarChart3;
  if (section === 5) return Sparkles;
  if (section === 6) return Target;
  if (section === 7) return Users;
  if (section === 8) return Clock;
  if (section === 9) return TrendingDown;
  if (section === 11) return Star;
  if (section === 12) return ThumbsUp;
  if (section === 19) return Layers;
  if (section === 23) return UserPlus;
  return Activity;
}

function sectionData(section: number, rankings: any) {
  const exposure = rankings?.discoveryExposure || null;
  const topNew = rankings?.topNewIslandsByPlaysPublished || rankings?.topNewIslandsByPlays || [];

  switch (section) {
    case 2:
      return (
        <div className="grid md:grid-cols-2 gap-4 mb-4">
          <RankingTable title="Trending Topics" icon={TrendingUp} items={toTableItems(rankings?.trendingTopics).slice(0, 12)} />
        </div>
      );
    case 3:
      return (
        <div className="grid md:grid-cols-2 gap-4 mb-4">
          <RankingTable title="Top Plays" icon={Play} items={toTableItems(rankings?.topTotalPlays).slice(0, 12)} />
          <RankingTable title="Top Unique Players" icon={Users} items={toTableItems(rankings?.topUniquePlayers).slice(0, 12)} />
        </div>
      );
    case 4:
      return (
        <div className="grid md:grid-cols-2 gap-4 mb-4">
          <RankingTable title="Top Peak CCU" icon={BarChart3} items={toTableItems(rankings?.topPeakCCU).slice(0, 12)} />
          <RankingTable title="Top Peak CCU (UGC)" icon={BarChart3} items={toTableItems(rankings?.topPeakCCU_UGC).slice(0, 12)} />
        </div>
      );
    case 5:
      return (
        <div className="grid md:grid-cols-2 gap-4 mb-4">
          <RankingTable title="Top New by Plays" icon={Play} items={toTableItems(topNew).slice(0, 12)} />
          <RankingTable title="Top New by CCU" icon={BarChart3} items={toTableItems(rankings?.topNewIslandsByCCU).slice(0, 12)} />
        </div>
      );
    case 6:
      return (
        <div className="grid md:grid-cols-2 gap-4 mb-4">
          <RankingTable title="Top D1 Retention" icon={Target} items={toTableItems(rankings?.topRetentionD1).slice(0, 12)} valueFormatter={(v) => pct(Number(v))} />
          <RankingTable title="Top D7 Retention" icon={Target} items={toTableItems(rankings?.topRetentionD7).slice(0, 12)} valueFormatter={(v) => pct(Number(v))} />
        </div>
      );
    case 7:
      return (
        <div className="grid md:grid-cols-2 gap-4 mb-4">
          <RankingTable title="Top Creators by Plays" icon={Play} items={toTableItems(rankings?.topCreatorsByPlays).slice(0, 12)} />
          <RankingTable title="Top Creators by Minutes" icon={Clock} items={toTableItems(rankings?.topCreatorsByMinutes).slice(0, 12)} />
        </div>
      );
    case 8:
      return (
        <div className="grid md:grid-cols-2 gap-4 mb-4">
          <RankingTable title="Top Avg Minutes per Player" icon={Clock} items={toTableItems(rankings?.topAvgMinutesPerPlayer).slice(0, 12)} />
          <RankingTable title="Top Minutes Played" icon={Clock} items={toTableItems(rankings?.topMinutesPlayed).slice(0, 12)} />
        </div>
      );
    case 9:
      return (
        <div className="grid md:grid-cols-2 gap-4 mb-4">
          <RankingTable title="Low Performance Islands" icon={TrendingDown} items={toTableItems(rankings?.failedIslandsList).slice(0, 12)} />
        </div>
      );
    case 10:
      return <div className="mb-4"><RankingTable title="Plays per Player" icon={Target} items={toTableItems(rankings?.topPlaysPerPlayer).slice(0, 12)} /></div>;
    case 11:
      return (
        <div className="grid md:grid-cols-2 gap-4 mb-4">
          <RankingTable title="Favorites per 100" icon={Star} items={toTableItems(rankings?.topFavsPer100).slice(0, 12)} />
          <RankingTable title="Recommendations per 100" icon={ThumbsUp} items={toTableItems(rankings?.topRecPer100).slice(0, 12)} />
        </div>
      );
    case 12:
      return (
        <div className="grid md:grid-cols-2 gap-4 mb-4">
          <RankingTable title="Favorites per Play" icon={Star} items={toTableItems(rankings?.topFavsPerPlay).slice(0, 12)} />
          <RankingTable title="Recommendations per Play" icon={ThumbsUp} items={toTableItems(rankings?.topRecsPerPlay).slice(0, 12)} />
        </div>
      );
    case 13:
      return (
        <div className="grid md:grid-cols-2 gap-4 mb-4">
          <RankingTable title="Stickiness D1" icon={Target} items={toTableItems(rankings?.topStickinessD1).slice(0, 12)} />
          <RankingTable title="Stickiness D7" icon={Target} items={toTableItems(rankings?.topStickinessD7).slice(0, 12)} />
        </div>
      );
    case 14:
      return (
        <div className="grid md:grid-cols-2 gap-4 mb-4">
          <RankingTable title="Retention-Adjusted D1" icon={Target} items={toTableItems(rankings?.topRetentionAdjD1).slice(0, 12)} />
          <RankingTable title="Retention-Adjusted D7" icon={Target} items={toTableItems(rankings?.topRetentionAdjD7).slice(0, 12)} />
        </div>
      );
    case 15:
      return (
        <div className="space-y-4 mb-4">
          <div className="grid md:grid-cols-2 gap-4">
            <RankingTable title="Top Categories by Plays" icon={MapIcon} items={toTableItems(rankings?.topCategoriesByPlays).slice(0, 12)} />
            <RankingTable title="Top Tags" icon={Layers} items={toTableItems(rankings?.topTags).slice(0, 12)} />
          </div>
          {Array.isArray(rankings?.partnerSignals) && rankings.partnerSignals.length > 0 && (
            <div className="grid md:grid-cols-1 gap-4">
              <RankingTable
                title="Section 15.5 - Partner Signals (Aggregated)"
                icon={Layers}
                items={toTableItems((rankings.partnerSignals || []).map((s: any) => ({
                  name: s.projectName || s.codename || "Partner Signal",
                  value: s.plays || 0,
                  subtitle: `codename: ${s.codename || "n/a"} - islands: ${s.islands || 0}`,
                }))).slice(0, 12)}
              />
            </div>
          )}
        </div>
      );
    case 16:
    case 17:
      return (
        <div className="grid md:grid-cols-2 gap-4 mb-4">
          <RankingTable title="Top Risers" icon={TrendingUp} items={toTableItems(rankings?.topRisers).slice(0, 12)} />
          <RankingTable title="Top Decliners" icon={TrendingDown} items={toTableItems(rankings?.topDecliners).slice(0, 12)} />
        </div>
      );
    case 18:
      return (
        <div className="grid md:grid-cols-2 gap-4 mb-4">
          <RankingTable title="Revived Islands" icon={TrendingUp} items={toTableItems(rankings?.revivedIslands).slice(0, 12)} />
          <RankingTable title="Dead Islands" icon={TrendingDown} items={toTableItems(rankings?.deadIslands).slice(0, 12)} />
        </div>
      );
    case 19:
      return (
        <div className="grid md:grid-cols-2 gap-4 mb-4">
          <RankingTable title="Exposure Top by Panel" icon={Clock} items={toTableItems(exposure?.topByPanel).slice(0, 12)} />
          <RankingTable title="Exposure Panel Summaries" icon={Layers} items={toTableItems(exposure?.panelSummaries).slice(0, 12)} />
        </div>
      );
    case 20:
      return <div className="mb-4"><RankingTable title="Multi-Panel Presence" icon={Layers} items={toTableItems(rankings?.multiPanelPresence).slice(0, 12)} /></div>;
    case 21:
      return <div className="mb-4"><RankingTable title="Panel Loyalty" icon={Target} items={toTableItems(rankings?.panelLoyalty).slice(0, 12)} /></div>;
    case 22:
      return (
        <div className="grid md:grid-cols-2 gap-4 mb-4">
          <RankingTable title="Most Updated (Total Version)" icon={Sparkles} items={toTableItems(rankings?.mostUpdatedIslandsThisWeek).slice(0, 12)} />
          <RankingTable title="Most Updated (Weekly Updates)" icon={Sparkles} items={toTableItems(rankings?.mostUpdatedIslandsWeekly).slice(0, 12)} />
        </div>
      );
    case 23:
      return <div className="mb-4"><RankingTable title="Rookie Creators" icon={UserPlus} items={toTableItems(rankings?.rookieCreators).slice(0, 12)} /></div>;
    case 24:
      return <div className="mb-4"><RankingTable title="Capacity Analysis" icon={Users} items={toTableItems(rankings?.capacityAnalysis).slice(0, 12)} /></div>;
    case 25:
      return <div className="mb-4"><RankingTable title="Tool Split" icon={MapIcon} items={toTableItems(rankings?.toolSplit).slice(0, 12)} /></div>;
    case 26:
      return (
        <div className="grid md:grid-cols-2 gap-4 mb-4">
          <RankingTable title="Category Risers" icon={TrendingUp} items={toTableItems(rankings?.categoryRisers).slice(0, 12)} />
          <RankingTable title="Category Decliners" icon={TrendingDown} items={toTableItems(rankings?.categoryDecliners).slice(0, 12)} />
        </div>
      );
    case 27:
      return (
        <div className="grid md:grid-cols-2 gap-4 mb-4">
          <RankingTable title="Creator Risers" icon={TrendingUp} items={toTableItems(rankings?.creatorRisers).slice(0, 12)} />
          <RankingTable title="Creator Decliners" icon={TrendingDown} items={toTableItems(rankings?.creatorDecliners).slice(0, 12)} />
        </div>
      );
    default:
      return null;
  }
}

export function ReportPreview({
  report,
  liveEditorSections,
  liveTitlePublic,
  liveSubtitlePublic,
  liveEditorNote,
  liveCoverUrl,
}: ReportPreviewProps) {
  const kpis = report.kpis_json || {};
  const rankings = report.rankings_json || {};
  const aiSections = report.ai_sections_json || {};
  const editorSections = liveEditorSections ?? report.editor_sections_json ?? {};

  const titlePublic = liveTitlePublic ?? report.title_public;
  const subtitlePublic = liveSubtitlePublic ?? report.subtitle_public;
  const editorNote = liveEditorNote ?? report.editor_note;
  const coverUrl = liveCoverUrl ?? (report as any).cover_image_url;

  const getNarrative = (sectionNum: number): string | null => {
    const edited = editorSections[`section${sectionNum}`];
    if (edited) return edited;
    const ai = aiSections[`section${sectionNum}`];
    return ai?.narrative || null;
  };

  const getTitle = (sectionNum: number): string => {
    const ai = aiSections[`section${sectionNum}`];
    return ai?.title || SECTION_TITLES[sectionNum] || `Section ${sectionNum}`;
  };

  return (
    <div className="pb-20">
      {coverUrl && (
        <div className="rounded-xl overflow-hidden mb-6 max-h-64">
          <img src={coverUrl} alt="Report cover" className="w-full h-64 object-cover" />
        </div>
      )}

      <div className="mb-6">
        <h1 className="font-display text-3xl font-bold">{titlePublic || report.week_key}</h1>
        {subtitlePublic && <p className="text-muted-foreground mt-1">{subtitlePublic}</p>}
        <p className="text-sm text-muted-foreground mt-1">
          {new Date(report.date_from).toLocaleDateString("en-US")} - {new Date(report.date_to).toLocaleDateString("en-US")}
        </p>
      </div>

      {editorNote && (
        <div className="rounded-xl border border-accent/30 bg-accent/5 p-6 mb-8">
          <p className="text-xs font-semibold text-accent uppercase tracking-wider mb-2">Editor Note</p>
          <div className="prose prose-sm max-w-none text-foreground/80">
            <ReactMarkdown>{editorNote}</ReactMarkdown>
          </div>
        </div>
      )}

      <SectionHeader icon={Activity} number={1} title={getTitle(1)} description="Snapshot of current report data" />
      <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-5 gap-3 mb-4">
        <KpiCard icon={MapIcon} label="Total Islands" value={fmt(kpis.totalIslands)} />
        <KpiCard icon={Activity} label="Active Islands" value={fmt(kpis.activeIslands)} />
        <KpiCard icon={Users} label="Creators" value={fmt(kpis.totalCreators)} />
        <KpiCard icon={Sparkles} label="New Maps" value={fmt(kpis.newMapsThisWeekPublished ?? kpis.newMapsThisWeek)} />
        <KpiCard icon={UserPlus} label="New Creators" value={fmt(kpis.newCreatorsThisWeek)} />
      </div>
      <div className="grid grid-cols-2 sm:grid-cols-4 gap-3 mb-4">
        <KpiCard icon={Play} label="Total Plays" value={fmt(kpis.totalPlays)} />
        <KpiCard icon={Clock} label="Total Minutes" value={fmt(kpis.totalMinutesPlayed)} />
        <KpiCard icon={Target} label="Avg D1" value={pct(kpis.avgRetentionD1)} />
        <KpiCard icon={Target} label="Avg D7" value={pct(kpis.avgRetentionD7)} />
      </div>
      <AiNarrative text={getNarrative(1)} />

      {Array.from({ length: 26 }, (_, i) => i + 2).map((sectionNum) => {
        const narrative = getNarrative(sectionNum);
        const dataNode = sectionData(sectionNum, rankings);
        if (!narrative && !dataNode) return null;

        return (
          <div key={sectionNum}>
            <div className="border-t border-border my-8" />
            <SectionHeader
              icon={sectionIcon(sectionNum)}
              number={sectionNum}
              title={getTitle(sectionNum)}
              description="Preview based on current weekly_reports payload"
            />
            {dataNode}
            <AiNarrative text={narrative} />
          </div>
        );
      })}
    </div>
  );
}
