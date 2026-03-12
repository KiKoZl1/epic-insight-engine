import { cn } from "@/lib/utils";

interface PlatformBrandProps {
  className?: string;
  iconClassName?: string;
  textClassName?: string;
  compact?: boolean;
}

export function PlatformBrand({ className, iconClassName, textClassName, compact = false }: PlatformBrandProps) {
  return (
    <div className={cn("flex items-center gap-2.5", className)}>
      <div
        className={cn(
          "relative flex h-9 w-9 items-center justify-center overflow-hidden rounded-xl border border-primary/35 bg-primary/[0.12] text-primary shadow-[0_0_0_1px_rgba(255,127,0,0.16)]",
          iconClassName,
        )}
        aria-hidden
      >
        <svg viewBox="0 0 24 24" className="h-5 w-5">
          <circle cx="12" cy="12" r="7.5" fill="none" stroke="currentColor" strokeOpacity="0.28" strokeWidth="1.2" />
          <circle cx="12" cy="12" r="3.2" fill="none" stroke="currentColor" strokeWidth="1.6" />
          <path d="M12 2.5V5.2M12 18.8V21.5M2.5 12H5.2M18.8 12H21.5" stroke="currentColor" strokeOpacity="0.6" strokeWidth="1.2" strokeLinecap="round" />
          <path d="M16.6 7.4l-1.8 1.8M7.4 16.6l1.8-1.8" stroke="currentColor" strokeOpacity="0.6" strokeWidth="1.2" strokeLinecap="round" />
          <path d="M8.6 6.6l8.8 8.8" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" />
        </svg>
      </div>
      {!compact ? (
        <span className={cn("font-display text-base font-bold tracking-tight sm:text-lg", textClassName)}>
          UEFN <span className="text-primary">Tools</span>
        </span>
      ) : null}
    </div>
  );
}
