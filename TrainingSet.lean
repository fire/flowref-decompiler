import LeanDuckDB

/-! # flowref-training-parquet — AutoResearch-style training-set snapshots

This executable converts the reproducible training-set manifest and oracle result
TSV files into standalone Parquet files. It uses DuckDB only as an in-process
Parquet writer/query engine: no persistent database is created.

Usage:
  flowref-training-parquet <manifest.tsv> <results.tsv> <out-dir>
-/

open DuckDB

/-- Single-quote a string for a SQL literal. -/
def sqlLit (s : String) : String := "'" ++ s.replace "'" "''" ++ "'"

/-- A scalar query → first cell of the first row (or `""`). -/
def scalar (sql : String) : IO String := do
  let t ← query sql
  pure ((t.rows[0]?.bind (·[0]?)).getD "")

def copyParquet (body outPath : String) : IO Unit := do
  let _ ← query s!"COPY ({body}) TO {sqlLit outPath} (FORMAT PARQUET, COMPRESSION ZSTD)"
  pure ()

def main (args : List String) : IO Unit := do
  match args with
  | [manifest, results, outDir] =>
      IO.FS.createDirAll outDir
      let manifestRel := s!"read_csv_auto({sqlLit manifest}, delim='\\t', header=true)"
      let resultsRel := s!"read_csv_auto({sqlLit results}, delim='\\t', header=true)"
      let manifestOut := s!"{outDir}/training_manifest.parquet"
      let resultsOut := s!"{outDir}/training_results.parquet"
      let summaryOut := s!"{outDir}/training_summary.parquet"
      let hypothesesOut := s!"{outDir}/training_hypotheses.parquet"

      copyParquet s!"SELECT * FROM {manifestRel}" manifestOut
      copyParquet s!"SELECT * FROM {resultsRel}" resultsOut
      copyParquet
        (s!"SELECT count(*) AS total, " ++
         s!"sum(CASE WHEN verdict='EQUIVALENT' THEN 1 ELSE 0 END) AS observed_equivalent, " ++
         s!"sum(CASE WHEN verdict='NOT-EQUIVALENT' THEN 1 ELSE 0 END) AS soundness_violations, " ++
         s!"sum(CASE WHEN unsafe_compiles='yes' THEN 1 ELSE 0 END) AS unsafe_compiles " ++
         s!"FROM {resultsRel}")
        summaryOut
      copyParquet
        ("SELECT * FROM (VALUES " ++
         "('H1','single-block memory','Lower memory operands after oracle-observed load/store C shape','strict_observed_delta')," ++
         "('H2','general calls','Lift call result followed by ALU combine with uninterpreted callee summary','strict_observed_delta')," ++
         "('H3','control flow','Widen compact branch diamonds only after binary oracle equivalence','strict_observed_delta')," ++
         "('H4','harness hygiene','Keep fixture inventory, materialized binaries, and oracle results in one reproducible Parquet snapshot','drift_reduction')" ++
         ") AS t(hypothesis_id, area, claim, metric)")
        hypothesesOut

      let total ← scalar s!"SELECT count(*) FROM {resultsRel}"
      let observed ← scalar s!"SELECT sum(CASE WHEN verdict='EQUIVALENT' THEN 1 ELSE 0 END) FROM {resultsRel}"
      let violations ← scalar s!"SELECT sum(CASE WHEN verdict='NOT-EQUIVALENT' THEN 1 ELSE 0 END) FROM {resultsRel}"
      IO.println s!"training parquet snapshot: {observed}/{total} observed-equivalent, soundness violations={violations}"
      IO.println s!"  {manifestOut}"
      IO.println s!"  {resultsOut}"
      IO.println s!"  {summaryOut}"
      IO.println s!"  {hypothesesOut}"
  | _ =>
      IO.eprintln "usage: flowref-training-parquet <manifest.tsv> <results.tsv> <out-dir>"
      IO.Process.exit 2
