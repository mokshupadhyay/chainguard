import { useQuery, useQueryClient } from '@tanstack/react-query'
import { useState, type ReactNode } from 'react'
import { formatUnits, isAddress, maxUint256, parseUnits, zeroAddress } from 'viem'
import { useAccount, useConnect, useDisconnect, useReadContract, useReadContracts, useSwitchChain } from 'wagmi'
import { erc20Abi, factoryAbi, guardAbi, reactiveAbi } from './abi'
import { fetchTxs } from './api'
import { baseAddr, baseSepolia, baseTx, cfg, configured, lasna, lasnaAddr, lasnaTx, short } from './config'
import { useLoopEvents, useTx, type ChainEvt } from './hooks'

const DEAD = '0x000000000000000000000000000000000000dEaD'
const fmt = (v?: bigint) => (v === undefined ? '…' : v === maxUint256 ? 'UNLIMITED (2²⁵⁶−1)' : formatUnits(v, 18))

function Card({ title, children, right }: { title: string; children: ReactNode; right?: ReactNode }) {
  return (
    <section className="rounded-xl border border-slate-800 bg-slate-900/60 p-5">
      <div className="mb-3 flex items-center justify-between gap-2">
        <h2 className="font-semibold text-slate-200">{title}</h2>
        {right}
      </div>
      {children}
    </section>
  )
}
const Btn = ({ children, ...p }: React.ButtonHTMLAttributes<HTMLButtonElement>) => (
  <button {...p} className={`rounded-lg bg-emerald-500 px-3 py-1.5 text-sm font-medium text-slate-950 hover:bg-emerald-400 disabled:cursor-not-allowed disabled:opacity-40 ${p.className ?? ''}`}>{children}</button>
)
const Link = ({ href, children }: { href: string; children: ReactNode }) => (
  <a href={href} target="_blank" rel="noreferrer" className="text-sky-400 underline-offset-2 hover:underline">{children}</a>
)
function TxState({ t, explorer }: { t: ReturnType<typeof useTx>; explorer?: (h: string) => string }) {
  if (t.status === 'idle') return null
  const color = t.status === 'confirmed' ? 'text-emerald-400' : t.status === 'failed' ? 'text-red-400' : 'text-amber-400'
  const text = { signing: 'Waiting for wallet signature…', pending: 'Pending confirmation…', confirmed: 'Confirmed', failed: `Failed: ${t.error ?? 'transaction reverted'}` }[t.status]
  return <p className={`mt-2 text-xs ${color}`}>{text} {t.hash && <Link href={(explorer ?? baseTx)(t.hash)}>{short(t.hash)}</Link>}</p>
}

export default function App() {
  const { address, isConnected, chainId } = useAccount()
  const { connect, connectors, isPending: connecting } = useConnect()
  const { disconnect } = useDisconnect()
  const { switchChain } = useSwitchChain()
  const wrongNet = isConnected && chainId !== baseSepolia.id

  return (
    <div className="mx-auto max-w-5xl space-y-5 px-4 py-6">
      <header className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <h1 className="text-2xl font-bold tracking-tight">🛡️ ChainGuard</h1>
          <p className="text-sm text-slate-400">A reactive watchdog that auto-revokes dangerous token approvals — no bot.</p>
        </div>
        <div className="flex items-center gap-2 text-sm">
          {isConnected ? (
            <>
              <span className={`rounded-full px-2 py-1 text-xs ${wrongNet ? 'bg-red-500/20 text-red-300' : 'bg-emerald-500/20 text-emerald-300'}`}>
                {wrongNet ? 'Wrong network' : 'Base Sepolia'}
              </span>
              <span className="font-mono text-slate-300">{short(address!)}</span>
              <button onClick={() => disconnect()} className="text-slate-400 hover:text-slate-200">Disconnect</button>
            </>
          ) : (
            <Btn disabled={connecting || !connectors.length} onClick={() => connect({ connector: connectors[0] })}>{connecting ? 'Connecting…' : 'Connect wallet'}</Btn>
          )}
        </div>
      </header>

      {!configured && (
        <Card title="Configuration needed">
          <p className="text-sm text-amber-300">Contract addresses are not configured. Set <code>VITE_MOCK_ERC20</code>, <code>VITE_GUARD_FACTORY</code> and <code>VITE_CHAINGUARD_REACTIVE</code> after deploying (see docs/DEPLOYMENT.md). No data is shown until real contracts are configured.</p>
        </Card>
      )}
      {wrongNet && <Card title="Switch network"><Btn onClick={() => switchChain({ chainId: baseSepolia.id })}>Switch to Base Sepolia</Btn></Card>}
      {!isConnected && configured && <Card title="Get started"><p className="text-sm text-slate-400">Connect a wallet on Base Sepolia to deploy your Guard.</p></Card>}
      {isConnected && !wrongNet && configured && <Dashboard owner={address!} />}

      <footer className="pt-4 text-xs text-slate-500">
        Contracts: {cfg.token && <><Link href={baseAddr(cfg.token)}>Token</Link> · </>}{cfg.factory && <><Link href={baseAddr(cfg.factory)}>Factory</Link> · </>}{cfg.reactive && <Link href={lasnaAddr(cfg.reactive)}>Reactive (Lasna)</Link>}
      </footer>
    </div>
  )
}

function Dashboard({ owner }: { owner: `0x${string}` }) {
  const qc = useQueryClient()
  const guards = useReadContract({ chainId: baseSepolia.id, address: cfg.factory, abi: factoryAbi, functionName: 'guardsOf', args: [owner], query: { refetchInterval: 5000 } })
  const guard = guards.data?.at(-1)
  const create = useTx('create-guard', undefined, () => void guards.refetch())

  if (guards.isLoading) return <Card title="Your Guard"><p className="text-sm text-slate-400">Loading…</p></Card>
  if (!guard)
    return (
      <Card title="Deploy your Guard">
        <p className="mb-3 text-sm text-slate-400">The Guard is a vault you own. It holds tokens and is the approver, so ChainGuard can legitimately revoke its approvals. Default policy: revoke unlimited approvals. Send a little ETH with it to pay for revoke callbacks.</p>
        <Btn disabled={create.status === 'signing' || create.status === 'pending'} onClick={() => create.send({ address: cfg.factory!, abi: factoryAbi, functionName: 'createGuard', value: parseUnits('0.002', 18) })}>Deploy Guard (+0.002 ETH callback gas)</Btn>
        <TxState t={create} />
        {guards.isError && <p className="mt-2 text-xs text-red-400">Could not read factory: {guards.error.message.split('\n')[0]}</p>}
      </Card>
    )
  return <GuardView guard={guard} owner={owner} refresh={() => void qc.invalidateQueries()} />
}

function GuardView({ guard, owner, refresh }: { guard: `0x${string}`; owner: `0x${string}`; refresh: () => void }) {
  const token = cfg.token!
  const [spender, setSpender] = useState<string>(DEAD)
  const [amount, setAmount] = useState('100')
  const sp = isAddress(spender) ? spender : undefined
  const poll = { refetchInterval: 3000 }

  const policy = useReadContract({ chainId: baseSepolia.id, address: guard, abi: guardAbi, functionName: 'policy', query: poll })
  const mirrored = useReadContract({ chainId: lasna.id, address: cfg.reactive, abi: reactiveAbi, functionName: 'policies', args: [guard], query: { refetchInterval: 5000 } })
  const registeredOnLasna = useReadContract({ chainId: lasna.id, address: cfg.reactive, abi: reactiveAbi, functionName: 'registered', args: [guard], query: { refetchInterval: 4000 } })
  const readyOnBase = useReadContract({ chainId: baseSepolia.id, address: guard, abi: guardAbi, functionName: 'ready', query: poll })
  const watched = useReadContract({ chainId: lasna.id, address: cfg.reactive, abi: reactiveAbi, functionName: 'tokens' })
  const tokenInfo = useReadContracts({
    allowFailure: true,
    contracts: (watched.data ?? []).flatMap((t) => [
      { chainId: baseSepolia.id, address: t, abi: erc20Abi, functionName: 'symbol' } as const,
      { chainId: baseSepolia.id, address: guard, abi: guardAbi, functionName: 'protectedToken', args: [t] } as const,
    ]),
    query: { enabled: !!watched.data?.length, refetchInterval: 5000 },
  })
  const bal = useReadContract({ chainId: baseSepolia.id, address: token, abi: erc20Abi, functionName: 'balanceOf', args: [guard], query: poll })
  const allowance = useReadContract({ chainId: baseSepolia.id, address: token, abi: erc20Abi, functionName: 'allowance', args: [guard, sp ?? zeroAddress], query: { ...poll, enabled: !!sp } })
  const restrictOn = useReadContract({ chainId: baseSepolia.id, address: guard, abi: guardAbi, functionName: 'restrictSpenders', query: poll })
  const restrictMirror = useReadContract({ chainId: lasna.id, address: cfg.reactive, abi: reactiveAbi, functionName: 'restrictSpenders', args: [guard], query: { refetchInterval: 5000 } })
  const spenderOk = useReadContract({ chainId: baseSepolia.id, address: guard, abi: guardAbi, functionName: 'allowedSpender', args: [sp ?? zeroAddress], query: { ...poll, enabled: !!sp } })
  const events = useLoopEvents(guard, cfg.reactive)
  const apiTxs = useQuery({ queryKey: ['txs', guard], queryFn: () => fetchTxs(guard), refetchInterval: 10000 })

  const mint = useTx('mint-demo-tokens', guard, refresh)
  const approve = useTx('approve-unlimited', guard, refresh)
  const setPol = useTx('set-policy', guard, refresh)
  const limited = useTx('approve-limited', guard, refresh)
  const mode = useTx('set-spender-mode', guard, refresh)
  const rule = useTx('set-spender-allowed', guard, refresh)

  const p = policy.data
  const m = mirrored.data
  const inSync = p && m && p[0] === m[0] && p[1] === m[1] && p[2] === m[2]
  const ready = readyOnBase.data === true
  const registered = registeredOnLasna.data === true
  const tokenRows = (watched.data ?? []).map((t, i) => ({ addr: t, symbol: (tokenInfo.data?.[2 * i]?.result as string | undefined) ?? short(t), on: tokenInfo.data?.[2 * i + 1]?.result === true }))
  const busy = (t: { status: string }) => t.status === 'signing' || t.status === 'pending'

  return (
    <div className="grid gap-5 md:grid-cols-2">
      <Card title="Your Guard" right={<Link href={baseAddr(guard)}>{short(guard)}</Link>}>
        <dl className="space-y-1 text-sm">
          <Row k="Owner (you)" v={short(owner)} />
          <Row k="Vault balance" v={`${bal.data !== undefined ? formatUnits(bal.data, 18) : '…'} cgUSDC`} />
        </dl>
        <Btn className="mt-3" disabled={busy(mint)} onClick={() => mint.send({ address: token, abi: erc20Abi, functionName: 'mint', args: [guard, parseUnits('1000', 18)] })}>Mint 1,000 demo tokens into Guard</Btn>
        <TxState t={mint} />
      </Card>

      <div className="md:col-span-2">
        <Card title="Protection status" right={<span className={`rounded-full px-2 py-0.5 text-xs ${ready ? 'bg-emerald-500/20 text-emerald-300' : 'bg-amber-500/20 text-amber-300'}`}>{ready ? 'Protected' : 'Registering…'}</span>}>
          <ol className="space-y-1 text-sm">
            <li className={registered ? 'text-emerald-400' : 'text-amber-400'}>{registered ? '✓' : '…'} Guard registered on Reactive Lasna{registeredOnLasna.isError ? ' (Lasna RPC unavailable)' : ''}</li>
            <li className={ready ? 'text-emerald-400' : 'text-amber-400'}>{ready ? '✓' : '…'} Lasna confirmed back to your Guard (on Base Sepolia)</li>
          </ol>
          {!ready && <p className="mt-2 text-xs text-amber-400">Approvals and policy changes are disabled until Lasna confirms. This is an on-chain handshake, not a timer, and usually takes under a minute. You can still withdraw your funds at any time.</p>}
          <h3 className="mt-4 text-sm font-medium text-slate-300">Protected tokens</h3>
          {tokenRows.length ? (
            <ul className="mt-1 space-y-1 text-sm">
              {tokenRows.map((t) => (
                <li key={t.addr} className="flex items-center justify-between gap-2">
                  <span><span className="font-medium">{t.symbol}</span> <Link href={baseAddr(t.addr)}>{short(t.addr)}</Link></span>
                  <span className={t.on ? 'text-emerald-400' : 'text-amber-400'}>{t.on ? 'protected ✓' : 'not confirmed yet'}</span>
                </li>
              ))}
            </ul>
          ) : <p className="mt-1 text-xs text-slate-500">{watched.isError ? 'Could not read the token allowlist from Lasna.' : 'Reading allowlist…'}</p>}
          <p className="mt-3 text-xs text-slate-500">Only the tokens above are watched. The Guard refuses to approve any other token, because an approval on an unwatched token could never be revoked automatically. NFT (ERC-721) approvals and tokens outside this allowlist are unsupported. You can still withdraw them.</p>
        </Card>
      </div>

      <Card title="Security policy">
        <label className="flex items-center gap-2 text-sm"><input type="checkbox" checked={p?.[0] ?? false} disabled={!p || !ready || busy(setPol)} onChange={(e) => setPol.send({ address: guard, abi: guardAbi, functionName: 'setPolicy', args: [e.target.checked, p![1], p![2]] })} /> Protection enabled</label>
        <label className="mt-1 flex items-center gap-2 text-sm"><input type="checkbox" checked={p?.[1] ?? false} disabled={!p || !ready || busy(setPol)} onChange={(e) => setPol.send({ address: guard, abi: guardAbi, functionName: 'setPolicy', args: [p![0], e.target.checked, p![2]] })} /> Revoke unlimited approvals</label>
        <p className="mt-2 text-xs text-slate-500">Max allowance cap: {p ? (p[2] === 0n ? 'disabled' : formatUnits(p[2], 18)) : '…'}</p>
        <p className={`mt-2 text-xs ${inSync ? 'text-emerald-400' : 'text-amber-400'}`}>
          {m === undefined ? 'Reading Lasna…' : inSync ? 'Policy active on Reactive Lasna ✓' : 'Waiting for the policy to reach Reactive Lasna (new Guards take a few seconds)…'}
        </p>
        <TxState t={setPol} />
      </Card>

      <Card title="Trusted spenders (allowlist)">
        <label className="flex items-center gap-2 text-sm"><input type="checkbox" checked={restrictOn.data ?? false} disabled={!ready || busy(mode)} onChange={(e) => mode.send({ address: guard, abi: guardAbi, functionName: 'setSpenderMode', args: [e.target.checked] })} /> Revoke approvals to any spender not on the list (even small ones)</label>
        <p className="mt-2 text-xs text-slate-500">The spender in the box below is {spenderOk.data ? 'ON' : 'not on'} your list.</p>
        <Btn className="mt-2" disabled={!ready || !sp || busy(rule)} onClick={() => rule.send({ address: guard, abi: guardAbi, functionName: 'setSpenderAllowed', args: [sp!, !spenderOk.data] })}>{spenderOk.data ? 'Remove spender from list' : 'Trust this spender'}</Btn>
        <p className={`mt-2 text-xs ${restrictMirror.data === restrictOn.data ? 'text-emerald-400' : 'text-amber-400'}`}>{restrictMirror.data === undefined ? 'Reading Lasna…' : restrictMirror.data === restrictOn.data ? 'Mode active on Reactive Lasna ✓' : 'Waiting for the mode to reach Reactive Lasna…'}</p>
        <TxState t={mode} /><TxState t={rule} />
      </Card>

      <div className="md:col-span-2">
        <Card title="Try it: create a dangerous approval">
          <p className="mb-3 text-sm text-slate-400">Your Guard grants an allowance to a spender. If it is unlimited, ChainGuard should revoke it on its own within seconds.</p>
          <div className="flex flex-wrap items-end gap-3">
            <label className="text-xs text-slate-400">Spender<input value={spender} onChange={(e) => setSpender(e.target.value)} className="mt-1 block w-96 max-w-full rounded border border-slate-700 bg-slate-950 px-2 py-1 font-mono text-sm text-slate-100" /></label>
            <Btn disabled={!ready || !sp || busy(approve) || !p?.[0]} onClick={() => approve.send({ address: guard, abi: guardAbi, functionName: 'approveToken', args: [token, sp!, maxUint256] })}>Approve UNLIMITED</Btn>
            <label className="text-xs text-slate-400">Amount<input value={amount} onChange={(e) => setAmount(e.target.value)} className="mt-1 block w-24 rounded border border-slate-700 bg-slate-950 px-2 py-1 text-sm text-slate-100" /></label>
            <Btn className="bg-slate-600 text-slate-100 hover:bg-slate-500" disabled={!ready || !sp || busy(limited) || !/^\d+(\.\d+)?$/.test(amount)} onClick={() => limited.send({ address: guard, abi: guardAbi, functionName: 'approveToken', args: [token, sp!, parseUnits(amount, 18)] })}>Approve limited</Btn>
          </div>
          {!ready && <p className="mt-2 text-xs text-amber-400">Disabled until your Guard is registered and confirmed by Reactive Lasna (see Protection status).</p>}
          {ready && !inSync && <p className="mt-2 text-xs text-amber-400">Registered, but the latest policy has not been mirrored on Lasna yet; wait for “Policy active” before relying on it.</p>}
          <TxState t={approve} /><TxState t={limited} />
          <p className="mt-3 text-sm">Current on-chain allowance: <span className={`font-mono ${allowance.data === 0n ? 'text-emerald-400' : allowance.data === maxUint256 ? 'text-red-400' : ''}`}>{fmt(allowance.data)}</span></p>
        </Card>
      </div>

      <div className="md:col-span-2"><Loop events={events.data} loading={events.isLoading} error={events.isError} spender={sp} allowance={allowance.data} /></div>

      <div className="md:col-span-2">
        <Card title="Event & transaction history">
          {events.data?.length ? (
            <ul className="divide-y divide-slate-800 text-sm">
              {events.data.map((e) => (
                <li key={e.txHash + e.kind} className="flex flex-wrap items-center justify-between gap-2 py-2">
                  <span>{label(e)} <span className="font-mono text-slate-500">→ {short(e.spender)}</span></span>
                  <span className="text-xs text-slate-400">{new Date(e.ts * 1000).toLocaleTimeString()} · <Link href={(e.chain === 'lasna' ? lasnaTx : baseTx)(e.txHash)}>{e.chain === 'lasna' ? 'Reactscan' : 'Basescan'} {short(e.txHash)}</Link></span>
                </li>
              ))}
            </ul>
          ) : <p className="text-sm text-slate-500">No on-chain events yet.</p>}
          {apiTxs.data?.transactions.length ? <p className="mt-3 text-xs text-slate-500">Backend index: {apiTxs.data.transactions.length} tracked transactions ({apiTxs.data.transactions.filter((t) => t.status === 'pending').length} pending).</p> : <p className="mt-3 text-xs text-slate-600">Backend history unavailable or empty — on-chain data above is authoritative.</p>}
        </Card>
      </div>
    </div>
  )
}

const Row = ({ k, v }: { k: string; v: string }) => <div className="flex justify-between"><dt className="text-slate-400">{k}</dt><dd className="font-mono">{v}</dd></div>
const label = (e: ChainEvt) => ({ approved: `Guard approved ${fmt(e.value)}`, reactive: 'Reactive decided: REVOKE', revoked: `Guard revoked (was ${fmt(e.value)})` }[e.kind])

function Loop({ events, loading, error, spender, allowance }: { events?: ChainEvt[]; loading: boolean; error: boolean; spender?: string; allowance?: bigint }) {
  const mine = (events ?? []).filter((e) => !spender || e.spender.toLowerCase() === spender.toLowerCase())
  const ap = mine.find((e) => e.kind === 'approved' && e.value !== 0n)
  const rx = ap && mine.find((e) => e.kind === 'reactive' && e.ts >= ap.ts - 2)
  const rv = ap && mine.find((e) => e.kind === 'revoked' && e.block >= ap.block)
  const steps = [
    { n: 1, t: 'Approval granted on Base Sepolia', done: !!ap, ev: ap },
    { n: 2, t: 'Reactive Lasna ran react() and decided to revoke', done: !!rx, ev: rx },
    { n: 3, t: 'Callback executed: Guard revoked on Base Sepolia', done: !!rv, ev: rv },
    { n: 4, t: 'Allowance is 0 on-chain', done: !!rv && allowance === 0n, ev: undefined },
  ]
  const cur = steps.findIndex((s) => !s.done)
  return (
    <Card title="Reactive loop status" right={ap && rv ? <span className="text-xs text-emerald-400">Latency (Base→Base): {Math.max(0, rv.ts - ap.ts)}s</span> : undefined}>
      {error && <p className="mb-2 text-xs text-red-400">Could not read chain events right now (RPC). Retrying…</p>}
      <ol className="space-y-2">
        {steps.map((s, i) => (
          <li key={s.n} className="flex items-center gap-3 text-sm">
            <span className={`grid h-6 w-6 place-items-center rounded-full text-xs ${s.done ? 'bg-emerald-500 text-slate-950' : i === cur && ap ? 'animate-pulse bg-amber-400 text-slate-950' : 'bg-slate-700 text-slate-400'}`}>{s.done ? '✓' : s.n}</span>
            <span className={s.done ? 'text-slate-100' : 'text-slate-400'}>{s.t}</span>
            {s.ev && <Link href={(s.ev.chain === 'lasna' ? lasnaTx : baseTx)(s.ev.txHash)}>{short(s.ev.txHash)}</Link>}
          </li>
        ))}
      </ol>
      {loading && <p className="mt-2 text-xs text-slate-500">Loading events…</p>}
      {!ap && !loading && <p className="mt-3 text-xs text-slate-500">Create an approval above (unlimited, or any approval to an untrusted spender) to watch the loop run.</p>}
    </Card>
  )
}
