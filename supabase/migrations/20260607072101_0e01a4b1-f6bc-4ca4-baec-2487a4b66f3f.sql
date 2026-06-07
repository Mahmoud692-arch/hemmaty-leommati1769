
-- ====== Settings keys ======
INSERT INTO public.public_site_settings (key, value)
VALUES
  ('suggestion_reward_points', '50'::jsonb),
  ('article_min_read_seconds', '180'::jsonb),
  ('article_min_scroll_percent', '70'::jsonb),
  ('hadith_min_read_seconds', '60'::jsonb)
ON CONFLICT (key) DO NOTHING;

-- ====== content_suggestions ======
CREATE TABLE IF NOT EXISTS public.content_suggestions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  content_type text NOT NULL CHECK (content_type IN ('article','hadith','story','quote')),
  title text NOT NULL,
  body text NOT NULL,
  source text,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','approved','rejected')),
  admin_notes text,
  reviewed_by uuid,
  reviewed_at timestamptz,
  target_section text,
  published_entity_id text,
  points_awarded int NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

GRANT SELECT, INSERT, UPDATE ON public.content_suggestions TO authenticated;
GRANT ALL ON public.content_suggestions TO service_role;

ALTER TABLE public.content_suggestions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "owner reads own suggestions"
ON public.content_suggestions FOR SELECT TO authenticated
USING (auth.uid() = user_id OR has_role(auth.uid(), 'admin'::app_role));

CREATE POLICY "owner inserts own suggestions"
ON public.content_suggestions FOR INSERT TO authenticated
WITH CHECK (auth.uid() = user_id AND is_email_confirmed(auth.uid()));

CREATE POLICY "admin updates suggestions"
ON public.content_suggestions FOR UPDATE TO authenticated
USING (has_role(auth.uid(), 'admin'::app_role))
WITH CHECK (has_role(auth.uid(), 'admin'::app_role));

CREATE INDEX IF NOT EXISTS idx_suggestions_user ON public.content_suggestions(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_suggestions_status ON public.content_suggestions(status, created_at DESC);

CREATE OR REPLACE FUNCTION public._set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END $$;

DROP TRIGGER IF EXISTS trg_suggestions_updated_at ON public.content_suggestions;
CREATE TRIGGER trg_suggestions_updated_at
BEFORE UPDATE ON public.content_suggestions
FOR EACH ROW EXECUTE FUNCTION public._set_updated_at();

-- ====== hadith_read_progress (effective seconds tracking) ======
CREATE TABLE IF NOT EXISTS public.hadith_read_progress (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  hadith_collection text NOT NULL,
  hadith_number int NOT NULL,
  effective_seconds int NOT NULL DEFAULT 0,
  points_awarded boolean NOT NULL DEFAULT false,
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, hadith_collection, hadith_number)
);

GRANT SELECT, INSERT, UPDATE ON public.hadith_read_progress TO authenticated;
GRANT ALL ON public.hadith_read_progress TO service_role;

ALTER TABLE public.hadith_read_progress ENABLE ROW LEVEL SECURITY;

CREATE POLICY "owner manages hadith progress"
ON public.hadith_read_progress FOR ALL TO authenticated
USING (auth.uid() = user_id)
WITH CHECK (auth.uid() = user_id);

-- ====== submit_suggestion ======
CREATE OR REPLACE FUNCTION public.submit_suggestion(
  _content_type text, _title text, _body text, _source text DEFAULT NULL
)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_uid uuid := auth.uid(); v_id uuid;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not authenticated'; END IF;
  IF NOT public.is_email_confirmed(v_uid) THEN RAISE EXCEPTION 'email not confirmed'; END IF;
  IF _content_type NOT IN ('article','hadith','story','quote') THEN
    RAISE EXCEPTION 'invalid content type'; END IF;
  IF length(coalesce(_title,'')) < 3 OR length(coalesce(_title,'')) > 250 THEN
    RAISE EXCEPTION 'invalid title length'; END IF;
  IF length(coalesce(_body,'')) < 20 OR length(coalesce(_body,'')) > 20000 THEN
    RAISE EXCEPTION 'invalid body length'; END IF;

  INSERT INTO public.content_suggestions(user_id, content_type, title, body, source)
  VALUES (v_uid, _content_type, _title, _body, NULLIF(_source,''))
  RETURNING id INTO v_id;
  RETURN v_id;
END $$;
REVOKE EXECUTE ON FUNCTION public.submit_suggestion(text,text,text,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.submit_suggestion(text,text,text,text) TO authenticated;

-- ====== admin_review_suggestion ======
CREATE OR REPLACE FUNCTION public.admin_review_suggestion(
  _id uuid, _approve boolean, _admin_notes text DEFAULT NULL, _target_section text DEFAULT NULL
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_row public.content_suggestions%ROWTYPE;
  v_points int := 0;
BEGIN
  IF NOT public.has_role(v_uid, 'admin'::app_role) THEN
    RAISE EXCEPTION 'forbidden'; END IF;
  SELECT * INTO v_row FROM public.content_suggestions WHERE id = _id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'not found'; END IF;
  IF v_row.status <> 'pending' THEN
    RAISE EXCEPTION 'already reviewed'; END IF;

  IF _approve THEN
    SELECT COALESCE((value)::int, 50) INTO v_points
    FROM public.public_site_settings WHERE key = 'suggestion_reward_points';

    UPDATE public.content_suggestions SET
      status = 'approved',
      admin_notes = _admin_notes,
      target_section = _target_section,
      reviewed_by = v_uid,
      reviewed_at = now(),
      points_awarded = v_points
    WHERE id = _id;

    UPDATE public.profiles
    SET total_points = total_points + v_points
    WHERE user_id = v_row.user_id;

    INSERT INTO public.points_adjustments(user_id, delta, reason, notification_message, created_by)
    VALUES (v_row.user_id, v_points, 'suggestion_approved:'||_id::text,
            'تمت الموافقة على اقتراحك "'||v_row.title||'" — حصلت على +'||v_points||' نقطة 🎉', v_uid);

    INSERT INTO public.notifications(user_id, title, message, type, link)
    VALUES (v_row.user_id, 'تمت الموافقة على اقتراحك',
            'حصلت على +'||v_points||' نقطة على اقتراحك: '||v_row.title, 'success', '/me');

    RETURN jsonb_build_object('ok', true, 'approved', true, 'points', v_points);
  ELSE
    UPDATE public.content_suggestions SET
      status = 'rejected',
      admin_notes = _admin_notes,
      reviewed_by = v_uid,
      reviewed_at = now()
    WHERE id = _id;

    INSERT INTO public.notifications(user_id, title, message, type, link)
    VALUES (v_row.user_id, 'تم رفض اقتراحك',
            COALESCE(_admin_notes, 'لم يُقبل اقتراحك هذه المرة. حاول مجدداً!'), 'info', '/me');

    RETURN jsonb_build_object('ok', true, 'approved', false);
  END IF;
END $$;
REVOKE EXECUTE ON FUNCTION public.admin_review_suggestion(uuid,boolean,text,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_review_suggestion(uuid,boolean,text,text) TO authenticated;

-- ====== award_hadith_reading_points ======
CREATE OR REPLACE FUNCTION public.award_hadith_reading_points(
  _collection text, _number int, _seconds int
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_min int;
  v_already boolean;
  v_points int;
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('ok',false,'reason','not_authenticated'); END IF;

  SELECT COALESCE((value)::int, 60) INTO v_min
  FROM public.public_site_settings WHERE key = 'hadith_min_read_seconds';
  IF v_min IS NULL THEN v_min := 60; END IF;

  INSERT INTO public.hadith_read_progress(user_id, hadith_collection, hadith_number, effective_seconds, updated_at)
  VALUES (v_uid, _collection, _number, GREATEST(0,_seconds), now())
  ON CONFLICT (user_id, hadith_collection, hadith_number) DO UPDATE SET
    effective_seconds = GREATEST(public.hadith_read_progress.effective_seconds, EXCLUDED.effective_seconds),
    updated_at = now();

  SELECT points_awarded INTO v_already FROM public.hadith_read_progress
  WHERE user_id = v_uid AND hadith_collection = _collection AND hadith_number = _number;
  IF v_already THEN RETURN jsonb_build_object('ok',true,'awarded',false,'reason','already'); END IF;

  IF _seconds >= v_min THEN
    UPDATE public.hadith_read_progress SET points_awarded = true
    WHERE user_id = v_uid AND hadith_collection = _collection AND hadith_number = _number;

    -- Idempotent insert into hadith_reads
    INSERT INTO public.hadith_reads(user_id, hadith_collection, hadith_number)
    SELECT v_uid, _collection, _number
    WHERE NOT EXISTS (
      SELECT 1 FROM public.hadith_reads
      WHERE user_id = v_uid AND hadith_collection = _collection AND hadith_number = _number
    );

    -- Read configured points
    SELECT COALESCE((value)::int, 5) INTO v_points
    FROM public.public_site_settings WHERE key = 'points_hadith_read';
    IF v_points IS NULL THEN v_points := 5; END IF;

    UPDATE public.profiles
    SET total_points = total_points + v_points,
        hadiths_read = hadiths_read + 1
    WHERE user_id = v_uid;

    RETURN jsonb_build_object('ok',true,'awarded',true,'points',v_points);
  END IF;
  RETURN jsonb_build_object('ok',true,'awarded',false,'min_seconds',v_min,'seconds',_seconds);
END $$;
REVOKE EXECUTE ON FUNCTION public.award_hadith_reading_points(text,int,int) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.award_hadith_reading_points(text,int,int) TO authenticated;

-- ====== Update award_reading_points to honor settings ======
CREATE OR REPLACE FUNCTION public.award_reading_points(_article_slug text, _scroll_percent int, _seconds_spent int)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_min_seconds int;
  v_min_scroll int;
  v_cfg_min int;
  v_already boolean;
  v_read_minutes int;
  v_points int;
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('ok',false,'reason','not_authenticated'); END IF;

  SELECT COALESCE((value)::int, 180) INTO v_cfg_min
  FROM public.public_site_settings WHERE key = 'article_min_read_seconds';
  IF v_cfg_min IS NULL THEN v_cfg_min := 180; END IF;

  SELECT COALESCE((value)::int, 70) INTO v_min_scroll
  FROM public.public_site_settings WHERE key = 'article_min_scroll_percent';
  IF v_min_scroll IS NULL THEN v_min_scroll := 70; END IF;

  SELECT COALESCE(read_minutes,3) INTO v_read_minutes FROM public.articles WHERE slug = _article_slug;
  IF v_read_minutes IS NULL THEN v_read_minutes := 3; END IF;
  v_min_seconds := GREATEST(v_cfg_min, (v_read_minutes * 60 * 0.7)::int);

  INSERT INTO public.article_read_progress (user_id, article_slug, seconds_spent, scroll_percent, updated_at)
  VALUES (v_uid, _article_slug, _seconds_spent, _scroll_percent, now())
  ON CONFLICT (user_id, article_slug) DO UPDATE SET
    seconds_spent = GREATEST(public.article_read_progress.seconds_spent, EXCLUDED.seconds_spent),
    scroll_percent = GREATEST(public.article_read_progress.scroll_percent, EXCLUDED.scroll_percent),
    updated_at = now();

  SELECT points_awarded INTO v_already FROM public.article_read_progress
  WHERE user_id = v_uid AND article_slug = _article_slug;
  IF v_already THEN RETURN jsonb_build_object('ok',true,'awarded',false,'reason','already'); END IF;

  IF _scroll_percent >= v_min_scroll AND _seconds_spent >= v_min_seconds THEN
    UPDATE public.article_read_progress SET points_awarded = true
    WHERE user_id = v_uid AND article_slug = _article_slug;

    SELECT COALESCE((value)::int, 10) INTO v_points
    FROM public.public_site_settings WHERE key = 'points_article_read';
    IF v_points IS NULL THEN v_points := 10; END IF;

    UPDATE public.profiles SET total_points = total_points + v_points, articles_read = articles_read + 1
    WHERE user_id = v_uid;
    INSERT INTO public.article_reads (user_id, article_slug)
    SELECT v_uid, _article_slug
    WHERE NOT EXISTS (SELECT 1 FROM public.article_reads WHERE user_id = v_uid AND article_slug = _article_slug);
    RETURN jsonb_build_object('ok',true,'awarded',true,'points',v_points);
  END IF;
  RETURN jsonb_build_object('ok',true,'awarded',false,'min_seconds',v_min_seconds,'min_scroll',v_min_scroll);
END $$;
REVOKE EXECUTE ON FUNCTION public.award_reading_points(text,int,int) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.award_reading_points(text,int,int) TO authenticated;
