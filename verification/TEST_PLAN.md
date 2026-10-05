TEST PLAN 10G ETH-PHY

Objetivo: verificar que el RTL cumple la norma IEEE 802.3.

- Cláusula 46: XGMII.
- Cláusula 49: PCS 10GBASE-R (codificación 64B/66B, scrambler, block sync, BER monitor).

## Tests XGMII

- Test happy path (flujo común correcto) generando XGMII.
- Test generar palabras XGMII de 32 bits (dato) y 4 bits control (control). En el rtl actual se genera directamente XGMII DE 64 bits.
- Test romper orden de linea al generar XGMII: Que pasa si el primer dato generado va a la lane 4 en lugar de a la lane 0? Se rompe el orden?
- Test generar start (0xFB) en un byte que no corresponda a la lane 0 (en la palabra de 64 bits, cualquier byte distinto del 0 y del 4). Según norma el start sólo puede ir en la lane 0. Qué sale del lado PCS? Debería salir un bloque de error.
- Test generar frames de distintos largos para que el terminate (0xFD) caiga en cada uno de los 8 bytes de la palabra XGMII. Verificar que del lado PCS sale el código de terminate correcto según la tabla de la norma.
- Test generar caracteres de control inexistentes en la tabla de XGMII (por ej. 0x00 o 0x55 con el bit de control en 1). Según norma eso termina en error.
- Test generar el caracter de error (0xFE) en medio de un frame. Según norma del lado PCS debe salir un bloque de error.

## Tests PCS

- Test happy path (flujo común correcto) generando PCS.
- Test romper sync header con 00 o 11 (Según norma eso deriva en bloque inválido)
- Test poner códigos de control inexistentes en la tabla (Según norma eso deriva en bloque inválido)
- Test descorrelacionar bytes de control (por ej 0x78 para start) con el contenido del frame. Ejemplo: 0x78 en bytes de control indica bit de start en el primer bit. Que pasa si muevo el bit de start a una posicion diferente y el codigo de control sigue siendo el mismo?
- Test enviar sync header inverso: 01 para control y 10 para dato.
- Test enviar pcs sin scrambleo.
- Test scramblear header (Inválido según norma).
- Test romper 16 sync headers dentro de 64 bloques seguidos. Según norma se pierde la sincronización (`rx_block_lock` en 0). Que pasa si rompo 15? Debería mantenerla.
- Test enviar un terminate sin start previo, o dos starts seguidos sin terminate. Según norma eso deriva en error y del lado XGMII debe salir el caracter de error (0xFE).
- Test invertir un solo bit dentro del dato de un frame. Según norma (por cómo funciona el scrambler) del lado XGMII deben salir 3 bits errados, no 1.

Diagrama del RTL. 
<img width="2988" height="1160" alt="ETH_PHY_10G-Diagrama_RTL_ETH_PHY_10G drawio" src="https://github.com/user-attachments/assets/cff4d857-69b1-44a9-b1ab-a50b8ac96d16" />

Propuesta sobre como crear los agentes.
<img width="3615" height="2570" alt="ETH_PHY_10G-Agentes_Verificación_ETH_PHY_10G drawio" src="https://github.com/user-attachments/assets/39bb33ae-d815-408b-959f-f4410d70c64b" />
