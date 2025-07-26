-- SQL to create the 'profiles' table for Talktwirl
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text unique not null,
  email text,
  created_at timestamp with time zone default timezone('utc'::text, now())
);

-- Enable Row Level Security
alter table public.profiles enable row level security;

-- Policy: Allow authenticated users to insert/update their own profile
create policy "Allow users to insert/update their profile" on public.profiles
  for all
  using (auth.uid() = id);
