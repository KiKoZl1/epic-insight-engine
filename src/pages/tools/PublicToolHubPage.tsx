import { useMemo, useState } from "react";
import { useTranslation } from "react-i18next";
import { useAuth } from "@/hooks/useAuth";
import { ToolHubLayout } from "@/components/tool-hub/ToolHubLayout";
import { AuthGateDialog } from "@/components/navigation/AuthGateDialog";
import { TOOL_HUBS, ToolHubId, ToolHubToolConfig } from "@/tool-hubs/registry";

interface PublicToolHubPageProps {
  hubId: ToolHubId;
}

export function PublicToolHubPage({ hubId }: PublicToolHubPageProps) {
  const { t } = useTranslation();
  const { user } = useAuth();
  const [authGate, setAuthGate] = useState<{ open: boolean; label?: string }>({ open: false });
  const hub = useMemo(() => TOOL_HUBS[hubId], [hubId]);

  const handleProtectedToolClick = (tool: ToolHubToolConfig) => {
    setAuthGate({ open: true, label: t(tool.titleKey) });
  };

  return (
    <>
      <ToolHubLayout hub={hub} isAuthenticated={Boolean(user)} onProtectedToolClick={handleProtectedToolClick} />
      <AuthGateDialog
        open={authGate.open}
        onOpenChange={(open) => setAuthGate((prev) => ({ ...prev, open }))}
        featureLabel={authGate.label}
      />
    </>
  );
}
