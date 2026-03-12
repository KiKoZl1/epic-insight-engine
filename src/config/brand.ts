const FALLBACK_BRAND_NAME = "UEFNToolkit";
const FALLBACK_CANONICAL_URL = "https://uefntoolkit.com";

function normalizeBrandName(value: string): string {
  const trimmed = value.trim();
  return trimmed || FALLBACK_BRAND_NAME;
}

function normalizeCanonicalUrl(value: string): string {
  const trimmed = value.trim();
  if (!trimmed) return FALLBACK_CANONICAL_URL;
  try {
    const parsed = new URL(trimmed);
    return `${parsed.protocol}//${parsed.host}`;
  } catch {
    return FALLBACK_CANONICAL_URL;
  }
}

export const BRAND_NAME = normalizeBrandName(String(import.meta.env.VITE_BRAND_NAME || ""));
export const BRAND_SLUG = BRAND_NAME.toLowerCase().replace(/[^a-z0-9]+/g, "").trim() || "uefntoolkit";
export const BRAND_CANONICAL_URL = normalizeCanonicalUrl(String(import.meta.env.VITE_CANONICAL_URL || ""));
export const BRAND_CANONICAL_DOMAIN = (() => {
  try {
    return new URL(BRAND_CANONICAL_URL).hostname;
  } catch {
    return "uefntoolkit.com";
  }
})();
