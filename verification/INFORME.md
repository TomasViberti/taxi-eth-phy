# Informe de verificación 10G ETH-PHY

Objetivo: verificar que el RTL `taxi_eth_phy_10g` cumple la norma IEEE 802.3.

- Cláusula 46: XGMII.
- Cláusula 49: PCS 10GBASE-R (codificación 64B/66B, scrambler, block lock, máquinas de estado de TX y RX).

La verificación es de caja negra: se mira lo que entra y lo que sale del DUT. El RTL se lee sólo para entender el sistema; los resultados esperados de cada test salen de la norma y no de cómo está hecho el RTL. Si un test falla es porque el RTL no hace lo que pide la norma.

Cómo correr todo: ver [INSTRUCCIONES.md](INSTRUCCIONES.md). Ítems: ver [TEST_PLAN.md](TEST_PLAN.md).

## Ambiente

Simulador Verilator 5.036 con cocotb 2.1.0. Los tests están escritos en SystemVerilog, Python sólo genera clocks y reset, arranca el test y al final lee los contadores de error de los checkers.

### Agentes

Hay dos agentes, uno por interfaz del DUT:

- Puertos: cada agente tiene puertos `logic` con el clock y las señales que maneja. En `tb_top` se conectan con `logic` a los puertos del DUT (no se usa `interface`: son sólo dos señales por agente).
- Generador: tasks que hacen lo que define la norma (idle, start, datos, terminate, frame completo) y tasks de inyección de errores que la rompen a propósito.
- Checker XGMII: máquina de estados con lock que corre sola en todos los ciclos (ver abajo). Cuenta lo que ve y al final el test compara esos contadores con lo que pide la norma.
- Checker PCS: también corre solo. Descramblea cada bloque (cl. 49.2.10), lo valida (cl. 49.2.4.6) y lo pasa a los 8 caracteres XGMII que representa según la figura 49-7. Esa palabra entra a una copia del checker XGMII, que verifica la estructura del frame y la PRBS con el mismo lock. Suma un contador propio, `blk_err_count`, de bloques inválidos.

| Agente | Puertos | Qué maneja |
|---|---|---|
| XGMII | gen: `txd[63:0]`, `txc[7:0]`; checker: `rxd[63:0]`, `rxc[7:0]` | Palabras XGMII de 64 bits, 8 lanes |
| PCS | gen: `rx_data[63:0]`, `rx_hdr[1:0]`; checker: `tx_data[63:0]`, `tx_hdr[1:0]` | Bloques 64B/66B. El generador scramblea, el checker descramblea |

El payload de los frames sale de una PRBS31 (`common/prbs.sv`, cl. 49.2.8). Los checkers no usan semilla: verifica el payload con el checker PRBS31 auto-sincronizante de la cl. 49.2.12, que predice cada bit a partir de los 31 bits recibidos anteriores. En `prbs.sv` también están el scrambler y el descrambler (1 + x^39 + x^58).

### Checker XGMII con lock

La XGMII es un flujo de bytes (cl. 46.2). En cada ciclo el checker recorre las 8 lanes en orden y cada byte hace avanzar una FSM que sigue la estructura de la figura 46-3:

```
UNLOCKED --/I/--> IDLE --/S/ (lane 0 o 4)--> PREAMBLE --6 x 0x55--> SFD --0xD5--> DATA --/T/--> IDLE
```

- UNLOCKED: no verifica nada. Se lockea con un /I/ (entre frames) o con un /S/ en lane 0 o 4.
- Lockeado: cada byte tiene que ser el que sigue en la secuencia. Los datos pasan por el checker PRBS31; los primeros 31 bits de cada frame sólo lo sincronizan.
- Ante el primer byte que no es el esperado se deslockea y no verifica nada hasta el próximo /I/ o /S/. Así un error no se arrastra al resto del frame.

Contadores: `frame_count` (frames completos sin errores), `e_count` (bytes /E/, una palabra de error = 8), `prbs_err_count`, `seq_err_count` (bytes fuera de la secuencia) y `unlock_count`. El test llama a `clear()` antes del estímulo y a `check_counts(frames, e, prbs, seq)` al final; cada contador que no coincide suma 1 a `error_count`.

La idea de lock viene del block lock del PCS (cl. 49.2.9, figura 49-14), pero ahí se pierde con 16 headers malos en 64 bloques. Deslockearse al primer error es un criterio de verificación, no de la norma. La cl. 46 no define lock para el RS.

Para el sync header se usa la convención bit 0 = primer bit transmitido, igual que para los datos. El "01" de la norma (dato) queda como `header = 2'b10`.

### Conexión

Según qué se verifica, cambia de dónde salen las entradas del DUT. El checker que queda del lado contrario al generador verifica la mitad del DUT que atraviesa el estímulo, y el que queda al final del loopback verifica la vuelta completa.

Tests XGMII (`loopback_xgmii = 0`), loopback serdes:

```
xgmii_gen -> TX -> serdes_tx -+-> pcs_checker      (lado contrario: verifica el TX)
                              |
                              +-> RX -> xgmii_checker   (vuelta completa)
```

Tests PCS (`loopback_xgmii = 1`), loopback XGMII:

```
pcs_gen -> RX -> xgmii_rxd -+-> xgmii_checker      (lado contrario: verifica el RX)
                            |
                            +-> TX -> serdes_tx -> pcs_checker   (vuelta completa)
```

### Latencia

Los tests no dependen de la latencia del RTL. Los dos checkers se alinean con lo que sale: se lockean en el primer /I/ o /S/ que ven, y el test espera con idles a que salga todo antes de llamar a `check_counts`. El descrambler del checker PCS es auto-sincronizante (cl. 49.2.6), así que tampoco necesita alinearse con el scrambler del TX.

## Tests y resultados

20 tests: 13 pasan, 7 fallan.

<img width="1912" height="663" alt="image" src="https://github.com/user-attachments/assets/ca720e2b-4dc4-4edb-9f2a-0b4a0652a196" />


### Tests XGMII

Estímulo con el generador XGMII. Se verifica la salida serdes del TX con el checker PCS y la salida XGMII del RX con el checker XGMII.

| Test | Ítem | Qué se manda | Qué pide la norma | Resultado |
|---|---|---|---|---|
| `test_happy_path` | Happy path | Frames de 8, 1 y 20 palabras | Bloques 0x78, datos y terminate; frame igual en XGMII RX | PASA |
| `test_start_lane4` | Orden de lane | Frames con el start en lane 4 | Bloque 0x33, datos corridos 4 bytes, terminate 0xCC | PASA |
| `test_start_bad_lane` | Start en lane inválida | Start en lanes 1, 2, 3, 5, 6, 7 | Bloque de error por cada uno (TX_C -> TX_E) | FALLA |
| `test_term_lanes` | Terminate en cada lane | 8 frames, FD en la lane k | Block types 0x87, 0x99, 0xAA, 0xB4, 0xCC, 0xD2, 0xE1, 0xFF | PASA |
| `test_bad_ctrl` | Control inexistente | 0x55 en las 8 lanes y 0x00 en la lane 3 | Bloque de error entero en los dos casos | FALLA |
| `test_error_char` | 0xFE en el frame | Dato con 0xFE en la lane 3 | Bloque de error y el frame sigue (TX_D -> TX_E -> TX_D) | PASA |
| `test_double_start` | Dos starts | Start, start, datos, terminate | Segundo start como bloque de error (TX_D -> TX_E) | FALLA |
| `test_start_term` | Start + terminate | Start seguido de terminate, sin datos | Válido (TX_C -> TX_D -> TX_T), frame igual | PASA |

El ítem de palabras XGMII de 32 bits no tiene test: el RTL tiene la interfaz XGMII de 64 bits.

### Tests PCS

Estímulo con el generador PCS. Se verifica la salida XGMII del RX con el checker XGMII. El checker PCS al final del loopback XGMII se verifica en el happy path.

| Test | Ítem | Qué se manda | Qué pide la norma | Resultado |
|---|---|---|---|---|
| `test_happy_path` | Happy path | Frames con start en posición 0 y 4 | Frames iguales en XGMII RX y en la vuelta por el TX | PASA |
| `test_bad_sync_hdr` | Header 00 / 11 | Idles y datos con header 00 y 11 | Bloque tipo E: palabra de error, después sigue normal | PASA |
| `test_bad_ctrl` | Códigos inexistentes | Código de 7 bits 0x01; block types 0x00 y 0x11 | Bloque tipo E: palabra de error entera | FALLA |
| `test_start_mismatch` | Block type vs contenido | 0x78 con contenido de un start en posición 4 | La posición la da el block type: FB en lane 0 y el resto como dato | PASA |
| `test_inverse_hdr` | Header inverso | Idle con header de dato; dato con header de control | Palabra de error en los dos casos | FALLA |
| `test_no_scramble` | Sin scrambleo | Frame sin scramblear | El frame no sale intacto y el lock se mantiene | PASA |
| `test_scramble_hdr` | Header scrambleado | Idles con el header scrambleado | Se pierde block lock | PASA |
| `test_lock_loss` | 16 headers malos | 16 inválidos cada 64 bloques | Se pierde block lock | PASA |
| `test_lock_keep` | 15 headers malos | 15 inválidos cada 64 bloques | Se mantiene block lock | PASA |
| `test_term_no_start` | Terminate sin start | Terminate entre idles | Palabra de error (RX_C -> RX_E) | FALLA |
| `test_double_start` | Dos starts | Start, start, datos, terminate | Palabra de error en el segundo start (RX_D -> RX_E) | FALLA |
| `test_bit_flip` | Bit invertido | 1 bit invertido en la línea (bits 0 y 20) | 3 bits errados: k, k+39 y k+58 | PASA |

Para el lock (16 y 15 headers malos) la ventana de 64 bloques de la máquina de lock no se ve desde afuera, entonces no se sabe dónde arranca. Por eso se manda un patrón periódico: 16 inválidos seguidos y 48 válidos, repetido. Con período 64 cualquier ventana tiene exactamente 16 inválidos, esté donde esté alineada. Lo mismo con 15.

## Problemas encontrados

Los 7 tests que fallan se explican con dos problemas del RTL.

### 1. El TX no implementa maquina de estados para transmisión

El lado TX no implementa la máquina de estados de la norma (cl. 49.2.13.2.2).


El encoder del RTL (`taxi_xgmii_baser_enc.sv`) codifica cada palabra por separado, sin mirar la anterior. Casos:

- Dos starts seguidos (`xgmii-test_double_start`): el segundo start sale como un start normal (bloque 0x78), no como bloque de error.

  ```
  PCS CHECKER ERROR en error block
      esperado: header=01 data=3c78f1e3c78f1e1e
      recibido: header=01 data=d555555555555578
  ```

- Palabra toda de control con un carácter inválido en una sola lane (`xgmii-test_bad_ctrl` con 0x00 en la lane 3, `xgmii-test_start_bad_lane` con el start en la lane 7): el TX pone /E/ sólo en esa posición y deja el resto como idle. Según la norma la palabra entera es tipo E y tiene que salir el bloque de error completo.

  ```
  PCS CHECKER ERROR en error block
      esperado: header=01 data=3c78f1e3c78f1e1e
      recibido: header=01 data=00000003c000001e
  ```

  Cuando la palabra mezcla datos y controles (start en lanes 1, 2, 3, 5, 6, 0xFE en medio del frame) sí sale el bloque de error entero. En una palabra toda de control el TX reemplaza por /E/ sólo las lanes inválidas: con 0x55 en las 8 lanes queda igual al bloque de error y el test pasa, pero con una sola lane inválida no.

### 2. El RX no implementa la máquina de estados de recepción

Lo mismo del lado RX (cl. 49.2.13.2.3).

El decoder del RTL (`taxi_xgmii_baser_dec.sv`) también decodifica cada bloque por separado. Lleva la cuenta de si está dentro de un frame y levanta `rx_sequence_error`, pero deja pasar el bloque igual. Esa bandera no está en la norma; sirve para saber que algo anduvo mal pero no corrige la salida.

- Terminate sin start (`pcs-test_term_no_start`): sale el FD por XGMII (`rxd=07070707fdffffff`).
- Dos starts seguidos (`pcs-test_double_start`): el segundo start sale como start.

  ```
  XGMII CHECKER ERROR en error word
      esperado: c=11111111 d=fefefefefefefefe
      recibido: c=00000001 d=d5555555555555fb
  ```

- Idle con header de dato (`pcs-test_inverse_hdr`): sale como dato, `c=00000000 d=000000000000001e`. Dentro del frame, un dato con header de control cuyo primer byte es 0xFF se lee como terminate en la posición 7, y como el bloque siguiente es un dato (terminate seguido de dato es error) también tendría que salir la palabra de error. Sale el FD.
- Código de control de 7 bits inválido (`pcs-test_bad_ctrl`): sale 0xFE sólo en esa lane (`07070707fe070707`). Según la norma el bloque es tipo E y sale la palabra de error entera. Con block types inexistentes (0x00, 0x11) sí sale la palabra entera.

Lo que sí anda: sync header inválido, block lock (pierde con 16, mantiene con 15), start en lane 4, terminate en cada posición y la multiplicación de errores del descrambler.
