# test_phy.py
#
# Lanzador de los tests XGMII y PCS. Los tests están escritos en SV
# (verification/agents/<agente>/tests/). Python no genera datos ni chequea:
#
# 1. pytest: por cada archivo de test, compila con Verilator
#    RTL + agentes + tb_top.sv + ese test.sv, y corre la simulación.
# 2. cocotb (run_sv_test): dentro de la simulación genera clocks y reset,
#    pone start = 1, espera done y lee error_count de los checkers SV.
#
# Uso (desde verification/sim/):
#   pytest test_phy.py                           # todos los tests
#   pytest test_phy.py -k xgmii                  # sólo los de un agente
#   pytest test_phy.py -k "pcs and happy_path"   # uno solo
#   WAVES=1 pytest test_phy.py -k happy          # + ondas para GTKWave
#   pytest test_phy.py -s -k ...                 # + log y errores del checker
#
# Las ondas quedan en sim_build/<agente>/<test>/waves.fst

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

    # Resultado de los checkers SV
    errors = int(dut.u_xgmii_chk.error_count.value) + int(dut.u_pcs_chk.error_count.value)
    assert errors == 0, f"los checkers encontraron {errors} errores"


# ----------------------------------------------------------------------
# pytest: compila y lanza una simulación por cada test SV
# ----------------------------------------------------------------------

sim_dir = os.path.abspath(os.path.dirname(__file__))
ver_dir = os.path.abspath(os.path.join(sim_dir, '..'))
repo_dir = os.path.abspath(os.path.join(ver_dir, '..'))
rtl_dir = os.path.join(repo_dir, 'src', 'eth', 'rtl')
agents_dir = os.path.join(ver_dir, 'agents')

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

# Verificación: utilidades, agentes XGMII y PCS y tb
ver_sources = [
    os.path.join(ver_dir, 'common', 'prbs.sv'),
    os.path.join(agents_dir, 'xgmii', 'xgmii_if.sv'),
    os.path.join(agents_dir, 'xgmii', 'xgmii_gen.sv'),
    os.path.join(agents_dir, 'xgmii', 'xgmii_checker.sv'),
    os.path.join(agents_dir, 'pcs', 'pcs_if.sv'),
    os.path.join(agents_dir, 'pcs', 'pcs_gen.sv'),
    os.path.join(agents_dir, 'pcs', 'pcs_checker.sv'),
    os.path.join(ver_dir, 'tb', 'tb_top.sv'),
]

# Un test por cada archivo agents/<agente>/tests/test_*.sv
agents = ['xgmii', 'pcs']
sv_tests = [(agent, os.path.splitext(os.path.basename(f))[0])
            for agent in agents
            for f in sorted(glob.glob(os.path.join(agents_dir, agent, 'tests', 'test_*.sv')))]


@pytest.mark.parametrize("agent, sv_test", sv_tests, ids=[f"{a}-{t}" for a, t in sv_tests])
def test_phy(agent, sv_test):
    waves = os.environ.get('WAVES') == '1'

    cocotb_test.simulator.run(
        simulator="verilator",
        python_search=[sim_dir],
        verilog_sources=rtl_sources + ver_sources + [os.path.join(agents_dir, agent, 'tests', f"{sv_test}.sv")],
        toplevel="tb_top",
        module="test_phy",
        sim_build=os.path.join(sim_dir, "sim_build", agent, sv_test),
        timescale="1ns/1ps",
        compile_args=["--timing", "--trace-fst", "--trace-structs", "-Wno-fatal"],
        plus_args=["+waves"] if waves else [],
    )
