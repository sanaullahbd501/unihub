-- ============================================================================
-- Migration: Add foreign key relationship from classes.created_by to public.users
-- ============================================================================

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.table_constraints 
        WHERE constraint_name = 'fk_classes_created_by_public_users' 
          AND table_name = 'classes'
    ) THEN
        ALTER TABLE public.classes 
            ADD CONSTRAINT fk_classes_created_by_public_users 
            FOREIGN KEY (created_by) REFERENCES public.users(id) ON DELETE SET NULL;
    END IF;
END $$;

NOTIFY pgrst, 'reload schema';
