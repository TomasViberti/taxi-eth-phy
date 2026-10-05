// prbs.sv
//
// Generador de secuencia PRBS (LFSR), usado como fuente de datos del payload.
//
// Idea:
// - Es una utilidad. El generador de cada agente la usa para
//   llenar el payload y el checker (en caso que se genere prbs en el checker)
//   para predecir el payload. Como tarea tentativa será almacenar el polinomio generador
