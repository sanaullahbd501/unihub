-- ============================================================================
-- Migration: Group Lock Toggle, CR Student Management, and Target Specific Students
-- ============================================================================

-- 1. Add is_join_locked column to class_groups
ALTER TABLE public.class_groups 
    ADD COLUMN IF NOT EXISTS is_join_locked BOOLEAN NOT NULL DEFAULT FALSE;

-- 2. Notice Target Users (for assigning notices directly to individual students by name/id)
CREATE TABLE IF NOT EXISTS public.notice_target_users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    notice_id UUID NOT NULL REFERENCES public.notices(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    CONSTRAINT unique_notice_target_user UNIQUE (notice_id, user_id)
);

-- 3. Enable RLS on notice_target_users
ALTER TABLE public.notice_target_users ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Notice target users are viewable by authenticated users" ON public.notice_target_users;
CREATE POLICY "Notice target users are viewable by authenticated users"
    ON public.notice_target_users FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "Notice target users insertable by authenticated users" ON public.notice_target_users;
CREATE POLICY "Notice target users insertable by authenticated users"
    ON public.notice_target_users FOR INSERT TO authenticated WITH CHECK (true);

DROP POLICY IF EXISTS "Notice target users deletable by authenticated users" ON public.notice_target_users;
CREATE POLICY "Notice target users deletable by authenticated users"
    ON public.notice_target_users FOR DELETE TO authenticated USING (true);

-- 4. Allow Class and Group creators to update class_groups (for join lock toggle)
DROP POLICY IF EXISTS "Creators can update class groups" ON public.class_groups;
CREATE POLICY "Creators can update class groups"
    ON public.class_groups FOR UPDATE TO authenticated
    USING (
        created_by = auth.uid()
        OR EXISTS (
            SELECT 1 FROM public.classes c
            WHERE c.id = class_groups.class_id AND c.created_by = auth.uid()
        )
    );

-- 5. Allow CRs to remove students from their managed groups (and students can still leave)
DROP POLICY IF EXISTS "Users can leave a group" ON public.group_members;
DROP POLICY IF EXISTS "Members deletion policy" ON public.group_members;
CREATE POLICY "Members deletion policy"
    ON public.group_members FOR DELETE TO authenticated
    USING (
        auth.uid() = user_id
        OR EXISTS (
            SELECT 1 FROM public.class_groups cg
            JOIN public.classes c ON c.id = cg.class_id
            WHERE cg.id = group_members.group_id
              AND (cg.created_by = auth.uid() OR c.created_by = auth.uid())
        )
        OR EXISTS (
            SELECT 1 FROM public.users u
            WHERE u.id = auth.uid() AND (u.role)::text ILIKE 'admin'
        )
    );

-- 6. Add notice_target_users to Supabase Realtime
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables 
        WHERE pubname = 'supabase_realtime' 
          AND schemaname = 'public' 
          AND tablename = 'notice_target_users'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.notice_target_users;
    END IF;
END $$;

-- 7. Notify PostgREST to reload schema
NOTIFY pgrst, 'reload schema';
