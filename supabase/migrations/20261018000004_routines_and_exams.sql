-- Routines table
CREATE TABLE IF NOT EXISTS public.routines (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    class_id UUID REFERENCES public.classes(id) ON DELETE CASCADE,
    group_id UUID REFERENCES public.class_groups(id) ON DELETE CASCADE,
    subject TEXT NOT NULL,
    teacher_name TEXT,
    day_of_week INT NOT NULL, -- 1=Monday, 2=Tuesday, ..., 7=Sunday
    start_time TIME NOT NULL,
    end_time TIME NOT NULL,
    is_online BOOLEAN NOT NULL DEFAULT false,
    room_number TEXT,
    meeting_link TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

-- Exams table
CREATE TABLE IF NOT EXISTS public.exams (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    class_id UUID REFERENCES public.classes(id) ON DELETE CASCADE,
    group_id UUID REFERENCES public.class_groups(id) ON DELETE CASCADE,
    subject TEXT NOT NULL,
    exam_type TEXT NOT NULL, -- 'CT', 'MID', 'FINAL', 'QUIZ'
    exam_date DATE NOT NULL,
    start_time TIME NOT NULL,
    end_time TIME NOT NULL,
    room_number TEXT,
    is_online BOOLEAN NOT NULL DEFAULT false,
    meeting_link TEXT,
    delete_at TIMESTAMPTZ NOT NULL, -- Auto-expiring 3 hours after end_time
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

-- Enable RLS
ALTER TABLE public.routines ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.exams ENABLE ROW LEVEL SECURITY;

-- Routines policies
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'routines' AND policyname = 'Public read routines') THEN
        CREATE POLICY "Public read routines" ON public.routines FOR SELECT USING (true);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'routines' AND policyname = 'Authenticated insert routines') THEN
        CREATE POLICY "Authenticated insert routines" ON public.routines FOR INSERT TO authenticated WITH CHECK (true);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'routines' AND policyname = 'Authenticated update routines') THEN
        CREATE POLICY "Authenticated update routines" ON public.routines FOR UPDATE TO authenticated USING (true);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'routines' AND policyname = 'Authenticated delete routines') THEN
        CREATE POLICY "Authenticated delete routines" ON public.routines FOR DELETE TO authenticated USING (true);
    END IF;
END $$;

-- Exams policies
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'exams' AND policyname = 'Public read exams') THEN
        CREATE POLICY "Public read exams" ON public.exams FOR SELECT USING (true);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'exams' AND policyname = 'Authenticated insert exams') THEN
        CREATE POLICY "Authenticated insert exams" ON public.exams FOR INSERT TO authenticated WITH CHECK (true);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'exams' AND policyname = 'Authenticated update exams') THEN
        CREATE POLICY "Authenticated update exams" ON public.exams FOR UPDATE TO authenticated USING (true);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'exams' AND policyname = 'Authenticated delete exams') THEN
        CREATE POLICY "Authenticated delete exams" ON public.exams FOR DELETE TO authenticated USING (true);
    END IF;
END $$;
