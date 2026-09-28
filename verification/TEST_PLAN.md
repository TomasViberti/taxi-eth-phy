TEST PLAN 10G ETH-PHY

- Test happy path (flujo común correcto) generando PCS.
- Test happy path (flujo común correcto) generando XGMII.
- Test romper sync header con 00 o 11 (Según norma eso deriva en bloque inválido)
- Test poner códigos de control inexistentes en la tabla (Según norma eso deriva en bloque inválido)
- Test generar palabras XGMII de 32 bits (dato) y 4 bits control (control). En el rtl actual se genera directamente XGMII DE 64 bits.
- Test descorrelacionar bytes de control (por ej 0x78 para start) con el contenido del frame. Ejemplo: 0x78 en bytes de control indica bit de start en el primer bit. Que pasa si muevo el bit de start a una posicion diferente y el codigo de control sigue siendo el mismo?
- Test enviar sync header inverso: 01 para control y 10 para dato.
- Test enviar pcs sin scrambleo.
- Test scramblear header (Inválido según norma).
- Test romper orden de linea al generar XGMII: Que pasa si el primer dato generado va a la lane 4 en lugar de a la lane 0? Se rompe el orden?

