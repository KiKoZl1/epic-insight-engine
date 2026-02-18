/**
 * Normalization utilities for Epic CSV data (pt-BR formats).
 */

/** pt-BR column name → canonical English mapping */
const COLUMN_MAP: Record<string, string> = {
  'data': 'date',
  'diagnósticos': 'impressions',
  'impressões': 'impressions',
  'cliques': 'clicks',
  'fonte': 'source',
  'país': 'country',
  'plataforma': 'platform',
  'pessoas ativas': 'active_people',
  'tempo de jogo ativo': 'active_playtime',
  'tempo de fila': 'queue_time',
  'avaliação': 'rating',
  'diversão': 'fun',
  'dificuldade': 'difficulty',
  'versão': 'version',
  'notas': 'notes',
  'retenção d1': 'retention_d1',
  'retenção d7': 'retention_d7',
  'd1': 'retention_d1',
  'd7': 'retention_d7',
};

export function normalizeColumnName(col: string): string {
  const lower = col.trim().toLowerCase();
  return COLUMN_MAP[lower] || lower.replace(/\s+/g, '_');
}

/**
 * Parse a pt-BR number string.
 * "191.916" → 191916 (thousands separator)
 * "7,8" → 7.8 (decimal comma)
 * "1.234,56" → 1234.56
 */
export function parsePtBrNumber(raw: string): number | null {
  if (!raw || raw.trim() === '' || raw === '-') return null;
  let s = raw.trim();
  
  // Remove % if present
  const isPct = s.endsWith('%');
  if (isPct) s = s.slice(0, -1).trim();

  // If has both . and , → dot is thousands, comma is decimal
  if (s.includes('.') && s.includes(',')) {
    s = s.replace(/\./g, '').replace(',', '.');
  } else if (s.includes(',')) {
    // Only comma → decimal separator
    s = s.replace(',', '.');
  } else if (s.includes('.')) {
    // Only dot — check if it's thousands (e.g., "191.916") or decimal (e.g., "3.5")
    const parts = s.split('.');
    if (parts.length === 2 && parts[1].length === 3 && parts[0].length > 0) {
      // Likely thousands separator
      s = s.replace('.', '');
    }
    // else keep as decimal
  }

  const n = parseFloat(s);
  if (isNaN(n)) return null;
  return isPct ? n / 100 : n;
}

/**
 * Parse a date string to YYYY-MM-DD.
 * Handles: dd/mm/yyyy, dd-mm-yyyy, yyyy-mm-dd, mm/dd/yyyy (US)
 */
export function normalizeDate(raw: string): string | null {
  if (!raw || raw.trim() === '') return null;
  const s = raw.trim();

  // Try ISO format first
  if (/^\d{4}-\d{2}-\d{2}/.test(s)) return s.slice(0, 10);

  // dd/mm/yyyy or dd-mm-yyyy (pt-BR)
  const brMatch = s.match(/^(\d{1,2})[/-](\d{1,2})[/-](\d{4})$/);
  if (brMatch) {
    const [, d, m, y] = brMatch;
    return `${y}-${m.padStart(2, '0')}-${d.padStart(2, '0')}`;
  }

  // Try Date.parse as fallback
  const ts = Date.parse(s);
  if (!isNaN(ts)) {
    const dt = new Date(ts);
    return dt.toISOString().slice(0, 10);
  }

  return null;
}

/** Extract clean event name from hash ID pattern like "EventName [abc123]" */
export function cleanEventName(raw: string): string {
  return raw.replace(/\s*\[.*?\]\s*$/, '').trim();
}

/** Normalize a full row of data */
export function normalizeRow(
  row: Record<string, string>,
  dateColumns: string[] = ['date', 'data', 'Date', 'Data']
): Record<string, string | number | null> {
  const result: Record<string, string | number | null> = {};

  for (const [key, value] of Object.entries(row)) {
    const normKey = normalizeColumnName(key);

    if (dateColumns.some(dc => dc.toLowerCase() === key.toLowerCase())) {
      result[normKey] = normalizeDate(value);
    } else {
      // Try number parse, fallback to string
      const num = parsePtBrNumber(value);
      result[normKey] = num !== null ? num : value.trim();
    }
  }

  return result;
}
