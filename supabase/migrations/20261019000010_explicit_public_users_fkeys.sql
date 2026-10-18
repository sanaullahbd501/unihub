-- ============================================================================
-- Migration: Add explicit foreign key relationships to public.users for PostgREST joins
-- ============================================================================

DO $$
BEGIN
    -- 1. group_members -> public.users
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.table_constraints 
        WHERE constraint_name = 'fk_group_members_public_users' 
          AND table_name = 'group_members'
    ) THEN
        ALTER TABLE public.group_members 
            ADD CONSTRAINT fk_group_members_public_users 
            FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;
    END IF;

    -- 2. notice_target_users -> public.users
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.table_constraints 
        WHERE constraint_name = 'fk_notice_target_users_public_users' 
          AND table_name = 'notice_target_users'
    ) THEN
        ALTER TABLE public.notice_target_users 
            ADD CONSTRAINT fk_notice_target_users_public_users 
            FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;
    END IF;

    -- 3. class_co_crs -> public.users
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.table_constraints 
        WHERE constraint_name = 'fk_class_co_crs_public_users' 
          AND table_name = 'class_co_crs'
    ) THEN
        ALTER TABLE public.class_co_crs 
            ADD CONSTRAINT fk_class_co_crs_public_users 
            FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;
    END IF;
END $$;

NOTIFY pgrst, 'reload schema';
