-- ============================================================================
-- Migration: Add app_versions table for In-App Update and Routine Automation
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.app_versions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    platform TEXT NOT NULL DEFAULT 'android', -- 'android', 'web', 'all'
    latest_version TEXT NOT NULL,
    build_number INT NOT NULL DEFAULT 1,
    download_url TEXT NOT NULL,
    release_notes TEXT,
    is_force_update BOOLEAN NOT NULL DEFAULT FALSE,
    min_supported_version TEXT DEFAULT '1.0.0',
    created_at TIMESTAMPTZ DEFAULT timezone('utc'::text, now()) NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- Enable RLS
ALTER TABLE public.app_versions ENABLE ROW LEVEL SECURITY;

-- Everyone (students, CRs, guests) can view app version info
DROP POLICY IF EXISTS "Public can view app_versions" ON public.app_versions;
CREATE POLICY "Public can view app_versions" ON public.app_versions
    FOR SELECT USING (true);

-- Authenticated admins / CRs can update version info
DROP POLICY IF EXISTS "Admins can manage app_versions" ON public.app_versions;
CREATE POLICY "Admins can manage app_versions" ON public.app_versions
    FOR ALL TO authenticated
    USING (EXISTS (
        SELECT 1 FROM public.users 
        WHERE users.id = auth.uid() 
          AND (users.role IN ('admin', 'super_admin', 'cr'))
    ));

-- Insert initial version record
INSERT INTO public.app_versions (platform, latest_version, build_number, download_url, release_notes, is_force_update)
VALUES 
    (
        'android', 
        '1.0.1', 
        2, 
        'https://unihubd.pages.dev/unihub.apk', 
        '• Emergency Call-Style Full-Screen Incoming Alert\n• In-App Update & Direct APK Download\n• Routine Multi-Interval Auto Reminders (1d, 12h, 1h, 10m)\n• Verified Play Protect Release Signature\n• CR Student Roster Management & Join Lock', 
        false
    ),
    (
        'web',
        '1.0.1',
        2,
        'https://unihubd.pages.dev',
        '• Routine multi-group support\n• Student roster and join locks\n• Notice cleanup rules',
        false
    )
ON CONFLICT DO NOTHING;

NOTIFY pgrst, 'reload schema';
