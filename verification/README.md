# Verificación 10G ETH-PHY

Verificación de caja negra del RTL `taxi_eth_phy_10g` contra la norma IEEE 802.3
(cl. 46 XGMII, cl. 49 PCS 10GBASE-R). Ver [TEST_PLAN.md](TEST_PLAN.md).

## Estructura

```
verification/
├── TEST_PLAN.md
├── common/          # utilidades compartidas (PRBS)
├── agents/
│   ├── xgmii/       # agente XGMII: interface + generador + checker
│   └── pcs/         # agente PCS: mismo esquema
├── tb/              # top del testbench: DUT + clocks/reset + agentes
├── tests/           # un archivo por ítem del TEST_PLAN
└── sim/             # lista de archivos y scripts de simulación
```

