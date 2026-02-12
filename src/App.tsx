import { Toaster } from "@/components/ui/toaster";
import { Toaster as Sonner } from "@/components/ui/sonner";
import { TooltipProvider } from "@/components/ui/tooltip";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { BrowserRouter, Routes, Route } from "react-router-dom";
import { AuthProvider } from "@/hooks/useAuth";
import { ProtectedRoute } from "@/components/ProtectedRoute";
import Index from "./pages/Index";
import Auth from "./pages/Auth";
import AppLayout from "./components/AppLayout";
import AppDashboard from "./pages/AppDashboard";
import ProjectDetail from "./pages/ProjectDetail";
import ReportDashboard from "./pages/ReportDashboard";
import DiscoverTrendsList from "./pages/DiscoverTrendsList";
import DiscoverTrendsReport from "./pages/DiscoverTrendsReport";
import IslandLookup from "./pages/IslandLookup";
import NotFound from "./pages/NotFound";

const queryClient = new QueryClient();

const App = () => (
  <QueryClientProvider client={queryClient}>
    <TooltipProvider>
      <Toaster />
      <Sonner />
      <BrowserRouter>
        <AuthProvider>
          <Routes>
            <Route path="/" element={<Index />} />
            <Route path="/auth" element={<Auth />} />
            <Route path="/app" element={<ProtectedRoute><AppLayout /></ProtectedRoute>}>
              <Route index element={<AppDashboard />} />
              <Route path="projects/:id" element={<ProjectDetail />} />
              <Route path="projects/:id/reports/:reportId" element={<ReportDashboard />} />
              <Route path="discover-trends" element={<DiscoverTrendsList />} />
              <Route path="discover-trends/:reportId" element={<DiscoverTrendsReport />} />
              <Route path="island-lookup" element={<IslandLookup />} />
            </Route>
            <Route path="*" element={<NotFound />} />
          </Routes>
        </AuthProvider>
      </BrowserRouter>
    </TooltipProvider>
  </QueryClientProvider>
);

export default App;
