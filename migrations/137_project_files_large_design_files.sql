-- ============================================================
-- 137 — Allow large design files in the rrev-files bucket
--
-- CAD assemblies (STEP, SLDASM, Rhino, etc.) routinely run
-- 200-500 MB. The Supabase default per-file cap on rrev-files
-- was set lower; this raises it to 500 MB and removes the
-- MIME-type allowlist so partners can upload any engineering
-- format we receive (.step, .stp, .stl, .iges, .sldprt,
-- .sldasm, .slddrw, .ipt, .iam, .catpart, .3dm, .f3d, .dwg,
-- .dxf, plus PDFs, images, and ZIP/RAR archives).
--
-- App-side validation lives in src/lib/uploads/limits.ts —
-- this migration is the storage-layer enforcement to back it up.
-- ============================================================

begin;

update storage.buckets
set
  file_size_limit = 524288000,  -- 500 MiB
  allowed_mime_types = null     -- no MIME restriction
where id = 'rrev-files';

commit;
