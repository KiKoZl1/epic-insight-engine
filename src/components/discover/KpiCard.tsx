import { LucideIcon, TrendingUp, TrendingDown } from "lucide-react";
import { Card, CardContent } from "@/components/ui/card";

interface KpiCardProps {
  icon: LucideIcon;
  label: string;
  value: string | number;
  change?: number | null;
  suffix?: string;
}

export function KpiCard({ icon: Icon, label, value, change, suffix }: KpiCardProps) {
  return (
    <Card>
      <CardContent className="pt-4 pb-3">
        <div className="flex items-center gap-2 mb-2">
          <Icon className="h-4 w-4 text-primary" />
          <span className="text-xs text-muted-foreground">{label}</span>
        </div>
        <p className="font-display font-bold text-xl">
          {value}{suffix}
        </p>
        {change != null && change !== 0 && (
          <div className={`flex items-center gap-1 text-xs mt-1 ${change > 0 ? "text-success" : "text-destructive"}`}>
            {change > 0 ? <TrendingUp className="h-3 w-3" /> : <TrendingDown className="h-3 w-3" />}
            <span>{change > 0 ? "+" : ""}{change.toFixed(1)}%</span>
          </div>
        )}
      </CardContent>
    </Card>
  );
}
