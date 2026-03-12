import { Link } from "react-router-dom";
import { useTranslation } from "react-i18next";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";

interface AuthGateDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  featureLabel?: string;
}

export function AuthGateDialog({ open, onOpenChange, featureLabel }: AuthGateDialogProps) {
  const { t } = useTranslation();

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-md">
        <DialogHeader>
          <DialogTitle>{t("auth.gateTitle")}</DialogTitle>
          <DialogDescription>
            {featureLabel ? t("auth.gateDescriptionWithFeature", { feature: featureLabel }) : t("auth.gateDescription")}
          </DialogDescription>
        </DialogHeader>
        <DialogFooter className="gap-2 sm:justify-end">
          <Button variant="outline" asChild>
            <Link to="/auth" onClick={() => onOpenChange(false)}>
              {t("auth.signIn")}
            </Link>
          </Button>
          <Button asChild>
            <Link to="/auth" onClick={() => onOpenChange(false)}>
              {t("auth.signUp")}
            </Link>
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
