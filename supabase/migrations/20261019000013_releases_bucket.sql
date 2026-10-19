-- Create public releases storage bucket for APK downloads
INSERT INTO storage.buckets (id, name, public, file_size_limit) 
VALUES ('releases', 'releases', true, 104857600)
ON CONFLICT (id) DO UPDATE SET public = true, file_size_limit = 104857600;

DROP POLICY IF EXISTS "Public can download releases" ON storage.objects;
CREATE POLICY "Public can download releases" 
ON storage.objects FOR SELECT 
USING (bucket_id = 'releases');

DROP POLICY IF EXISTS "Allow anon and auth upload to releases" ON storage.objects;
CREATE POLICY "Allow anon and auth upload to releases" 
ON storage.objects FOR ALL 
USING (bucket_id = 'releases')
WITH CHECK (bucket_id = 'releases');
