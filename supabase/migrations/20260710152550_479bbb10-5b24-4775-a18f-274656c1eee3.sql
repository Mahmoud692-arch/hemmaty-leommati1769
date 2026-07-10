
-- Performance indexes (verified columns)
CREATE INDEX IF NOT EXISTS idx_articles_status_created ON public.articles(status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_articles_slug ON public.articles(slug);
CREATE INDEX IF NOT EXISTS idx_article_comments_article ON public.article_comments(article_slug, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_article_comments_user ON public.article_comments(user_id);
CREATE INDEX IF NOT EXISTS idx_article_favorites_user ON public.article_favorites(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_article_read_progress_user ON public.article_read_progress(user_id, updated_at DESC);
CREATE INDEX IF NOT EXISTS idx_article_reads_user ON public.article_reads(user_id);
CREATE INDEX IF NOT EXISTS idx_hadith_reads_user ON public.hadith_reads(user_id);
CREATE INDEX IF NOT EXISTS idx_hadith_favorites_user ON public.hadith_favorites(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_lesson_progress_user ON public.lesson_progress(user_id, updated_at DESC);
CREATE INDEX IF NOT EXISTS idx_quiz_attempts_user ON public.quiz_attempts(user_id);
CREATE INDEX IF NOT EXISTS idx_quiz_attempts_quiz ON public.quiz_attempts(quiz_id);
CREATE INDEX IF NOT EXISTS idx_notifications_user_read ON public.notifications(user_id, is_read, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_user_questions_user ON public.user_questions(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_content_suggestions_status ON public.content_suggestions(status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_content_suggestions_user ON public.content_suggestions(user_id);
CREATE INDEX IF NOT EXISTS idx_form_submissions_form ON public.form_submissions(form_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_last_visits_user ON public.last_visits(user_id);
CREATE INDEX IF NOT EXISTS idx_user_badges_user ON public.user_badges(user_id);
CREATE INDEX IF NOT EXISTS idx_profiles_points ON public.profiles(total_points DESC NULLS LAST);
CREATE INDEX IF NOT EXISTS idx_audit_log_created ON public.audit_log(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_log_actor ON public.audit_log(actor_id);

-- Rate limiting
CREATE TABLE IF NOT EXISTS public.rate_limits (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  action TEXT NOT NULL,
  window_start TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_rate_limits_lookup ON public.rate_limits(user_id, action, window_start DESC);

GRANT SELECT ON public.rate_limits TO authenticated;
GRANT ALL ON public.rate_limits TO service_role;

ALTER TABLE public.rate_limits ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "users_view_own_rate_limits" ON public.rate_limits;
CREATE POLICY "users_view_own_rate_limits" ON public.rate_limits
  FOR SELECT TO authenticated USING (auth.uid() = user_id);

CREATE OR REPLACE FUNCTION public.check_rate_limit(
  _action TEXT,
  _max_attempts INT DEFAULT 5,
  _window_seconds INT DEFAULT 60
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  _uid UUID := auth.uid();
  _count INT;
  _cutoff TIMESTAMPTZ := now() - make_interval(secs => _window_seconds);
BEGIN
  IF _uid IS NULL THEN
    RETURN jsonb_build_object('allowed', false, 'reason', 'unauthenticated');
  END IF;

  DELETE FROM public.rate_limits
   WHERE user_id = _uid AND action = _action AND window_start < _cutoff;

  SELECT COUNT(*) INTO _count
    FROM public.rate_limits
   WHERE user_id = _uid AND action = _action AND window_start >= _cutoff;

  IF _count >= _max_attempts THEN
    RETURN jsonb_build_object(
      'allowed', false,
      'reason', 'rate_limited',
      'retry_after_seconds', _window_seconds,
      'attempts', _count,
      'max', _max_attempts
    );
  END IF;

  INSERT INTO public.rate_limits(user_id, action) VALUES (_uid, _action);

  RETURN jsonb_build_object('allowed', true, 'attempts', _count + 1, 'max', _max_attempts);
END;
$$;

GRANT EXECUTE ON FUNCTION public.check_rate_limit(TEXT, INT, INT) TO authenticated;
