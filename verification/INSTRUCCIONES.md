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

Con `-s` se ve el log de la simulación, incluidos los mensajes de los checkers:

```bash
pytest test_phy.py -s -k "xgmii and double_start"
```

Cada error del checker sale así:

```
[531000] PCS CHECKER ERROR en error block
    esperado: header=01 data=3c78f1e3c78f1e1e
    recibido: header=01 data=d555555555555578
```

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
| `x_if_tx.data` / `x_if_tx.control` | Hex / Binary | Lo que manda el generador XGMII |
| `x_if_rx.data` / `x_if_rx.control` | Hex / Binary | Salida XGMII del RX (lo que mira el checker XGMII) |
| `p_if_rx.data` / `p_if_rx.header` | Hex / Binary | Lo que manda el generador PCS (scrambleado) |
| `p_if_tx.data` / `p_if_tx.header` | Hex / Binary | Salida serdes del TX (scrambleada) |
| `u_pcs_chk.blk_data` / `u_pcs_chk.blk_header` | Hex / Binary | Salida serdes del TX ya descrambleada por el checker PCS |
| `u_xgmii_chk.error_count`, `u_pcs_chk.error_count` | Decimal | Errores de cada checker. Tienen que quedar en 0 |
| `dut.rx_block_lock` | | Block lock del RX |
| `loopback_xgmii` | | 0 = conexión de los tests XGMII, 1 = conexión de los tests PCS |

El formato se cambia con clic derecho sobre la señal, *Data Format*. Lo que está en `p_if_tx` está scrambleado y no se puede leer a ojo; para ver los block types hay que mirar `u_pcs_chk.blk_data` (el byte bajo, `[7:0]`, es el block type).

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

        fork
            begin
                // generador
            end
            begin
                // checker
            end
        join_none
        wait fork;

        done = 1;
    end

endmodule
```

3. El test pasa si al final `error_count` vale 0 en los dos checkers.

Usar siempre `join_none` + `wait fork` en vez de `join`. Verilator 5.036 genera C++ que no compila cuando un `fork ... join` tiene varias ramas `begin ... end` (error `__Vfork_1__sync was not declared`).

## Archivos

| Archivo | Qué hace |
|---|---|
| `sim/test_phy.py` | Lanzador. pytest compila y corre un test SV por cada `test_*.sv`; cocotb genera clocks (156.25 MHz), reset y `start`, y al final lee `error_count` de los checkers |
| `sim/pytest.ini` | Formato de la salida de pytest |
| `tb/tb_top.sv` | DUT, agentes y conexiones (loopback serdes o loopback XGMII) |
| `agents/xgmii/` | Interface, generador y checker XGMII |
| `agents/pcs/` | Interface, generador y checker PCS |
| `common/prbs.sv` | PRBS31 para el payload, scrambler y descrambler |
