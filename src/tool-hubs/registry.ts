import { BarChart3, Binary, Camera, FileCode2, ImagePlus, LayoutDashboard, Layers3, LucideIcon, Search, Wand2 } from "lucide-react";

export type ToolHubId = "analyticsTools" | "thumbTools" | "widgetKit";

export interface ToolHubToolConfig {
  id: string;
  to: string;
  titleKey: string;
  descriptionKey: string;
  icon: LucideIcon;
  requiresAuth?: boolean;
}

export interface ToolHubConfig {
  id: ToolHubId;
  titleKey: string;
  subtitleKey: string;
  tools: ToolHubToolConfig[];
}

export const TOOL_HUBS: Record<ToolHubId, ToolHubConfig> = {
  analyticsTools: {
    id: "analyticsTools",
    titleKey: "nav.analyticsTools",
    subtitleKey: "analyticsTools.subtitle",
    tools: [
      {
        id: "island-analytics",
        to: "/app",
        titleKey: "nav.analyticsIslandAnalytics",
        descriptionKey: "nav.analyticsIslandAnalyticsDesc",
        icon: LayoutDashboard,
        requiresAuth: true,
      },
      {
        id: "island-lookup",
        to: "/app/island-lookup",
        titleKey: "nav.analyticsIslandLookup",
        descriptionKey: "nav.analyticsIslandLookupDesc",
        icon: Search,
        requiresAuth: true,
      },
      {
        id: "reports",
        to: "/reports",
        titleKey: "nav.reports",
        descriptionKey: "nav.reportsDesc",
        icon: BarChart3,
        requiresAuth: false,
      },
    ],
  },
  thumbTools: {
    id: "thumbTools",
    titleKey: "nav.thumbTools",
    subtitleKey: "thumbTools.subtitle",
    tools: [
      {
        id: "generate",
        to: "/app/thumb-tools/generate",
        titleKey: "nav.toolsGenerate",
        descriptionKey: "nav.toolsGenerateDesc",
        icon: ImagePlus,
        requiresAuth: true,
      },
      {
        id: "edit-studio",
        to: "/app/thumb-tools/edit-studio",
        titleKey: "nav.toolsEditStudio",
        descriptionKey: "nav.toolsEditStudioDesc",
        icon: Wand2,
        requiresAuth: true,
      },
      {
        id: "camera-control",
        to: "/app/thumb-tools/camera-control",
        titleKey: "nav.toolsCameraControl",
        descriptionKey: "nav.toolsCameraControlDesc",
        icon: Camera,
        requiresAuth: true,
      },
      {
        id: "layer-decomposition",
        to: "/app/thumb-tools/layer-decomposition",
        titleKey: "nav.toolsLayerDecomposition",
        descriptionKey: "nav.toolsLayerDecompositionDesc",
        icon: Layers3,
        requiresAuth: true,
      },
    ],
  },
  widgetKit: {
    id: "widgetKit",
    titleKey: "nav.widgetKit",
    subtitleKey: "widgetKit.subtitle",
    tools: [
      {
        id: "psd-umg",
        to: "/app/widgetkit/psd-umg",
        titleKey: "nav.widgetKitPsdUmg",
        descriptionKey: "nav.widgetKitPsdUmgDesc",
        icon: Binary,
        requiresAuth: true,
      },
      {
        id: "umg-verse",
        to: "/app/widgetkit/umg-verse",
        titleKey: "nav.widgetKitUmgVerse",
        descriptionKey: "nav.widgetKitUmgVerseDesc",
        icon: FileCode2,
        requiresAuth: true,
      },
    ],
  },
};

