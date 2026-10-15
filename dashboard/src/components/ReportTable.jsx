import { useState, useMemo } from 'react'
import { updatePotholeStatus } from '../api.js'

const SEVERITY_COLORS = {
  1: '#22c55e', 2: '#84cc16', 3: '#f59e0b', 4: '#ef4444', 5: '#dc2626',
}
const STATUS_COLORS = {
  new: '#64748b', verified: '#0ea5e9', assigned: '#f59e0b', fixed: '#22c55e', possibly_fixed: '#a78bfa',
}

function exportCsv(potholes) {
  const header = 'id,latitude,longitude,severity_max,severity_avg,confirmation_count,status,first_detected_at,last_detected_at\n'
  const rows = potholes.map((p) =>
    [p.id, p.latitude, p.longitude, p.severity_max, p.severity_avg?.toFixed(2),
     p.confirmation_count, p.status, p.first_detected_at, p.last_detected_at].join(',')
  ).join('\n')
  const blob = new Blob([header + rows], { type: 'text/csv' })
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a')
  a.href = url
  a.download = `potholes_${new Date().toISOString().slice(0, 10)}.csv`
  a.click()
  URL.revokeObjectURL(url)
}

export default function ReportTable({ potholes, apiKey, onStatusUpdate }) {
  const [search, setSearch] = useState('')
  const [sortField, setSortField] = useState('severity_max')
  const [sortAsc, setSortAsc] = useState(false)
  const [statusFilter, setStatusFilter] = useState('')
  const [severityFilter, setSeverityFilter] = useState('')
  const [updatingId, setUpdatingId] = useState(null)

  const filtered = useMemo(() => {
    let rows = potholes
    if (search) {
      const q = search.toLowerCase()
      rows = rows.filter((p) =>
        String(p.id).includes(q) ||
        p.status.includes(q) ||
        String(p.latitude).includes(q) ||
        String(p.longitude).includes(q)
      )
    }
    if (statusFilter) rows = rows.filter((p) => p.status === statusFilter)
    if (severityFilter) rows = rows.filter((p) => p.severity_max >= parseInt(severityFilter))
    return [...rows].sort((a, b) => {
      const av = a[sortField], bv = b[sortField]
      if (av === bv) return 0
      const cmp = av > bv ? 1 : -1
      return sortAsc ? cmp : -cmp
    })
  }, [potholes, search, sortField, sortAsc, statusFilter, severityFilter])

  function toggleSort(field) {
    if (sortField === field) setSortAsc(!sortAsc)
    else { setSortField(field); setSortAsc(false) }
  }

  async function handleStatusChange(id, newStatus) {
    if (!apiKey) return alert('Enter an authority API key to update status.')
    setUpdatingId(id)
    try {
      await updatePotholeStatus(id, newStatus, null, apiKey)
      onStatusUpdate()
    } catch (e) {
      alert(`Update failed: ${e.message}`)
    } finally {
      setUpdatingId(null)
    }
  }

  const Th = ({ field, label }) => (
    <th onClick={() => toggleSort(field)} style={styles.th}>
      {label} {sortField === field ? (sortAsc ? '↑' : '↓') : ''}
    </th>
  )

  return (
    <div style={styles.container}>
      {/* Controls row */}
      <div style={styles.controls}>
        <input
          style={styles.input}
          placeholder="🔍  Search by ID, status, coordinates…"
          value={search}
          onChange={(e) => setSearch(e.target.value)}
        />
        <select style={styles.select} value={statusFilter} onChange={(e) => setStatusFilter(e.target.value)}>
          <option value="">All Statuses</option>
          {['new', 'verified', 'assigned', 'fixed', 'possibly_fixed'].map((s) => (
            <option key={s} value={s}>{s}</option>
          ))}
        </select>
        <select style={styles.select} value={severityFilter} onChange={(e) => setSeverityFilter(e.target.value)}>
          <option value="">All Severities</option>
          {[1, 2, 3, 4, 5].map((n) => <option key={n} value={n}>≥ {n}</option>)}
        </select>
        <button style={styles.exportBtn} onClick={() => exportCsv(filtered)}>
          ⬇ CSV ({filtered.length})
        </button>
      </div>

      {/* Scrollable table */}
      <div style={styles.tableWrapper}>
        <table style={styles.table}>
          <thead>
            <tr style={styles.headerRow}>
              <Th field="id" label="#ID" />
              <Th field="severity_max" label="Severity" />
              <Th field="confirmation_count" label="Reports" />
              <Th field="status" label="Status" />
              <Th field="latitude" label="Latitude" />
              <Th field="longitude" label="Longitude" />
              <Th field="last_detected_at" label="Last Seen" />
              <th style={styles.th}>Actions</th>
            </tr>
          </thead>
          <tbody>
            {filtered.length === 0 ? (
              <tr>
                <td colSpan={8} style={{ textAlign: 'center', padding: '24px', color: '#64748b' }}>
                  No hazards match current filters.
                </td>
              </tr>
            ) : filtered.map((p) => (
              <tr key={p.id} style={styles.row}>
                <td style={styles.td}><b style={{ color: '#94a3b8' }}>#{p.id}</b></td>
                <td style={styles.td}>
                  <span style={{
                    ...styles.badge,
                    background: SEVERITY_COLORS[p.severity_max],
                  }}>
                    {p.severity_max}/5
                  </span>
                </td>
                <td style={{ ...styles.td, textAlign: 'center' }}>{p.confirmation_count}</td>
                <td style={styles.td}>
                  <span style={{
                    ...styles.badge,
                    background: STATUS_COLORS[p.status] || '#64748b',
                  }}>
                    {p.status}
                  </span>
                </td>
                <td style={styles.tdMono}>{p.latitude.toFixed(5)}</td>
                <td style={styles.tdMono}>{p.longitude.toFixed(5)}</td>
                <td style={styles.td}>{new Date(p.last_detected_at).toLocaleDateString()}</td>
                <td style={styles.td}>
                  {updatingId === p.id ? (
                    <span style={{ color: '#94a3b8', fontSize: 12 }}>Updating…</span>
                  ) : (
                    <select
                      style={styles.actionSelect}
                      value={p.status}
                      onChange={(e) => handleStatusChange(p.id, e.target.value)}
                    >
                      {['new', 'verified', 'assigned', 'fixed'].map((s) => (
                        <option key={s} value={s}>{s}</option>
                      ))}
                    </select>
                  )}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  )
}

const styles = {
  container: { display: 'flex', flexDirection: 'column', height: '100%', gap: 12 },
  controls: { display: 'flex', gap: 8, flexWrap: 'wrap', alignItems: 'center' },
  input: {
    flex: 2, minWidth: 220, padding: '8px 12px', borderRadius: 8,
    border: '1px solid #334155', background: '#1e293b', color: '#e2e8f0', fontSize: 13,
    outline: 'none',
  },
  select: {
    flex: 1, minWidth: 130, padding: '8px 10px', borderRadius: 8,
    border: '1px solid #334155', background: '#1e293b', color: '#e2e8f0', fontSize: 13,
    cursor: 'pointer',
  },
  exportBtn: {
    padding: '8px 16px', borderRadius: 8, border: 'none',
    background: '#06b6d4', color: '#000', fontWeight: 700, fontSize: 13, cursor: 'pointer',
  },
  tableWrapper: { overflowY: 'auto', flex: 1, borderRadius: 10, border: '1px solid #1e293b' },
  table: { width: '100%', borderCollapse: 'collapse', fontSize: 13 },
  headerRow: { background: '#1e293b', position: 'sticky', top: 0, zIndex: 1 },
  th: {
    padding: '10px 12px', textAlign: 'left', color: '#94a3b8',
    fontWeight: 600, letterSpacing: '0.5px', cursor: 'pointer', userSelect: 'none',
    borderBottom: '1px solid #334155',
  },
  row: {
    borderBottom: '1px solid #1e293b',
    transition: 'background 0.15s',
  },
  td: { padding: '10px 12px', color: '#e2e8f0', verticalAlign: 'middle' },
  tdMono: { padding: '10px 12px', color: '#94a3b8', fontFamily: 'monospace', fontSize: 12 },
  badge: {
    display: 'inline-block', padding: '2px 8px', borderRadius: 10,
    color: '#fff', fontWeight: 700, fontSize: 11,
  },
  actionSelect: {
    padding: '4px 8px', borderRadius: 6, border: '1px solid #334155',
    background: '#0f172a', color: '#e2e8f0', fontSize: 12, cursor: 'pointer',
  },
}
