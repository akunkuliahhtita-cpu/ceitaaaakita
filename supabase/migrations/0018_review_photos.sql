-- 0018_review_photos.sql
alter table public.reviews add column if not exists photos text[] not null default '{}';
alter table public.reviews drop constraint if exists reviews_photos_limit;
alter table public.reviews add constraint reviews_photos_limit check(cardinality(photos)<=5);

grant insert(user_id,order_id,rating,comment,display_name,photos) on public.reviews to authenticated;
grant update(rating,comment,display_name,photos) on public.reviews to authenticated;
grant select(id,rating,comment,display_name,photos,status,created_at,updated_at) on public.reviews to anon;

create or replace view public.review_feed with(security_barrier=true) as
select r.id,r.display_name as name,r.rating,r.title,r.comment as body,r.photos,r.is_featured,r.helpful_count,
 (r.created_at at time zone 'Asia/Jakarta')::date as day,
 exists(select 1 from public.review_votes v where v.review_id=r.id and v.user_id=auth.uid()) as voted,
 r.created_at,coalesce(o.plan_name,p.name,'Paket') as plan_name
from public.reviews r join public.orders o on o.id=r.order_id left join public.plans p on p.id=r.plan_id
where r.status='approved' and r.rating between 1 and 5 and o.status='paid' and o.base_amount>0 and o.user_id=r.user_id and o.plan_id=r.plan_id
order by r.created_at desc,r.id desc;
revoke all on public.review_feed from public,anon,authenticated;
grant select on public.review_feed to anon,authenticated;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('review-photos','review-photos',true,5242880,array['image/jpeg','image/png','image/webp'])
on conflict(id) do update set public=true,file_size_limit=5242880,allowed_mime_types=array['image/jpeg','image/png','image/webp'];

drop policy if exists review_photos_public_read on storage.objects;
create policy review_photos_public_read on storage.objects for select to anon,authenticated using(bucket_id='review-photos');
drop policy if exists review_photos_owner_upload on storage.objects;
create policy review_photos_owner_upload on storage.objects for insert to authenticated with check(
 bucket_id='review-photos' and exists(
  select 1 from public.orders o where o.id::text=(storage.foldername(name))[1]
   and o.user_id=auth.uid() and o.status='paid' and o.base_amount>0 and o.plan_id is not null
 )
);
drop policy if exists review_photos_owner_delete on storage.objects;
create policy review_photos_owner_delete on storage.objects for delete to authenticated using(
 bucket_id='review-photos' and exists(
  select 1 from public.orders o where o.id::text=(storage.foldername(name))[1] and o.user_id=auth.uid()
 )
);
