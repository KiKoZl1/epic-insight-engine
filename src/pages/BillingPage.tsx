import { useEffect, useState } from "react";
import { CreditCard, Loader2, Wallet } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { useToast } from "@/hooks/use-toast";
import {
  createPackCheckout,
  createSubscriptionCheckout,
  getCommerceCredits,
  listCreditPacks,
} from "@/lib/commerce/client";

type Pack = { pack_code: "pack_250" | "pack_650" | "pack_1400"; credits: number };

export default function BillingPage() {
  const { toast } = useToast();
  const [loading, setLoading] = useState(true);
  const [checkingOut, setCheckingOut] = useState<string>("");
  const [credits, setCredits] = useState<any>(null);
  const [packs, setPacks] = useState<Pack[]>([]);

  async function load() {
    setLoading(true);
    try {
      const [creditRes, packRes] = await Promise.all([getCommerceCredits(), listCreditPacks()]);
      setCredits(creditRes);
      setPacks(Array.isArray(packRes?.packs) ? packRes.packs : []);
    } catch (error) {
      toast({
        title: "Erro",
        description: String((error as Error)?.message || "Falha ao carregar billing."),
        variant: "destructive",
      });
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => {
    void load();
  }, []);

  async function startSubscriptionCheckout() {
    setCheckingOut("subscription");
    try {
      const data = await createSubscriptionCheckout();
      const checkoutUrl = String(data?.checkout_url || "");
      if (!checkoutUrl) throw new Error("checkout_url_missing");
      window.location.href = checkoutUrl;
    } catch (error) {
      toast({
        title: "Erro",
        description: String((error as Error)?.message || "Falha ao iniciar checkout."),
        variant: "destructive",
      });
    } finally {
      setCheckingOut("");
    }
  }

  async function startPackCheckout(packCode: Pack["pack_code"]) {
    setCheckingOut(packCode);
    try {
      const data = await createPackCheckout(packCode);
      const checkoutUrl = String(data?.checkout_url || "");
      if (!checkoutUrl) throw new Error("checkout_url_missing");
      window.location.href = checkoutUrl;
    } catch (error) {
      toast({
        title: "Erro",
        description: String((error as Error)?.message || "Falha ao iniciar checkout do pacote."),
        variant: "destructive",
      });
    } finally {
      setCheckingOut("");
    }
  }

  if (loading) {
    return (
      <div className="mx-auto max-w-4xl p-6">
        <div className="flex items-center gap-2 text-sm text-muted-foreground">
          <Loader2 className="h-4 w-4 animate-spin" />
          Carregando billing...
        </div>
      </div>
    );
  }

  const wallet = credits?.wallet || {};
  const account = credits?.account || {};
  const isPro = String(account.plan_type || "free") === "pro";

  return (
    <div className="mx-auto max-w-5xl space-y-6 p-6">
      <header className="space-y-1">
        <h1 className="font-display text-3xl font-bold">Billing & Creditos</h1>
        <p className="text-sm text-muted-foreground">Gestao de plano, saldo e compra de creditos extras.</p>
      </header>

      <div className="grid gap-4 md:grid-cols-3">
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-base">Weekly Wallet</CardTitle>
          </CardHeader>
          <CardContent className="text-3xl font-bold">{Number(wallet.weekly_wallet || 0)}</CardContent>
        </Card>
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-base">Monthly Pool</CardTitle>
          </CardHeader>
          <CardContent className="text-3xl font-bold">{Number(wallet.monthly_plan_remaining || 0)}</CardContent>
        </Card>
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-base">Extra Wallet</CardTitle>
          </CardHeader>
          <CardContent className="text-3xl font-bold">{Number(wallet.extra_wallet || 0)}</CardContent>
        </Card>
      </div>

      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2 text-lg">
            <CreditCard className="h-5 w-5" />
            Plano
          </CardTitle>
        </CardHeader>
        <CardContent className="space-y-4">
          <p className="text-sm">
            Plano atual: <span className="font-semibold uppercase">{String(account.plan_type || "free")}</span>
          </p>
          {!isPro ? (
            <Button onClick={startSubscriptionCheckout} disabled={checkingOut === "subscription"}>
              {checkingOut === "subscription" ? <Loader2 className="mr-2 h-4 w-4 animate-spin" /> : null}
              Assinar Plano Pro
            </Button>
          ) : (
            <p className="text-sm text-muted-foreground">Plano Pro ativo.</p>
          )}
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2 text-lg">
            <Wallet className="h-5 w-5" />
            Pacotes de Creditos Extras
          </CardTitle>
        </CardHeader>
        <CardContent className="grid gap-3 md:grid-cols-3">
          {packs.map((pack) => (
            <div key={pack.pack_code} className="rounded-lg border border-border/70 p-4">
              <p className="text-sm text-muted-foreground">{pack.pack_code}</p>
              <p className="mt-1 text-2xl font-bold">{pack.credits} creditos</p>
              <Button
                className="mt-3 w-full"
                variant="outline"
                onClick={() => void startPackCheckout(pack.pack_code)}
                disabled={checkingOut === pack.pack_code}
              >
                {checkingOut === pack.pack_code ? <Loader2 className="mr-2 h-4 w-4 animate-spin" /> : null}
                Comprar
              </Button>
            </div>
          ))}
        </CardContent>
      </Card>
    </div>
  );
}
