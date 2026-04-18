-- Lark sync support: mark which rows came from Lark vs manual entry, and
-- record when each holiday calendar was last refreshed from Lark.

alter table calendar_events
  add column if not exists source varchar(10) not null default 'MANUAL';

alter table holiday_calendars
  add column if not exists last_synced_at timestamptz;

create index if not exists calendar_events_source_idx on calendar_events (source);
