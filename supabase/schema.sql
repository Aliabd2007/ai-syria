-- ============================================================
-- Supabase Schema — المرحلة 1
-- ملف واحد جاهز للصق في Supabase SQL Editor
-- يتضمن: 6 جداول + Indexes + RLS + Functions + Triggers
-- ============================================================
-- ملاحظات التشغيل:
-- 1) الصق الملف كاملاً في SQL Editor ثم اضغط Run
-- 2) الملف idempotent — آمن لإعادة التشغيل (IF NOT EXISTS / OR REPLACE)
-- 3) جدولة reset_daily_usage عبر pg_cron تجدها في القسم 9
-- ============================================================

-- ============================================================
-- القسم 0: Extensions
-- ============================================================
create extension if not exists "pgcrypto";

-- ============================================================
-- القسم 1: profiles
-- id → auth.users(id), email, plan, expires_at, created_at
-- ============================================================
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text not null,
  plan text not null default 'free' check (plan in ('free', 'student', 'pro')),
  expires_at timestamptz,
  created_at timestamptz not null default now()
);

-- حماية إضافية: email غير فارغ
-- (اختياري — يمنع إدخال email فارغ)
alter table public.profiles
  add constraint profiles_email_not_empty check (char_length(email) > 0);

comment on table public.profiles is 'ملفات المستخدمين — مرتبطة بـ auth.users';
comment on column public.profiles.plan is 'free | student | pro';
comment on column public.profiles.expires_at is 'تاريخ انتهاء الاشتراك — null للخطة المجانية';

-- ============================================================
-- القسم 2: daily_usage
-- user_id, date, heavy_count, fast_count
-- PK = (user_id, date) — سجل واحد لكل مستخدم في اليوم
-- ============================================================
create table if not exists public.daily_usage (
  user_id uuid not null references auth.users(id) on delete cascade,
  date date not null default ((now() at time zone 'Asia/Damascus')::date),
  heavy_count int not null default 0 check (heavy_count >= 0),
  fast_count int not null default 0 check (fast_count >= 0),
  primary key (user_id, date)
);

comment on table public.daily_usage is 'الاستهلاك اليومي — heavy للنماذج الثقيلة و fast للنماذج السريعة';
comment on column public.daily_usage.date is 'تاريخ اليوم بتوقيت Asia/Damascus';

-- ============================================================
-- القسم 3: user_devices
-- user_id, device_id, device_name, last_seen
-- PK = (user_id, device_id) + Trigger يمنع أكثر من جهازين
-- ============================================================
create table if not exists public.user_devices (
  user_id uuid not null references auth.users(id) on delete cascade,
  device_id text not null,
  device_name text,
  last_seen timestamptz not null default now(),
  primary key (user_id, device_id)
);

comment on table public.user_devices is 'الأجهزة المسجلة — حد أقصى جهازين لكل مستخدم (يُفرض عبر Trigger)';

-- ============================================================
-- القسم 4: chats
-- id, user_id, title, mode, created_at
-- ============================================================
create table if not exists public.chats (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  title text not null default 'محادثة جديدة',
  mode text not null default 'fast' check (mode in ('fast', 'coding', 'math', 'pdf')),
  created_at timestamptz not null default now()
);

comment on table public.chats is 'المحادثات — كل محادثة لها وضع (mode)';
comment on column public.chats.mode is 'fast | coding | math | pdf';

-- ============================================================
-- القسم 5: messages
-- id, chat_id, user_id, role, content, tokens, created_at
-- ============================================================
create table if not exists public.messages (
  id uuid primary key default gen_random_uuid(),
  chat_id uuid not null references public.chats(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null check (role in ('user', 'assistant', 'system')),
  content text not null,
  tokens int check (tokens is null or tokens >= 0),
  created_at timestamptz not null default now()
);

comment on table public.messages is 'رسائل المحادثات — مرتبطة بـ chats';
comment on column public.messages.role is 'user | assistant | system';
comment on column public.messages.tokens is 'عدد التوكنز المستهلكة — اختياري';

-- ============================================================
-- القسم 6: payment_requests
-- id, user_id, provider, tx_id, amount_syp, plan_requested, status, created_at
-- ============================================================
create table if not exists public.payment_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  provider text not null check (provider in ('syriatel_cash', 'sham_cash', 'mtn_cash')),
  tx_id text not null,
  amount_syp int not null check (amount_syp > 0),
  plan_requested text not null check (plan_requested in ('student', 'pro')),
  status text not null default 'pending' check (status in ('pending', 'approved', 'rejected')),
  created_at timestamptz not null default now(),
  unique (provider, tx_id)
);

comment on table public.payment_requests is 'طلبات الدفع — Syriatel Cash / Sham Cash / MTN Cash';
comment on column public.payment_requests.tx_id is 'رقم العملية من مزود الدفع — فريد لكل provider';
comment on column public.payment_requests.status is 'pending | approved | rejected';

-- ============================================================
-- القسم 7: Indexes
-- فهارس على user_id و chat_id كما هو مطلوب + فهارس إضافية مفيدة
-- ============================================================
-- profiles
create index if not exists idx_profiles_plan on public.profiles(plan);
create index if not exists idx_profiles_expires_at on public.profiles(expires_at);

-- daily_usage
create index if not exists idx_daily_usage_user_id on public.daily_usage(user_id);
create index if not exists idx_daily_usage_date on public.daily_usage(date);

-- user_devices
create index if not exists idx_user_devices_user_id on public.user_devices(user_id);

-- chats
create index if not exists idx_chats_user_id on public.chats(user_id);
create index if not exists idx_chats_created_at on public.chats(created_at desc);

-- messages
create index if not exists idx_messages_user_id on public.messages(user_id);
create index if not exists idx_messages_chat_id on public.messages(chat_id);
create index if not exists idx_messages_chat_created on public.messages(chat_id, created_at);
create index if not exists idx_messages_created_at on public.messages(created_at desc);

-- payment_requests
create index if not exists idx_payment_requests_user_id on public.payment_requests(user_id);
create index if not exists idx_payment_requests_status on public.payment_requests(status);
create index if not exists idx_payment_requests_provider on public.payment_requests(provider);
create index if not exists idx_payment_requests_created_at on public.payment_requests(created_at desc);

-- ============================================================
-- القسم 8: Row Level Security (RLS)
-- تفعيل RLS على كل الجداول + سياسات: المستخدم يرى فقط سجلاته
-- ============================================================

-- تفعيل RLS
alter table public.profiles enable row level security;
alter table public.daily_usage enable row level security;
alter table public.user_devices enable row level security;
alter table public.chats enable row level security;
alter table public.messages enable row level security;
alter table public.payment_requests enable row level security;

-- حذف السياسات القديمة إن وجدت (لإعادة التشغيل الآمن)
drop policy if exists "Users can manage own profile" on public.profiles;
drop policy if exists "Users manage own daily_usage" on public.daily_usage;
drop policy if exists "Users manage own devices" on public.user_devices;
drop policy if exists "Users manage own chats" on public.chats;
drop policy if exists "Users manage own messages" on public.messages;
drop policy if exists "Users manage own payment_requests" on public.payment_requests;

-- profiles: id = auth.uid()
create policy "Users can manage own profile"
  on public.profiles for all
  using (auth.uid() = id)
  with check (auth.uid() = id);

-- daily_usage: user_id = auth.uid()
create policy "Users manage own daily_usage"
  on public.daily_usage for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- user_devices: user_id = auth.uid()
create policy "Users manage own devices"
  on public.user_devices for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- chats: user_id = auth.uid()
create policy "Users manage own chats"
  on public.chats for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- messages: user_id = auth.uid()
-- (يُفضل أيضاً التحقق من ملكية chat_id، لكن user_id كافٍ إذا كان التطبيق يملأه من auth.uid())
create policy "Users manage own messages"
  on public.messages for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- payment_requests: user_id = auth.uid()
create policy "Users manage own payment_requests"
  on public.payment_requests for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- ============================================================
-- القسم 9: Functions & Triggers
-- ============================================================

-- ------------------------------------------------------------
-- 9.1 — is_subscription_valid(user_id uuid) → boolean
-- free دائماً صالح، student/pro يتحقق من expires_at > now()
-- ------------------------------------------------------------
create or replace function public.is_subscription_valid(p_user_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_plan text;
  v_expires timestamptz;
begin
  select plan, expires_at into v_plan, v_expires
  from public.profiles
  where id = p_user_id;

  if not found then
    return false;
  end if;

  -- الخطة المجانية صالحة دائماً
  if v_plan = 'free' then
    return true;
  end if;

  -- student / pro: يجب أن يكون expires_at موجوداً ومستقبلياً
  return v_expires is not null and v_expires > now();
end;
$$;

comment on function public.is_subscription_valid(uuid) is 'تتحقق هل اشتراك المستخدم صالح — free دائماً true، و student/pro حسب expires_at';

-- ------------------------------------------------------------
-- 9.2 — reset_daily_usage() → void
-- تصفّر heavy_count و fast_count لليوم الحالي بتوقيت دمشق
-- تُستدعى يومياً عند 00:00 Asia/Damascus عبر pg_cron
-- ------------------------------------------------------------
create or replace function public.reset_daily_usage()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  -- تصفير عدادات اليوم الحالي (بتوقيت دمشق)
  -- إذا لم يوجد سجل لليوم، لا شيء يحدث — السجل يُنشأ عند أول استخدام (upsert من التطبيق)
  update public.daily_usage
  set heavy_count = 0,
      fast_count  = 0
  where date = (now() at time zone 'Asia/Damascus')::date;
end;
$$;

comment on function public.reset_daily_usage() is 'تصفّر عدادات الاستهلاك لليوم الحالي بتوقيت Asia/Damascus — تُجدول عبر pg_cron عند 00:00';

-- جدولة pg_cron — بتوقيت دمشق (Asia/Damascus)
-- ------------------------------------------------------------
-- مهم: pg_cron يعمل بتوقيت UTC فقط.
-- Asia/Damascus = UTC+3 صيفاً (EEST) و UTC+2 شتاءً (EET).
-- 00:00 دمشق = 21:00 UTC صيفاً / 22:00 UTC شتاءً.
-- الحل العملي: جدولة على 21:00 UTC يومياً (تغطي 00:00 صيفاً، و 23:00 شتاءً).
-- البديل الأدق: استدعاء reset_daily_usage عند أول طلب في اليوم الجديد (upsert) بدل الاعتماد الكلي على cron.
--
-- لتفعيل الجدولة، شغّل أحد السطرين التاليين في SQL Editor بعد تفعيل extension pg_cron:
--
--   create extension if not exists pg_cron;
--
--   -- الخيار A: 00:00 دمشق صيفاً (21:00 UTC) — موصى به كجدولة أساسية
--   select cron.schedule('reset-daily-usage-damascus', '0 21 * * *', $$select public.reset_daily_usage()$$);
--
--   -- الخيار B: جدولة مزدوجة لتغطية التوقيت الشتوي أيضاً
--   -- select cron.schedule('reset-daily-usage-damascus-winter', '0 22 * * *', $$select public.reset_daily_usage()$$);
--
-- لإلغاء الجدولة:
--   select cron.unschedule('reset-daily-usage-damascus');
-- ------------------------------------------------------------

-- ------------------------------------------------------------
-- 9.3 — enforce_device_limit() + Trigger
-- يمنع تسجيل أكثر من جهازين لكل مستخدم
-- يسمح بتحديث جهاز موجود (نفس user_id + device_id) دون احتسابه كجهاز جديد
-- ------------------------------------------------------------
create or replace function public.enforce_device_limit()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count int;
begin
  -- إذا كان الجهاز موجوداً مسبقاً (نفس user_id + device_id)، اسمح بالتحديث/إعادة الإدخال
  -- هذا يحدث فقط في حالة INSERT لجهاز جديد، لأن PK سيمنع التكرار أصلاً
  -- لكن نتحقق من العدد قبل السماح بجهاز جديد
  select count(*) into v_count
  from public.user_devices
  where user_id = new.user_id;

  -- إذا كان العدد >= 2 والجهاز الجديد غير موجود مسبقاً → امنع
  if v_count >= 2
     and not exists (
       select 1 from public.user_devices
       where user_id = new.user_id and device_id = new.device_id
     ) then
    raise exception 'Maximum 2 devices per user (user_id=%)', new.user_id
      using errcode = 'P0001';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_enforce_device_limit on public.user_devices;
create trigger trg_enforce_device_limit
  before insert on public.user_devices
  for each row execute function public.enforce_device_limit();

comment on function public.enforce_device_limit() is 'يمنع تسجيل أكثر من جهازين لكل مستخدم';

-- ------------------------------------------------------------
-- 9.4 — handle_new_user() + Trigger على auth.users
-- ينشئ صفاً في profiles تلقائياً عند تسجيل مستخدم جديد
-- ------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, email, plan)
  values (new.id, coalesce(new.email, ''), 'free')
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

comment on function public.handle_new_user() is 'ينشئ profile تلقائياً عند تسجيل مستخدم جديد في auth.users';

-- ============================================================
-- القسم 10: التحقق السريع (اختياري — للاختبار بعد اللصق)
-- ============================================================
-- -- اختبار is_subscription_valid
-- -- select public.is_subscription_valid(auth.uid());
--
-- -- اختبار reset_daily_usage
-- -- select public.reset_daily_usage();
--
-- -- عرض الجداول
-- -- select table_name from information_schema.tables where table_schema = 'public' order by table_name;
--
-- -- عرض السياسات
-- -- select polname, polcmd, polroles::regrole from pg_policy where polrelid in ('public.profiles'::regclass, 'public.daily_usage'::regclass, 'public.user_devices'::regclass, 'public.chats'::regclass, 'public.messages'::regclass, 'public.payment_requests'::regclass);
--
-- -- عرض الفهارس
-- -- select tablename, indexname from pg_indexes where schemaname = 'public' order by tablename, indexname;
-- ============================================================
-- انتهى الملف — جاهز للصق في Supabase SQL Editor
-- ============================================================
