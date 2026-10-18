-- Enable deletion of notices, notice_target_groups, and notifications
DO $$
BEGIN
    DROP POLICY IF EXISTS "Notice creators and CRs can delete notices" ON public.notices;
    CREATE POLICY "Notice creators and CRs can delete notices"
        ON public.notices FOR DELETE TO authenticated 
        USING (
            auth.uid() = created_by 
            OR (SELECT role::text FROM public.users WHERE id = auth.uid()) ILIKE 'cr'
            OR (SELECT role::text FROM public.users WHERE id = auth.uid()) ILIKE 'admin'
        );

    DROP POLICY IF EXISTS "Notice creators can delete notice target groups" ON public.notice_target_groups;
    CREATE POLICY "Notice creators can delete notice target groups"
        ON public.notice_target_groups FOR DELETE TO authenticated 
        USING (true);

    DROP POLICY IF EXISTS "Authenticated users can delete notifications" ON public.notifications;
    CREATE POLICY "Authenticated users can delete notifications"
        ON public.notifications FOR DELETE TO authenticated 
        USING (
            auth.uid() = created_by 
            OR (SELECT role::text FROM public.users WHERE id = auth.uid()) ILIKE 'cr'
            OR (SELECT role::text FROM public.users WHERE id = auth.uid()) ILIKE 'admin'
        );
END $$;
