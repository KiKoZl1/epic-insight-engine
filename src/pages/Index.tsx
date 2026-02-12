import { Link } from "react-router-dom";
import { Button } from "@/components/ui/button";
import { BarChart3, Upload, Brain, TrendingUp, Search, Zap } from "lucide-react";

const tools = [
  {
    icon: Upload,
    title: "Island Analytics",
    desc: "Faça upload do ZIP exportado da Epic e receba análise completa com IA, diagnósticos e plano de ação.",
    cta: "Analisar Ilha",
  },
  {
    icon: TrendingUp,
    title: "Discover Trends",
    desc: "Relatórios semanais automáticos do ecossistema Discovery: rankings, retenção, categorias e tendências.",
    cta: "Ver Trends",
  },
  {
    icon: Search,
    title: "Island Lookup",
    desc: "Pesquise qualquer ilha pública por código e veja métricas em tempo real direto da API da Epic.",
    cta: "Pesquisar Ilha",
  },
];

const features = [
  { icon: BarChart3, title: "Dashboard Visual", desc: "Gráficos, rankings e KPIs visuais — nada de só texto." },
  { icon: Brain, title: "IA Analista", desc: "Narrativas e diagnósticos gerados por IA para cada seção." },
  { icon: Zap, title: "Dados em Tempo Real", desc: "API pública da Epic integrada para métricas live." },
];

export default function Index() {
  return (
    <div className="min-h-screen bg-background">
      {/* Nav */}
      <nav className="flex items-center justify-between px-6 py-4 max-w-6xl mx-auto">
        <div className="flex items-center gap-2">
          <div className="flex h-9 w-9 items-center justify-center rounded-lg bg-primary">
            <BarChart3 className="h-5 w-5 text-primary-foreground" />
          </div>
          <span className="font-display text-lg font-bold">FN Analytics</span>
        </div>
        <div className="flex gap-3">
          <Button variant="ghost" asChild>
            <Link to="/auth">Entrar</Link>
          </Button>
          <Button asChild>
            <Link to="/auth">Começar Grátis</Link>
          </Button>
        </div>
      </nav>

      {/* Hero */}
      <section className="px-6 pt-20 pb-16 max-w-4xl mx-auto text-center">
        <div className="inline-flex items-center gap-2 rounded-full border px-4 py-1.5 text-sm text-muted-foreground mb-6">
          <Brain className="h-4 w-4 text-primary" />
          Plataforma completa de Analytics para Fortnite Discovery
        </div>
        <h1 className="font-display text-4xl sm:text-5xl lg:text-6xl font-bold leading-tight tracking-tight mb-6">
          Dados, trends e insights para{" "}
          <span className="text-primary">criadores de Fortnite</span>
        </h1>
        <p className="text-lg text-muted-foreground max-w-2xl mx-auto mb-8">
          Analise suas ilhas, acompanhe o ecossistema Discovery e pesquise qualquer mapa — tudo com gráficos visuais e análise por IA.
        </p>
        <div className="flex gap-4 justify-center">
          <Button size="lg" asChild>
            <Link to="/auth">Começar Agora</Link>
          </Button>
        </div>
      </section>

      {/* Tools */}
      <section className="px-6 py-16 max-w-6xl mx-auto">
        <h2 className="font-display text-3xl font-bold text-center mb-10">3 Ferramentas Poderosas</h2>
        <div className="grid md:grid-cols-3 gap-6">
          {tools.map((t) => (
            <div key={t.title} className="rounded-xl border bg-card p-6 hover:shadow-lg transition-shadow flex flex-col">
              <div className="flex h-12 w-12 items-center justify-center rounded-lg bg-primary/10 mb-4">
                <t.icon className="h-6 w-6 text-primary" />
              </div>
              <h3 className="font-display font-semibold text-xl mb-2">{t.title}</h3>
              <p className="text-sm text-muted-foreground flex-1">{t.desc}</p>
              <Button className="mt-4 w-full" variant="outline" asChild>
                <Link to="/auth">{t.cta}</Link>
              </Button>
            </div>
          ))}
        </div>
      </section>

      {/* Features */}
      <section className="px-6 py-16 max-w-6xl mx-auto">
        <div className="grid sm:grid-cols-3 gap-6">
          {features.map((f) => (
            <div key={f.title} className="text-center">
              <div className="flex h-10 w-10 items-center justify-center rounded-lg bg-primary/10 mx-auto mb-3">
                <f.icon className="h-5 w-5 text-primary" />
              </div>
              <h3 className="font-display font-semibold mb-1">{f.title}</h3>
              <p className="text-sm text-muted-foreground">{f.desc}</p>
            </div>
          ))}
        </div>
      </section>

      {/* CTA */}
      <section className="px-6 py-20">
        <div className="max-w-3xl mx-auto rounded-2xl bg-primary p-10 text-center text-primary-foreground">
          <h2 className="font-display text-3xl font-bold mb-4">
            Pronto para dominar o Discovery?
          </h2>
          <p className="text-primary-foreground/80 mb-6">
            Crie sua conta e acesse todas as ferramentas gratuitamente.
          </p>
          <Button size="lg" variant="secondary" asChild>
            <Link to="/auth">Criar Conta Grátis</Link>
          </Button>
        </div>
      </section>

      {/* Footer */}
      <footer className="px-6 py-8 border-t text-center text-sm text-muted-foreground">
        © 2026 FN Analytics. Feito para criadores de Fortnite.
      </footer>
    </div>
  );
}
