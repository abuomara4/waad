// Every 10 minutes (notify.yml): send what waits for ZATCA — documents that could not be sent (network / Fatoora down) or that
// nobody pushed because nobody opened the app — so a simplified invoice is reported within ZATCA's 24 hours.
// Same code as the server function (supabase/functions/_shared/process.ts); it talks to the database directly with the
// SUPABASE_DB_URL secret the job already has (no extra secret). Run: DB=postgresql://… deno run -A .github/scripts/zatca_retry.ts
import postgres from 'npm:postgres@3.4.4';
import { processCompany, type Rpc } from '../../supabase/functions/_shared/process.ts';

const url = (Deno.env.get('DB') || '').trim();
if (!url) { console.log('no DB — skipped'); Deno.exit(0); }
const sql = postgres(url, { prepare: false, max: 1, idle_timeout: 5, connect_timeout: 20, ssl: /localhost|127\.0\.0\.1|host=\/tmp/.test(url) ? false : 'require' });

const Q: Record<string, [string, string[]]> = {
  zatca_creds: ['select public.zatca_creds($1::uuid) as r', ['p_company']],
  zatca_claim: ['select public.zatca_claim($1::uuid) as r', ['p_company']],
  zatca_doc_data: ['select public.zatca_doc_data($1::uuid) as r', ['p_doc']],
  zatca_signed: ['select public.zatca_signed($1::bigint, $2, $3, $4, $5) as r', ['p_id', 'p_pih', 'p_hash', 'p_xml', 'p_qr']],
  zatca_result: ['select public.zatca_result($1::bigint, $2, $3::jsonb, $4, $5, $6::int, $7) as r', ['p_id', 'p_status', 'p_resp', 'p_xml', 'p_qr', 'p_retry', 'p_error']],
};
const rpc: Rpc = async (fn, a) => {
  const [q, keys] = Q[fn];
  // deno-lint-ignore no-explicit-any
  const vals = keys.map(k => { const v = (a as any)[k]; return v != null && typeof v === 'object' ? JSON.stringify(v) : v ?? null; });
  const rows = await sql.unsafe(q, vals);
  return rows[0] ? rows[0].r : null;
};

const t0 = Date.now();
try {
  const due = await sql`select public.zatca_waiting() as c`;
  console.log(`companies with documents due: ${due.length}`);
  // the log is public: only counts per status, never company ids, document numbers or ZATCA's messages (they live in the database)
  const tally: Record<string, number> = {};
  for (const { c } of due) {
    if (Date.now() - t0 > 200000) { console.log('time budget used — the rest waits for the next run'); break; }
    try { for (const o of await processCompany(c, rpc, { budgetMs: 40000 })) tally[o.status] = (tally[o.status] || 0) + 1; }
    catch { tally['company failed'] = (tally['company failed'] || 0) + 1; }
  }
  console.log('documents:', JSON.stringify(tally));
} finally { await sql.end({ timeout: 5 }); }
