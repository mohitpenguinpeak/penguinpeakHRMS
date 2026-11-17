create or replace function public.company_is_workday(day date)
returns boolean language sql stable strict set search_path = '' as $$
  select coalesce(
    (select bool_and(h.type = 'Working day') from public.holidays h where h.holiday_date = day),
    extract(isodow from day) <= 5 or (
      extract(isodow from day) = 6 and
      (extract(day from day) between 8 and 14 or extract(day from day) between 22 and 28)
    )
  );
$$;
