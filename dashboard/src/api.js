/**
 * Centralized API client for PotholeGuard Dashboard.
 * Dynamically resolves the Backend URL:
 * 1. localStorage ('PG_API_URL') if set by user in UI
 * 2. window.VITE_API_BASE_URL (runtime injection)
 * 3. Vite environment variable import.meta.env.VITE_API_BASE_URL
 * 4. Default fallback: http://localhost:8000/api
 */

export function getApiBase() {
  if (typeof window !== 'undefined' && localStorage.getItem('PG_API_URL')) {
    return localStorage.getItem('PG_API_URL').trim().replace(/\/+$/, '')
  }
  if (typeof window !== 'undefined' && window.VITE_API_BASE_URL) {
    return window.VITE_API_BASE_URL.trim().replace(/\/+$/, '')
  }
  const envUrl = import.meta.env.VITE_API_BASE_URL
  if (envUrl) {
    return envUrl.trim().replace(/\/+$/, '')
  }
  return 'http://localhost:8000/api'
}

export function setApiBase(url) {
  if (typeof window !== 'undefined') {
    if (url) {
      localStorage.setItem('PG_API_URL', url.trim().replace(/\/+$/, ''))
    } else {
      localStorage.removeItem('PG_API_URL')
    }
  }
}

/** Centralized fetch wrapper with default JSON headers */
async function apiFetch(path, options = {}) {
  const base = getApiBase()
  const res = await fetch(`${base}${path}`, {
    headers: { 'Content-Type': 'application/json', ...options.headers },
    ...options,
  })
  if (!res.ok) {
    const text = await res.text()
    throw new Error(`API ${res.status}: ${text}`)
  }
  return res.json()
}

/** GET /health — verifies backend connectivity */
export async function checkHealth() {
  return apiFetch('/health')
}

/** GET /potholes - supports bbox, severity, status, limit filters */
export async function fetchPotholes({ bbox, severityMin, status, limit = 500 } = {}) {
  const params = new URLSearchParams()
  if (bbox) params.set('bbox', bbox)
  if (severityMin) params.set('severity_min', severityMin)
  if (status) params.set('status', status)
  params.set('limit', limit)
  return apiFetch(`/potholes?${params}`)
}

/** GET /stats */
export async function fetchStats() {
  return apiFetch('/stats')
}

/** PATCH /potholes/{id}/status — requires authority API key */
export async function updatePotholeStatus(id, status, notes, apiKey) {
  return apiFetch(`/potholes/${id}/status`, {
    method: 'PATCH',
    headers: { 'X-API-Key': apiKey },
    body: JSON.stringify({ status, notes }),
  })
}
