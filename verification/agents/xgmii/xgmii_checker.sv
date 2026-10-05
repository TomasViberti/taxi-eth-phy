// xgmii_checker.sv
//
// Checker XGMII.
//
// Requisito: tiene que funcionar junto con xgmii_gen o solo (por ejemplo,
// mirando la salida XGMII cuando el estímulo viene de pcs_gen). Por eso el
// checker sólo mira la interface XGMII y no recibe nada del generador.
//
//
//
//
// Planteo 1 - Checker que observa y cuenta
//
// El checker mira lo que pasa y verifica que se cumplan las reglas de
// la norma (start en lane 0, terminate seguido de idles, caracteres de
// control válidos, etc.). Va contando lo que ve: frames correctos, errores,
// violaciones de la norma. 
// Al final, el test mira esos contadores y decide si pasó.
// Ej: en el happy path espero 0 errores; si mando un start en lane 2,
// espero al menos 1 error.
//
// 
// Planteo 2 - Checker con tasks inversas a las del generador
//
// Por cada task del generador hay una task del checker que espera lo que
// debería salir:
//
// generador                 checker
// send_frame(len, ifg)  ->  expect_frame(len)
// send_error()          ->  expect_error()
// send_start_at_lane(k) ->  expect_error()  
//
// 
// En los dos planteos
//