# Generated cases (ignored)

Patient-specific volumes, masks, UIDs, provenance, QC reports, and logs belong
under this directory and are ignored by Git. Never force-add them.

## Layout

- `legacy/<run>/` — every run that finished, kept for comparison. A run is one
  set of settings; the same case appears several times when settings changed.
- `best/<CASE>` — a symlink to the chosen run for that case. Open
  `best/<CASE>/review/` to review a case without knowing which run won.

Nothing is deleted when a better run appears; only the `best/` symlink moves.
Runs that failed before producing masks are deleted, since they hold no result.
