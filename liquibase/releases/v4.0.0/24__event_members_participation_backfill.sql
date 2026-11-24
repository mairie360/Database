-- The creator of an event who assigned themselves takes part in it (MAIR-1122).
UPDATE event_members em SET participation = 'accepted'
FROM events e
WHERE e.id = em.event_id AND e.created_by = em.user_id AND em.participation = 'pending';
