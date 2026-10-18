-- Enable Realtime for notices, routines, exams, notifications
DO $$
BEGIN
    BEGIN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.notices;
    EXCEPTION WHEN duplicate_object THEN
        -- already added
    END;

    BEGIN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.routines;
    EXCEPTION WHEN duplicate_object THEN
        -- already added
    END;

    BEGIN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.exams;
    EXCEPTION WHEN duplicate_object THEN
        -- already added
    END;

    BEGIN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.notifications;
    EXCEPTION WHEN duplicate_object THEN
        -- already added
    END;
END $$;
