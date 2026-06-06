
-- 1) change_avatar: only accept URLs from our own avatars bucket
CREATE OR REPLACE FUNCTION public.change_avatar(_new_url text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_last timestamptz;
  v_old text;
  v_prefix text := 'https://lnvhvbrkacsmlntsjzrx.supabase.co/storage/v1/object/public/avatars/';
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'غير مسجّل دخول'; END IF;
  IF _new_url IS NULL OR position(v_prefix in _new_url) <> 1 THEN
    RAISE EXCEPTION 'رابط الصورة غير صالح';
  END IF;
  IF position(('avatars/' || v_uid::text || '/') in _new_url) = 0 THEN
    RAISE EXCEPTION 'رابط الصورة لا يخص هذا المستخدم';
  END IF;
  SELECT avatar_changed_at, avatar_url INTO v_last, v_old FROM public.profiles WHERE user_id=v_uid;
  IF v_last IS NOT NULL AND v_last > now() - interval '60 days' THEN
    RETURN jsonb_build_object('ok',false,'reason','cooldown',
      'next_allowed_at', v_last + interval '60 days');
  END IF;
  UPDATE public.profiles SET avatar_url=_new_url, avatar_changed_at=now(), updated_at=now()
  WHERE user_id=v_uid;
  INSERT INTO public.avatar_change_log (user_id, old_url, new_url) VALUES (v_uid, v_old, _new_url);
  RETURN jsonb_build_object('ok',true);
END $function$;

-- 2) notifications: restrict INSERT to admins only
DROP POLICY IF EXISTS "الإدارة تنشئ الإشعارات" ON public.notifications;
CREATE POLICY "admins insert notifications"
ON public.notifications
FOR INSERT
TO authenticated
WITH CHECK (has_role(auth.uid(), 'admin'::app_role));

-- 3) Remove broad public SELECT policies on storage.objects.
-- Public buckets (avatars, media) are served via the public CDN path which bypasses RLS,
-- so direct files remain accessible while anonymous listing is no longer allowed.
DROP POLICY IF EXISTS "avatars_public_read" ON storage.objects;
DROP POLICY IF EXISTS "Public read media bucket" ON storage.objects;

-- 4) Drop leftover article_audio table (TTS feature removed)
DROP TABLE IF EXISTS public.article_audio;

-- 5) Revoke anon EXECUTE on SECURITY DEFINER admin/award/util functions.
-- Keep `leaderboard`, `has_role`, `is_email_confirmed` callable.
DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT p.oid::regprocedure AS sig, p.proname
    FROM pg_proc p
    WHERE p.pronamespace = 'public'::regnamespace
      AND p.prosecdef = true
      AND p.proname NOT IN ('leaderboard','has_role','is_email_confirmed')
  LOOP
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM anon, PUBLIC', r.sig);
  END LOOP;
END $$;
