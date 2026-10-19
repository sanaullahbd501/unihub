-- ============================================================================
-- Migration: Routine Reminders Queue and Dispatch System
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.routine_sent_reminders (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    routine_id UUID REFERENCES public.routines(id) ON DELETE CASCADE,
    interval_label TEXT NOT NULL, -- '1_day', '12_hours', '6_hours', '3_hours', '1_hour', '30_min', '10_min', 'now'
    reminder_date DATE NOT NULL,
    sent_at TIMESTAMPTZ DEFAULT timezone('utc'::text, now()) NOT NULL,
    UNIQUE (routine_id, interval_label, reminder_date)
);

ALTER TABLE public.routine_sent_reminders ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Allow authenticated read of sent reminders" ON public.routine_sent_reminders
    FOR SELECT TO authenticated USING (true);

CREATE POLICY "Allow system insert of sent reminders" ON public.routine_sent_reminders
    FOR INSERT TO authenticated WITH CHECK (true);

NOTIFY pgrst, 'reload schema';
