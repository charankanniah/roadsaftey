import { useState, useEffect, useCallback } from 'react'
import MapView from './components/MapView.jsx'
import ReportTable from './components/ReportTable.jsx'
import { fetchPotholes, fetchStats } from './api.js'

const SEVERITY_COLORS = {
  1: '#22c55e', 2: '#84cc16', 3: '#f59e0b', 4: '#ef4444', 5: '#dc2626',
}

export default function App() {
  const [potholes, setPotholes] = useState([])
  const [stats, setStats] = useState(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [activeView, setActiveView] = useState('map') // 'map' | 'table'
  const [apiKey, setApiKey] = useState('')
  const [filters, setFilters] = useState({ status: '', severityMin: '' })
  const [lastRefresh, setLastRefresh] = useState(null)

  const loadData = useCallback(async () => {
    setLoading(true)
    setError(null)
    try {
      const [ph, st] = await Promise.all([fetchPotholes({ limit: 500 }), fetchStats()])
      setPotholes(ph)
      setStats(st)
      setLastRefresh(new Date())
    } catch (e) {
      setError(e.message)
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => {
    loadData()
    const interval = setInterval(loadData, 15000) // Auto-refresh every 15s
    return () => clearInterval(interval)
  }, [loadData])

  return (
    <div style={s.app}>
      {/* Header */}
      <header style={s.header}>
        <div style={s.headerLeft}>
          <span style={s.logo}>🛡️ PotholeGuard</span>
          <span style={s.subtitle}>Authority Dashboard</span>
        </div>

        {/* Stats Strip */}
        {stats && (
          <div style={s.statsStrip}>
            <StatPill label="Total" value={stats.total_potholes} color="#64748b" />
            <StatPill label="Verified" value={stats.verified_count} color="#0ea5e9" />
            <StatPill label="Fixed" value={stats.fixed_count} color="#22c55e" />
            <StatPill label="⚠ High Risk" value={stats.high_severity_count} color="#ef4444" />
          </div>
        )}

        {/* Authority API Key input */}
        <div style={s.headerRight}>
          <input
            style={s.apiKeyInput}
            placeholder="🔑 Authority API Key"
            value={apiKey}
            onChange={(e) => setApiKey(e.target.value)}
            type="password"
          />
          <button style={s.refreshBtn} onClick={loadData} disabled={loading}>
            {loading ? '⏳' : '↻'} Refresh
          </button>
        </div>
      </header>

      {/* Filter bar */}
      <div style={s.filterBar}>
        {/* View toggle */}
        <div style={s.viewToggle}>
          <button
            style={{ ...s.toggleBtn, ...(activeView === 'map' ? s.toggleActive : {}) }}
            onClick={() => setActiveView('map')}
          >
            🗺 Map
          </button>
          <button
            style={{ ...s.toggleBtn, ...(activeView === 'table' ? s.toggleActive : {}) }}
            onClick={() => setActiveView('table')}
          >
            📋 Table
          </button>
        </div>

        {/* Severity filter */}
        <select
          style={s.filterSelect}
          value={filters.severityMin}
          onChange={(e) => setFilters((f) => ({ ...f, severityMin: e.target.value }))}
        >
          <option value="">All Severities</option>
          {[1, 2, 3, 4, 5].map((n) => <option key={n} value={n}>≥ Severity {n}</option>)}
        </select>

        {/* Status filter */}
        <select
          style={s.filterSelect}
          value={filters.status}
          onChange={(e) => setFilters((f) => ({ ...f, status: e.target.value }))}
        >
          <option value="">All Statuses</option>
          {['new', 'verified', 'assigned', 'fixed', 'possibly_fixed'].map((st) => (
            <option key={st} value={st}>{st}</option>
          ))}
        </select>

        {/* Severity legend */}
        <div style={s.legend}>
          {Object.entries(SEVERITY_COLORS).map(([sev, color]) => (
            <span key={sev} style={{ ...s.legendDot, background: color }}>{sev}</span>
          ))}
        </div>

        <span style={s.refreshTime}>
          {lastRefresh ? `Updated ${lastRefresh.toLocaleTimeString()}` : ''}
        </span>
      </div>

      {/* Error banner */}
      {error && (
        <div style={s.errorBanner}>
          ⚠ Cannot reach backend: {error} — Is docker compose running?
        </div>
      )}

      {/* Main content area */}
      <main style={s.main}>
        {activeView === 'map' ? (
          <MapView
            potholes={potholes}
            apiKey={apiKey}
            onStatusUpdate={loadData}
            filters={filters}
          />
        ) : (
          <ReportTable
            potholes={potholes}
            apiKey={apiKey}
            onStatusUpdate={loadData}
          />
        )}
      </main>
    </div>
  )
}

function StatPill({ label, value, color }) {
  return (
    <div style={{ ...s.statPill, borderColor: color }}>
      <span style={{ color, fontSize: 20, fontWeight: 900 }}>{value}</span>
      <span style={{ color: '#94a3b8', fontSize: 11, marginTop: 2 }}>{label}</span>
    </div>
  )
}

const s = {
  app: {
    display: 'flex', flexDirection: 'column', height: '100vh', overflow: 'hidden',
    background: '#0b0f17', color: '#e2e8f0',
  },
  header: {
    display: 'flex', alignItems: 'center', gap: 16, flexWrap: 'wrap',
    padding: '12px 20px', background: '#0f172a',
    borderBottom: '1px solid #1e293b',
  },
  headerLeft: { display: 'flex', flexDirection: 'column' },
  logo: { fontSize: 18, fontWeight: 900, color: '#06b6d4' },
  subtitle: { fontSize: 11, color: '#64748b', marginTop: 1 },
  statsStrip: { display: 'flex', gap: 12, flex: 1, justifyContent: 'center', flexWrap: 'wrap' },
  statPill: {
    display: 'flex', flexDirection: 'column', alignItems: 'center',
    background: '#1e293b', borderRadius: 10, padding: '6px 16px',
    border: '1px solid', minWidth: 70,
  },
  headerRight: { display: 'flex', gap: 8, alignItems: 'center', marginLeft: 'auto' },
  apiKeyInput: {
    padding: '7px 12px', borderRadius: 8, border: '1px solid #334155',
    background: '#1e293b', color: '#e2e8f0', fontSize: 13, outline: 'none', width: 200,
  },
  refreshBtn: {
    padding: '7px 14px', borderRadius: 8, border: 'none',
    background: '#06b6d4', color: '#000', fontWeight: 700, fontSize: 13, cursor: 'pointer',
  },
  filterBar: {
    display: 'flex', alignItems: 'center', gap: 10, padding: '8px 20px',
    background: '#0f172a', borderBottom: '1px solid #1e293b', flexWrap: 'wrap',
  },
  viewToggle: { display: 'flex', gap: 4 },
  toggleBtn: {
    padding: '5px 14px', borderRadius: 8, border: '1px solid #334155',
    background: 'transparent', color: '#94a3b8', fontSize: 13, cursor: 'pointer',
  },
  toggleActive: { background: '#1e293b', color: '#06b6d4', borderColor: '#06b6d4' },
  filterSelect: {
    padding: '6px 10px', borderRadius: 8, border: '1px solid #334155',
    background: '#1e293b', color: '#e2e8f0', fontSize: 13, cursor: 'pointer',
  },
  legend: { display: 'flex', gap: 6, alignItems: 'center', marginLeft: 8 },
  legendDot: {
    width: 24, height: 24, borderRadius: '50%', display: 'inline-flex',
    alignItems: 'center', justifyContent: 'center', color: '#fff', fontSize: 11, fontWeight: 700,
  },
  refreshTime: { color: '#475569', fontSize: 11, marginLeft: 'auto' },
  errorBanner: {
    background: '#7f1d1d', color: '#fca5a5', padding: '10px 20px',
    fontSize: 13, fontWeight: 600,
  },
  main: {
    flex: 1, overflow: 'hidden', padding: 16,
    display: 'flex', flexDirection: 'column',
  },
}
