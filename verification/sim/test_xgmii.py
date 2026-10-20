# test_xgmii.py
#
# Lanzador de los tests XGMII. Los tests están escritos en SV
# (verification/agents/xgmii/tests/). Python no genera datos ni chequea:
#
# 1. pytest: por cada archivo de test, compila con Verilator
#    RTL + agentes + tb_top.sv + ese test.sv, y corre la simulación.
# 2. cocotb (run_sv_test): dentro de la simulación genera clocks y reset,
#    pone start = 1, espera done y lee error_count del checker SV.
#
# Uso (desde verification/sim/):
#   pytest test_xgmii.py -v                      # todos los tests
#   pytest test_xgmii.py -v -k happy_path        # uno solo
#   WAVES=1 pytest test_xgmii.py -v -k happy     # + ondas para GTKWave
#
# Las ondas quedan en sim_build/<test>/waves.fst

import glob
import os

import cocotb
import cocotb_test.simulator
import pytest
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, with_timeout


# ----------------------------------------------------------------------
# cocotb: corre dentro de la simulación
# ----------------------------------------------------------------------

@cocotb.test()
async def run_sv_test(dut):
    # Clocks de 156.25 MHz (palabras de 64 bits)
    cocotb.start_soon(Clock(dut.tx_clk, 6.4, unit="ns").start())
    cocotb.start_soon(Clock(dut.rx_clk, 6.4, unit="ns").start())

    # Reset
    dut.start.value = 0
    dut.tx_rst.value = 1
    dut.rx_rst.value = 1
    for _ in range(4):
        await RisingEdge(dut.tx_clk)
    dut.tx_rst.value = 0
    dut.rx_rst.value = 0
    for _ in range(2):
        await RisingEdge(dut.tx_clk)

    # Arranca el test SV y espera a que termine
    dut.start.value = 1
    await with_timeout(RisingEdge(dut.done), 1, "ms")

    # Resultado del checker SV
    errors = int(dut.u_chk.error_count.value)
    assert errors == 0, f"el checker encontró {errors} errores"


# ----------------------------------------------------------------------
# pytest: compila y lanza una simulación por cada test SV
# ----------------------------------------------------------------------

sim_dir = os.path.abspath(os.path.dirname(__file__))
ver_dir = os.path.abspath(os.path.join(sim_dir, '..'))
repo_dir = os.path.abspath(os.path.join(ver_dir, '..'))
rtl_dir = os.path.join(repo_dir, 'src', 'eth', 'rtl')
tests_dir = os.path.join(ver_dir, 'agents', 'xgmii', 'tests')

# RTL del DUT
rtl_sources = [
    os.path.join(repo_dir, 'src', 'lfsr', 'rtl', 'taxi_lfsr.sv'),
    os.path.join(rtl_dir, 'taxi_eth_phy_10g.sv'),
    os.path.join(rtl_dir, 'taxi_eth_phy_10g_tx.sv'),
    os.path.join(rtl_dir, 'taxi_eth_phy_10g_tx_if.sv'),
    os.path.join(rtl_dir, 'taxi_xgmii_baser_enc.sv'),
    os.path.join(rtl_dir, 'taxi_eth_phy_10g_rx.sv'),
    os.path.join(rtl_dir, 'taxi_eth_phy_10g_rx_if.sv'),
    os.path.join(rtl_dir, 'taxi_eth_phy_10g_rx_ber_mon.sv'),
    os.path.join(rtl_dir, 'taxi_eth_phy_10g_rx_frame_sync.sv'),
    os.path.join(rtl_dir, 'taxi_eth_phy_10g_rx_watchdog.sv'),
    os.path.join(rtl_dir, 'taxi_xgmii_baser_dec.sv'),
]

# Verificación: utilidades, agente XGMII y tb
ver_sources = [
    os.path.join(ver_dir, 'common', 'prbs.sv'),
    os.path.join(ver_dir, 'agents', 'xgmii', 'xgmii_if.sv'),
    os.path.join(ver_dir, 'agents', 'xgmii', 'xgmii_gen.sv'),
    os.path.join(ver_dir, 'agents', 'xgmii', 'xgmii_checker.sv'),
    os.path.join(ver_dir, 'tb', 'tb_top.sv'),
]

# Un test por cada archivo test_*.sv
sv_tests = sorted(os.path.splitext(os.path.basename(f))[0]
                  for f in glob.glob(os.path.join(tests_dir, 'test_*.sv')))


@pytest.mark.parametrize("sv_test", sv_tests)
def test_xgmii(sv_test):
    waves = os.environ.get('WAVES') == '1'

    cocotb_test.simulator.run(
        simulator="verilator",
        python_search=[sim_dir],
        verilog_sources=rtl_sources + ver_sources + [os.path.join(tests_dir, f"{sv_test}.sv")],
        toplevel="tb_top",
        module="test_xgmii",
        sim_build=os.path.join(sim_dir, "sim_build", sv_test),
        timescale="1ns/1ps",
        compile_args=["--timing", "--trace-fst", "--trace-structs", "-Wno-fatal"],
        plus_args=["+waves"] if waves else [],
    )
