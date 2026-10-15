import { useEffect, useRef } from 'react'
import L from 'leaflet'
import { updatePotholeStatus } from '../api.js'

// Ensure Leaflet is mounted on window for plugins
if (typeof window !== 'undefined') {
  window.L = L
}

/** Severity level → CSS colour mapping */
const SEVERITY_COLORS = {
  1: '#22c55e', // green
  2: '#84cc16', // lime
  3: '#f59e0b', // amber
  4: '#ef4444', // red
  5: '#dc2626', // crimson
}

/** Status badge background colours */
const STATUS_COLORS = {
  new: '#64748b',
  verified: '#0ea5e9',
  assigned: '#f59e0b',
  fixed: '#22c55e',
  possibly_fixed: '#a78bfa',
}

function createPotholeIcon(pothole) {
  const color = SEVERITY_COLORS[pothole.severity_max] || '#64748b'
  const size = pothole.status === 'verified' ? 28 : 24
  return L.divIcon({
    className: '',
    html: `
      <div style="
        width:${size}px;height:${size}px;
        background:${color};
        border-radius:50%;
        border: ${pothole.status === 'verified' ? '2.5px solid white' : '1.5px solid rgba(255,255,255,0.5)'};
        display:flex;align-items:center;justify-content:center;
        color:#fff;font-weight:bold;font-size:${size > 24 ? 13 : 11}px;
        box-shadow:0 0 8px ${color}88;
      ">${pothole.severity_max}</div>`,
    iconSize: [size, size],
    iconAnchor: [size / 2, size / 2],
  })
}

function buildPopupHtml(p, apiKey) {
  const statusColor = STATUS_COLORS[p.status] || '#64748b'
  const statuses = ['new', 'verified', 'assigned', 'fixed']
  const statusBtns = statuses
    .filter((s) => s !== p.status)
    .map(
      (s) =>
        `<button
          class="status-btn"
          data-id="${p.id}"
          data-status="${s}"
          style="
            background:${STATUS_COLORS[s]};color:#fff;border:none;
            border-radius:5px;padding:4px 9px;font-size:11px;cursor:pointer;
            margin-right:4px;margin-top:4px;font-weight:600;
          "
        >${s}</button>`
    )
    .join('')

  return `
    <div style="font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;color:#1e293b;min-width:220px;">
      <div style="font-weight:900;font-size:15px;margin-bottom:8px;">
        ⚠ Pothole #${p.id}
      </div>
      <div style="margin-bottom:6px;">
        <span style="background:${SEVERITY_COLORS[p.severity_max]};color:#fff;padding:2px 8px;border-radius:10px;font-size:12px;font-weight:bold;">
          Severity ${p.severity_max}/5
        </span>
        <span style="background:${statusColor};color:#fff;padding:2px 8px;border-radius:10px;font-size:12px;font-weight:600;margin-left:6px;">
          ${p.status}
        </span>
      </div>
      <table style="font-size:12px;width:100%;border-collapse:collapse;">
        <tr><td style="color:#64748b;padding:2px 0;">Avg. Severity</td><td><b>${p.severity_avg?.toFixed(1)}</b></td></tr>
        <tr><td style="color:#64748b;padding:2px 0;">Confirmations</td><td><b>${p.confirmation_count}</b></td></tr>
        <tr><td style="color:#64748b;padding:2px 0;">First seen</td><td>${new Date(p.first_detected_at).toLocaleDateString()}</td></tr>
        <tr><td style="color:#64748b;padding:2px 0;">Last seen</td><td>${new Date(p.last_detected_at).toLocaleDateString()}</td></tr>
        <tr><td style="color:#64748b;padding:2px 0;">Coordinates</td><td>${p.latitude.toFixed(5)}, ${p.longitude.toFixed(5)}</td></tr>
      </table>
      ${p.notes ? `<div style="margin-top:6px;font-size:11px;color:#64748b;">📝 ${p.notes}</div>` : ''}
      ${apiKey ? `<div style="margin-top:10px;font-size:11px;color:#64748b;font-weight:600;">Change Status:</div><div>${statusBtns}</div>` : ''}
    </div>
  `
}

/** Interactive Leaflet map with OpenStreetMap tiles and marker clustering */
export default function MapView({ potholes, apiKey, onStatusUpdate, filters }) {
  const mapContainerRef = useRef(null)
  const mapRef = useRef(null)
  const clusterGroupRef = useRef(null)

  // Initialise map once
  useEffect(() => {
    if (mapRef.current) return

    mapRef.current = L.map(mapContainerRef.current, {
      center: [37.7749, -122.4194],
      zoom: 13,
    })

    L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
      attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors',
      maxZoom: 19,
    }).addTo(mapRef.current)

    // Load markercluster plugin dynamically or fallback to LayerGroup
    const initClusterGroup = () => {
      if (typeof L.markerClusterGroup === 'function') {
        clusterGroupRef.current = L.markerClusterGroup({ chunkedLoading: true })
      } else {
        clusterGroupRef.current = L.layerGroup()
      }
      mapRef.current.addLayer(clusterGroupRef.current)
    }

    if (typeof window !== 'undefined') {
      window.L = L
      import('leaflet.markercluster')
        .then(() => initClusterGroup())
        .catch(() => initClusterGroup())
    } else {
      initClusterGroup()
    }

    return () => {
      if (mapRef.current) {
        mapRef.current.remove()
        mapRef.current = null
      }
    }
  }, [])

  // Update markers when data changes
  useEffect(() => {
    if (!mapRef.current || !clusterGroupRef.current) return
    clusterGroupRef.current.clearLayers()

    const filtered = potholes.filter((p) => {
      if (filters.status && p.status !== filters.status) return false
      if (filters.severityMin && p.severity_max < parseInt(filters.severityMin)) return false
      return true
    })

    filtered.forEach((p) => {
      const marker = L.marker([p.latitude, p.longitude], { icon: createPotholeIcon(p) })
      const popupContent = document.createElement('div')
      popupContent.innerHTML = buildPopupHtml(p, apiKey)

      // Wire up status-change buttons inside popup
      popupContent.querySelectorAll('.status-btn').forEach((btn) => {
        btn.addEventListener('click', async () => {
          const id = parseInt(btn.dataset.id)
          const newStatus = btn.dataset.status
          try {
            await updatePotholeStatus(id, newStatus, null, apiKey)
            onStatusUpdate()
            marker.closePopup()
          } catch (e) {
            alert(`Failed to update: ${e.message}`)
          }
        })
      })

      marker.bindPopup(popupContent)
      clusterGroupRef.current.addLayer(marker)
    })

    // Auto-fit map to data
    if (filtered.length > 0) {
      const latLngs = filtered.map((p) => [p.latitude, p.longitude])
      mapRef.current.fitBounds(L.latLngBounds(latLngs), { padding: [30, 30], maxZoom: 15 })
    }
  }, [potholes, apiKey, filters, onStatusUpdate])

  return (
    <div
      ref={mapContainerRef}
      style={{ width: '100%', height: '100%', borderRadius: '12px', overflow: 'hidden' }}
    />
  )
}
