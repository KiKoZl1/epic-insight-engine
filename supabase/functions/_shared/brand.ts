const DEFAULT_BRAND_NAME = "UEFNToolkit";
const DEFAULT_BRAND_SLUG = "uefntoolkit";
const DEFAULT_CANONICAL_DOMAIN = "uefntoolkit.com";

function normalizeSlug(value: string): string {
  const normalized = value.trim().toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "");
  return normalized || DEFAULT_BRAND_SLUG;
}

function normalizeBrandName(value: string): string {
  const normalized = value.trim();
  return normalized || DEFAULT_BRAND_NAME;
}

function normalizeDomain(value: string): string {
  const normalized = value.trim().toLowerCase().replace(/^https?:\/\//, "").replace(/\/+$/, "");
  return normalized || DEFAULT_CANONICAL_DOMAIN;
}

export const BRAND_NAME = normalizeBrandName(String(Deno.env.get("BRAND_NAME") || ""));
export const BRAND_SLUG = normalizeSlug(String(Deno.env.get("BRAND_SLUG") || BRAND_NAME));
export const BRAND_CANONICAL_DOMAIN = normalizeDomain(String(Deno.env.get("BRAND_CANONICAL_DOMAIN") || ""));
export const BRAND_CANONICAL_URL = `https://${BRAND_CANONICAL_DOMAIN}`;
export const OPENROUTER_REFERER_DEFAULT = BRAND_CANONICAL_URL;
export const OPENROUTER_TITLE_DEFAULT = `${BRAND_NAME}-TGIS`;

export function buildUserAgent(suffix: string): string {
  const normalizedSuffix = normalizeSlug(String(suffix || ""));
  return `${BRAND_SLUG}/${normalizedSuffix}`;
}
