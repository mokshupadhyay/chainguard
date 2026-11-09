-- ChainGuard index schema. This is an INDEX of on-chain state, never enforcement state.
create table if not exists guards (
  address text primary key,
  owner text not null,
  chain_id bigint not null,
  created_tx_hash text,
  created_block bigint,
  created_at timestamptz not null default now()
);
create index if not exists guards_owner_idx on guards (lower(owner));

create table if not exists events (
  id bigserial primary key,
  chain_id bigint not null,
  tx_hash text not null,
  log_index integer not null,
  block_number bigint not null,
  block_time timestamptz,
  kind text not null,          -- guard_created | policy_set | approved | revoked | approval_observed | policy_mirrored | revoke_requested | approval_ignored
  guard text,
  token text,
  spender text,
  value numeric,
  data jsonb not null default '{}'::jsonb,
  indexed_at timestamptz not null default now(),
  unique (chain_id, tx_hash, log_index)   -- idempotency key
);
create index if not exists events_guard_idx on events (lower(guard), block_number desc);

create table if not exists transactions (
  chain_id bigint not null,
  tx_hash text not null,
  guard text,
  label text not null,
  status text not null default 'pending' check (status in ('pending','confirmed','failed')),
  block_number bigint,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (chain_id, tx_hash)
);

create table if not exists sync_state (
  key text primary key,
  last_block bigint not null
);
