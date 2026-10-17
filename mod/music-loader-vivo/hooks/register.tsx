import { atom, read, update } from 'claude-code'
import type { Register } from 'claude-code'

import type { TareaVista } from '../types'

// Carpeta donde los scripts de Music Loader escriben tarea-<nombre>.json (progreso.ps1).
// CAMBIA TU_USUARIO por tu usuario de Windows (la carpeta de %USERPROFILE%).
const DIR = 'C:/Users/TU_USUARIO/reportes-musica'
const tareas = atom({ plugin: 'music-loader-vivo', key: 'tareas' } as const, [] as TareaVista[])

const NOMBRES: Record<string, string> = {
  danos: 'Revisión de daños', 'letras-analisis': 'Análisis de letras', 'letras-escribir': 'Escribiendo letras',
  generos: 'Géneros', metadatos: 'Metadatos', portadas: 'Portadas', mantenimiento: 'Mantenimiento', descarga: 'Descarga',
}
const MALOS = ['problemas', 'danados', 'saltadas']
const VENTANA = 120000  // la hora de fin se calcula con la velocidad de los ultimos 2 minutos

function barra(pct: number): string {
  const n = Math.round(pct / 5)
  return '█'.repeat(n) + '░'.repeat(20 - n)
}
function hora(ms: number): string {
  const d = new Date(ms)
  const h = d.getHours(), m = d.getMinutes()
  return `${h % 12 || 12}:${String(m).padStart(2, '0')} ${h < 12 ? 'a.m.' : 'p.m.'}`
}
function miles(n: number): string { return n.toLocaleString('es') }

export const register: Register = on => {
  const avisos: Record<string, { mitad: boolean; fin: boolean; problemas: number; inicio: string }> = {}
  const muestras: Record<string, [number, number][]> = {}  // tarea -> [hora, hechos]
  const ultimoAvance: Record<string, { hechos: number; ms: number }> = {}

  on('session.start', async ($, e, next) => {
    const r = await next(e)
    let anterior = ''
    $.clock.every(3000, async () => {
      let entradas
      try { entradas = await $.fs.list(DIR) } catch { return }
      const ahora = await $.clock.now()
      const vistas: TareaVista[] = []
      for (const f of entradas) {
        if (!/^tarea-.+\.json$/.test(f.name)) continue
        let t: any
        try { t = JSON.parse((await $.fs.read(`${DIR}/${f.name}`)).replace(/^\uFEFF/, '')) } catch { continue }
        const actualizado = Date.parse(t.actualizado), inicio = Date.parse(t.inicio)
        if (!(ahora - actualizado < 20 * 60000 || (!t.terminado && ahora - actualizado < 2 * 3600000))) continue  // solo recientes
        const total = Number(t.total) || 0, hechos = Number(t.hechos) || 0
        const pct = total ? Math.min(100, Math.round((100 * hechos) / total)) : 0
        // velocidad reciente (ultimos 2 min); si no hay suficiente, el promedio desde el inicio
        const m = (muestras[t.tarea] ??= [])
        if (!m.length || m[m.length - 1][1] !== hechos) m.push([ahora, hechos])
        while (m.length > 2 && ahora - m[0][0] > VENTANA) m.shift()
        const [t0, h0] = m[0]
        const reciente = ahora - t0 > 20000 && hechos > h0 ? (hechos - h0) / ((ahora - t0) / 60000) : 0
        const porMin = reciente || hechos / Math.max(0.1, (ahora - inicio) / 60000)
        // detenida: segundos sin avanzar
        const ua = ultimoAvance[t.tarea]
        if (!ua || ua.hechos !== hechos) ultimoAvance[t.tarea] = { hechos, ms: ahora }
        const detenida = t.terminado ? 0 : Math.round((ahora - ultimoAvance[t.tarea].ms) / 1000)
        const datos = Object.entries(t.datos || {}) as [string, unknown][]
        const problemas = datos.filter(([k]) => MALOS.includes(k)).reduce((s, [, v]) => s + (Number(v) || 0), 0)
        const nombre = NOMBRES[t.tarea] || t.tarea
        vistas.push({
          tarea: t.tarea, nombre, hechos, total, pct, porMin, terminado: !!t.terminado, problemas, detenida,
          inicio: hora(inicio), actual: t.terminado ? '' : String(t.actual || ''),
          fin: t.terminado ? hora(actualizado) : porMin > 0 ? hora(ahora + ((total - hechos) / porMin) * 60000) : '—',
          datos: datos.map(([k, v]) => `${k.replace(/_/g, ' ')} ${v}`).join(' · '),
        })
        // avisos solo en momentos clave: empieza, mitad, termina, error
        let a = avisos[t.tarea]
        if (!a || a.inicio !== t.inicio) { a = avisos[t.tarea] = { mitad: false, fin: false, problemas: 0, inicio: t.inicio }; if (!t.terminado) $.ui.toast(`▶ Empezó: ${nombre} (${miles(total)} canciones)`) }
        if (!a.mitad && pct >= 50 && !t.terminado) { a.mitad = true; $.ui.toast(`⏳ ${nombre} va por la mitad (${miles(hechos)} de ${miles(total)})`) }
        if (problemas > a.problemas) { a.problemas = problemas; $.ui.toast(`⚠ ${nombre}: ${problemas} con problema`) }
        if (t.terminado && !a.fin) { a.fin = true; $.ui.toast(`✅ Terminó: ${nombre} (${miles(hechos)} de ${miles(total)}${problemas ? `, ${problemas} con problema` : ''})`) }
      }
      vistas.sort((x, y) => Number(x.terminado) - Number(y.terminado) || x.nombre.localeCompare(y.nombre))
      const firma = JSON.stringify(vistas.map(v => [v.tarea, v.hechos, v.terminado, v.problemas, v.fin, v.actual, v.detenida > 60]))
      if (firma !== anterior) { anterior = firma; await update($, tareas, () => vistas) }
    })
    return r
  })

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    const vistas = await read($, tareas)
    if (e.props.hasSurvey || vistas.length === 0) return next(e)
    const { Box, Text } = $.ui.resolve(e)
    return (
      <Box flexDirection="column">
        {vistas.map(v => (
          <Box key={v.tarea} flexDirection="column">
            <Text>
              <Text bold>{v.nombre.padEnd(20)}</Text>
              <Text color={v.terminado ? 'success' : v.problemas ? 'error' : v.detenida > 60 ? 'warning' : 'claude'}>{barra(v.pct)}</Text>
              <Text bold> {String(v.pct).padStart(3)}%</Text>
              <Text dimColor>  canción {miles(v.hechos)} de {miles(v.total)}</Text>
              {v.problemas ? <Text color="error">  ⚠ {v.problemas} con problema</Text> : null}
            </Text>
            <Text dimColor>
              {'  '}inicio {v.inicio} · {v.terminado ? `terminó ${v.fin}` : `fin estimado ${v.fin} · ${v.porMin.toFixed(1)}/min`}
              {v.detenida > 60 ? <Text color="warning"> · sin avanzar hace {Math.round(v.detenida / 60)} min</Text> : null}
            </Text>
            {v.actual ? <Text dimColor>{'  '}♪ {v.actual}</Text> : null}
            {v.datos ? <Text dimColor>{'  '}{v.datos}</Text> : null}
          </Box>
        ))}
      </Box>
    )
  })
}
