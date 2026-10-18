-- ============================================================================
-- Migration: CR Management, Classes, Groups, Co-CR, Multi-Group Targeting
-- ============================================================================

-- 1. Classes Table
CREATE TABLE IF NOT EXISTS public.classes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    university_name TEXT DEFAULT 'World University of Bangladesh (WUB)',
    department_name TEXT DEFAULT 'CSE',
    created_by UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

-- 2. Class Groups (e.g., 95B, 95C)
CREATE TABLE IF NOT EXISTS public.class_groups (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    class_id UUID NOT NULL REFERENCES public.classes(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    invite_code TEXT UNIQUE NOT NULL,
    description TEXT,
    created_by UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

-- 3. Class Co-CRs
CREATE TABLE IF NOT EXISTS public.class_co_crs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    class_id UUID NOT NULL REFERENCES public.classes(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    added_by UUID REFERENCES auth.users(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    CONSTRAINT unique_class_co_cr UNIQUE (class_id, user_id)
);

-- 4. Group Members (Students enrolled in groups)
CREATE TABLE IF NOT EXISTS public.group_members (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    group_id UUID NOT NULL REFERENCES public.class_groups(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    role TEXT NOT NULL DEFAULT 'student',
    joined_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    CONSTRAINT unique_group_member UNIQUE (group_id, user_id)
);

-- 5. Notice Target Groups (Many-to-many relationship for multi-group notice targeting)
CREATE TABLE IF NOT EXISTS public.notice_target_groups (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    notice_id UUID NOT NULL REFERENCES public.notices(id) ON DELETE CASCADE,
    group_id UUID NOT NULL REFERENCES public.class_groups(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    CONSTRAINT unique_notice_target_group UNIQUE (notice_id, group_id)
);

-- 6. Add event_time and target_type to notices if not already present
ALTER TABLE public.notices 
    ADD COLUMN IF NOT EXISTS event_time TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS target_type TEXT DEFAULT 'GROUP';

-- 7. Update User Profile RLS to allow role update by user
DROP POLICY IF EXISTS "Users can update permitted fields of their own profile" ON public.users;
CREATE POLICY "Users can update permitted fields of their own profile"
    ON public.users FOR UPDATE TO authenticated 
    USING (auth.uid() = id)
    WITH CHECK (auth.uid() = id);

DROP POLICY IF EXISTS "Users can view profiles" ON public.users;
CREATE POLICY "Users can view profiles"
    ON public.users FOR SELECT TO authenticated 
    USING (true);

-- 8. Enable RLS on new tables
ALTER TABLE public.classes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.class_groups ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.class_co_crs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.group_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notice_target_groups ENABLE ROW LEVEL SECURITY;

-- 9. RLS Policies
DROP POLICY IF EXISTS "Classes are viewable by authenticated users" ON public.classes;
CREATE POLICY "Classes are viewable by authenticated users"
    ON public.classes FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "Authenticated users can create classes" ON public.classes;
CREATE POLICY "Authenticated users can create classes"
    ON public.classes FOR INSERT TO authenticated WITH CHECK (auth.uid() = created_by);

DROP POLICY IF EXISTS "Class creators can update their classes" ON public.classes;
CREATE POLICY "Class creators can update their classes"
    ON public.classes FOR UPDATE TO authenticated USING (auth.uid() = created_by);

DROP POLICY IF EXISTS "Class groups are viewable by authenticated users" ON public.class_groups;
CREATE POLICY "Class groups are viewable by authenticated users"
    ON public.class_groups FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "Creators and Co-CRs can create class groups" ON public.class_groups;
CREATE POLICY "Creators and Co-CRs can create class groups"
    ON public.class_groups FOR INSERT TO authenticated WITH CHECK (auth.uid() = created_by);

DROP POLICY IF EXISTS "Group members are viewable by authenticated users" ON public.group_members;
CREATE POLICY "Group members are viewable by authenticated users"
    ON public.group_members FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "Users can join a group" ON public.group_members;
CREATE POLICY "Users can join a group"
    ON public.group_members FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can leave a group" ON public.group_members;
CREATE POLICY "Users can leave a group"
    ON public.group_members FOR DELETE TO authenticated USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Co-CRs are viewable by authenticated users" ON public.class_co_crs;
CREATE POLICY "Co-CRs are viewable by authenticated users"
    ON public.class_co_crs FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "Class creators can add Co-CRs" ON public.class_co_crs;
CREATE POLICY "Class creators can add Co-CRs"
    ON public.class_co_crs FOR INSERT TO authenticated WITH CHECK (true);

DROP POLICY IF EXISTS "Notice target groups are viewable by authenticated users" ON public.notice_target_groups;
CREATE POLICY "Notice target groups are viewable by authenticated users"
    ON public.notice_target_groups FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "Notice creators can insert target groups" ON public.notice_target_groups;
CREATE POLICY "Notice creators can insert target groups"
    ON public.notice_target_groups FOR INSERT TO authenticated WITH CHECK (true);

-- 10. Notices RLS Update (Allow CRs to insert notices and allow students to view notices)
DROP POLICY IF EXISTS "Notices are insertable by authenticated users" ON public.notices;
CREATE POLICY "Notices are insertable by authenticated users"
    ON public.notices FOR INSERT TO authenticated WITH CHECK (auth.uid() = created_by);

DROP POLICY IF EXISTS "Notices are viewable by authenticated users" ON public.notices;
CREATE POLICY "Notices are viewable by authenticated users"
    ON public.notices FOR SELECT TO authenticated USING (true);
