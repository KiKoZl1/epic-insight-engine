import { Sparkles } from "lucide-react";
import { Card, CardContent } from "@/components/ui/card";
import ReactMarkdown from "react-markdown";

interface AiNarrativeProps {
  text: string | null | undefined;
}

export function AiNarrative({ text }: AiNarrativeProps) {
  if (!text) return null;

  return (
    <Card className="border-primary/20 bg-primary/5">
      <CardContent className="pt-4">
        <div className="flex items-center gap-2 mb-3">
          <Sparkles className="h-4 w-4 text-primary" />
          <span className="text-xs font-semibold text-primary uppercase tracking-wider">Análise IA</span>
        </div>
        <div className="prose prose-sm max-w-none text-foreground/80">
          <ReactMarkdown>{text}</ReactMarkdown>
        </div>
      </CardContent>
    </Card>
  );
}
