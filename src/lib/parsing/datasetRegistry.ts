/**
 * Dataset Registry — maps Epic CSV filenames to internal dataset categories.
 * Each entry defines the expected filename pattern (regex), the category,
 * and a canonical name used as a key in parsed data.
 */

export interface DatasetDef {
  pattern: RegExp;
  category: 'acquisition' | 'engagement' | 'retention' | 'surveys' | 'versions';
  canonical: string;
  label: string;
}

export const DATASET_REGISTRY: DatasetDef[] = [
  // ── Acquisition ──
  { pattern: /ctr.*di[aá]rio|daily.*ctr/i, canonical: 'acq_ctr_daily', category: 'acquisition', label: 'CTR Diário' },
  { pattern: /impress[oõ]es.*total|total.*impression/i, canonical: 'acq_impressions_total', category: 'acquisition', label: 'Impressões Totais' },
  { pattern: /impress[oõ]es.*fonte|impression.*source/i, canonical: 'acq_impressions_source', category: 'acquisition', label: 'Impressões por Fonte' },
  { pattern: /impress[oõ]es.*pa[ií]s|impression.*countr/i, canonical: 'acq_impressions_country', category: 'acquisition', label: 'Impressões por País' },
  { pattern: /cliques.*total|total.*click/i, canonical: 'acq_clicks_total', category: 'acquisition', label: 'Cliques Totais' },
  { pattern: /cliques.*fonte|click.*source/i, canonical: 'acq_clicks_source', category: 'acquisition', label: 'Cliques por Fonte' },
  { pattern: /cliques.*pa[ií]s|click.*countr/i, canonical: 'acq_clicks_country', category: 'acquisition', label: 'Cliques por País' },
  { pattern: /cliques.*plataforma|click.*platform/i, canonical: 'acq_clicks_platform', category: 'acquisition', label: 'Cliques por Plataforma' },

  // ── Engagement ──
  { pattern: /tempo.*jogo.*ativo.*total|active.*play.*time.*total/i, canonical: 'eng_playtime_total', category: 'engagement', label: 'Tempo de Jogo Total' },
  { pattern: /tempo.*jogo.*ativo.*pa[ií]s|active.*play.*time.*countr/i, canonical: 'eng_playtime_country', category: 'engagement', label: 'Tempo de Jogo por País' },
  { pattern: /tempo.*jogo.*ativo.*plataforma|active.*play.*time.*platform/i, canonical: 'eng_playtime_platform', category: 'engagement', label: 'Tempo de Jogo por Plataforma' },
  { pattern: /pessoas.*ativas.*total|active.*people.*total/i, canonical: 'eng_active_total', category: 'engagement', label: 'Pessoas Ativas Total' },
  { pattern: /pessoas.*ativas.*pa[ií]s|active.*people.*countr/i, canonical: 'eng_active_country', category: 'engagement', label: 'Pessoas Ativas por País' },
  { pattern: /pessoas.*ativas.*plataforma|active.*people.*platform/i, canonical: 'eng_active_platform', category: 'engagement', label: 'Pessoas Ativas por Plataforma' },
  { pattern: /tempo.*fila|queue.*time|matchmak/i, canonical: 'eng_queue_time', category: 'engagement', label: 'Tempo de Fila' },
  { pattern: /evento|event/i, canonical: 'eng_events', category: 'engagement', label: 'Eventos Custom' },
  { pattern: /novos.*retornando|new.*return/i, canonical: 'eng_new_returning', category: 'engagement', label: 'Novos vs Retornando' },

  // ── Retention ──
  { pattern: /reten[cç][aã]o|retention/i, canonical: 'ret_retention', category: 'retention', label: 'Retenção D1/D7' },

  // ── Surveys ──
  { pattern: /avalia[cç][aã]o.*resum|rating.*summar/i, canonical: 'srv_rating_summary', category: 'surveys', label: 'Avaliação Resumo' },
  { pattern: /avalia[cç][aã]o.*tend|rating.*trend/i, canonical: 'srv_rating_trend', category: 'surveys', label: 'Avaliação Tendência' },
  { pattern: /avalia[cç][aã]o.*detal|rating.*detail/i, canonical: 'srv_rating_detail', category: 'surveys', label: 'Avaliação Detalhado' },
  { pattern: /avalia[cç][aã]o.*bench|rating.*bench/i, canonical: 'srv_rating_benchmark', category: 'surveys', label: 'Avaliação Benchmark' },
  { pattern: /divers[aã]o.*resum|fun.*summar/i, canonical: 'srv_fun_summary', category: 'surveys', label: 'Diversão Resumo' },
  { pattern: /divers[aã]o.*tend|fun.*trend/i, canonical: 'srv_fun_trend', category: 'surveys', label: 'Diversão Tendência' },
  { pattern: /divers[aã]o.*bench|fun.*bench/i, canonical: 'srv_fun_benchmark', category: 'surveys', label: 'Diversão Benchmark' },
  { pattern: /dificuldade.*resum|difficulty.*summar/i, canonical: 'srv_difficulty_summary', category: 'surveys', label: 'Dificuldade Resumo' },
  { pattern: /dificuldade.*tend|difficulty.*trend/i, canonical: 'srv_difficulty_trend', category: 'surveys', label: 'Dificuldade Tendência' },
  { pattern: /dificuldade.*bench|difficulty.*bench/i, canonical: 'srv_difficulty_benchmark', category: 'surveys', label: 'Dificuldade Benchmark' },

  // ── Versions ──
  { pattern: /vers[oõ]|version|release|changelog/i, canonical: 'ver_changelog', category: 'versions', label: 'Changelog/Versões' },
];

export function identifyDataset(fileName: string): DatasetDef | null {
  const name = fileName.replace(/\.csv$/i, '');
  return DATASET_REGISTRY.find(d => d.pattern.test(name)) || null;
}
