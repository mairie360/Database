DROP TRIGGER IF EXISTS trg_course_ratings_updated_at ON course_ratings;
CREATE TRIGGER trg_course_ratings_updated_at
    BEFORE UPDATE ON course_ratings
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
