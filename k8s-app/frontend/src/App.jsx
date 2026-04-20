import { useState, useEffect, useCallback } from 'react'

const API = '/api'

// ─── Inline styles (no CSS files needed) ─────────────────────────────────────
const s = {
  app:    { maxWidth: '900px', margin: '0 auto', padding: '2rem', fontFamily: '"Segoe UI", system-ui, sans-serif', color: '#1a1a2e' },
  header: { display: 'flex', alignItems: 'center', gap: '1rem', marginBottom: '2rem', paddingBottom: '1.25rem', borderBottom: '2px solid #e2e8f0' },
  h1:     { margin: 0, fontSize: '1.75rem', fontWeight: 700 },
  h2:     { marginTop: 0, fontWeight: 600, color: '#2d3748' },
  badge:  (ok) => ({ padding: '0.3rem 0.9rem', borderRadius: '20px', fontSize: '0.78rem', fontWeight: 700, letterSpacing: '0.02em', background: ok ? '#c6f6d5' : '#fed7d7', color: ok ? '#22543d' : '#742a2a' }),
  card:   { background: '#f7fafc', border: '1px solid #e2e8f0', borderRadius: '10px', padding: '1.5rem', marginBottom: '2rem' },
  form:   { display: 'flex', gap: '0.75rem', flexWrap: 'wrap', alignItems: 'center' },
  input:  { padding: '0.6rem 0.9rem', borderRadius: '6px', border: '1.5px solid #cbd5e0', fontSize: '0.95rem', flex: 1, minWidth: '140px', outline: 'none' },
  btn:    (v) => ({ padding: '0.6rem 1.25rem', borderRadius: '6px', border: 'none', cursor: 'pointer', fontWeight: 600, fontSize: '0.9rem', transition: 'opacity .15s', background: v === 'danger' ? '#e53e3e' : '#3182ce', color: '#fff' }),
  table:  { width: '100%', borderCollapse: 'collapse', fontSize: '0.93rem' },
  th:     { padding: '0.75rem 1rem', textAlign: 'left', background: '#edf2f7', fontWeight: 600, borderBottom: '2px solid #e2e8f0' },
  td:     { padding: '0.75rem 1rem', borderBottom: '1px solid #e2e8f0', verticalAlign: 'middle' },
  empty:  { textAlign: 'center', padding: '3rem', color: '#a0aec0', fontStyle: 'italic' },
  error:  { padding: '0.85rem 1rem', background: '#fff5f5', border: '1px solid #fc8181', borderRadius: '6px', marginBottom: '1rem', color: '#c53030', fontSize: '0.9rem' },
  muted:  { color: '#a0aec0', fontStyle: 'italic' },
}

export default function App() {
  const [items,       setItems]       = useState([])
  const [health,      setHealth]      = useState(null)
  const [name,        setName]        = useState('')
  const [description, setDescription] = useState('')
  const [loading,     setLoading]     = useState(false)
  const [error,       setError]       = useState(null)

  const fetchItems = useCallback(async () => {
    try {
      const res  = await fetch(`${API}/items`)
      const data = await res.json()
      setItems(data.items ?? [])
    } catch {
      setError('Could not reach the backend. Is the Go server running?')
    }
  }, [])

  const fetchHealth = useCallback(async () => {
    try {
      const res = await fetch(`${API}/health`)
      setHealth(await res.json())
    } catch {
      setHealth({ status: 'unreachable', database: 'unknown' })
    }
  }, [])

  useEffect(() => {
    fetchItems()
    fetchHealth()
  }, [fetchItems, fetchHealth])

  const addItem = async (e) => {
    e.preventDefault()
    setLoading(true)
    setError(null)
    try {
      const res = await fetch(`${API}/items`, {
        method:  'POST',
        headers: { 'Content-Type': 'application/json' },
        body:    JSON.stringify({ name, description }),
      })
      if (!res.ok) {
        const err = await res.json()
        throw new Error(err.error || 'Failed to add item')
      }
      setName('')
      setDescription('')
      await fetchItems()
    } catch (err) {
      setError(err.message)
    } finally {
      setLoading(false)
    }
  }

  const deleteItem = async (id) => {
    setError(null)
    try {
      const res = await fetch(`${API}/items/${id}`, { method: 'DELETE' })
      if (!res.ok) throw new Error('Failed to delete item')
      await fetchItems()
    } catch (err) {
      setError(err.message)
    }
  }

  const isHealthy = health?.status === 'healthy'

  return (
    <div style={s.app}>

      {/* ── Header ── */}
      <div style={s.header}>
        <h1 style={s.h1}>☸️ K8s Item Manager v2</h1>
        {health && (
          <span style={s.badge(isHealthy)}>
            API: {health.status} &nbsp;|&nbsp; DB: {health.database}
          </span>
        )}
      </div>

      {/* ── Error banner ── */}
      {error && <div style={s.error}>⚠️ {error}</div>}

      {/* ── Add form ── */}
      <div style={s.card}>
        <h2 style={s.h2}>Add Item</h2>
        <form onSubmit={addItem} style={s.form}>
          <input
            style={s.input}
            value={name}
            onChange={e => setName(e.target.value)}
            placeholder="Name *"
            required
          />
          <input
            style={s.input}
            value={description}
            onChange={e => setDescription(e.target.value)}
            placeholder="Description (optional)"
          />
          <button type="submit" disabled={loading} style={s.btn('primary')}>
            {loading ? 'Adding…' : '+ Add Item'}
          </button>
        </form>
      </div>

      {/* ── Items table ── */}
      <h2 style={{ ...s.h2, marginBottom: '1rem' }}>Items ({items.length})</h2>

      {items.length === 0 ? (
        <div style={s.empty}>No items yet — add one above!</div>
      ) : (
        <table style={s.table}>
          <thead>
            <tr>
              <th style={s.th}>Name</th>
              <th style={s.th}>Description</th>
              <th style={s.th}>Created</th>
              <th style={s.th}></th>
            </tr>
          </thead>
          <tbody>
            {items.map(item => (
              <tr key={item.id}>
                <td style={s.td}><strong>{item.name}</strong></td>
                <td style={s.td}>{item.description || <span style={s.muted}>—</span>}</td>
                <td style={s.td}>{new Date(item.createdAt).toLocaleString()}</td>
                <td style={s.td}>
                  <button onClick={() => deleteItem(item.id)} style={s.btn('danger')}>
                    Delete
                  </button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      )}

    </div>
  )
}
