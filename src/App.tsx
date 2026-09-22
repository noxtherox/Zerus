import { Toaster } from "@/components/ui/sonner";
import { TooltipProvider } from "@/components/ui/tooltip";
import { lazy, Suspense, useSyncExternalStore } from "react";
import { isTauri } from "@tauri-apps/api/core";
import { BrowserRouter, Routes, Route } from "react-router";
import { Landing } from "./pages/Landing";

const Index = lazy(() => import("./pages/Index"));
const Mobile = lazy(() => import("./pages/Mobile"));
const NotFound = lazy(() => import("./pages/NotFound"));

const phoneViewport = () => !isTauri() && window.matchMedia("(max-width: 767px)").matches;
const subscribeViewport = (onChange: () => void) => {
  const query = window.matchMedia("(max-width: 767px)");
  query.addEventListener("change", onChange);
  return () => query.removeEventListener("change", onChange);
};

function Workspace() {
  const mobile = useSyncExternalStore(subscribeViewport, phoneViewport, () => false);
  return mobile ? <Mobile /> : <Index />;
}

const App = () => (
  <TooltipProvider>
    <Toaster />
    <BrowserRouter>
      <Suspense fallback={<div className="min-h-screen bg-background" />}>
        <Routes>
          <Route path="/" element={isTauri() ? <Index /> : <Landing />} />
          <Route path="/app" element={<Workspace />} />
          <Route path="/mobile" element={<Mobile />} />
          <Route path="*" element={<NotFound />} />
        </Routes>
      </Suspense>
    </BrowserRouter>
  </TooltipProvider>
);

export default App;
