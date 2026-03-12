import { expect, test } from "@playwright/test";

const publicHubRoutes = ["/tools/analytics", "/tools/thumb-tools", "/tools/widgetkit"];

test.describe("public tool hubs", () => {
  test("anonymous users can access hub parent pages", async ({ page }) => {
    for (const route of publicHubRoutes) {
      const response = await page.goto(route, { waitUntil: "domcontentloaded" });
      expect(response?.status()).toBeLessThan(400);
      expect(new URL(page.url()).pathname).toBe(route);
    }
  });

  test("protected subtools prompt auth for anonymous users", async ({ page }) => {
    await page.goto("/tools/thumb-tools", { waitUntil: "networkidle" });
    await page.getByRole("button", { name: /generate/i }).click();
    await expect(page.getByRole("dialog")).toBeVisible();
    await expect(page.getByRole("dialog")).toContainText(/login|sign in|entrar/i);
  });

  test("public subtools remain directly reachable", async ({ page }) => {
    await page.goto("/tools/analytics", { waitUntil: "networkidle" });
    await page.getByRole("link", { name: /open tool:\s*reports|abrir ferramenta:\s*reports/i }).click();
    await expect(page).toHaveURL(/\/reports$/);
  });

  test("topbar keeps category order on desktop", async ({ page, isMobile }) => {
    test.skip(isMobile, "desktop-only assertion");

    await page.goto("/", { waitUntil: "networkidle" });

    const discover = page.getByRole("link", { name: /discover/i }).first();
    const analytics = page.getByRole("link", { name: /analytics tools/i }).first();
    const thumbTools = page.getByRole("link", { name: /thumb tools/i }).first();
    const widgetKit = page.getByRole("link", { name: /widgetkit/i }).first();

    await expect(discover).toBeVisible();
    await expect(analytics).toBeVisible();
    await expect(thumbTools).toBeVisible();
    await expect(widgetKit).toBeVisible();

    const [discoverBox, analyticsBox, thumbBox, widgetBox] = await Promise.all([
      discover.boundingBox(),
      analytics.boundingBox(),
      thumbTools.boundingBox(),
      widgetKit.boundingBox(),
    ]);

    expect(discoverBox && analyticsBox && thumbBox && widgetBox).toBeTruthy();
    if (!discoverBox || !analyticsBox || !thumbBox || !widgetBox) return;

    expect(discoverBox.x).toBeLessThan(analyticsBox.x);
    expect(analyticsBox.x).toBeLessThan(thumbBox.x);
    expect(thumbBox.x).toBeLessThan(widgetBox.x);
  });
});
