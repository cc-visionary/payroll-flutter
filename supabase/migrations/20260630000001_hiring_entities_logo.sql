-- Company logo for document letterheads. Stored as base64 (PNG/JPG) directly
-- on the hiring entity. Nullable; absence falls back to a bundled brand asset.
-- Intentionally NOT selected by the entity list query (see hiring_entity_repository),
-- so the picker list stays light despite the column's potential size.
alter table hiring_entities
  add column if not exists logo_base64 text,
  add column if not exists logo_mime text;

comment on column hiring_entities.logo_base64 is
  'Base64-encoded PNG/JPG logo (no data: prefix). Capped ~300KB source at the UI.';
comment on column hiring_entities.logo_mime is
  'MIME type of logo_base64, e.g. image/png or image/jpeg.';
