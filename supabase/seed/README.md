# Seed data — legacy SQL files

> **Prefer:** `dart run tool/seed.dart --env env/prod.json` — applies everything (data + admin users) in one idempotent command. These SQL files are kept as a reference / fallback only.

The Dart seeder reads the same constants (see `tool/seed_data.dart`) and writes the same rows. Keep the two in sync if you edit seed data; the SQL files exist so anyone who wants to inspect the raw statements or run them via `psql`/the Supabase SQL editor still can.

| File | What it seeds |
|---|---|
| `01_company.sql` | Parent company + 2 hiring entities (GameCove, Luxium) |
| `02_roles.sql` | 4 system roles with permission arrays |
| `08_payroll_calendar.sql` | Semi-monthly calendar for current year |
| `11_departments.sql` | OPS / HR / SLS / MKT departments |

## Employee data dump (optional)

payrollos has no employee seeder — employees are production data. To copy real-ish employees into a dev Supabase:

```bash
pg_restore --host=localhost --dbname=payrollos /path/to/payrollos/local_dump.dump

pg_dump --host=localhost --dbname=payrollos --data-only \
  --table=employees --column-inserts --rows-per-insert=50 \
  > supabase/seed/12_employees.sql
```

**`12_employees.sql` contains real PII — do not commit it to a public repo.** It's already covered by the `.gitignore` rule on this directory's contents.
