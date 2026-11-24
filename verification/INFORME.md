# Informe final de verificación: PHY 10GBASE-R (taxi_eth_phy_10g)

## 1. Objetivo

El objetivo de este trabajo fue verificar que el RTL `taxi_eth_phy_10g` cumple con la norma IEEE 802.3-2022 en las dos cláusulas que implementa:

- **Cláusula 46: XGMII.** Es la interfaz entre el Reconciliation Sublayer (RS) y el PCS: cómo se arma un frame en bytes, qué caracteres de control existen y dónde pueden ir.
- **Cláusula 49: PCS 10GBASE-R.** Es la codificación 64B/66B, el scrambler, el block lock, el monitor de BER y las máquinas de estado de transmisión y recepción.

La verificación es de **caja negra**: solo miro lo que entra y lo que sale del DUT. El RTL lo leí únicamente para entender el sistema y para explicar las fallas una vez encontradas. **Los resultados esperados de cada test salen de la norma, nunca del RTL.** Si un test falla, quiere decir que el RTL no hace lo que pide la norma, no que el test esté mal adaptado al RTL.

Resultado general: **se corrieron 20 tests; 13 pasan y 7 fallan.** Las 7 fallas se explican con dos problemas del RTL: no están implementadas las máquinas de estado de transmisión ni de recepción de la cláusula 49 (sección 8).

---

## 2. El DUT

### 2.1 Qué es

`taxi_eth_phy_10g` es el PCS de 10GBASE-R. En la pila de capas de Ethernet queda así:

```
MAC
 │
RS  (Reconciliation Sublayer)
 │   ← XGMII (cl. 46): 64 bits de datos + 8 bits de control por ciclo
PCS (cl. 49)  ← DUT
 │   ← interfaz con la PMA ("serdes"): bloque de 66 bits por ciclo (64 de payload + 2 de sync header)
PMA / PMD
```

El DUT no incluye la MAC ni la PMA/PMD. Los puertos "serdes" son la interfaz paralela con la PMA: no hay un SerDes físico en la simulación.

Internamente el DUT tiene dos caminos independientes:

- **TX:** XGMII → encoder 64B/66B (`taxi_xgmii_baser_enc.sv`) → scrambler → serdes_tx.
- **RX:** serdes_rx → block lock → descrambler → decoder 64B/66B (`taxi_xgmii_baser_dec.sv`) → XGMII. También tiene el monitor de BER.

### 2.2 Parámetros usados

Usé todos los parámetros con su valor por defecto:

| Parámetro | Valor | Significado |
|---|---|---|
| `DATA_W` | 64 | XGMII de 64 bits: un bloque 64B/66B por ciclo |
| `SCRAMBLER_DISABLE` | 0 | Scrambler activo, como pide la norma |
| `TX_GBX_IF_EN` / `RX_GBX_IF_EN` | 0 | Sin gearbox: entra y sale un bloque válido en todos los ciclos |
| `BIT_REVERSE` | 0 | Sin inversión del orden de bits |
| `PRBS31_EN` | 0 | Modo de patrón de prueba PRBS31 del DUT deshabilitado |
| `COUNT_125US` | 125000/6,4 | Timer de 125 µs del monitor de BER, contado en ciclos de 6,4 ns |

Las entradas `cfg_tx_prbs31_enable` y `cfg_rx_prbs31_enable` están en 0. La PRBS31 que uso como payload de los frames está en el testbench, no es la del DUT (sección 4.5).

### 2.3 Clocks y reset

El DUT tiene dos dominios de reloj: `tx_clk` para el camino TX y `rx_clk` para el RX. En hardware real son distintos, porque `rx_clk` se recupera de la línea y tiene una tolerancia de ±100 ppm respecto del oscilador local. Por eso la XGMII define TX_CLK y RX_CLK por separado.

En la simulación, cocotb genera **los dos clocks con el mismo período, 6,4 ns, y arrancan en el mismo instante**. Así que en la práctica son un único reloj y no hay cruce de dominios.

El período de 6,4 ns (156,25 MHz) sale de la velocidad de la línea 10GBASE-R:

```
10,3125 Gb/s ÷ 66 bits por bloque = 156,25 M bloques/s  →  156,25 MHz
```

Del lado XGMII da lo mismo: 10 Gb/s ÷ 64 bits = 156,25 MHz.

El reset (`tx_rst`, `rx_rst`) es activo en alto. Se mantiene durante 4 ciclos y después se esperan 2 ciclos más antes de arrancar el test.

---

## 3. Metodología

### 3.1 Criterio general

Cada test parte de **una regla concreta de la norma** y la prueba aislada. El método que seguí para diseñar cada test es siempre el mismo:

1. **Elegir la regla.** Qué dice la norma que tiene que pasar ante cierta entrada.
2. **Armar un estímulo que pruebe solo esa regla.** Un único error por caso, para que, si algo falla, se sepa por qué.
3. **Partir de un estado conocido.** Antes de cada caso mando idles, así el DUT está con seguridad entre frames y la norma da una sola salida posible.
4. **Separar los casos.** Después de cada caso mando idles (en general 20). Eso devuelve el DUT al estado entre frames, le da tiempo al checker para volver a lockearse y cubre la latencia del RTL, así todo lo que entró ya salió antes de contar.
5. **Calcular desde la norma qué tiene que salir** y compararlo con lo observado.

### 3.2 Checkers por reglas y scoreboard por conteos

Los checkers **no comparan contra una copia de lo que se mandó**. Verifican, ciclo a ciclo, que la salida cumpla las reglas de la norma:

- la estructura del frame (cl. 46.2),
- el formato de los bloques (figura 49-7),
- la secuencia de bloques (figura 49-17),
- que el payload sea una PRBS31 válida.

Mientras verifican, cuentan lo que ven: frames correctos, caracteres de error, errores de PRBS, errores de secuencia y bloques inválidos.

Al final de cada test, la task `check_counts` compara esos contadores con los valores que exige la norma para ese estímulo. Cumple la función de **scoreboard, pero de conteos, no de transacciones**. No hay modelo de referencia: el valor esperado lo calculo yo, aplicando la cláusula correspondiente, y lo escribo en el test.

Ventajas de este enfoque:

- **No depende de la latencia del RTL.** Los checkers se sincronizan con lo que sale, no con lo que entró.
- **Un error no se arrastra.** Ante el primer error el checker se deslockea y vuelve a sincronizarse en el próximo punto seguro (sección 4.2). En una comparación contra una copia, en cambio, un byte perdido desalinea todo lo que viene después.
- **El contenido de los datos se verifica sin guardar una copia.** El checker reconstruye la PRBS31 a partir de lo que recibe.

Limitación: un error que no rompe ninguna regla, que deja la PRBS coherente y que no cambia los totales no se detectaría. Por ejemplo, un frame entero perdido y otro duplicado (sección 9).

---

## 4. Arquitectura del ambiente de verificación

### 4.1 Herramientas y flujo

- **Simulador:** Verilator 5.036 con `--timing`.
- **cocotb 2.1.0 + pytest:** lanzan las simulaciones. Python solo genera los clocks y el reset, arranca el test y lee el resultado.
- **Tests, agentes y testbench:** todo en SystemVerilog.

Flujo de una simulación (`sim/test_phy.py`):

1. pytest compila el testbench con el archivo del test y lanza una simulación por cada test.
2. cocotb genera los clocks de 156,25 MHz, aplica el reset y sube la señal `start`.
3. El módulo `test` de SystemVerilog corre el estímulo y, al terminar, pone `done = 1`.
4. Python espera `done`, con un timeout de 1 ms, y lee `u_xgmii_chk.error_count + u_pcs_chk.error_count`. **Si la suma es 0, el test pasa.**

Cada test deja su log en `sim/sim_build/<agente>/<test>/sim.log`. Con `WAVES=1` también genera las ondas (`waves.fst`) para abrir en GTKWave.

### 4.2 Estructura de archivos

```
verification/
├── tb/tb_top.sv             testbench: DUT, agentes, loopbacks
├── common/prbs.sv           PRBS31, scrambler y descrambler
├── agents/
│   ├── xgmii/
│   │   ├── xgmii_gen.sv     generador XGMII
│   │   ├── xgmii_checker.sv checker XGMII
│   │   └── tests/           8 tests con estímulo por XGMII
│   └── pcs/
│       ├── pcs_gen.sv       generador PCS (bloques 64B/66B)
│       ├── pcs_checker.sv   checker PCS
│       └── tests/           12 tests con estímulo por la línea
└── sim/test_phy.py          cocotb + pytest
```

### 4.3 Testbench (`tb_top`) y loopbacks

En `tb_top` se instancian el DUT, los dos generadores y los dos checkers. No usé `interface`: cada agente tiene puertos `logic` (dos señales y el clock) que se conectan directamente con `logic` a los puertos del DUT.

| Agente | Clock | Se conecta a |
|---|---|---|
| `xgmii_gen` | `tx_clk` | Entrada XGMII del TX (`xgmii_txd/txc`) |
| `pcs_checker` | `tx_clk` | Salida serdes del TX (`serdes_tx_data/hdr`) |
| `pcs_gen` | `rx_clk` | Entrada serdes del RX (`serdes_rx_data/hdr`) |
| `xgmii_checker` | `rx_clk` | Salida XGMII del RX (`xgmii_rxd/rxc`) |

Cada agente usa el mismo clock que la mitad del DUT a la que se conecta.

Una señal del testbench, `loopback_xgmii`, decide por dónde entra el estímulo. Lo hace con dos pares de multiplexores combinacionales:

```systemverilog
assign xgmii_txd      = loopback_xgmii ? xgmii_rxd   : gen_txd;        // entrada XGMII del TX
assign serdes_rx_data = loopback_xgmii ? gen_rx_data : serdes_tx_data; // entrada serdes del RX
```

Lo mismo se hace con `txc`, con el header y con los `valid`. Los checkers no cambian de lugar: `xgmii_checker` siempre mira la salida del RX y `pcs_checker` siempre mira la salida del TX.

**Tests XGMII (`loopback_xgmii = 0`, loopback de línea):**

```
xgmii_gen ──► TX ──► serdes_tx ──┬──► pcs_checker      (verifica el TX)
                                 │
                                 └──► RX ──► xgmii_rx ──► xgmii_checker   (vuelta completa)
```

El estímulo entra por la XGMII. `pcs_checker` verifica que el TX genere los bloques correctos, y `xgmii_checker` verifica que el frame vuelva entero después de pasar por el RX.

**Tests PCS (`loopback_xgmii = 1`, loopback XGMII):**

```
pcs_gen ──► RX ──► xgmii_rx ──┬──► xgmii_checker     (verifica el RX)
                              │
                              └──► TX ──► serdes_tx ──► pcs_checker   (vuelta completa)
```

El estímulo entra por la línea, con bloques armados a mano que pueden estar mal formados a propósito. `xgmii_checker` verifica lo que decodifica el RX.

En los dos modos, cada frame atraviesa el DUT dos veces, así que las dos mitades se prueban con el mismo estímulo.

Los dos multiplexores son los únicos lugares donde una señal pasa de `tx_clk` a `rx_clk` o al revés. En la simulación esto no genera problemas porque los dos clocks son idénticos y van en fase. En hardware real, un loopback así necesitaría un FIFO elástico con inserción y borrado de idles para compensar la diferencia de frecuencia (cl. 49.2.4.7).

### 4.4 Estructura de un test

Todos los tests siguen la misma plantilla:

```systemverilog
initial tb_top.loopback_xgmii = 1;          // solo en los tests PCS

wait (start);
while (!tb_top.dut.rx_block_lock) gen.send_idle(1);   // esperar block lock
gen.send_idle(10);                           // margen: descrambler sincronizado
chk.clear();                                 // los contadores arrancan desde acá
... estímulo ...                             // tasks del generador, una detrás de otra
gen.send_idle(20);                           // dejar salir todo
chk.check_counts(.frames(..), .e(..), .prbs(..), .seq(..));  // lo que pide la norma
done = 1;
```

Antes del `clear()` hay que esperar dos cosas:

- que el RX consiga block lock (cl. 49.2.9, ventana de 64 sync headers);
- que el descrambler se sincronice (cl. 49.2.10, necesita 58 bits).

Lo que sale antes de eso es basura del arranque. En los logs se ven unos pocos lock/unlock al principio (antes de los ~40 ns), y por eso no se cuentan.

### 4.5 PRBS31, scrambler y descrambler (`common/prbs.sv`)

Las tres funciones viven en un módulo compartido:

- **`generate_prbs`:** PRBS31 con polinomio 1 + x²⁸ + x³¹ y salida invertida (cl. 49.2.8). Es la fuente del payload de todos los frames.
- **`scramble`:** scrambler auto-sincronizante 1 + x³⁹ + x⁵⁸ (cl. 49.2.6). Lo usa el generador PCS.
- **`descramble`:** el descrambler correspondiente (cl. 49.2.10). Lo usa el checker PCS.
- **`scramble_hdr`:** scramblea también el sync header. Solo sirve para inyectar un error, porque según la norma el header no se scramblea.

---

## 5. Agentes

### 5.1 Generador XGMII (`xgmii_gen`)

Hace de RS del lado TX: entrega palabras de 64 bits (8 lanes) y 8 bits de control, una por ciclo. La lane 0 es `TXD[7:0]`.

Tasks que respetan la norma (cl. 46.2):

- `send_idle(n)`: n palabras de /I/ (0x07 con control = 1).
- `send_start()`: /S/ (0xFB) en la lane 0, 6 bytes de preámbulo (0x55) y el SFD (0xD5). El /S/ reemplaza el primer octeto del preámbulo (cl. 46.2.2): por eso quedan 6 de preámbulo y no 7.
- `send_data(n)`: n palabras de payload PRBS31.
- `send_terminate(k)`: k bytes de dato, /T/ (0xFD) en la lane k y el resto /I/.
- `send_frame(n, k)` y `send_frame_lane4(n)`: un frame completo, con el /S/ en la lane 0 o en la lane 4 (las dos posiciones válidas, cl. 49.2.4.8).

Tasks para inyectar errores:

- `send_word(data, ctrl)`: manda una palabra cualquiera, válida o no.
- `send_start_lane(k)`: manda el /S/ en una lane no permitida.

### 5.2 Checker XGMII (`xgmii_checker`)

La XGMII es un flujo de bytes que se reparten en lanes por turno (cl. 46.2, figura 46-3). El checker es una **máquina de estados que corre sola en todos los ciclos**: recorre las 8 lanes en orden y cada byte la hace avanzar.

```
UNLOCKED ──/I/──► INTER_FRAME ──/S/ (lane 0 o 4)──► IN_PREAMBLE ──6 × 0x55──► IN_SFD ──0xD5──► IN_DATA ──/T/──► INTER_FRAME
```

- **UNLOCKED:** no verifica nada. Se lockea en los dos únicos puntos donde sabe con seguridad dónde está: un /I/ (entre frames) o un /S/ válido (empieza un frame).
- **Lockeado:** cada byte tiene que ser exactamente el que corresponde según la estructura del frame. Los bytes de datos pasan por un checker PRBS31 auto-sincronizante (cl. 49.2.12). Los primeros 31 bits de cada frame solo cargan su registro; después, cada bit se compara con `~(reg[27] ^ reg[30])`.
- **Ante el primer byte inesperado se deslockea**, cuenta el error y no verifica nada hasta el próximo /I/ o /S/. Así un error no se propaga al resto del frame.

Esto de deslockearse con el primer error es un **criterio de verificación, no de la norma**. El block lock del PCS (cl. 49.2.9) tolera hasta 15 headers malos cada 64. El checker, en cambio, tiene que reportar todos los errores.

Contadores:

| Contador | Qué cuenta |
|---|---|
| `frame_count` | Frames completos sin errores |
| `e_count` | Bytes /E/ (0xFE con control = 1). Se cuentan siempre, esté lockeado o no. Una palabra de error suma 8 |
| `prbs_err_count` | Datos que no siguen la PRBS31 |
| `seq_err_count` | Bytes válidos fuera de la secuencia esperada (un /E/ no suma acá porque ya se contó en `e_count`) |
| `unlock_count` | Cuántas veces se deslockeó (solo se imprime) |

### 5.3 Generador PCS (`pcs_gen`)

Hace de línea del lado RX: entrega un bloque de 66 bits por ciclo (64 de payload + 2 de sync header).

Su núcleo es un `always @(posedge clk)` que **escribe la línea en todos los ciclos**. Si hay un bloque en la cola lo saca; si no, manda un idle. Después scramblea el payload y lo pone en la salida. Las tasks no manejan la salida directamente: encolan el bloque y esperan un flanco. Hecho así tiene dos ventajas:

- La línea nunca queda con un bloque repetido. Si quedara, el descrambler del RX lo convertiría en basura.
- El scrambler avanza exactamente un bloque por ciclo, como en un transmisor real.

El sync header no se scramblea (cl. 49.2.4.3). Para el header uso la convención "bit 0 = primer bit transmitido", así que el "01" de dato de la norma queda como `2'b10` en el código, y el "10" de control como `2'b01`.

Tasks que respetan la norma (formatos de la figura 49-7):

- `send_idle(n)`: block type 0x1E con 8 códigos /I/ (0x00, 7 bits).
- `send_error()`: block type 0x1E con 8 códigos /E/ (0x1E, 7 bits).
- `send_start()`: block type 0x78 + D1..D7 = 6 de preámbulo + SFD.
- `send_data(n)`: n bloques de datos PRBS31, con header de dato y sin block type.
- `send_terminate(k)`: block type del /T/ en la posición k (0x87, 0x99, 0xAA, 0xB4, 0xCC, 0xD2, 0xE1, 0xFF), k bytes de dato y el resto en 0.
- `send_frame(n, k)` y `send_frame_lane4(n)`: un frame completo. El segundo usa el start 0x33 (4 /I/, 4 bits en 0 y 3 bytes de preámbulo), y todo el frame queda corrido 4 bytes.

Tasks para inyectar errores:

- `send_idle_hdr(h)` y `send_data_hdr(h)`: un bloque con el sync header que se le pase (00, 11 o invertido).
- `send_ctrl_code(pos, code)`: un bloque 0x1E con un código de 7 bits cualquiera en la posición `pos`.
- `send_block_type(t)`: un bloque de control con un block type cualquiera.
- `send_data_flip(bit)`: invierte un bit en la línea, después del scrambler. Simula un error de transmisión.
- Las variables `scramble_en` y `scramble_hdr` sacan el scrambler o lo aplican también al header.

### 5.4 Checker PCS (`pcs_checker`)

Hace lo mismo que el checker XGMII, pero a nivel de bloque, y sigue el diagrama de recepción de la norma (cl. 49.2.13.2.3, figura 49-17). En cada ciclo hace tres pasos:

1. **Descramblea** el payload (cl. 49.2.10). Lo hace en todos los ciclos, para que el descrambler no pierda la sincronización.
2. **Clasifica** el bloque (task `classify`, el equivalente a la función R_TYPE de la norma):
   - header de dato → `BLOCK_DATA`;
   - header 00 o 11 → `BLOCK_ERROR`, inválido (cl. 49.2.4.6 a);
   - 0x1E con 8 /I/ → `BLOCK_CONTROL`. Si tiene algún /E/ → `BLOCK_ERROR` (válido). Si tiene un código que no está en la tabla 49-1 → `BLOCK_ERROR`, inválido (cl. 49.2.4.6 c);
   - 0x78 o 0x33 bien formado → `BLOCK_START` (posición 0 o 4);
   - uno de los 8 block types de terminate, con el relleno en 0 y los códigos válidos → `BLOCK_TERMINATE`;
   - cualquier otro block type → `BLOCK_ERROR`, inválido (cl. 49.2.4.6 b).
3. **Avanza la máquina de estados:**

```
UNLOCKED ──control──► INTER_FRAME ──start──► IN_FRAME ──terminate──► INTER_FRAME
    └────────────start──────────────────────► IN_FRAME
```

- `INTER_FRAME` equivale a RX_C de la norma: acepta control (y se queda) o start (pasa a IN_FRAME).
- `IN_FRAME` equivale a RX_D: acepta datos o un terminate.
- Cualquier otro bloque, en la norma, lleva a RX_E. En el checker es un unlock.

Dentro del frame verifica el preámbulo, el SFD y la PRBS31 del payload igual que el checker XGMII, byte por byte. Tiene los mismos contadores y uno más, `blk_err_count`, con los bloques inválidos según la cl. 49.2.4.6.

Tamaños dentro de un bloque, que sirven para leer los dos agentes PCS:

| Campo | Tamaño |
|---|---|
| Sync header | 2 bits (fuera del payload) |
| Block type | 8 bits, en `block[7:0]`, solo en los bloques de control |
| Byte de dato (D0..D7) | 8 bits |
| Código de control (C0..C7) | 7 bits (tabla 49-1: /I/ = 0x00, /E/ = 0x1E) |

Los controles se comprimen a 7 bits para que en un bloque todo control entren el block type y 8 códigos: 8 + 8 × 7 = 64. /S/ y /T/ no ocupan lugar porque van implícitos en el block type. Cuando sobran bits (en el 0x33 y en los terminate), se rellenan con 0.

---

## 6. Resumen de resultados

| # | Test | Agente | Resultado |
|---|---|---|---|
| 1 | `test_happy_path` | XGMII | PASA |
| 2 | `test_term_lanes` | XGMII | PASA |
| 3 | `test_start_lane4` | XGMII | PASA |
| 4 | `test_start_term` | XGMII | PASA |
| 5 | `test_error_char` | XGMII | PASA |
| 6 | `test_bad_ctrl` | XGMII | **FALLA** |
| 7 | `test_start_bad_lane` | XGMII | **FALLA** |
| 8 | `test_double_start` | XGMII | **FALLA** |
| 9 | `test_happy_path` | PCS | PASA |
| 10 | `test_bad_sync_hdr` | PCS | PASA |
| 11 | `test_start_mismatch` | PCS | PASA |
| 12 | `test_bit_flip` | PCS | PASA |
| 13 | `test_no_scramble` | PCS | PASA |
| 14 | `test_scramble_hdr` | PCS | PASA |
| 15 | `test_lock_loss` | PCS | PASA |
| 16 | `test_lock_keep` | PCS | PASA |
| 17 | `test_bad_ctrl` | PCS | **FALLA** |
| 18 | `test_inverse_hdr` | PCS | **FALLA** |
| 19 | `test_double_start` | PCS | **FALLA** |
| 20 | `test_term_no_start` | PCS | **FALLA** |

**Total: 20 tests, 13 pasan y 7 fallan.**

[Insertar acá la captura de la salida de pytest.]

En las secciones que siguen, los valores esperados se escriben como `frames / e / prbs / seq`, en el mismo orden que los argumentos de `check_counts`.

---

## 7. Resultados por test

### 7.1 Tests XGMII (estímulo por XGMII, `loopback_xgmii = 0`)

En estos tests se verifican los dos checkers. `pcs_checker` mira los bloques que genera el TX. `xgmii_checker` mira lo que sale del RX después del loopback de línea. Los dos tienen que dar los mismos conteos.

Para los casos de error, la regla de la norma es la **máquina de estados de transmisión** (cl. 49.2.13.2.3, función T_TYPE y diagrama de transmisión):

- Cada palabra XGMII se clasifica como C (todo control válido), S (start válido), D (todo datos), T (terminate válido) o E (cualquier otra cosa).
- Una palabra que no corresponde en el estado actual, o que directamente es E, lleva el TX a TX_E, y el TX manda un **bloque de error completo**: 0x1E con 8 códigos /E/.
- Cuando el RX recibe ese bloque, saca por la XGMII una palabra de 8 × 0xFE. Por eso cada palabra mala suma 8 a `e`.

#### 7.1.1 `test_happy_path` (XGMII): PASA

- **Objetivo:** verificar el camino normal completo.
- **Estímulo:** 3 frames correctos de 8, 1 y 20 palabras de datos, con el /T/ en las lanes 0, 4 y 7.
- **Esperado según la norma:** el TX tiene que generar start 0x78, bloques de datos y el terminate que corresponde a cada lane (figura 49-7). Después de la vuelta por el RX, los 3 frames tienen que salir con el formato de la cl. 46.2 y con el payload PRBS31 intacto. Esperado `3 / 0 / 0 / 0` en los dos checkers.
- **Obtenido:**
  ```
  PCS CHECKER:   frames=3 e=0 prbs=0 seq=0 blk=0 unlocks=0
  XGMII CHECKER: frames=3 e=0 prbs=0 seq=0 unlocks=0
  ```
- **Conclusión:** el TX codifica y el RX decodifica correctamente los frames válidos. Ningún checker se deslockeó en todo el test.

#### 7.1.2 `test_term_lanes`: PASA

- **Objetivo:** verificar el terminate en cada una de las 8 posiciones.
- **Estímulo:** 8 frames de 2 palabras. En el frame k, el /T/ cae en la lane k.
- **Esperado según la norma:** cada posición tiene su propio block type (figura 49-7): 0x87, 0x99, 0xAA, 0xB4, 0xCC, 0xD2, 0xE1, 0xFF, con k bytes de dato y 7 − k bits de relleno en 0. Esperado `8 / 0 / 0 / 0`.
- **Obtenido:** `frames=8 e=0 prbs=0 seq=0` en los dos checkers.
- **Conclusión:** los 8 formatos de terminate se codifican y decodifican bien, incluido el T0 (sin datos) y el T7 (sin códigos de control).

#### 7.1.3 `test_start_lane4`: PASA

- **Objetivo:** verificar el start en la lane 4. Con la XGMII de 64 bits es válido, porque la lane 4 es la lane 0 de la segunda palabra de 32 bits (cl. 49.2.4.8).
- **Estímulo:** 2 frames con el /S/ en la lane 4, de 4 y 1 palabras.
- **Esperado según la norma:** el TX tiene que usar el block type 0x33: 4 /I/, 4 bits en 0 y 3 bytes de preámbulo. El resto del frame queda corrido 4 bytes. Esperado `2 / 0 / 0 / 0`.
- **Obtenido:** `frames=2 e=0 prbs=0 seq=0` en los dos checkers.
- **Conclusión:** el formato 0x33 y el corrimiento de 4 bytes funcionan correctamente.

#### 7.1.4 `test_start_term`: PASA

- **Objetivo:** verificar un start seguido directamente de un terminate, sin palabras de datos en el medio.
- **Estímulo:** 2 frames. En el primero el /T/ está en la lane 0, así que el frame no tiene payload. En el segundo está en la lane 5, con 5 bytes de payload.
- **Esperado según la norma:** start en TX_C lleva a TX_D, y terminate en TX_D lleva a TX_T. Es una secuencia válida. Esperado `2 / 0 / 0 / 0`.
- **Obtenido:** `frames=2 e=0 prbs=0 seq=0` en los dos checkers.
- **Conclusión:** los frames mínimos se manejan bien. En el segundo hay 40 bits de payload: los primeros 31 sincronizan el checker PRBS y los 9 restantes se verifican.

#### 7.1.5 `test_error_char`: PASA

- **Objetivo:** verificar un carácter de error (/E/) en medio de un frame.
- **Estímulo:** start, 2 palabras de datos, una palabra de datos con 0xFE en la lane 3 (control = 1 solo en esa lane), 1 palabra de datos y terminate.
- **Esperado según la norma:** la palabra mezcla datos y un /E/, así que no es D, S, T ni C: es E. En TX_D pasa a TX_E y el TX manda un bloque de error. La palabra de datos siguiente lo vuelve a TX_D. Del lado de la XGMII sale una palabra de 8 /E/ y el frame no puede contar como correcto. Esperado `0 / 8 / 0 / 0`.
- **Obtenido:**
  ```
  PCS CHECKER:   unlock (IN_FRAME): bloque BLOCK_ERROR (bloque con /E/), se esperaba data o terminate
  XGMII CHECKER: unlock en lane 0 (IN_DATA): ctrl=1 octet=fe, se esperaba data o terminate
  PCS CHECKER:   frames=0 e=8 prbs=0 seq=0 blk=0 unlocks=1
  XGMII CHECKER: frames=0 e=8 prbs=0 seq=0 unlocks=1
  ```
- **Conclusión:** el TX convierte la palabra en un bloque de error entero. Este caso funciona porque la palabra mezcla datos y controles (sección 8.1).

#### 7.1.6 `test_bad_ctrl` (XGMII): FALLA

- **Objetivo:** verificar caracteres de control que no existen en la tabla 46-3.
- **Estímulo:** entre idles, dos palabras.
  1. 0x55 con control = 1 en las 8 lanes.
  2. Todas las lanes con /I/ salvo la lane 3, que lleva 0x00 con control = 1.
- **Esperado según la norma:** las dos palabras tienen un carácter de control inválido, así que no son C: son E. En TX_C pasan a TX_E y el TX tiene que mandar un **bloque de error completo**, aunque el carácter inválido esté en una sola lane. Del lado de la XGMII salen 2 palabras de 8 /E/. Esperado `0 / 16 / 0 / 0`.
- **Obtenido:**
  ```
  XGMII CHECKER: unlock en lane 0 (INTER_FRAME): ctrl=1 octet=fe, se esperaba idle o start
  XGMII CHECKER: unlock en lane 3 (INTER_FRAME): ctrl=1 octet=fe, se esperaba idle o start
  XGMII CHECKER: lock en lane 4 (INTER_FRAME)
  PCS CHECKER:   frames=0 e=9 prbs=0 seq=0 blk=0 unlocks=2
  PCS CHECKER ERROR: e = 9, se esperaba 16
  XGMII CHECKER: frames=0 e=9 prbs=0 seq=0 unlocks=2
  XGMII CHECKER ERROR: e = 9, se esperaba 16
  ```
- **Análisis:**
  - La primera palabra sale bien: 8 /E/.
  - En la segunda, el checker se deslockea en la lane 3 y se vuelve a lockear en la lane 4 **de la misma palabra**. Eso quiere decir que las lanes 4 a 7 son /I/, igual que las 0 a 2: el TX puso **un solo /E/**, en la lane del carácter inválido, y dejó el resto como idle.
  - Total: 8 + 1 = 9, contra los 16 que pide la norma.
  - Los dos checkers dan 9, así que el error ya está en el bloque que genera el TX: el RX solo lo pasa.
  - En la primera palabra las 8 lanes son inválidas, así que reemplazarlas una por una da el mismo resultado que el bloque de error completo. Por eso ese caso no muestra el problema.
- **Contraste con la norma:** según la función T_TYPE, la palabra entera es de tipo E, y en TX_E se transmite `EBLOCK_T` (8 /E/). El RTL trata el error lane por lane, no palabra por palabra.

#### 7.1.7 `test_start_bad_lane`: FALLA

- **Objetivo:** verificar un /S/ en una lane no permitida. Según la norma, el /S/ solo puede ir en la lane 0 o en la 4 (cl. 46.2 y 49.2.4.8).
- **Estímulo:** entre idles, 6 palabras con el /S/ en las lanes 1, 2, 3, 5, 6 y 7. Las lanes anteriores al /S/ llevan /I/ y las posteriores, preámbulo.
- **Esperado según la norma:** un /S/ en esas lanes no es un S válido, así que la palabra es E. En TX_C pasa a TX_E: un bloque de error por cada caso. Esperado 6 × 8 = 48 /E/, o sea `0 / 48 / 0 / 0`.
- **Obtenido:**
  ```
  ... 5 unlocks en lane 0 (palabras de error completas) ...
  XGMII CHECKER: unlock en lane 7 (INTER_FRAME): ctrl=1 octet=fe, se esperaba idle o start
  PCS CHECKER:   frames=0 e=41 prbs=0 seq=0 blk=0 unlocks=6
  PCS CHECKER ERROR: e = 41, se esperaba 48
  XGMII CHECKER: frames=0 e=41 prbs=0 seq=0 unlocks=6
  XGMII CHECKER ERROR: e = 41, se esperaba 48
  ```
- **Análisis:**
  - En las lanes 1, 2, 3, 5 y 6, la palabra mezcla controles (los /I/ anteriores y el /S/) con datos (el preámbulo). Ahí el TX sí manda el bloque de error completo: 5 × 8 = 40.
  - Con el /S/ en la lane 7, la palabra es **toda de control** (7 /I/ + /S/) y el TX solo reemplaza la lane 7 por /E/: suma 1.
  - Total: 41, contra 48.
- **Contraste con la norma:** es la misma causa que en `test_bad_ctrl`. En una palabra toda de control, el RTL reemplaza por /E/ solo las lanes inválidas, en vez de transmitir `EBLOCK_T` como pide el diagrama de transmisión.

#### 7.1.8 `test_double_start` (XGMII): FALLA

- **Objetivo:** verificar un segundo start en medio de un frame.
- **Estímulo:** start, start, 2 palabras de datos y terminate en la lane 3.
- **Esperado según la norma:** el primer start lleva de TX_C a TX_D. En TX_D solo son válidos D o T, así que el segundo start lleva a TX_E y el TX manda un bloque de error. Después, los datos lo devuelven a TX_D. Del lado de la XGMII sale una palabra de 8 /E/ y ningún frame correcto. Esperado `0 / 8 / 0 / 0`.
- **Obtenido:**
  ```
  PCS CHECKER:   unlock (IN_FRAME): bloque BLOCK_START, se esperaba data o terminate
  XGMII CHECKER: unlock en lane 0 (IN_DATA): ctrl=1 octet=fb, se esperaba data o terminate
  PCS CHECKER:   frames=0 e=0 prbs=0 seq=1 blk=0 unlocks=1
  PCS CHECKER ERROR: e = 0, se esperaba 8
  PCS CHECKER ERROR: seq = 1, se esperaba 0
  XGMII CHECKER: frames=0 e=0 prbs=0 seq=1 unlocks=1
  XGMII CHECKER ERROR: e = 0, se esperaba 8
  XGMII CHECKER ERROR: seq = 1, se esperaba 0
  ```
- **Análisis:** el TX codificó el segundo start como un start normal (block type 0x78), no como un bloque de error. El checker PCS ve un `BLOCK_START` dentro del frame y el checker XGMII ve un /S/ (0xFB) en medio de los datos. Los dos lo cuentan como error de secuencia y no aparece ningún /E/.
- **Contraste con la norma:** el TX no recuerda si está dentro de un frame. Codifica cada palabra por separado, sin la máquina de estados de transmisión, que es la que decide que un S en TX_D lleva a TX_E.

### 7.2 Tests PCS (estímulo por la línea, `loopback_xgmii = 1`)

En estos tests se verifica el RX con `xgmii_checker`. Solo en el happy path se verifica también `pcs_checker`, al final del loopback XGMII.

Para los casos de error, la regla de la norma es la **máquina de estados de recepción** (cl. 49.2.13.2.3, función R_TYPE y figura 49-17):

- Cada bloque se clasifica como C, S, D, T o E. Un bloque inválido según la cl. 49.2.4.6 es E.
- Un bloque que no corresponde en el estado actual, o que es E, lleva el RX a RX_E, y el RX saca por la XGMII una **palabra de error completa**: 0xFE en las 8 lanes, con control = 1.
- El bloque siguiente lo saca de RX_E: un C lo lleva a RX_C y un D a RX_D.
- Cada bloque malo, entonces, suma 8 a `e`.

#### 7.2.1 `test_happy_path` (PCS): PASA

- **Objetivo:** verificar el camino normal del RX y la vuelta completa por el TX.
- **Estímulo:** 4 frames correctos: tres con start 0x78 y terminate en las posiciones 0, 4 y 7, y uno con start 0x33.
- **Esperado según la norma:** el RX tiene que decodificar los 4 frames con el formato de la cl. 46.2 y el payload intacto. Al pasar por el TX, los bloques tienen que volver a ser los de la figura 49-7. Esperado `4 / 0 / 0 / 0` en los dos checkers.
- **Obtenido:**
  ```
  XGMII CHECKER: frames=4 e=0 prbs=0 seq=0 unlocks=0
  PCS CHECKER:   frames=4 e=0 prbs=0 seq=0 blk=0 unlocks=0
  ```
- **Conclusión:** el RX decodifica bien todos los formatos válidos, incluido el start en la posición 4, y la vuelta por el TX es consistente.

#### 7.2.2 `test_bad_sync_hdr`: PASA

- **Objetivo:** verificar los sync headers inválidos.
- **Estímulo:** un idle con header 00 y otro con header 11, separados por idles. Después, un frame con un bloque de datos con header 00 y otro con header 11.
- **Esperado según la norma:** un header 00 o 11 hace que el bloque sea inválido (cl. 49.2.4.6 a), o sea de tipo E. Tanto en RX_C como en RX_D lleva a RX_E, y sale una palabra de error. El bloque siguiente sale normal. Son 4 palabras de error, y el frame queda arruinado. Esperado `0 / 32 / 0 / 0`.
- **Obtenido:**
  ```
  XGMII CHECKER: unlock en lane 0 (INTER_FRAME): ctrl=1 octet=fe ...   (2 veces)
  XGMII CHECKER: unlock en lane 0 (IN_DATA): ctrl=1 octet=fe, se esperaba data o terminate
  XGMII CHECKER: frames=0 e=32 prbs=0 seq=0 unlocks=3
  ```
- **Conclusión:** cada header inválido produce una palabra de error completa, tanto entre frames como dentro de uno.
- Hay 3 unlocks para 4 errores porque, después del primer /E/ dentro del frame, el checker ya está deslockeado. El segundo bloque malo del frame suma sus 8 /E/ igual, porque `e_count` se cuenta siempre, pero no genera un unlock nuevo.

#### 7.2.3 `test_start_mismatch`: PASA

- **Objetivo:** verificar que el RX use el block type para decidir la posición del start, y no el contenido del bloque.
- **Estímulo:** un bloque con block type 0x78 (start en la posición 0), pero con el contenido de un 0x33: 4 /I/, 4 bits en 0 y 3 bytes de preámbulo. Después, datos y terminate.
- **Esperado según la norma:** la posición del start la da solo el block type (figura 49-7). Para un 0x78, los bytes 1 a 7 son D1..D7, así que el RX tiene que sacarlos como datos tal cual: /S/ en la lane 0, 0x00 en las lanes 1 a 4 y 0x55 en las lanes 5 a 7. El bloque es válido, así que el RX no debe marcarlo como /E/. Quien detecta el problema es el checker XGMII: en la lane 1 esperaba preámbulo y llega 0x00 (cl. 46.2.2). Esperado `0 / 0 / 0 / 1`.
- **Obtenido:**
  ```
  XGMII CHECKER: unlock en lane 1 (IN_PREAMBLE): ctrl=0 octet=00, se esperaba preámbulo (0x55)
  XGMII CHECKER: frames=0 e=0 prbs=0 seq=1 unlocks=1
  ```
- **Conclusión:** el RX respeta el block type y pasa los datos sin interpretarlos.

#### 7.2.4 `test_bit_flip`: PASA

- **Objetivo:** verificar el efecto de un error de un bit en la línea.
- **Estímulo:** 2 frames. En el primero se invierte el bit 0 de un bloque de datos, y en el segundo el bit 20. La inversión se hace en la línea, después del scrambler.
- **Esperado según la norma:** el descrambler es 1 + x³⁹ + x⁵⁸ (cl. 49.2.10), así que un bit errado en la posición k de la línea sale errado en k, k + 39 y k + 58.
  - Para el bit 0: errores en los bits 0, 39 y 58 del bloque.
  - Para el bit 20: errores en los bits 20 y 59, y en el bit 14 del bloque siguiente.
  - El checker PRBS detecta el primer bit errado de cada frame y se deslockea, así que cuenta 1 error por frame. Esperado `0 / 0 / 2 / 0`.
- **Obtenido:**
  ```
  XGMII CHECKER: unlock en lane 0 (IN_DATA): ctrl=0 octet=fe, el bit 0 no cumple la PRBS31
  XGMII CHECKER: unlock en lane 2 (IN_DATA): ctrl=0 octet=ef, el bit 4 no cumple la PRBS31
  XGMII CHECKER: frames=0 e=0 prbs=2 seq=0 unlocks=2
  ```
- **Conclusión:** los errores aparecen exactamente donde predice el polinomio del descrambler. El bit 20 del bloque es el bit 4 del byte 2, que corresponde a la lane 2.

#### 7.2.5 `test_no_scramble`: PASA

- **Objetivo:** verificar que el RX descramblee siempre.
- **Estímulo:** un frame mandado con `scramble_en = 0`, seguido de 1500 idles.
- **Esperado según la norma:** el RX descramblea todo el payload (cl. 49.2.10), así que un payload sin scramblear sale cambiado y el frame no puede llegar intacto. El sync header no se scramblea, así que el block lock tiene que mantenerse en todo momento. Es un test negativo: pasa si `frame_count == 0` y `rx_block_lock` nunca baja. Esto lo controla un monitor en un `fork`, en paralelo con el estímulo.
- **Obtenido:** ningún frame correcto y `rx_block_lock` siempre en alto. Del lado de la XGMII sale basura (/E/ en varias lanes), como se espera de un payload sin scramblear.
- **Conclusión:** el RX descramblea siempre, y el block lock depende solo de los headers.

#### 7.2.6 `test_scramble_hdr`: PASA

- **Objetivo:** verificar que el block lock se pierda si los headers no son válidos.
- **Estímulo:** idles con el sync header scrambleado junto con el payload. Según la norma esto es incorrecto, porque el header no se scramblea (cl. 49.2.4.3).
- **Esperado según la norma:** al scramblearse, cerca de la mitad de los headers sale 00 o 11. Con 16 headers inválidos en una ventana de 64 se pierde el block lock (cl. 49.2.9). Pasa si `rx_block_lock` baja.
- **Obtenido:** `rx_block_lock` baja.
- **Conclusión:** la máquina de block lock detecta la pérdida de sincronización.

#### 7.2.7 `test_lock_loss`: PASA

- **Objetivo:** verificar el umbral exacto de pérdida de block lock.
- **Estímulo:** un patrón periódico de 16 headers inválidos (8 pares de 00 y 11) y 48 válidos, repetido. Desde afuera no se sabe dónde arranca la ventana de 64 de la máquina de lock. Con un período de 64, cualquier ventana de 64 bloques tiene exactamente 16 inválidos, empiece donde empiece. Se repite hasta 8 veces; ese límite es un timeout, no sale de la norma.
- **Esperado según la norma:** con 16 headers inválidos en 64 se pierde el block lock (cl. 49.2.9). Pasa si `rx_block_lock` baja.
- **Obtenido:** `rx_block_lock` baja.
- **Conclusión:** con 16 headers inválidos se pierde el lock, como pide la norma.

#### 7.2.8 `test_lock_keep`: PASA

- **Objetivo:** verificar que no se pierda el lock justo por debajo del umbral.
- **Estímulo:** el mismo patrón con 15 inválidos y 49 válidos, durante 8 períodos (512 bloques).
- **Esperado según la norma:** con 15 inválidos por ventana no se llega al umbral, así que el block lock no tiene que bajar nunca. Lo controla un monitor en un `fork`, ciclo a ciclo.
- **Obtenido:** `rx_block_lock` no baja en ningún momento. En el log se ven las palabras de error que produce cada header inválido, que es lo esperado. No afectan el resultado, porque este test solo mira el lock.
- **Conclusión:** junto con `test_lock_loss`, confirma que **el umbral es exactamente 16**.

#### 7.2.9 `test_bad_ctrl` (PCS): FALLA

- **Objetivo:** verificar bloques de control con contenido que no existe en la norma.
- **Estímulo:** entre idles, tres bloques.
  1. Block type 0x1E con 8 /I/, salvo el código de la posición 3, que vale 0x01: no está en la tabla 49-1.
  2. Block type 0x00, con 8 /I/.
  3. Block type 0x11, con 8 /I/.
  Ninguno de esos dos block types existe en la figura 49-7.
- **Esperado según la norma:** los tres bloques son inválidos (cl. 49.2.4.6 c para el primero y b para los otros dos), así que son de tipo E. En RX_C pasan a RX_E y sale una **palabra de error entera**. Esperado 3 × 8 = 24 /E/, o sea `0 / 24 / 0 / 0`.
- **Obtenido:**
  ```
  XGMII CHECKER: unlock en lane 3 (INTER_FRAME): ctrl=1 octet=fe, se esperaba idle o start
  XGMII CHECKER: lock en lane 4 (INTER_FRAME)
  XGMII CHECKER: unlock en lane 0 (INTER_FRAME): ctrl=1 octet=fe, se esperaba idle o start
  XGMII CHECKER: unlock en lane 0 (INTER_FRAME): ctrl=1 octet=fe, se esperaba idle o start
  XGMII CHECKER: frames=0 e=17 prbs=0 seq=0 unlocks=3
  XGMII CHECKER ERROR: e = 17, se esperaba 24
  ```
- **Análisis:**
  - Con el código inválido, el checker se deslockea en la lane 3 y se vuelve a lockear en la lane 4 de la misma palabra. El RX sacó `07070707FE070707`: **un solo /E/**, en la lane del código malo.
  - Con los block types inexistentes sí sale la palabra entera.
  - Total: 1 + 8 + 8 = 17, contra 24.
  - Elegí a propósito la posición 3, y no la 0, para poder distinguir si el RX marca el bloque entero o solo el byte.
- **Contraste con la norma:** la función R_TYPE devuelve E para todo el bloque si alguno de sus códigos es inválido, y en RX_E se saca `EBLOCK_R` (8 /E/). El RTL decodifica código por código y solo reemplaza el inválido.

#### 7.2.10 `test_inverse_hdr`: FALLA

- **Objetivo:** verificar los sync headers invertidos.
- **Estímulo:**
  1. Entre idles, un bloque de idle con header de **dato**.
  2. Dentro de un frame, un bloque de datos con header de **control**.
- **Esperado según la norma:**
  1. Con header de dato, el bloque es de tipo D. Un D en RX_C lleva a RX_E: sale una palabra de error.
  2. Con header de control, el primer byte del bloque se toma como block type. Con esta PRBS vale 0xFF, así que se lee como un terminate T7. Pero el bloque siguiente es un dato, y un T solo es válido si lo sigue un C o un S (R_TYPE_NEXT en la figura 49-17). Entonces también va a RX_E y sale una palabra de error.
  Esperado 2 × 8 = 16 /E/, o sea `0 / 16 / 0 / 0`.
- **Obtenido:**
  ```
  XGMII CHECKER: unlock en lane 0 (INTER_FRAME): ctrl=0 octet=1e, se esperaba idle o start
  XGMII CHECKER: unlock en lane 0 (IN_DATA): ctrl=0 octet=8f, el bit 4 no cumple la PRBS31
  XGMII CHECKER: frames=0 e=0 prbs=1 seq=1 unlocks=2
  XGMII CHECKER ERROR: e = 0, se esperaba 16
  XGMII CHECKER ERROR: prbs = 1, se esperaba 0
  XGMII CHECKER ERROR: seq = 1, se esperaba 0
  ```
- **Análisis:**
  1. El idle con header de dato **salió como datos**: control = 0, y en la lane 0 está 0x1E, que es el block type del idle pasado como dato. El checker lo cuenta como error de secuencia, porque entre frames esperaba /I/ o /S/.
  2. El bloque de datos con header de control se decodificó como terminate T7: el RX sacó los bytes 1 a 7 como datos y el /T/ en la lane 7. Al perderse el byte 0, la PRBS se rompe en la lane 0 y el checker lo cuenta como error de PRBS.
  En ninguno de los dos casos aparece un /E/.
- **Contraste con la norma:** las dos situaciones requieren la máquina de recepción. La primera necesita saber que un D en RX_C no es válido. La segunda necesita mirar el bloque siguiente para validar el T. El RTL no tiene ninguna de las dos cosas.

#### 7.2.11 `test_double_start` (PCS): FALLA

- **Objetivo:** verificar un segundo start en medio de un frame, del lado del RX.
- **Estímulo:** bloque de start, otro bloque de start, 2 bloques de datos y terminate.
- **Esperado según la norma:** el primer start lleva de RX_C a RX_D. El segundo llega en RX_D, donde solo son válidos D o T, así que lleva a RX_E y sale una palabra de error. Los datos siguientes vuelven a RX_D. Esperado `0 / 8 / 0 / 0`.
- **Obtenido:**
  ```
  XGMII CHECKER: unlock en lane 0 (IN_DATA): ctrl=1 octet=fb, se esperaba data o terminate
  XGMII CHECKER: frames=0 e=0 prbs=0 seq=1 unlocks=1
  XGMII CHECKER ERROR: e = 0, se esperaba 8
  XGMII CHECKER ERROR: seq = 1, se esperaba 0
  ```
- **Análisis:** el RX decodificó el segundo start como un start normal: /S/ (0xFB) en la lane 0, seguido de preámbulo y SFD. El checker XGMII lo detecta como error de secuencia, porque es un /S/ en medio de los datos, pero no hay ningún /E/.
- **Contraste con la norma:** es el mismo caso que `xgmii-test_double_start`, pero del lado RX. El decoder no implementa la transición RX_D → RX_E ante un S.

#### 7.2.12 `test_term_no_start`: FALLA

- **Objetivo:** verificar un terminate sin start previo.
- **Estímulo:** entre idles, un bloque de terminate T3 (3 bytes de dato y /T/ en la posición 3).
- **Esperado según la norma:** un T en RX_C no es válido y lleva a RX_E: sale una palabra de error y después idles. Esperado `0 / 8 / 0 / 0`.
- **Obtenido:**
  ```
  XGMII CHECKER: unlock en lane 0 (INTER_FRAME): ctrl=0 octet=ff, se esperaba idle o start
  XGMII CHECKER: lock en lane 4 (INTER_FRAME)
  XGMII CHECKER: frames=0 e=0 prbs=0 seq=1 unlocks=1
  XGMII CHECKER ERROR: e = 0, se esperaba 8
  XGMII CHECKER ERROR: seq = 1, se esperaba 0
  ```
- **Análisis:** el RX decodificó el terminate normalmente. Sacó los 3 bytes de dato en las lanes 0 a 2 (el checker ve un dato, 0xFF, donde esperaba /I/), el /T/ en la lane 3 e idles desde la lane 4, donde el checker se vuelve a lockear. No hay ningún /E/.
- **Contraste con la norma:** el decoder no recuerda que no hay un frame abierto, así que no aplica la transición RX_C → RX_E ante un T.

---

## 8. Análisis de las fallas

Las 7 fallas se explican con dos problemas del RTL. Los dos tienen la misma raíz: **el encoder y el decoder procesan cada palabra o bloque por separado, sin las máquinas de estado de la cláusula 49.**

### 8.1 El TX no implementa la máquina de estados de transmisión

**Qué pide la norma.** La cl. 49.2.13.2.3 define T_TYPE, que clasifica cada palabra XGMII como C, S, D, T o E, y el diagrama de transmisión, con los estados TX_C, TX_D, TX_T y TX_E. Ante una palabra que no corresponde en el estado actual, o ante una palabra de tipo E, el TX pasa a TX_E y transmite un bloque de error completo (`EBLOCK_T`).

**Qué hace el RTL.** El encoder (`taxi_xgmii_baser_enc.sv`) codifica cada palabra sin mirar las anteriores. Hay dos síntomas:

1. **No detecta los errores de secuencia.** Un start dentro de un frame se codifica como un start normal → falla `xgmii-test_double_start`.
2. **Trata los errores lane por lane.** En una palabra toda de control, reemplaza por /E/ solo las lanes inválidas y deja el resto como /I/, en vez de mandar el bloque de error completo → fallan `xgmii-test_bad_ctrl` (0x00 en la lane 3) y `xgmii-test_start_bad_lane` (el /S/ en la lane 7).

Cuando la palabra mezcla datos y controles, el resultado sí es correcto, porque no existe ningún formato de bloque para esa combinación: pasa `test_error_char` y los /S/ en las lanes 1, 2, 3, 5 y 6. También es correcto cuando todas las lanes son inválidas (0x55 en las 8), porque reemplazar todas da lo mismo que el bloque de error.

### 8.2 El RX no implementa la máquina de estados de recepción

**Qué pide la norma.** La misma cláusula define R_TYPE y R_TYPE_NEXT, y el diagrama de recepción (figura 49-17), con los estados RX_C, RX_D, RX_T y RX_E. Un bloque inválido, o un bloque válido fuera de secuencia, lleva a RX_E, y el RX saca por la XGMII una palabra de error completa (`EBLOCK_R`). Además, un T solo es válido si el bloque siguiente es un C o un S.

**Qué hace el RTL.** El decoder (`taxi_xgmii_baser_dec.sv`) decodifica cada bloque por separado. Lleva la cuenta de si está dentro de un frame y levanta la salida `rx_sequence_error` cuando detecta un error de secuencia, pero **deja pasar el bloque igual**. Esa bandera no existe en la norma: sirve para avisar que algo anduvo mal, pero no corrige la salida de la XGMII. Hay tres síntomas:

1. **Errores de secuencia sin /E/:**
   - un terminate sin start sale como terminate → falla `pcs-test_term_no_start`;
   - un segundo start sale como start → falla `pcs-test_double_start`;
   - un bloque de datos entre idles sale como datos → falla `pcs-test_inverse_hdr`, caso 1.
2. **No mira el bloque siguiente:** un T seguido de un D no se marca como error → falla `pcs-test_inverse_hdr`, caso 2.
3. **Un código de control inválido se marca solo en su lane** → falla `pcs-test_bad_ctrl` (0x01 en la posición 3).

Los block types inexistentes y los sync headers inválidos sí producen la palabra de error completa. Por eso pasan `test_bad_sync_hdr` y la parte de block types de `test_bad_ctrl`.

### 8.3 Lo que sí cumple con la norma

- Codificación y decodificación de frames válidos: los 8 formatos de terminate, el start en las posiciones 0 y 4 y los frames sin payload.
- Bloques de error ante un /E/ dentro de un frame y ante palabras que mezclan datos con controles inválidos.
- Sync headers inválidos (00 y 11).
- Uso del block type como única fuente para la posición del start.
- Scrambler y descrambler, incluida la multiplicación de errores (k, k + 39, k + 58).
- Block lock: se mantiene con 15 headers inválidos cada 64 y se pierde con 16.

---

## 9. Limitaciones y trabajo futuro

- **Scoreboard por conteos.** Se comparan totales, no transacciones. Un error que no rompe ninguna regla ni la PRBS y que no cambia los totales no se detectaría, como un frame perdido y otro duplicado. Un scoreboard por frame resolvería ese caso.
- **Sin cobertura funcional.** No hay `covergroup`. La cobertura se organizó por cláusula: cada test apunta a una regla concreta de la norma (ver TEST_PLAN.md).
- **Salidas de estado sin verificar.** `rx_bad_block`, `rx_sequence_error`, `rx_high_ber`, `rx_error_count` y `rx_status` no se miran: la verificación se hace sobre las interfaces XGMII y serdes. `rx_block_lock` se lee por jerarquía en los tests de lock.
- **Monitor de BER sin test.** No hay ningún test que lleve a `rx_high_ber` (cl. 49.2.13, timer de 125 µs).
- **Bitslip sin verificar.** `serdes_rx_bitslip` queda sin conectar. El generador PCS siempre manda los bloques alineados, así que no se prueba la búsqueda de alineación de la máquina de lock.
- **XGMII de 32 bits.** No tiene test, porque el DUT está instanciado con la XGMII de 64 bits.
- **Checker PCS en los tests PCS.** Por el loopback, el checker PCS ve la vuelta por el TX en todos los tests PCS, pero solo se verifica en el happy path.
- **Detalles del checker PCS:**
  - Un terminate que llega antes de completar el preámbulo y el SFD (por ejemplo, un 0x33 seguido de un T0) contaría el frame como correcto. Ningún test actual pasa por ese caso.
  - Los bloques inválidos solo se cuentan en `blk_err_count` cuando el checker está lockeado.
- **Clocks.** TX y RX se simulan con el mismo reloj, así que no se ejercita la diferencia de ±100 ppm entre los dos dominios ni la compensación con idles.

---

## 10. Conclusiones

Armé un ambiente de verificación en SystemVerilog con dos agentes, uno por interfaz del DUT (XGMII y serdes). Cada agente tiene un generador basado en tasks, que puede producir tráfico válido o errores inyectados a propósito, y un checker implementado como máquina de estados con lock que verifica las reglas de la norma ciclo a ciclo. Con dos loopbacks seleccionables, el mismo DUT se prueba entrando por cualquiera de las dos interfaces, y cada frame atraviesa las dos mitades del PHY.

De los 20 tests, **13 pasan y 7 fallan**. El camino de datos del PHY cumple con la norma: codificación 64B/66B, scrambling, block lock y manejo de headers inválidos.

Las 7 fallas tienen una causa común: **el RTL no implementa las máquinas de estado de transmisión y recepción de la cl. 49.2.13**. El encoder y el decoder trabajan palabra por palabra, sin memoria de dónde están dentro del flujo. Por eso no detectan los errores de secuencia (dos starts, un terminate sin start, un bloque de datos fuera de un frame, un T seguido de un D) y, en algunos casos, marcan con /E/ solo la lane errónea en lugar de la palabra o el bloque completo. El decoder detecta parte de estas situaciones con la bandera `rx_sequence_error`, pero no la refleja en la XGMII como pide la norma.

Para cumplir con la norma, habría que agregar las dos máquinas de estado (diagramas de transmisión y recepción de la cl. 49.2.13) entre la clasificación de cada palabra o bloque y su codificación o decodificación. Con eso, cualquier palabra o bloque de tipo E, o fuera de secuencia, se reemplazaría por el bloque o la palabra de error completa.
