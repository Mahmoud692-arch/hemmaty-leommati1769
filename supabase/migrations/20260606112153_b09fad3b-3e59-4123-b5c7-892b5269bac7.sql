
-- Admin-safe listing: never returns user_id for anonymous questions
CREATE OR REPLACE FUNCTION public.admin_list_questions()
RETURNS TABLE (
  id uuid,
  question text,
  answer text,
  is_anonymous boolean,
  is_published boolean,
  answered_at timestamptz,
  created_at timestamptz,
  sender_user_id uuid,
  sender_name text,
  sender_email text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    q.id,
    q.question,
    q.answer,
    q.is_anonymous,
    q.is_published,
    q.answered_at,
    q.created_at,
    CASE WHEN q.is_anonymous THEN NULL ELSE q.user_id END AS sender_user_id,
    CASE WHEN q.is_anonymous THEN NULL ELSE p.full_name END AS sender_name,
    CASE WHEN q.is_anonymous THEN NULL ELSE p.email END AS sender_email
  FROM public.user_questions q
  LEFT JOIN public.profiles p ON p.user_id = q.user_id
  WHERE public.has_role(auth.uid(), 'admin'::app_role)
  ORDER BY q.created_at DESC;
$$;

REVOKE EXECUTE ON FUNCTION public.admin_list_questions() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_list_questions() TO authenticated;

-- Per-user view: only admin, returns ALL questions (anonymous or not) for a SPECIFIC user
CREATE OR REPLACE FUNCTION public.admin_list_user_questions(_user_id uuid)
RETURNS TABLE (
  id uuid,
  question text,
  answer text,
  is_anonymous boolean,
  is_published boolean,
  answered_at timestamptz,
  created_at timestamptz
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT q.id, q.question, q.answer, q.is_anonymous, q.is_published, q.answered_at, q.created_at
  FROM public.user_questions q
  WHERE public.has_role(auth.uid(), 'admin'::app_role)
    AND q.user_id = _user_id
  ORDER BY q.created_at DESC;
$$;

REVOKE EXECUTE ON FUNCTION public.admin_list_user_questions(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_list_user_questions(uuid) TO authenticated;

-- Tighten direct table SELECT: admins can no longer SELECT raw rows (must use the safe RPCs).
-- Owners can still see their own questions.
DROP POLICY IF EXISTS "أسئلة المستخدم: المالك والإدارة فق" ON public.user_questions;

CREATE POLICY "owner reads own questions only"
ON public.user_questions
FOR SELECT
TO authenticated
USING (auth.uid() = user_id);
