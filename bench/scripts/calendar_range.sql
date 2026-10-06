-- Calendar_API calendar/get/view.rs: events visible to a user over one month
\set uid random_exponential(2, 20000, 3)
SELECT EXISTS(SELECT 1 FROM users WHERE id = :uid AND NOT COALESCE(is_archived, false)) AS is_user_active;
\set day random(-700, 700)
SELECT to_jsonb(t) FROM (
  SELECT e.id, e.name, e.start_date, e.end_date, e.category, e.service_label AS service, e.location, e.visibility,
    EXISTS (SELECT 1 FROM event_members em WHERE em.event_id = e.id AND em.user_id = :uid) AS is_member,
    CASE WHEN rr.id IS NULL THEN NULL ELSE jsonb_build_object('frequency', rr.type_recurrence::text, 'interval', rr.intervalle) END AS recurrence
  FROM events e LEFT JOIN recurrence_rules rr ON rr.id = e.recurrence_id
  WHERE (e.visibility = 'public' OR e.owner_id = :uid
         OR EXISTS (SELECT 1 FROM event_members em WHERE em.event_id = e.id AND em.user_id = :uid))
    AND ((e.start_date <= now() + (:day + 30) * interval '1 day' AND e.end_date >= now() + :day * interval '1 day')
      OR (rr.id IS NOT NULL AND rr.start_date <= now() + (:day + 30) * interval '1 day'
          AND (rr.end_date IS NULL OR rr.end_date > now() + :day * interval '1 day')))
  ORDER BY e.start_date, e.id) t;
