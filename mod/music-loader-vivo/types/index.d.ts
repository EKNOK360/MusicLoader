export type TareaVista = {
  tarea: string
  nombre: string
  hechos: number
  total: number
  pct: number
  porMin: number
  inicio: string
  fin: string
  terminado: boolean
  detenida: number
  problemas: number
  actual: string
  datos: string
}

declare module 'claude-code' {
  interface PluginState {
    'music-loader-vivo': { tareas: TareaVista[] }
  }
}
