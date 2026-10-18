-- ============================================================================
-- UniHub Database Schema - Initial Migration (Clean Slate)
-- Architecture aligned with UniHub Master Handover & Detailed Product Plan
-- ============================================================================

-- 1. Create Enums
DO $$ BEGIN
    CREATE TYPE public.user_role AS ENUM ('student', 'cr', 'admin', 'super_admin');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
    CREATE TYPE public.notification_type AS ENUM ('NOTICE', 'ROUTINE', 'GENERAL', 'EMERGENCY', 'RESULT', 'ASSIGNMENT', 'LIBRARY');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
    CREATE TYPE public.target_audience_type AS ENUM ('ALL', 'UNIVERSITY', 'DEPARTMENT', 'BATCH', 'USER');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

-- 2. Universities Table
CREATE TABLE IF NOT EXISTS public.universities (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    short_name TEXT,
    logo_url TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

-- 3. Departments Table
CREATE TABLE IF NOT EXISTS public.departments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    university_id UUID NOT NULL REFERENCES public.universities(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    short_code TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

-- 4. User Profiles Table (Linked to Supabase auth.users)
CREATE TABLE IF NOT EXISTS public.users (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    email TEXT NOT NULL,
    full_name TEXT,
    university_id UUID REFERENCES public.universities(id) ON DELETE SET NULL,
    department_id UUID REFERENCES public.departments(id) ON DELETE SET NULL,
    batch TEXT,
    semester TEXT,
    role public.user_role NOT NULL DEFAULT 'student',
    avatar_url TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

-- 5. Notification Tokens Table (Push Notification - Priority #1)
CREATE TABLE IF NOT EXISTS public.notification_tokens (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    fcm_token TEXT NOT NULL UNIQUE,
    platform TEXT NOT NULL CHECK (platform IN ('android', 'ios', 'web')),
    device_label TEXT,
    is_active BOOLEAN NOT NULL DEFAULT true,
    last_seen_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

-- 6. Notifications Table (Central Notification Record)
CREATE TABLE IF NOT EXISTS public.notifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title TEXT NOT NULL,
    body TEXT NOT NULL,
    type public.notification_type NOT NULL DEFAULT 'GENERAL',
    target_type public.target_audience_type NOT NULL DEFAULT 'ALL',
    university_id UUID REFERENCES public.universities(id) ON DELETE CASCADE,
    department_id UUID REFERENCES public.departments(id) ON DELETE CASCADE,
    batch TEXT,
    target_user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    deep_link TEXT,
    priority TEXT NOT NULL DEFAULT 'NORMAL',
    data JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

-- 7. Notification Receivers Table (In-app notification history & read state)
CREATE TABLE IF NOT EXISTS public.notification_receivers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    notification_id UUID NOT NULL REFERENCES public.notifications(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    is_read BOOLEAN NOT NULL DEFAULT false,
    read_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    CONSTRAINT unique_user_notification UNIQUE (notification_id, user_id)
);

-- 8. Notices Table
CREATE TABLE IF NOT EXISTS public.notices (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    university_id UUID NOT NULL REFERENCES public.universities(id) ON DELETE CASCADE,
    department_id UUID REFERENCES public.departments(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    content TEXT NOT NULL,
    category TEXT NOT NULL DEFAULT 'GENERAL',
    attachment_url TEXT,
    is_published BOOLEAN NOT NULL DEFAULT true,
    created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

-- 9. Routines Table
CREATE TABLE IF NOT EXISTS public.routines (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    university_id UUID NOT NULL REFERENCES public.universities(id) ON DELETE CASCADE,
    department_id UUID NOT NULL REFERENCES public.departments(id) ON DELETE CASCADE,
    batch TEXT NOT NULL,
    semester TEXT NOT NULL,
    day_of_week TEXT NOT NULL,
    schedule JSONB NOT NULL DEFAULT '[]'::jsonb,
    effective_from DATE NOT NULL DEFAULT CURRENT_DATE,
    created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

-- 10. Library Files Table
CREATE TABLE IF NOT EXISTS public.library_files (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    university_id UUID NOT NULL REFERENCES public.universities(id) ON DELETE CASCADE,
    department_id UUID REFERENCES public.departments(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    description TEXT,
    file_url TEXT NOT NULL,
    file_type TEXT,
    file_size_bytes BIGINT,
    uploaded_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_users_university_dept ON public.users(university_id, department_id);
CREATE INDEX IF NOT EXISTS idx_notification_tokens_user ON public.notification_tokens(user_id);
CREATE INDEX IF NOT EXISTS idx_notification_receivers_user ON public.notification_receivers(user_id, is_read);
CREATE INDEX IF NOT EXISTS idx_notifications_target ON public.notifications(university_id, department_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_notices_university_dept ON public.notices(university_id, department_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_routines_lookup ON public.routines(university_id, department_id, batch, semester);

-- Auto User Profile Trigger
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger AS $$
BEGIN
    INSERT INTO public.users (id, email, full_name, role)
    VALUES (
        new.id,
        new.email,
        coalesce(new.raw_user_meta_data->>'full_name', split_part(new.email, '@', 1)),
        'student'
    )
    ON CONFLICT (id) DO NOTHING;
    RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE PROCEDURE public.handle_new_user();

-- Enable RLS
ALTER TABLE public.universities ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.departments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notification_tokens ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notification_receivers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notices ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.routines ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.library_files ENABLE ROW LEVEL SECURITY;

-- Policies
DROP POLICY IF EXISTS "Universities are viewable by all authenticated users" ON public.universities;
CREATE POLICY "Universities are viewable by all authenticated users"
    ON public.universities FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "Departments are viewable by all authenticated users" ON public.departments;
CREATE POLICY "Departments are viewable by all authenticated users"
    ON public.departments FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "Users can view their own profile" ON public.users;
CREATE POLICY "Users can view their own profile"
    ON public.users FOR SELECT TO authenticated USING (auth.uid() = id);

DROP POLICY IF EXISTS "Users can update permitted fields of their own profile" ON public.users;
CREATE POLICY "Users can update permitted fields of their own profile"
    ON public.users FOR UPDATE TO authenticated USING (auth.uid() = id)
    WITH CHECK (auth.uid() = id AND role = (SELECT role FROM public.users WHERE id = auth.uid()));

DROP POLICY IF EXISTS "Users can manage their own device tokens" ON public.notification_tokens;
CREATE POLICY "Users can manage their own device tokens"
    ON public.notification_tokens FOR ALL TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can view notifications targeted to their scope" ON public.notifications;
CREATE POLICY "Users can view notifications targeted to their scope"
    ON public.notifications FOR SELECT TO authenticated USING (
        target_type = 'ALL' OR target_user_id = auth.uid() OR university_id IN (SELECT university_id FROM public.users WHERE id = auth.uid())
    );

DROP POLICY IF EXISTS "Users can view and update their own notification read status" ON public.notification_receivers;
CREATE POLICY "Users can view and update their own notification read status"
    ON public.notification_receivers FOR ALL TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Notices are viewable by users in the same university" ON public.notices;
CREATE POLICY "Notices are viewable by users in the same university"
    ON public.notices FOR SELECT TO authenticated USING (
        is_published = true AND (university_id IN (SELECT university_id FROM public.users WHERE id = auth.uid()) OR university_id IS NULL)
    );

DROP POLICY IF EXISTS "Routines are viewable by users in the same department" ON public.routines;
CREATE POLICY "Routines are viewable by users in the same department"
    ON public.routines FOR SELECT TO authenticated USING (
        university_id IN (SELECT university_id FROM public.users WHERE id = auth.uid())
    );

DROP POLICY IF EXISTS "Library files are viewable by users in the same university" ON public.library_files;
CREATE POLICY "Library files are viewable by users in the same university"
    ON public.library_files FOR SELECT TO authenticated USING (
        university_id IN (SELECT university_id FROM public.users WHERE id = auth.uid())
    );
