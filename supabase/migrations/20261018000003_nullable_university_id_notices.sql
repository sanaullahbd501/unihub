-- Migration: Allow notices to be published without mandatory university_id
-- Enables CRs to broadcast group/class notices seamlessly

ALTER TABLE public.notices ALTER COLUMN university_id DROP NOT NULL;

INSERT INTO public.universities (id, name, short_name) 
VALUES ('c4b3a880-1a1a-4f55-9a88-888888888888', 'World University of Bangladesh', 'WUB')
ON CONFLICT DO NOTHING;
