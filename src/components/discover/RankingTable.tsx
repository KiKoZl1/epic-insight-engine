import { memo, useMemo } from "react";
import { LucideIcon } from "lucide-react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";

interface RankingItem {
  name: string;
  code?: string;
  value: number;
  label?: string;
  subtitle?: string;
  imageUrl?: string;
}

interface RankingTableProps {
  title: string;
  icon: LucideIcon;
  items: RankingItem[];
  valueFormatter?: (v: number) => string;
  barColor?: string;
  showImage?: boolean;
  showBadges?: boolean;
  onImageClick?: (src: string) => void;
}

const BADGE_STYLES = [
  { label: "1", cls: "bg-primary/20 text-primary border-primary/30" },
  { label: "2", cls: "bg-muted text-muted-foreground border-border" },
  { label: "3", cls: "bg-amber-500/15 text-amber-400 border-amber-500/30" },
];

function defaultFormatter(v: number): string {
  const n = Number(v);
  if (isNaN(n)) return "--";
  if (n >= 1_000_000) return (n / 1_000_000).toFixed(1) + "M";
  if (n >= 1_000) return (n / 1_000).toFixed(1) + "K";
  return n.toLocaleString("en-US");
}

function RankingTableBase({
  title,
  icon: Icon,
  items,
  valueFormatter = defaultFormatter,
  barColor = "bg-primary",
  showImage = false,
  showBadges = false,
  onImageClick,
}: RankingTableProps) {
  const safeItems = useMemo(() => (Array.isArray(items) ? items.slice(0, 10) : []), [items]);
  const maxVal = useMemo(
    () => (safeItems.length > 0 ? Math.max(...safeItems.map((i) => Number(i.value) || 0), 1) : 1),
    [safeItems],
  );

  if (safeItems.length === 0) return null;

  return (
    <Card className="border-border/50">
      <CardHeader className="pb-3">
        <CardTitle className="text-sm font-medium flex items-center gap-2">
          <Icon className="h-4 w-4 text-primary" />
          {title}
        </CardTitle>
      </CardHeader>
      <CardContent className="space-y-1.5">
        {safeItems.map((item, idx) => {
          const badge = showBadges && idx < 3 ? BADGE_STYLES[idx] : null;
          const itemValue = Number(item.value) || 0;
          const width = Math.max(0, Math.min(100, (itemValue / maxVal) * 100));

          return (
            <div
              key={idx}
              className="flex items-center gap-3 rounded-md px-2 py-1.5 hover:bg-secondary/50 transition-colors"
            >
              {badge ? (
                <span className={`flex items-center justify-center h-6 w-6 rounded-full border text-[10px] font-bold shrink-0 ${badge.cls}`}>
                  {badge.label}
                </span>
              ) : (
                <span className="text-[11px] font-mono text-muted-foreground w-6 text-center shrink-0">
                  {idx + 1}
                </span>
              )}
              {showImage && item.imageUrl && (
                <img
                  src={item.imageUrl}
                  alt=""
                  className={`h-8 w-8 rounded object-cover shrink-0 border border-border/30 ${onImageClick ? "cursor-pointer hover:ring-2 hover:ring-primary/40 transition-all" : ""}`}
                  loading="lazy"
                  onClick={onImageClick ? () => onImageClick(item.imageUrl!) : undefined}
                  onError={(e) => { (e.target as HTMLImageElement).style.display = "none"; }}
                />
              )}
              <div className="flex-1 min-w-0">
                <div className="flex items-center justify-between mb-0.5">
                  <div className="flex flex-col min-w-0 mr-2">
                    <span className="text-xs font-medium truncate">{item.name}</span>
                    {item.subtitle && (
                      <span className="text-[10px] text-muted-foreground truncate">{item.subtitle}</span>
                    )}
                  </div>
                  <span className="text-xs font-display font-semibold whitespace-nowrap text-primary">
                    {item.label || valueFormatter(itemValue)}
                  </span>
                </div>
                <div className="h-1 rounded-full bg-secondary overflow-hidden">
                  <div
                    className={`h-full rounded-full ${barColor} transition-all`}
                    style={{ width: `${width}%`, opacity: 0.7 }}
                  />
                </div>
              </div>
            </div>
          );
        })}
      </CardContent>
    </Card>
  );
}

export const RankingTable = memo(RankingTableBase);
