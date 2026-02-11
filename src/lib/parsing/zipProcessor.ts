/**
 * ZIP extraction and CSV processing pipeline.
 */
import JSZip from 'jszip';
import Papa from 'papaparse';
import { identifyDataset, type DatasetDef } from './datasetRegistry';
import { normalizeRow } from './normalize';

export interface ProcessingLog {
  type: 'info' | 'warning' | 'error';
  message: string;
}

export interface ParsedDataset {
  canonical: string;
  category: string;
  label: string;
  fileName: string;
  rows: Record<string, any>[];
  columns: string[];
  rowCount: number;
}

export interface ProcessingResult {
  datasets: Record<string, ParsedDataset>;
  logs: ProcessingLog[];
  csvCount: number;
  totalRows: number;
}

export async function processZipFile(
  file: File,
  onProgress?: (pct: number, msg: string) => void
): Promise<ProcessingResult> {
  const logs: ProcessingLog[] = [];
  const datasets: Record<string, ParsedDataset> = {};
  let totalRows = 0;
  let csvCount = 0;

  onProgress?.(5, 'Lendo arquivo ZIP...');

  const buffer = await file.arrayBuffer();
  const zip = await JSZip.loadAsync(buffer);

  onProgress?.(15, 'Extraindo CSVs...');

  // Collect CSV files (skip __MACOSX, etc.)
  const csvFiles: { name: string; entry: JSZip.JSZipObject }[] = [];
  zip.forEach((path, entry) => {
    if (
      !entry.dir &&
      path.toLowerCase().endsWith('.csv') &&
      !path.startsWith('__MACOSX') &&
      !path.startsWith('.')
    ) {
      csvFiles.push({ name: path.split('/').pop() || path, entry });
    }
  });

  if (csvFiles.length === 0) {
    logs.push({ type: 'error', message: 'Nenhum arquivo CSV encontrado no ZIP.' });
    return { datasets, logs, csvCount: 0, totalRows: 0 };
  }

  logs.push({ type: 'info', message: `${csvFiles.length} CSV(s) encontrado(s).` });
  csvCount = csvFiles.length;

  for (let i = 0; i < csvFiles.length; i++) {
    const { name, entry } = csvFiles[i];
    const pct = 15 + Math.round((i / csvFiles.length) * 75);
    onProgress?.(pct, `Processando ${name}...`);

    try {
      const text = await entry.async('text');
      
      // Detect separator: try ; first (common pt-BR), fallback to ,
      const firstLine = text.split('\n')[0] || '';
      const delimiter = firstLine.includes(';') ? ';' : ',';

      const parsed = Papa.parse<Record<string, string>>(text, {
        header: true,
        delimiter,
        skipEmptyLines: true,
      });

      if (parsed.errors.length > 0) {
        logs.push({
          type: 'warning',
          message: `${name}: ${parsed.errors.length} erro(s) de parsing.`,
        });
      }

      const dataset = identifyDataset(name);
      if (!dataset) {
        logs.push({ type: 'warning', message: `${name}: não identificado no registry. Ignorado.` });
        continue;
      }

      const normalizedRows = parsed.data.map(row => normalizeRow(row));
      const columns = normalizedRows.length > 0 ? Object.keys(normalizedRows[0]) : [];

      datasets[dataset.canonical] = {
        canonical: dataset.canonical,
        category: dataset.category,
        label: dataset.label,
        fileName: name,
        rows: normalizedRows,
        columns,
        rowCount: normalizedRows.length,
      };

      totalRows += normalizedRows.length;
      logs.push({
        type: 'info',
        message: `${name} → ${dataset.label} (${normalizedRows.length} linhas).`,
      });
    } catch (err) {
      logs.push({
        type: 'error',
        message: `${name}: falha ao processar — ${err instanceof Error ? err.message : 'erro desconhecido'}.`,
      });
    }
  }

  onProgress?.(95, 'Finalizando...');

  // Check for expected but missing datasets
  const expectedCritical = ['acq_impressions_total', 'acq_clicks_total', 'eng_playtime_total', 'ret_retention'];
  for (const key of expectedCritical) {
    if (!datasets[key]) {
      logs.push({ type: 'warning', message: `Dataset esperado não encontrado: ${key}.` });
    }
  }

  onProgress?.(100, 'Concluído!');
  return { datasets, logs, csvCount, totalRows };
}
