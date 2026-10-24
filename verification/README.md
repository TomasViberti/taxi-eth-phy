# Verificación 10G ETH-PHY

Verificación de caja negra del RTL `taxi_eth_phy_10g` contra la norma IEEE 802.3
(cl. 46 XGMII, cl. 49 PCS 10GBASE-R). Ver [TEST_PLAN.md](TEST_PLAN.md).

- Cómo correr los tests: [INSTRUCCIONES.md](INSTRUCCIONES.md)
- Resultados: [INFORME.md](INFORME.md)

## Estructura

```
verification/
├── TEST_PLAN.md
├── common/          # utilidades compartidas (PRBS)
├── agents/
│   ├── xgmii/       # agente XGMII: interface + generador + checker
│   │   └── tests/   # tests con estímulo XGMII, uno por ítem del TEST_PLAN
│   └── pcs/         # agente PCS: mismo esquema
│       └── tests/   # tests con estímulo PCS, uno por ítem del TEST_PLAN
├── tb/              # top del testbench: DUT + agentes + loopback
└── sim/             # script de simulación (test_phy.py)
```

