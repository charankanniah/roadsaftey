import { useState, useEffect, useCallback } from 'react'
import MapView from './components/MapView.jsx'
import ReportTable from './components/ReportTable.jsx'
import { fetchPotholes, fetchStats, getApiBase, setApiBase } from './api.js'

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
  const [currentApi, setCurrentApi] = useState(() => getApiBase())
  const [apiUrlInput, setApiUrlInput] = useState(() => getApiBase())
  const [showApiSettings, setShowApiSettings] = useState(false)

  const handleSaveApiUrl = () => {
    if (apiUrlInput && apiUrlInput.trim()) {
      setApiBase(apiUrlInput.trim())
      const updated = getApiBase()
      setCurrentApi(updated)
      setShowApiSettings(false)
      loadData()
    }
  }

  const handleResetApiUrl = () => {
    setApiBase(null)
    const updated = getApiBase()
    setCurrentApi(updated)
    setApiUrlInput(updated)
    setShowApiSettings(false)
    loadData()
  }

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

        {/* Authority API Key & Backend Settings */}
        <div style={s.headerRight}>
          <button
            style={s.apiBadgeBtn}
            onClick={() => setShowApiSettings((prev) => !prev)}
            title="Configure Backend API URL"
          >
            ⚙️ {currentApi.replace(/\/api\/?$/, '').replace(/^https?:\/\//, '') || 'API URL'}
          </button>
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

      {/* Backend API Settings Bar (expandable) */}
      {showApiSettings && (
        <div style={s.apiSettingsPanel}>
          <span style={{ fontSize: 13, fontWeight: 700, color: '#38bdf8' }}>Backend API URL:</span>
          <input
            type="text"
            style={s.apiSettingsInput}
            value={apiUrlInput}
            onChange={(e) => setApiUrlInput(e.target.value)}
            placeholder="e.g. https://potholeguard-backend.onrender.com/api"
          />
          <button style={s.apiConnectBtn} onClick={handleSaveApiUrl}>Save & Connect</button>
          <button style={s.apiResetBtn} onClick={handleResetApiUrl}>Reset to Default</button>
          <button style={s.apiCloseBtn} onClick={() => setShowApiSettings(false)}>✕</button>
        </div>
      )}

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

      {/* Error banner with inline API URL fixer */}
      {error && (
        <div style={s.errorBanner}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', flexWrap: 'wrap', gap: 8 }}>
            <span>⚠ <strong>Cannot reach backend:</strong> {error}</span>
            <span style={{ fontSize: 12, opacity: 0.9 }}>Active Target: <code>{currentApi}</code></span>
          </div>
          <div style={s.errorConfigRow}>
            <span style={{ fontSize: 12, color: '#fecaca', whiteSpace: 'nowrap' }}>Change Backend URL:</span>
            <input
              type="text"
              style={s.apiSettingsInput}
              value={apiUrlInput}
              onChange={(e) => setApiUrlInput(e.target.value)}
              placeholder="https://your-backend.onrender.com/api"
            />
            <button style={s.apiConnectBtn} onClick={handleSaveApiUrl}>
              Connect
            </button>
            <button style={s.apiResetBtn} onClick={handleResetApiUrl}>
              Reset
            </button>
          </div>
          <div style={{ fontSize: 11, color: '#fecaca', opacity: 0.85, marginTop: 4 }}>
            💡 <em>For permanent production setup:</em> In Vercel Project Settings &rarr; Environment Variables, add <code>VITE_API_BASE_URL</code> with your deployed backend URL (e.g. <code>https://potholeguard-backend.onrender.com/api</code>) and redeploy.
          </div>
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
    background: '#7f1d1d', color: '#fca5a5', padding: '12px 20px',
    fontSize: 13, fontWeight: 600,
  },
  apiBadgeBtn: {
    padding: '6px 12px', borderRadius: 8, border: '1px solid #334155',
    background: '#1e293b', color: '#38bdf8', fontSize: 12, fontWeight: 600,
    cursor: 'pointer', maxWidth: 170, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap',
  },
  apiSettingsPanel: {
    display: 'flex', alignItems: 'center', gap: 10, padding: '8px 20px',
    background: '#0c1322', borderBottom: '1px solid #0284c7', flexWrap: 'wrap',
  },
  apiSettingsInput: {
    padding: '6px 12px', borderRadius: 6, border: '1px solid #334155',
    background: '#1e293b', color: '#e2e8f0', fontSize: 13, outline: 'none', flex: 1, minWidth: 260,
  },
  apiConnectBtn: {
    padding: '6px 14px', borderRadius: 6, border: 'none',
    background: '#0284c7', color: '#fff', fontWeight: 700, fontSize: 12, cursor: 'pointer',
  },
  apiResetBtn: {
    padding: '6px 10px', borderRadius: 6, border: '1px solid #475569',
    background: 'transparent', color: '#94a3b8', fontSize: 12, cursor: 'pointer',
  },
  apiCloseBtn: {
    padding: '4px 8px', borderRadius: 6, border: 'none',
    background: 'transparent', color: '#94a3b8', fontSize: 14, cursor: 'pointer', marginLeft: 'auto',
  },
  errorConfigRow: {
    display: 'flex', alignItems: 'center', gap: 8, marginTop: 8, flexWrap: 'wrap',
  },
  main: {
    flex: 1, overflow: 'hidden', padding: 16,
    display: 'flex', flexDirection: 'column',
  },
}
