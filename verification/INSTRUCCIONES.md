# Cómo correr la verificación

Instrucciones para levantar el ambiente, correr los tests y ver las ondas en GTKWave.

## Dependencias

Probado en Ubuntu con estas versiones:

| Herramienta | Versión | Para qué |
|---|---|---|
| Verilator | 5.036 | Simulador. Tiene que ser 5.x porque los tests usan `--timing` |
| g++ y make | g++ 15.2, make 4.4 | Compilan el C++ que genera Verilator |
| Python | 3.14 | Corre pytest y cocotb |
| cocotb | 2.1.0 | Maneja clocks, reset y start desde Python |
| cocotb-test | 0.3.0 | Compila y lanza la simulación desde pytest |
| pytest | 9.1.1 | Lanzador de los tests |
| GTKWave | 3.3.126 | Para ver las ondas |

Ojo con cocotb: el `tox.ini` de la raíz del repo fija `cocotb == 2.0.1`, pero esa versión no instala en Python 3.14 (soporta hasta 3.13). Con Python 3.14 hay que usar cocotb 2.1.0. Con Python 3.13 o menor anda cualquiera de las dos.

Verilator, g++, make y GTKWave van por el sistema (`apt install gtkwave`, etc.). Lo de Python va en un entorno virtual, en el paso siguiente.

## Preparar el entorno (una sola vez)

Desde la raíz del repo:

```bash
python3 -m venv .venv
.venv/bin/pip install pytest cocotb cocotb-test
```

El `.venv/` no se sube: Python lo crea con su propio `.gitignore` adentro.

## Correr los tests

Cada vez que se abre una terminal nueva hay que activar el entorno y pararse en `verification/sim/`:

```bash
cd ~/Escritorio/taxi-eth-phy
source .venv/bin/activate
cd verification/sim
```

No hay un paso de compilación aparte. pytest compila y simula cada test en la misma corrida: Verilator traduce RTL + agentes + `tb_top.sv` + el archivo del test a C++, `make` lo compila y después corre la simulación con cocotb. Cada test se compila por separado en `sim_build/<agente>/<test>/`.

| Qué | Comando |
|---|---|
| Todos los tests | `pytest test_phy.py` |
| Sólo los XGMII | `pytest test_phy.py -k xgmii` |
| Sólo los PCS | `pytest test_phy.py -k pcs` |
| Uno solo | `pytest test_phy.py -k "pcs and bit_flip"` |
| Varios | `pytest test_phy.py -k "happy_path or term_lanes"` |
| Listar los tests sin correrlos | `pytest test_phy.py --collect-only -q` |

`-k` busca por substring en el nombre del test, que tiene la forma `<agente>-<test>` (por ejemplo `pcs-test_bit_flip`). Hay tests con el mismo nombre en los dos agentes (`test_happy_path`, `test_bad_ctrl`, `test_double_start`), por eso conviene poner el agente adelante: `-k "xgmii and happy_path"`.

La salida muestra un test por línea con su estado:

```
test_phy.py::test_phy[xgmii-test_happy_path] PASSED
test_phy.py::test_phy[xgmii-test_double_start] FAILED
...
=================== 7 failed, 13 passed in 167.75s ===================
```

Eso lo configura `verification/sim/pytest.ini` (`-v --tb=no -rN`). Si se corre pytest desde otra carpeta no toma ese archivo y sale todo el log.

### Ver por qué falló un test

Con `-s` se ve el log de la simulación de los tests que fallan, incluidos los mensajes de los checkers:

```bash
pytest test_phy.py -s -k "xgmii and double_start"
```

Para ver el log también de los tests que pasan:

```bash
pytest test_phy.py -o log_cli=true --log-cli-level=INFO -k "xgmii and happy"
```

El checker XGMII avisa cada lock y unlock, y al final muestra sus contadores:

```
[659000] XGMII CHECKER: unlock en lane 0 (S_DATA): c=1 d=fb, se esperaba dato o /T/
[659000] XGMII CHECKER: frames=0 e=0 prbs=0 seq=1 unlocks=1
[659000] XGMII CHECKER ERROR: e = 0, se esperaba 8
```

El checker PCS muestra lo mismo con `PCS CHECKER`, y además avisa cada bloque inválido:

```
[32000] PCS CHECKER: bloque inválido hdr=01 block=3c78f7800000001e, código de control que no está en la tabla 49-1
```

Los que salen antes del `clear()` del test son del arranque (reset y descrambler todavía sin sincronizar) y no cuentan.

El número entre corchetes es el tiempo de simulación en ps, sirve para ir directo a ese punto en GTKWave.

### Recompilar desde cero

Si se cambió algo y parece que quedó compilado algo viejo:

```bash
rm -rf sim_build
```

## Ondas en GTKWave

Las ondas se generan sólo si se pide, con `WAVES=1` adelante del comando:

```bash
WAVES=1 pytest test_phy.py                         # todos, con ondas
WAVES=1 pytest test_phy.py -k "pcs and bit_flip"   # uno solo, con ondas
```

Cada test deja su archivo en `sim_build/<agente>/<test>/waves.fst`. Para abrirlo:

```bash
gtkwave sim_build/pcs/test_bit_flip/waves.fst
```

Si se corre sin `WAVES=1` después de haber generado ondas, el `waves.fst` viejo queda ahí pero ya no corresponde a la última corrida. Para no confundirse, borrar `sim_build` antes.

### Señales para mirar

En el árbol de GTKWave (panel SST) todo cuelga de `tb_top`:

| Señal | Formato | Qué es |
|---|---|---|
| `gen_txd` / `gen_txc` | Hex / Binary | Lo que manda el generador XGMII |
| `xgmii_rxd` / `xgmii_rxc` | Hex / Binary | Salida XGMII del RX (lo que mira el checker XGMII) |
| `gen_rx_data` / `gen_rx_hdr` | Hex / Binary | Lo que manda el generador PCS (scrambleado) |
| `serdes_tx_data` / `serdes_tx_hdr` | Hex / Binary | Salida serdes del TX (scrambleada) |
| `u_pcs_chk.dec_data` / `u_pcs_chk.dec_ctrl` | Hex / Binary | Salida serdes del TX descrambleada y decodificada a XGMII por el checker PCS (figura 49-7) |
| `u_pcs_chk.u_frame_chk.state` | | Estado de la FSM de frame del checker PCS |
| `u_xgmii_chk.error_count`, `u_pcs_chk.error_count` | Decimal | Errores de cada checker. Tienen que quedar en 0 |
| `u_xgmii_chk.state` | | Estado del checker XGMII (UNLOCKED, S_IDLE, S_PREAMBLE, S_SFD, S_DATA) |
| `u_xgmii_chk.frame_count`, `e_count`, `prbs_err_count`, `seq_err_count` | Decimal | Lo que fue viendo el checker XGMII |
| `dut.rx_block_lock` | | Block lock del RX |
| `loopback_xgmii` | | 0 = conexión de los tests XGMII, 1 = conexión de los tests PCS |

El formato se cambia con clic derecho sobre la señal, *Data Format*. Lo que está en `serdes_tx_data` está scrambleado y no se puede leer a ojo; para leerlo hay que mirar `u_pcs_chk.dec_data` / `dec_ctrl`, que es el bloque ya pasado a la palabra XGMII que representa.

Una vez armada la vista conviene guardarla con *File, Write Save File* (por ejemplo `phy.gtkw`) y después abrirla junto con cualquier test:

```bash
gtkwave sim_build/xgmii/test_term_lanes/waves.fst phy.gtkw
```

## Agregar un test

1. Crear `verification/agents/<agente>/tests/test_<nombre>.sv`. pytest lo encuentra solo, no hay que tocar el script.
2. El archivo define un módulo llamado `test` con esta forma:

```systemverilog
module test (input logic start, output logic done);

    // Sólo en los tests PCS: el RX recibe lo que manda pcs_gen
    initial tb_top.loopback_xgmii = 1;

    initial begin
        done = 0;
        wait (start);

        // Idles hasta que el RX se sincronice con los headers
        while (!tb_top.dut.rx_block_lock) tb_top.u_pcs_gen.send_idle(1);
        tb_top.u_pcs_gen.send_idle(10);

        // Los checkers cuentan desde acá
        tb_top.u_pcs_chk.clear();
        tb_top.u_xgmii_chk.clear();

        // Estímulo: llamadas al generador, en orden
        tb_top.u_pcs_gen.send_frame(8, 0);
        tb_top.u_pcs_gen.send_idle(20);

        // Lo que la norma dice que tiene que salir
        tb_top.u_xgmii_chk.check_counts(.frames(1), .e(0), .prbs(0), .seq(0));
        tb_top.u_pcs_chk.check_counts(.frames(1), .e(0), .prbs(0), .seq(0));

        done = 1;
    end

endmodule
```

3. El test pasa si al final `error_count` vale 0 en los dos checkers.

Si un test necesita hilos en paralelo (por ejemplo, un monitor de `rx_block_lock` como en `test_lock_keep`), usar `join_none` + `wait fork` en vez de `join`. Verilator 5.036 genera C++ que no compila cuando un `fork ... join` tiene varias ramas `begin ... end` (error `__Vfork_1__sync was not declared`).

## Archivos

| Archivo | Qué hace |
|---|---|
| `sim/test_phy.py` | Lanzador. pytest compila y corre un test SV por cada `test_*.sv`; cocotb genera clocks (156.25 MHz), reset y `start`, y al final lee `error_count` de los checkers |
| `sim/pytest.ini` | Formato de la salida de pytest |
| `tb/tb_top.sv` | DUT, agentes y conexiones (loopback serdes o loopback XGMII) |
| `agents/xgmii/` | Generador y checker XGMII |
| `agents/pcs/` | Generador y checker PCS |
| `common/prbs.sv` | PRBS31 para el payload, scrambler y descrambler |
