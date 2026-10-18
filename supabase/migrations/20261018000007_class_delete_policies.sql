-- Enable class creators and group creators to delete classes and class_groups
DO $$
BEGIN
    DROP POLICY IF EXISTS "Class creators can delete their classes" ON public.classes;
    CREATE POLICY "Class creators can delete their classes"
        ON public.classes FOR DELETE TO authenticated 
        USING (auth.uid() = created_by);

    DROP POLICY IF EXISTS "Class group creators can delete their groups" ON public.class_groups;
    CREATE POLICY "Class group creators can delete their groups"
        ON public.class_groups FOR DELETE TO authenticated 
        USING (auth.uid() = created_by);
END $$;
