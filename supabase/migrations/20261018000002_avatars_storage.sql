-- Create avatars storage bucket
INSERT INTO storage.buckets (id, name, public) 
VALUES ('avatars', 'avatars', true)
ON CONFLICT (id) DO NOTHING;

-- Storage policies for avatars
DROP POLICY IF EXISTS "Public Access" ON storage.objects;
CREATE POLICY "Public Access" 
ON storage.objects FOR SELECT 
USING (bucket_id = 'avatars');

DROP POLICY IF EXISTS "Authenticated user upload" ON storage.objects;
CREATE POLICY "Authenticated user upload" 
ON storage.objects FOR INSERT 
TO authenticated 
WITH CHECK (bucket_id = 'avatars');

DROP POLICY IF EXISTS "Authenticated user update" ON storage.objects;
CREATE POLICY "Authenticated user update" 
ON storage.objects FOR UPDATE 
TO authenticated 
USING (bucket_id = 'avatars');
