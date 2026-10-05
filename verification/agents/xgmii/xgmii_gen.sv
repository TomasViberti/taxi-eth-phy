// xgmii_gen.sv
//
// Generador XGMII basado en tasks.
//
// Idea:
// - Cada task de bajo nivel hace una cosa que define la norma.
// - Las tasks de alto nivel arman un frame completo llamando a las de bajo nivel.
// - Las tasks de inyección de errores rompen la norma a propósito, para los
//   tests que verifican cómo responde el DUT.
// - Un test es una secuencia de llamadas a estas tasks.
// - El generador sólo escribe en xgmii_if. No sabe si hay un checker ni cuál.
//
//
// Configuración prevista:
// - Fuente del payload: PRBS (semilla configurable) o patrón fijo.
//
