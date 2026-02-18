# Migration Artifacts

Use this folder to keep migration evidence and repeatable SQL snippets.

## Structure
- `sql/`: SQL templates for inventory, import windows, user remap, reconciliation.
- `exports/`: CSV exports/import files (ignored by git).
- `logs/`: screenshots/results/checkpoints (ignored by git).

## Recommended Flow
1. Run `sql/00_inventory_snapshot.sql` on old project.
2. Import CSVs to new project.
3. If needed, run `sql/10_fk_import_window.sql` and then `sql/11_fk_validate.sql`.
4. Remap users using `sql/20_user_id_remap_template.sql`.
5. Run `sql/30_reconciliation.sql` on old and new; save outputs in `logs/`.

