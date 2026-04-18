

**POLYMARKET**

**18 PLANTILLAS DE ESTRATEGIA PARA AGENTES IA**

*Estructuradas conforme a los 5 Pilares Generales de Estrategia*

Version 1.0  |  Proyect\_Moni\_Arbitration\_Full  |  Marzo 2026

| PILAR 1 Position Sizing | PILAR 2 Hurdle Rate | PILAR 3 Temporal Edge | PILAR 4 Signal Validation | PILAR 5 Exit & Hedging |
| :---: | :---: | :---: | :---: | :---: |

ARB-01 · ARB-02 · ARB-03 · ARB-04 · ARB-05 · MINT-01 · MINT-02 · MINT-03 · MINT-04 · MINT-05 · MINT-06 · TRADE-02 · IA-01 · IA-02 · IA-03 · IA-04 · IA-05 · IA-06

# **Indice de Estrategias**

**Grupo 1 — Arbitraje Puro**

* **ARB-01  —**  Arbitraje Binario Compra  \[RIESGO MUY BAJO\]

* **ARB-02  —**  Arbitraje Binario Venta / Minteo  \[RIESGO MUY BAJO\]

* **ARB-03  —**  NegRisk Compra Multi-condicion  \[RIESGO BAJO\]

* **ARB-04  —**  NegRisk Venta Multi-condicion  \[RIESGO MEDIO\]

* **ARB-05  —**  Arbitraje Combinatorio Cross-Market  \[RIESGO MEDIO — Capital \> $500k\]

**Grupo 2 — Minteo y Market Making**

* **MINT-01  —**  Minteo Simple $1,000 de Una Vez  \[RIESGO BAJO\]

* **MINT-02  —**  Minteo en Dos Partes $500 \+ $500  \[RIESGO MUY BAJO\]

* **MINT-03  —**  Market Making en el Midpoint — Escenario A  \[RIESGO MEDIO — Acumulacion Pasiva\]

* **MINT-04  —**  Market Making Premium — Escenario B  \[RIESGO BAJO — ESTRATEGIA GANADORA\]

* **MINT-05  —**  Market Making Sweet Spot  \[RIESGO BAJO — Balance Optimo\]

* **MINT-06  —**  Compounding Acelerado Multi-Ciclo  \[RIESGO BAJO — Meta-Estrategia\]

**Grupo 3 — Trading Activo Automatizado**

* **TRADE-02  —**  Trading de Impulso (Momentum) — Automatizado  \[RIESGO MEDIO\]

**Grupo 4 — IA y Automatizacion Avanzada**

* **IA-01  —**  Front-Running Automatizado de Noticias  \[RIESGO MEDIO\]

* **IA-02  —**  Copy-Trading de Ballenas (Whale Following)  \[RIESGO MEDIO\]

* **IA-03  —**  Modelo de Probabilidad Fair Value  \[RIESGO MEDIO\]

* **IA-04  —**  Bot de Arbitraje Tipos 1-3 (Sistema Automatizado)  \[RIESGO BAJO — ACTIVO EN PRODUCCION\]

* **IA-05  —**  Deteccion de Dependencias LLM \+ IP Solver  \[RIESGO ALTO — Capital \> $500k\]

* **IA-06  —**  Optimizacion Matematica Bregman \+ Frank-Wolfe  \[RIESGO BAJO — CAPA TRANSVERSAL ACTIVA\]

**Estructura de Cada Plantilla:**

| Pilar | Nombre | Contenido |
| ----- | ----- | ----- |
| **PILAR 1** | **Gestion de Riesgo y Position Sizing** | Kelly Criterion | Limite de Exposicion | Control de Slippage |
| **PILAR 2** | **Umbrales de Rentabilidad Neta** | Costos Transaccionales | Hurdle Rate | Ejemplo de Calculo Neto |
| **PILAR 3** | **Ventana de Tiempo y Caducidad** | Cercania al Cierre | TTL de la Senal | Control de Drift de Precio |
| **PILAR 4** | **Validacion de la Senal** | Confluencia de Criterios | Volumen / OI | Liquidez Falsa |
| **PILAR 5** | **Protocolo de Salida y Cobertura** | Cierre por Objetivo | Stop-Loss | Hedging de Piernas |

| ARB-01 RIESGO MUY BAJO | Arbitraje Binario Compra |
| :---: | :---- |
|  | Comprar simultaneamente tokens YES y NO cuando su suma es inferior a $1.00. Como exactamente uno siempre gana, el pago de $1.00 esta garantizado sin importar el resultado del evento. |
|  | **Grupo:** Grupo 1 — Arbitraje Puro   |   **Modulo:** pma\_full\_arb\_engine / detect\_type1() |

| PILAR 1  —  GESTION DE RIESGO Y POSITION SIZING |  |
| :---- | :---- |
| **Kelly Criterion** | f\* \= (profit\_bruto \- fee\_total) / profit\_bruto Kelly Fraccionado: f\_real \= f\* x 0.25 (seguridad) Ejemplo: profit 5%, fee 2% \=\> f\*=0.60 \=\> f\_real=0.15 |
| **Limite Exposicion** | Maximo 8% del bankroll por operacion individual Bankroll $10,000 \=\> limite $800 por trade ARB-01 Nunca superar $2,000 aunque Kelly lo permita |
| **Control Slippage** | Abortar si YES\_ask o NO\_ask se mueven \> 0.3% entre deteccion y ejecucion (ventana \<30ms) Umbral duro: YES\_ask \+ NO\_ask \>= $0.985 \=\> NO OPERAR |

| PILAR 2  —  UMBRALES DE RENTABILIDAD NETA |  |
| :---- | :---- |
| **Costos Totales** | Gas Polygon: \~$0.02 (2 tx paralelas via asyncio) Fee Polymarket: 2% sobre la ganancia neta Spread salida: 0% (tokens se resuelven a $1.00) |
| **Hurdle Rate** | Profit neto minimo aceptable: 1.5% Formula: (1.00 \- YES\_ask \- NO\_ask) \- $0.02 \- 0.02\*profit \> 0.015 Ejemplo: YES=0.48, NO=0.47 \=\> bruto 5% \=\> neto \~2.9% \=\> OPERAR |
| **Ejemplo Neto** | Si bruto \< 2% con capital \< $200 \=\> fee \> profit \=\> RECHAZAR Umbral de volumen minimo para cubrir gas: capital \> $100 |

| PILAR 3  —  VENTANA DE TIEMPO Y CADUCIDAD |  |
| :---- | :---- |
| **Cercanía al Cierre** | Mercado cierra \> 7 dias: OPERAR con Kelly normal Mercado cierra 1-7 dias: OPERAR con Kelly x 0.5 Mercado cierra 1-24h: SOLO si profit \> 3% neto Mercado cierra \< 1h: NO OPERAR (riesgo manipulacion) |
| **TTL de la Señal** | Tiempo de vida de la senal: 5 segundos maximo Si deteccion \-\> ejecucion \> 30ms: descartar la senal No reintentar la misma oportunidad si ya expiro |
| **Drift de Precio** | Monitorear drift de precios: si YES sube \> 0.5% en 1s durante ejecucion \=\> abortar |

| PILAR 4  —  VALIDACION DE LA SEÑAL |  |
| :---- | :---- |
| **Confluencia** | Minimo 2 de 3 criterios deben cumplirse: (A) detect\_type1() confirma: YES\_ask \+ NO\_ask \< 0.985 (B) VWAP YES \+ VWAP NO \< $0.975 (confirmacion de profundidad) (C) Bregman KL-divergence \< 0.05 (mercado alejado del equilibrio) |
| **Volumen / OI** | book\_depth YES \>= $500 Y book\_depth NO \>= $500 Rechazar si bid-ask spread de cualquier lado \> 3% Volumen\_24h del mercado \>= $5,000 |
| **Liquidez Falsa** | Verificar que las ordenes top del CLOB tengan age \< 60s Si el best\_ask es una orden solitaria \> 10x el promedio \=\> FALSA LIQUIDEZ \=\> rechazar |

| PILAR 5  —  PROTOCOLO DE SALIDA Y COBERTURA |  |
| :---- | :---- |
| **Cierre Objetivo** | Salida automatica: tokens se resuelven a $1.00 en fecha de cierre No hay accion de salida activa necesaria Monitorear que el mercado no sea anulado (void) por la plataforma |
| **Stop-Loss** | Abortar durante ejecucion si: \- Una de las dos piernas falla y la otra ya se ejecuto \- YES\_ask \+ NO\_ask \> $1.00 durante la ejecucion (window cerrado) Accion: cancelar la pierna pendiente en \< 100ms |
| **Hedging** | asyncio.gather(buy\_yes, buy\_no) \=\> EJECUCION SIMULTANEA obligatoria Si gather falla: rollback total. Nunca quedar con solo una pierna Timeout por pierna: 30ms. Superar \=\> abortar ambas |

| ARB-02 RIESGO MUY BAJO | Arbitraje Binario Venta / Minteo |
| :---: | :---- |
|  | Mintear un par YES+NO por exactamente $1.00 USDC via contrato CTF de Gnosis en Polygon y vender ambos tokens en paralelo cuando su suma supera $1.00. La ganancia es el exceso sobre el costo de minteo. |
|  | **Grupo:** Grupo 1 — Arbitraje Puro   |   **Modulo:** pma\_full\_arb\_engine / detect\_type2() |

| PILAR 1  —  GESTION DE RIESGO Y POSITION SIZING |  |
| :---- | :---- |
| **Kelly Criterion** | f\* \= (YES\_bid \+ NO\_bid \- 1.00 \- fee\_total) / (YES\_bid \+ NO\_bid \- 1.00) Kelly Fraccionado: f\_real \= f\* x 0.20 (latencia mayor \= riesgo mayor) Ejemplo: exceso 13% \=\> fee 2% \=\> f\*=0.85 \=\> f\_real=0.17 |
| **Limite Exposicion** | Maximo 7% del bankroll (mayor riesgo por latencia 4-6s) Bankroll $10,000 \=\> limite $700 por trade ARB-02 Durante los 4-6s de minteo el capital queda bloqueado e inmovilizado |
| **Control Slippage** | Calcular slippage esperado en la venta: si mover el mercado con la orden cuesta \> 0.5% \=\> reducir tamano de la orden al 50% Umbral duro: si precio cae \> 1% durante minteo \=\> abortar ventas |

| PILAR 2  —  UMBRALES DE RENTABILIDAD NETA |  |
| :---- | :---- |
| **Costos Totales** | Gas Polygon: \~$0.05 (1 mint tx \+ 2 sell tx) Fee Polymarket: 2% sobre cada venta Spread salida: incluido en el calculo de YES\_bid \+ NO\_bid |
| **Hurdle Rate** | Profit neto minimo: 2.0% (mayor que ARB-01 por riesgo latencia) Formula: (YES\_bid \+ NO\_bid \- 1.00) \- $0.05 \- 0.02\*(YES\_bid+NO\_bid) \> 0.02 Ejemplo: YES=0.58, NO=0.55 \=\> bruto 13% \=\> neto \~10.6% \=\> OPERAR |
| **Ejemplo Neto** | Si bruto \< 3% \=\> margen demasiado ajustado para 4-6s de exposicion \=\> RECHAZAR |

| PILAR 3  —  VENTANA DE TIEMPO Y CADUCIDAD |  |
| :---- | :---- |
| **Cercanía al Cierre** | Mercado cierra \> 48h: OPERAR normalmente Mercado cierra 24-48h: OPERAR si profit neto \> 5% Mercado cierra \< 24h: NO OPERAR (riesgo de resolucion durante minteo) Los 4-6s de minteo son criticos: mercado no debe resolver en ese lapso |
| **TTL de la Señal** | Tiempo de vida de la senal: 10 segundos (mayor que ARB-01) Verificar precios inmediatamente antes de firmar la tx de minteo Si precio cambio mas de 0.5% desde deteccion \=\> cancelar antes de Mint |
| **Drift de Precio** | Verificar bid prices en tiempo real durante el proceso de minteo Si YES\_bid cae \> 1% mientras se mintea \=\> abortar ventas y mantener tokens |

| PILAR 4  —  VALIDACION DE LA SEÑAL |  |
| :---- | :---- |
| **Confluencia** | Minimo 2 de 3 criterios: (A) detect\_type2(): YES\_bid \+ NO\_bid \> 1.02 (margen para fees) (B) VWAP bid YES \+ VWAP bid NO \> $1.015 (C) Bregman KL \> 0.05 (precio lejos del equilibrio, valida la oportunidad) |
| **Volumen / OI** | book\_depth bid YES \>= $300 Y book\_depth bid NO \>= $300 Verificar que las ordenes bid no sean de un unico actor (posible wash trading) Open Interest del mercado \>= $2,000 |
| **Liquidez Falsa** | Verificar age de las ordenes bid: si son recientes (\<30s) y de gran tamano \=\> sospechosas Confirmar que el volumen\_24h del mercado soporte el tamano de la orden planeada |

| PILAR 5  —  PROTOCOLO DE SALIDA Y COBERTURA |  |
| :---- | :---- |
| **Cierre Objetivo** | Salida: ejecucion inmediata de ambas ventas al completar el minteo Objetivo: vender YES @ YES\_bid y NO @ NO\_bid en \< 500ms post-minteo asyncio.gather(sell\_yes, sell\_no) inmediatamente tras confirmacion de Mint |
| **Stop-Loss** | Si el minteo tarda \> 8s en confirmarse en Polygon \=\> abortar y esperar resolucion Si despues del minteo YES\_bid cae \> 2% \=\> vender solo el lado mas liquido primero Stop-loss de cartera: si acumulacion de errores \> 3 en 1h \=\> pausar ARB-02 por 30min |
| **Hedging** | El minteo es el hedge natural: 1 YES \+ 1 NO \= $1.00 siempre Las dos ventas deben ejecutarse en \< 500ms post-minteo Nunca vender solo un lado sin tener el otro en el portfolio |

| ARB-03 RIESGO BAJO | NegRisk Compra Multi-condicion |
| :---: | :---- |
|  | En mercados NegRisk con outcomes mutuamente excluyentes, comprar tokens YES de TODAS las condiciones cuando su suma es inferior a $1.00. Exactamente una condicion siempre gana, garantizando el pago de $1.00. |
|  | **Grupo:** Grupo 1 — Arbitraje Puro   |   **Modulo:** pma\_full\_arb\_engine / detect\_type3() \[is\_negrisk=True\] |

| PILAR 1  —  GESTION DE RIESGO Y POSITION SIZING |  |
| :---- | :---- |
| **Kelly Criterion** | Aplicar Kelly por condicion individual, no al total f\_por\_condicion \= kelly\_total / num\_condiciones Ejemplo: 5 condiciones, kelly=20% \=\> 4% por condicion Capital total: kelly\_total x bankroll, dividido en partes iguales |
| **Limite Exposicion** | Maximo 5% del bankroll TOTAL para toda la operacion NegRisk Bankroll $10,000 \=\> $500 total, dividido entre todas las condiciones Mayor numero de condiciones \= mayor riesgo de iliquidez en alguna pierna |
| **Control Slippage** | Slippage por condicion: max 0.5% de movimiento por leg individual Si la condicion menos liquida mueve el mercado \> 1% \=\> reducir tamano 50% Umbral critico: MIN(liq\_i) \>= $200 para todas las condiciones |

| PILAR 2  —  UMBRALES DE RENTABILIDAD NETA |  |
| :---- | :---- |
| **Costos Totales** | Gas Polygon: \~$0.05 x num\_condiciones (ej. 5 condiciones \=\> $0.25) Fee Polymarket: 2% por condicion comprada Total fee: 0.02 x num\_condiciones x precio\_promedio\_condicion |
| **Hurdle Rate** | Profit neto minimo: 3.0% (mayor por complejidad multi-leg) Formula: (1.00 \- Suma(YES\_i)) \- Gas\_total \- Fee\_total \> 0.03 Ejemplo: 5 condiciones, suma=0.80 \=\> bruto 20% \=\> neto \~17% \=\> OPERAR |
| **Ejemplo Neto** | Si alguna condicion tiene precio \> 0.30 y liquidez \< $100 \=\> RECHAZAR toda la operacion Regla: la condicion mas iliquida define el tamano maximo de toda la operación |

| PILAR 3  —  VENTANA DE TIEMPO Y CADUCIDAD |  |
| :---- | :---- |
| **Cercanía al Cierre** | Mercado cierra \> 14 dias: OPERAR con tamano completo Mercado cierra 7-14 dias: OPERAR con tamano x 0.75 Mercado cierra 1-7 dias: OPERAR solo si profit \> 8% neto Mercado cierra \< 24h: NO OPERAR (riesgo de resolucion parcial durante ejecucion) |
| **TTL de la Señal** | Tiempo de vida de la senal: 15 segundos (multi-leg requiere mas tiempo) Reconfirmar TODOS los precios antes de cada compra individual Si cualquier condicion cambio \> 1% desde deteccion \=\> cancelar toda la operación |
| **Drift de Precio** | Establecer precio maximo aceptable por condicion antes de enviar ordenes Price limit orders en lugar de market orders para control de slippage |

| PILAR 4  —  VALIDACION DE LA SEÑAL |  |
| :---- | :---- |
| **Confluencia** | Minimo 3 de 4 criterios: (A) Suma(YES\_i) \< 0.97 (margen para fees) (B) MIN(liq\_i) \>= $300 para todas las condiciones (C) VWAP confirma la suma \< $0.97 (D) Bregman KL \> 0.08 (gran desviacion del equilibrio multi-outcome) |
| **Volumen / OI** | Todas las condiciones deben tener volumen\_24h \> $1,000 individualmente Open Interest total del mercado NegRisk \>= $10,000 Rechazar si alguna condicion tiene 0 trades en las ultimas 2 horas |
| **Liquidez Falsa** | La condicion menos liquida es el cuello de botella real Verificar que las ordenes de las condiciones iliquidas no son del mismo actor Usarsiempre VWAP sobre book\_depth para estimar liquidez real vs nominal |

| PILAR 5  —  PROTOCOLO DE SALIDA Y COBERTURA |  |
| :---- | :---- |
| **Cierre Objetivo** | Salida automatica: la condicion ganadora paga $1.00 en fecha de resolución Las condiciones perdedoras valen $0.00 Monitorear si el mercado NegRisk cambia de estructura antes del cierre |
| **Stop-Loss** | Si alguna condicion pierde \> 40% de su valor mientras se mantiene \=\> evaluar venta parcial Si la condicion ganadora probable sube a \> 0.90 \=\> vender las demas condiciones para recuperar capital Stop-loss de portfolio: si Suma(YES\_i) \> 0.98 post-compra \=\> el arbitraje desaparecio \=\> salir |
| **Hedging** | asyncio.gather(\*\[buy(cond\_i) for cond\_i in conditions\]) \=\> EJECUCION SIMULTANEA Si alguna compra falla: cancelar TODAS las demas en \< 200ms Nunca quedar con compras parciales en un mercado NegRisk |

| ARB-04 RIESGO MEDIO | NegRisk Venta Multi-condicion |
| :---: | :---- |
|  | Mintear sets completos de tokens NegRisk (1 de cada condicion por $1.00) y vender todos los YES al precio de mercado cuando su suma supera $1.00. Ocurre en solo \~5% de los mercados NegRisk. |
|  | **Grupo:** Grupo 1 — Arbitraje Puro   |   **Modulo:** pma\_full\_arb\_engine / detect\_type3\_inverse() \[Fase 2\] |

| PILAR 1  —  GESTION DE RIESGO Y POSITION SIZING |  |
| :---- | :---- |
| **Kelly Criterion** | f\* \= (Suma(YES\_bid\_i) \- 1.00 \- fee\_total) / (Suma(YES\_bid\_i) \- 1.00) Kelly Fraccionado: f\_real \= f\* x 0.15 (latencia 6-8s y frecuencia baja) Ejemplo: suma=1.15 \=\> exceso 15% \=\> f\*=0.87 \=\> f\_real=0.13 |
| **Limite Exposicion** | Maximo 5% del bankroll (riesgo latencia 6-8s \+ baja frecuencia) Bankroll $10,000 \=\> limite $500 por trade ARB-04 Nunca acumular mas de 2 operaciones ARB-04 simultaneas |
| **Control Slippage** | Slippage en ventas: cada YES puede moverse al vender en paralelo Estimar impacto: si orden \> 20% del book \=\> usar ordenes limit Umbral: si Suma(YES\_bid post-slippage) \< 1.03 \=\> RECHAZAR (margen insuficiente) |

| PILAR 2  —  UMBRALES DE RENTABILIDAD NETA |  |
| :---- | :---- |
| **Costos Totales** | Gas Polygon: \~$0.08 (1 mint\_set tx \+ N sell tx paralelas) Fee Polymarket: 2% por venta de cada condicion Total fee: $0.08 \+ 0.02 x Suma(YES\_bid\_i) Hurdle Rate: profit neto minimo 3.5% |
| **Hurdle Rate** | Formula: (Suma(YES\_bid\_i) \- 1.00) \- $0.08 \- 0.02\*Suma(YES) \> 0.035 Ejemplo: suma=1.15, 3 condiciones \=\> bruto 15% \=\> fee \~2.4% \=\> neto 12.5% \=\> OPERAR |
| **Ejemplo Neto** | Si suma \< 1.05 con 5+ condiciones \=\> fees \> profit \=\> RECHAZAR Minimo exceso bruto recomendado: 6% para operar con margen seguro |

| PILAR 3  —  VENTANA DE TIEMPO Y CADUCIDAD |  |
| :---- | :---- |
| **Cercanía al Cierre** | Mercado cierra \> 48h: OPERAR normalmente Mercado cierra 24-48h: OPERAR solo si exceso \> 8% bruto Mercado cierra \< 24h: NO OPERAR en ningun caso Los 6-8s de minteo son criticos: el mercado no debe resolver durante ese tiempo |
| **TTL de la Señal** | Tiempo de vida de la senal: 10 segundos Reconfirmar todos los YES\_bid antes de firmar mint\_set Si cualquier YES\_bid cayo \> 1% desde deteccion \=\> CANCELAR |
| **Drift de Precio** | Establecer precio minimo de venta para cada condicion antes del minteo Usar limit orders con precio floor para protegerse de drops durante minteo |

| PILAR 4  —  VALIDACION DE LA SEÑAL |  |
| :---- | :---- |
| **Confluencia** | Minimo 2 de 3: (A) Suma(YES\_bid\_i) \> 1.06 (margen amplio para fees y latencia) (B) MIN(book\_depth\_bid\_i) \>= $200 para todas las condiciones (C) El evento tiene baja volatilidad de precios en las ultimas 4h |
| **Volumen / OI** | Volumen\_24h del mercado NegRisk \>= $5,000 Cada condicion debe tener al menos 5 trades en la ultima hora Rechazar si alguna condicion tiene spread bid-ask \> 5% |
| **Liquidez Falsa** | Verificar que los bids no son del mismo maker que podria retirarlos Comprobar historico: el nivel de bid se ha mantenido \> 30min \=\> real |

| PILAR 5  —  PROTOCOLO DE SALIDA Y COBERTURA |  |
| :---- | :---- |
| **Cierre Objetivo** | Salida: vender todos los YES en \< 1s post-confirmacion del minteo asyncio.gather(\*\[sell(yes\_i) for yes\_i in conditions\]) con limit orders Objetivo: completar todas las ventas antes de que el mercado ajuste |
| **Stop-Loss** | Si el minteo tarda \> 10s \=\> abortar y gestionar el set manualmente Si durante las ventas alguna condicion cae \> 3% \=\> vender el resto con market orders urgente Si no se logran vender todas en 30s \=\> mantener el set completo (hedge natural) hasta resolución |
| **Hedging** | El set completo de tokens es su propio hedge: paga exactamente $1.00 en resolucion Priorizar ventas de las condiciones mas liquidas primero para asegurar profit parcial Si solo se logra vender el 70% del set \=\> el 30% restante se resuelve a valor natural |

| ARB-05 RIESGO MEDIO — Capital \> $500k | Arbitraje Combinatorio Cross-Market |
| :---: | :---- |
|  | Explotar dependencias logicas entre mercados distintos via pipeline de 3 fases: heuristica NLP, analisis LLM y verificacion con IP Solver. ADVERTENCIA CRITICA: latencia de 15-35s supera la ventana de oportunidad tipica de \~200ms. |
|  | **Grupo:** Grupo 1 — Arbitraje Puro   |   **Modulo:** pma\_full\_logic\_oracle \+ ip\_solver \+ cross\_market\_detector |

| PILAR 1  —  GESTION DE RIESGO Y POSITION SIZING |  |
| :---- | :---- |
| **Kelly Criterion** | f\* aplicado al profit del portafolio de dependencias, no por mercado individual Kelly Fraccionado: f\_real \= f\* x 0.10 (45% tasa exito, capital alto) Capital minimo requerido: $500,000 para que el ROI absoluto justifique la infraestructura |
| **Limite Exposicion** | Maximo 3% del bankroll por dependencia cross-market detectada Bankroll $500,000 \=\> $15,000 por oportunidad Maximo 5 oportunidades simultaneas \=\> 15% del capital expuesto total |
| **Control Slippage** | Con capital grande, mover el mercado es inevitable Estimar impacto: si orden \> 5% del open interest \=\> reducir tamano 60% Usar ordenes limit en lugar de market para todas las piernas |

| PILAR 2  —  UMBRALES DE RENTABILIDAD NETA |  |
| :---- | :---- |
| **Costos Totales** | Gas Polygon: \~$0.04 (2 mercados x 2 tx) por dependencia Fee Polymarket: 2% por cada pierna ejecutada Infraestructura LLM \+ Gurobi: \~$1,500/mes (prorrateado por operacion) Hurdle Rate: 5% neto minimo dado el costo de infraestructura |
| **Hurdle Rate** | Profit neto minimo: 5% (absorbe costo de infraestructura y latencia) Solo justificado con capital \> $500k donde el 5% \= $25,000 en valor absoluto Operaciones \< $25,000 no cubren el costo prorrateado del pipeline LLM |
| **Ejemplo Neto** | Con $500k y 5% neto \=\> $25,000 por ciclo de dependencias detectadas TargetMinimo: 2 operaciones exitosas por semana para cubrir infraestructura |

| PILAR 3  —  VENTANA DE TIEMPO Y CADUCIDAD |  |
| :---- | :---- |
| **Cercanía al Cierre** | Ambos mercados deben cerrar en \> 7 dias (ventana para que el arbitraje se corrija) Evitar dependencias donde un mercado cierra esta semana y el otro en 3 meses La diferencia de fechas de cierre entre Market A y Market B debe ser \< 30 dias |
| **TTL de la Señal** | Tiempo de vida de la senal: 60 minutos (dado que la ventana no es de 200ms sino estructural) Reevaluar la dependencia cada 15 minutos con el pipeline completo Si la oportunidad desaparece antes de ejecutar \=\> documentar para mejorar el pipeline |
| **Drift de Precio** | La latencia de 15-35s es el problema critico. Actuar solo en dependencias estructurales (mercados que han estado fuera de equilibrio por horas, no segundos) |

| PILAR 4  —  VALIDACION DE LA SEÑAL |  |
| :---- | :---- |
| **Confluencia** | Minimo 3 de 4 para ejecutar: (A) LLM confidence \> 80% en la dependencia logica (B) IP Solver confirma profit \> 5% neto (C) Ambos mercados tienen volumen\_24h \> $20,000 (D) La dependencia ha existido por \> 2 horas (no es flash) |
| **Volumen / OI** | Volumen\_24h en Market A \>= $10,000 Y Market B \>= $10,000 Open Interest combinado \>= $50,000 Rechazar si alguna pierna tiene spread \> 5% |
| **Liquidez Falsa** | El IP Solver debe confirmar con datos actuales en tiempo real, no cached Las dependencias detectadas por LLM deben ser revisadas manualmente la primera vez para calibrar el modelo |

| PILAR 5  —  PROTOCOLO DE SALIDA Y COBERTURA |  |
| :---- | :---- |
| **Cierre Objetivo** | Salida: cuando la dependencia logica se corrige (precios convergen al equilibrio) Objetivo de precio: proyeccion del IP Solver sobre precio de equilibrio Revision cada 15 minutos del estado de la dependencia |
| **Stop-Loss** | Stop-loss: si la dependencia logica se rompe (ej. evento A resuelve inesperadamente) Umbral: si el precio de una pierna se mueve \> 15% en contra \=\> cerrar toda la posicion Stop-loss de tiempo: si la dependencia persiste \> 7 dias sin convergencia \=\> salir |
| **Hedging** | Ambas piernas (compra en A, venta en B o viceversa) deben ejecutarse en \< 5s entre si Usar ordenes limit en ambos mercados pre-configuradas antes de ejecutar Si una pierna falla: cerrar la otra inmediatamente para neutralizar exposicion |

| MINT-01 RIESGO BAJO | Minteo Simple $1,000 de Una Vez |
| :---: | :---- |
|  | Mintear $1,000 USDC en un unico ciclo de 24 horas generando 1,000 tokens YES y 1,000 NO, colocando ordenes de venta premium a \+0.75c sobre el best ask. Ganancia neta \+$13.575 por ciclo. |
|  | **Grupo:** Grupo 2 — Minteo y Market Making   |   **Modulo:** pma\_full\_arb\_engine / ciclo de minteo MINT-04 |

| PILAR 1  —  GESTION DE RIESGO Y POSITION SIZING |  |
| :---- | :---- |
| **Kelly Criterion** | Position sizing fijo: $1,000 por ciclo (no aplica Kelly probabilistico) El profit es determinista dado que el spread es calculado antes de mintear Escalar linealmente: bankroll $5,000 \=\> 5 ciclos de $1,000 en 5 mercados distintos |
| **Limite Exposicion** | Maximo 20% del bankroll en ciclos MINT activos simultaneamente Bankroll $10,000 \=\> max $2,000 en MINT-01 (2 ciclos de $1,000) Diversificar en mercados distintos para reducir concentracion |
| **Control Slippage** | Control de spread: si best\_ask del mercado se mueve \> 0.5c durante el ciclo avisar al agente para reposicionar las ordenes de venta No aplica slippage de entrada (ordenes limit, no market) |

| PILAR 2  —  UMBRALES DE RENTABILIDAD NETA |  |
| :---- | :---- |
| **Costos Totales** | Gas Polygon: \~$0.05 (1 mint tx \+ 2 limit orders) Fee Polymarket: 0.002 x min(bid,ask) x 1000 por cada lado Fee YES: \~$0.835 | Fee NO: \~$0.865 | Total fees: \~$1.70 LP Rewards: \+$0.275/dia (Proximity Factor 0.55x) |
| **Hurdle Rate** | Profit neto minimo: \+$13.00 por ciclo de 24h (neto de fees y gas) NO operar en mercados con fee structure distinta que reduce el margen Si el mercado tiene volumen\_24h \< $10,000 \=\> LP rewards podrian ser menores |
| **Ejemplo Neto** | Bruto: $15.00 | Fees: \-$1.70 | Gas: \-$0.05 | LP: \+$0.275 Neto total: \+$13.575 (+1.3575% sobre $1,000) Proyeccion mensual con compounding: \~40.6% |

| PILAR 3  —  VENTANA DE TIEMPO Y CADUCIDAD |  |
| :---- | :---- |
| **Cercanía al Cierre** | Mercado debe cerrar en \> 48h para completar el ciclo de 24h con margen Si el mercado cierra en 24-48h \=\> reducir el ciclo a $500 (MINT-02 basico) Evitar mercados que cierran hoy o manana |
| **TTL de la Señal** | Las ordenes limit tienen vida de 24 horas El agente debe monitorear cada 4 horas si las ordenes siguen siendo competitivas Reposicionar si el midpoint del mercado se mueve \> 1c respecto al momento del minteo |
| **Drift de Precio** | Si el mercado se mueve \> 3c del midpoint original \=\> recalcular las ordenes Las ordenes a \+0.75c del midpoint original pueden quedar fuera del rango razonable |

| PILAR 4  —  VALIDACION DE LA SEÑAL |  |
| :---- | :---- |
| **Confluencia** | Verificar antes de mintear: (A) Mercado tiene volumen\_24h \> $10,000 (mercado activo) (B) El midpoint ha sido estable en las ultimas 4h (variacion \< 2c) (C) No hay eventos de resolucion inminente en las proximas 48h |
| **Volumen / OI** | Volume\_24h minimo: $10,000 para justificar LP rewards Open Interest minimo: $5,000 Bid-ask spread actual del mercado \< 2c (mercado liquido) |
| **Liquidez Falsa** | Verificar que el best\_ask no es una orden unica enorme que podria retirarse Comprobar que hay al menos 5 ordenes distintas en el book dentro de 1c del midpoint |

| PILAR 5  —  PROTOCOLO DE SALIDA Y COBERTURA |  |
| :---- | :---- |
| **Cierre Objetivo** | Salida natural: ordenes de venta se ejecutan cuando traders compran a \+0.75c Objeto: que ambas ordenes (YES y NO) se ejecuten dentro de las 24h del ciclo Si solo se ejecuta una pierna: aguardar resolucion del mercado con el token restante |
| **Stop-Loss** | Si el midpoint se mueve \> 5c en una direccion \=\> cancelar ordenes y re-evaluar Si el mercado pierde volumen drasticamente \=\> cancelar ordenes y re-mintear en otro mercado Si una noticia importante cambia el mercado \=\> cancelar y aguardar estabilizacion |
| **Hedging** | El minteo en si es el hedge: 1 YES \+ 1 NO \= $1.00 siempre, independiente del resultado Si las ordenes no se ejecutan en 24h \=\> resolucion natural garantiza el retorno del capital |

| MINT-02 RIESGO MUY BAJO | Minteo en Dos Partes $500 \+ $500 |
| :---: | :---- |
|  | Dividir el capital en dos ciclos secuenciales de $500 cada uno en 48 horas. Permite ajustar precios entre ciclos segun condiciones de mercado. Recomendado para mercados de liquidez media o volatiles. |
|  | **Grupo:** Grupo 2 — Minteo y Market Making   |   **Modulo:** pma\_full\_arb\_engine / ciclo MINT dividido en 2 sub-ciclos |

| PILAR 1  —  GESTION DE RIESGO Y POSITION SIZING |  |
| :---- | :---- |
| **Kelly Criterion** | Position sizing fijo: $500 por sub-ciclo Ventaja: entre el Ciclo 1 y Ciclo 2 se puede ajustar el offset si el mercado cambio Escalar: bankroll $5,000 \=\> 5 pares de sub-ciclos simultaneos en distintos mercados |
| **Limite Exposicion** | Maximo 15% del bankroll en ciclos MINT-02 activos Bankroll $10,000 \=\> $1,500 en MINT-02 (3 sub-ciclos de $500) En mercados de liquidez media: concentracion \< 10% del open interest total |
| **Control Slippage** | Reposicionar entre ciclos si el midpoint se movio \> 1c En mercados volatiles: usar precio limit mas conservador (+1.0c en lugar de \+0.75c) Verificar bid-ask spread antes de cada sub-ciclo |

| PILAR 2  —  UMBRALES DE RENTABILIDAD NETA |  |
| :---- | :---- |
| **Costos Totales** | Gas Polygon: \~$0.10 (2 mint tx \+ 4 limit orders en total) Fee: identico a MINT-01 pero por $500 \=\> fees \~$0.85 por sub-ciclo LP Rewards: \+$0.14/dia por sub-ciclo (menor capital activo) Neto total 48h: \+$13.30 (identico a MINT-01, mayor gas) |
| **Hurdle Rate** | Profit neto minimo por ciclo completo: \+$13.00 La diferencia de \-$0.05 en gas vs MINT-01 es irrelevante Ventaja real: ajuste de precios entre sub-ciclos puede mejorar el capture rate |
| **Ejemplo Neto** | Sub-ciclo 1: $500 \=\> \+$6.65 neto en 24h Sub-ciclo 2: $500 \=\> \+$6.65 neto en 24h siguientes Total 48h: \+$13.30 (misma ganancia, mejor adaptabilidad) |

| PILAR 3  —  VENTANA DE TIEMPO Y CADUCIDAD |  |
| :---- | :---- |
| **Cercanía al Cierre** | Mercado debe cerrar en \> 72h para completar los 2 sub-ciclos con margen Si el mercado cierra en 48-72h \=\> ejecutar solo el primer sub-ciclo El segundo sub-ciclo solo se lanza si el mercado sigue estable al final del primero |
| **TTL de la Señal** | Cada sub-ciclo tiene vida de 24 horas Al final del Ciclo 1 (24h): revisar el midpoint antes de lanzar Ciclo 2 Si el midpoint cambio \> 2c \=\> recalcular precio de las ordenes del Ciclo 2 |
| **Drift de Precio** | Ventaja de MINT-02: el Ciclo 2 puede usar informacion actualizada del mercado Si el mercado se volvio mas liquido en 24h \=\> subir a MINT-01 ($1,000) para el Ciclo 2 |

| PILAR 4  —  VALIDACION DE LA SEÑAL |  |
| :---- | :---- |
| **Confluencia** | Antes del Ciclo 1: mismos criterios que MINT-01 Antes del Ciclo 2 (adicional): (A) El Ciclo 1 se ejecuto correctamente y al menos una orden se ejecuto (B) El midpoint no se movio \> 3c en las 24h del Ciclo 1 (C) Volumen\_24h sigue siendo \> $8,000 |
| **Volumen / OI** | Liquidez media: mercados con volumen\_24h entre $5,000 y $20,000 Son el target ideal de MINT-02 (suficiente para LP rewards pero no tan competitivo) Rechazar mercados con volumen \< $3,000 (poca demanda para las ordenes) |
| **Liquidez Falsa** | Mismo analisis que MINT-01 Adicional: verificar entre ciclos que el open interest no cayó drasticamente |

| PILAR 5  —  PROTOCOLO DE SALIDA Y COBERTURA |  |
| :---- | :---- |
| **Cierre Objetivo** | Ciclo 1: ordenes de venta activas por 24h al \+0.75c del midpoint\_inicial Ciclo 2: nuevas ordenes al \+0.75c del midpoint\_actualizado (24h despues) Salida natural cuando las ordenes se ejecutan en cada ciclo |
| **Stop-Loss** | Si en el Ciclo 1 ninguna orden se ejecuta en 24h: \- Evaluar si el mercado perdio liquidez \- Si volumen cayo \> 50% \=\> NO lanzar Ciclo 2 \- Cancelar ordenes del Ciclo 1 y re-mintear en otro mercado |
| **Hedging** | Identico a MINT-01: el minteo es el hedge natural Si el Ciclo 2 no se puede lanzar: el capital del Ciclo 1 queda protegido por el par YES+NO |

| MINT-03 RIESGO MEDIO — Acumulacion Pasiva | Market Making en el Midpoint — Escenario A |
| :---: | :---- |
|  | Colocar ordenes de venta exactamente en el midpoint para maximizar LP Rewards (Proximity Factor 1.00x, Score 3,000 pts). Solo rentable si las ordenes NO se ejecutan rapidamente. Si se ejecutan: perdida neta \-$1.21. APY pasivo \~16.5%. |
|  | **Grupo:** Grupo 2 — Minteo y Market Making   |   **Modulo:** pma\_full / configuracion pasiva (no detectado por arb\_engine) |

| PILAR 1  —  GESTION DE RIESGO Y POSITION SIZING |  |
| :---- | :---- |
| **Kelly Criterion** | NO aplica Kelly convencional: es estrategia de acumulacion de rewards, no de profit de spread Capital asignado: hasta 30% del bankroll en MINT-03 para maximizar LP Score Bankroll $10,000 \=\> $3,000 en MINT-03 en distintos mercados |
| **Limite Exposicion** | Maximo 30% del bankroll en total para estrategia pasiva MINT-03 Distribuir en minimo 5 mercados distintos para diversificar riesgo de ejecucion Por mercado individual: no mas de 6% del bankroll |
| **Control Slippage** | CRITICO: si las ordenes en el midpoint se ejecutan \=\> perdida \-$1.21 por ciclo de $1,000 Umbral de proteccion: si la probabilidad del mercado se mueve rapidamente (\>2c en 1h) cancelar ordenes del midpoint y reposicionar a \+0.75c (cambio a MINT-04) |

| PILAR 2  —  UMBRALES DE RENTABILIDAD NETA |  |
| :---- | :---- |
| **Costos Totales** | Gas Polygon: \~$0.05 (1 mint tx \+ 2 limit orders) LP Rewards: \+$0.50/dia (Proximity Factor 1.00x, Score 3,000 pts) Si ordenes se ejecutan: spread negativo \-$1.71 \=\> neto \-$1.21 por ciclo |
| **Hurdle Rate** | Hurdle Rate en MODO PASIVO: APY rewards \>= 16.5% anual sobre el capital asignado NO es una estrategia de profit de spread Si las ordenes se ejecutan con frecuencia \> 1 vez/semana \=\> cambiar a MINT-04 |
| **Ejemplo Neto** | Modo ideal (ordenes no ejecutadas): \+$0.50/dia \= \+$182.5/año por ciclo de $1,000 APY solo rewards: 18.25% anual Modo malo (ordenes ejecutadas 2x/mes): \-$1.21 x 2 \+ $15 rewards \= \-$9.22/mes \=\> CAMBIAR A MINT-04 |

| PILAR 3  —  VENTANA DE TIEMPO Y CADUCIDAD |  |
| :---- | :---- |
| **Cercanía al Cierre** | Mercados con cierre \> 30 dias: IDEAL para MINT-03 (largo plazo de acumulacion) Mercados con cierre 14-30 dias: ACEPTABLE Mercados con cierre \< 14 dias: NO USAR MINT-03 (muy poca acumulacion de rewards) |
| **TTL de la Señal** | No hay senal de tiempo de vida: las ordenes son permanentes hasta ejecucion o cancelacion Revisar posicion cada 12 horas Si el mercado se acerca al cierre (\< 7 dias) \=\> convertir a MINT-04 o cerrar posicion |
| **Drift de Precio** | Si el midpoint se mueve \> 3c \=\> reposicionar ordenes al nuevo midpoint Monitoreo de drift: alertar si precio se mueve \> 2c en menos de 30 minutos |

| PILAR 4  —  VALIDACION DE LA SEÑAL |  |
| :---- | :---- |
| **Confluencia** | Seleccion de mercado para MINT-03: (A) Mercado con alta probabilidad de permanecer estable (noticias politicas lejos, no crypto) (B) Open Interest \> $20,000 (mercado maduro con LP rewards altos) (C) Historial de precios: variacion \< 5c en las ultimas 72h |
| **Volumen / OI** | Volume\_24h \> $20,000 para maximizar LP Score y rewards Mercados de elecciones con fecha \> 2 meses son candidatos ideales Crypto: NO recomendado (alta volatilidad mata la estrategia) |
| **Liquidez Falsa** | No aplica de la misma manera: en MINT-03 el riesgo no es la liquidez sino la ejecucion de las propias ordenes Monitorear si alguien esta comprando agresivamente (elevaria el precio en una direccion) |

| PILAR 5  —  PROTOCOLO DE SALIDA Y COBERTURA |  |
| :---- | :---- |
| **Cierre Objetivo** | Objetivo principal: que las ordenes NO se ejecuten Ganancia acumulada de LP Rewards dia a dia Salida planificada: cuando el mercado se acerca a \< 14 dias de cierre \=\> cancelar y retirar |
| **Stop-Loss** | Si las ordenes se ejecutan una vez: cancelar todo y cambiar a MINT-04 en ese mercado Si el precio se mueve \> 5c en 2h: cancelar ordenes del midpoint para evitar ejecucion Stop de APY: si el rewards acumulado \< 10% anual tras 30 dias \=\> reasignar capital |
| **Hedging** | El hedge es el minteo: el par YES+NO siempre vale \>= $0.998 hasta resolucion Si las ordenes se ejecutan: el token restante se mantiene hasta resolucion del evento El 'peor caso' es recuperar el capital invertido al cierre del mercado |

| MINT-04 RIESGO BAJO — ESTRATEGIA GANADORA | Market Making Premium — Escenario B |
| :---: | :---- |
|  | Colocar ordenes a \+0.75c del midpoint (Proximity Factor 0.55x). El spread capturado (+$13.30) supera masivamente la perdida de LP Rewards vs MINT-03. APY 26.2%. Base de MINT-01 y MINT-02. Estrategia ganadora en mercados liquidos. |
|  | **Grupo:** Grupo 2 — Minteo y Market Making   |   **Modulo:** pma\_full\_arb\_engine / ciclo de minteo principal |

| PILAR 1  —  GESTION DE RIESGO Y POSITION SIZING |  |
| :---- | :---- |
| **Kelly Criterion** | Position sizing semi-deterministico: profit calculable antes de ejecutar Kelly ajustado: f \= capture\_rate\_esperado x capital\_disponible Capture rate: si el mercado es muy liquido \=\> 95% de ordenes se ejecutan en 24h |
| **Limite Exposicion** | Maximo 25% del bankroll en MINT-04 activos Bankroll $10,000 \=\> $2,500 en MINT-04 (ej. 2-3 ciclos de $1,000 en distintos mercados) Preferir mercados de elecciones, crypto (BTC/ETH) y NBA/deportes top |
| **Control Slippage** | No aplica slippage de entrada (ordenes limit) Riesgo: que las ordenes no se ejecuten si el mercado no tiene suficiente actividad Umbral de actividad: si el mercado tiene \< 3 trades/hora \=\> bajar offset a \+0.50c (sweet spot) |

| PILAR 2  —  UMBRALES DE RENTABILIDAD NETA |  |
| :---- | :---- |
| **Costos Totales** | Gas Polygon: \~$0.05 | Fee: \~$1.70 total para $1,000 (igual que MINT-01) LP Rewards: \+$0.275/dia (Proximity Factor 0.55x vs 1.00x de MINT-03) Profit neto por ciclo: \+$13.575 (+1.3575%) |
| **Hurdle Rate** | Hurdle Rate: \+1.33% neto minimo por ciclo de 24h Con 30 ciclos/mes: 40.06% mensual proyectado (compounding) Si el mercado no ejecuta las ordenes en \> 36h \=\> evaluar reposicion |
| **Ejemplo Neto** | Bruto: $15.00 | Fees: \-$1.70 | Gas: \-$0.05 | LP: \+$0.275 Neto: \+$13.575 por ciclo de $1,000 Vs MINT-03: \+$13.575 vs \-$1.21 en mercados liquidos \= \+1,222% diferencia |

| PILAR 3  —  VENTANA DE TIEMPO Y CADUCIDAD |  |
| :---- | :---- |
| **Cercanía al Cierre** | Mercado cierra \> 48h: OPERAR con ciclo completo de 24h Mercado cierra 24-48h: OPERAR con ciclo de 12h y offset \+1.0c Mercado cierra \< 24h: NO OPERAR (riesgo de resolucion antes de ejecucion de ordenes) |
| **TTL de la Señal** | Ciclo de 24h: si las ordenes no se ejecutan en 24h \=\> monitorear y reposicionar Reposicionamiento: cada 6 horas verificar si el midpoint se movio \> 1c Si se movio: cancelar ordenes actuales y emitir nuevas al nuevo midpoint \+0.75c |
| **Drift de Precio** | Si el mercado sube/baja \> 3c \=\> reposicionar en lugar de esperar Drift rapido (\> 2c en 30min) puede indicar noticia importante \=\> pausar hasta estabilizacion |

| PILAR 4  —  VALIDACION DE LA SEÑAL |  |
| :---- | :---- |
| **Confluencia** | Minimo 2 de 3 para seleccionar el mercado: (A) Volumen\_24h \> $20,000 (mercado muy liquido) (B) Al menos 10 trades en la ultima hora en el CLOB (C) Bid-ask spread actual \< 1.5c (mercado ajustado y activo) |
| **Volumen / OI** | Target ideal: mercados de elecciones (BTC, presidenciales, NBA finales) Volumen\_24h \> $50,000: usar offset \+1.0c (mas agresivo \= mas LP rewards) Volumen\_24h $10k-$50k: usar offset \+0.75c (estandar MINT-04) Volumen\_24h \< $10k: usar MINT-02 en su lugar |
| **Liquidez Falsa** | Verificar que el volumen proviene de multiples wallets y no de wash trading Si el mismo actor representa \> 50% del volumen \=\> mercado artificial \=\> evitar |

| PILAR 5  —  PROTOCOLO DE SALIDA Y COBERTURA |  |
| :---- | :---- |
| **Cierre Objetivo** | Salida natural: ordenes limit se ejecutan cuando traders compran el spread Objetivo de capture rate: \> 80% de las ordenes ejecutadas en 24h Si capture rate es consistentemente \< 50% \=\> bajar a sweet spot MINT-05 |
| **Stop-Loss** | Si el mercado pierde \> 60% de su volumen en 24h \=\> cancelar ordenes y mover a otro mercado Si la plataforma anuncia cambios en el sistema de LP rewards \=\> re-evaluar toda la estrategia Stop de ciclo: si no hay ninguna ejecucion en 36h \=\> cancelar y re-mintear en otro mercado |
| **Hedging** | Hedge natural del minteo: YES \+ NO \= $1.00 siempre en resolucion Si solo una pierna se ejecuta: el token restante se mantiene hasta resolucion En portafolio multi-mercado: si un mercado es problemático, los otros ciclos cubren las perdidas |

| MINT-05 RIESGO BAJO — Balance Optimo | Market Making Sweet Spot |
| :---: | :---- |
|  | Balance optimo entre MINT-03 (max LP Rewards) y MINT-04 (max spread). El agente ajusta dinamicamente el offset (0.25c a 0.50c) segun la liquidez del mercado. Garantiza spread positivo y rewards al 70-85% del maximo. |
|  | **Grupo:** Grupo 2 — Minteo y Market Making   |   **Modulo:** pma\_full\_arb\_engine / minteo con offset dinamico |

| PILAR 1  —  GESTION DE RIESGO Y POSITION SIZING |  |
| :---- | :---- |
| **Kelly Criterion** | Position sizing adaptativo: kelly basado en el capture rate historico del offset elegido A 0.25c del midpoint: capture rate \~90% \=\> kelly mas agresivo (hasta 20% bankroll) A 0.50c del midpoint: capture rate \~70% \=\> kelly moderado (hasta 15% bankroll) |
| **Limite Exposicion** | Exposicion dinamica: varia segun el offset seleccionado A 0.25c: mayor exposicion (mayor capture, menor spread) \=\> max 20% bankroll A 0.50c: menor exposicion (menor capture, mayor spread) \=\> max 15% bankroll Distribuir en 3-5 mercados para diversificar |
| **Control Slippage** | No aplica slippage de entrada (ordenes limit) Riesgo: subejecutar si el offset es demasiado agresivo para el mercado Ajuste automatico: si en 12h no se ejecuta ninguna orden \=\> bajar offset 0.25c |

| PILAR 2  —  UMBRALES DE RENTABILIDAD NETA |  |
| :---- | :---- |
| **Costos Totales** | Gas y fees identicos a MINT-01 y MINT-04 ($0.05 gas \+ \~$1.70 fees) LP Rewards: 70-85% del maximo segun el offset elegido A 0.25c: Rewards \= $0.425/dia (85% de $0.50) | A 0.50c: $0.35/dia (70%) |
| **Hurdle Rate** | Hurdle Rate: spread positivo garantizado (condicion minima) \+ rewards \> 70% del maximo A 0.25c: spread \+$2.50 \+ rewards $0.425/dia \=\> neto \> $3.00/dia \=\> OPERAR A 0.50c: spread \+$7.50 \+ rewards $0.35/dia \=\> neto \> $8.00/dia \=\> OPERAR |
| **Ejemplo Neto** | Posicion 0.25c (mercados poco liquidos): neto diario estimado \+0.5% sobre capital Posicion 0.50c (mercados medios): neto diario estimado \+0.9% sobre capital Menos que MINT-04 pero mas que MINT-03 en todos los escenarios |

| PILAR 3  —  VENTANA DE TIEMPO Y CADUCIDAD |  |
| :---- | :---- |
| **Cercanía al Cierre** | Mercado cierra \> 72h: usar offset 0.25c (maximizar rewards en largo plazo) Mercado cierra 48-72h: usar offset 0.50c (capture rate alto, menos tiempo) Mercado cierra \< 48h: cambiar directamente a MINT-04 (0.75c) para maximizar capture |
| **TTL de la Señal** | Revision del offset cada 12 horas: ajustar segun el capture rate observado Si capture rate \> 80% con el offset actual: subir offset 0.25c Si capture rate \< 40% con el offset actual: bajar offset 0.25c |
| **Drift de Precio** | Si el midpoint se mueve \> 2c en 6h: reposicionar las ordenes al nuevo midpoint El offset se mantiene igual, solo cambia el precio base |

| PILAR 4  —  VALIDACION DE LA SEÑAL |  |
| :---- | :---- |
| **Confluencia** | Seleccion de offset segun caracteristicas del mercado: (A) Volumen\_24h \> $30,000 \=\> usar offset 0.50c (B) Volumen\_24h $10k-$30k \=\> usar offset 0.25c (C) Mercado con alta volatilidad \=\> usar offset 0.50c (menos riesgo de ejecucion) |
| **Volumen / OI** | Sweet spot para MINT-05: mercados con volumen\_24h entre $10,000 y $30,000 No compite con MINT-04 en mercados muy liquidos (\> $50k) donde el offset 0.75c es mas eficiente Ideal para mercados de mediana actividad: deportes menores, economia regional |
| **Liquidez Falsa** | Mismos criterios que MINT-04 Adicional: verificar que el midpoint es estable antes de elegir el offset inicial |

| PILAR 5  —  PROTOCOLO DE SALIDA Y COBERTURA |  |
| :---- | :---- |
| **Cierre Objetivo** | El agente ajusta el target dinamicamente segun el offset vigente Objetivo: capture rate \> 70% con el offset elegido en cada ciclo de 24h Salida natural: ejecucion de las ordenes limit |
| **Stop-Loss** | Si capture rate cae \< 30% durante 48h consecutivas: escalar a MINT-04 (+0.75c) Si el mercado pierde \> 50% del volumen: cerrar posicion y mover capital No mantener posiciones en mercados 'zombies' con \< 2 trades/hora |
| **Hedging** | Identico a MINT-01 y MINT-04: minteo provee hedge natural La adaptabilidad del offset es la ventaja clave: nunca quedarse en un offset que no funciona |

| MINT-06 RIESGO BAJO — Meta-Estrategia | Compounding Acelerado Multi-Ciclo |
| :---: | :---- |
|  | Meta-estrategia de reinversion sistematica: al completarse cada ciclo MINT-01/MINT-04, el agente reinvierte INMEDIATAMENTE la totalidad del capital \+ ganancia en el siguiente ciclo. Capital x7.8 en 12 meses con reinversion total. |
|  | **Grupo:** Grupo 2 — Minteo y Market Making   |   **Modulo:** pma\_full\_arb\_engine / scheduler de reinversion automatica |

| PILAR 1  —  GESTION DE RIESGO Y POSITION SIZING |  |
| :---- | :---- |
| **Kelly Criterion** | Kelly no aplica por ciclo: el sizing es Capital(n) \= Capital(n-1) x 1.01357 Control de Kelly para el portafolio total: nunca superar 40% del bankroll en MINT activo Bankroll $10,000 \=\> max $4,000 en ciclos MINT-06 simultaneos |
| **Limite Exposicion** | El capital en MINT-06 crece automaticamente con cada ciclo Implementar techo de capital: cuando ciclo supere $5,000 \=\> dividir en 2 ciclos de $2,500 Nunca tener \> 50% del bankroll en un solo ciclo de compounding |
| **Control Slippage** | A medida que el capital crece, el impacto en el mercado crece Cuando el ciclo supere $3,000: verificar que el mercado tiene suficiente liquidez Rotar mercados si la liquidez del mercado actual ya no es suficiente para el tamano |

| PILAR 2  —  UMBRALES DE RENTABILIDAD NETA |  |
| :---- | :---- |
| **Costos Totales** | Los fees crecen proporcionalmente con el capital del ciclo Formula de costo: fee\_n \= fee\_base x Capital(n) / $1,000 El crecimiento neto sigue siendo 1.3575% por ciclo (escala perfectamente) |
| **Hurdle Rate** | Hurdle Rate del compounding: \> 1.3% neto por ciclo (mismo que MINT-01) Si un ciclo produce menos del 1%: investigar el mercado seleccionado Objetivo de largo plazo: 40% mensual mantenido durante 12 meses consecutivos |
| **Ejemplo Neto** | Ciclo 1: $1,000 \=\> $1,013.57 | Ciclo 10: \~$1,144 | Ciclo 30: \~$1,500 12 meses (360 ciclos teóricos): capital x \~7.8 Capital inicial $10,000 \=\> $78,000 al ano (reinversion total, sin retiros) |

| PILAR 3  —  VENTANA DE TIEMPO Y CADUCIDAD |  |
| :---- | :---- |
| **Cercanía al Cierre** | Seleccionar mercados con \> 72h al cierre para que el ciclo complete La reinversion inmediata puede requerir identificar el siguiente mercado con anticipacion El agente debe tener una cola de mercados candidatos pre-evaluados |
| **TTL de la Señal** | El ciclo dura exactamente 24h por diseno La reinversion debe ocurrir en \< 30 minutos despues de completar el ciclo anterior Si no hay mercado disponible: mantener el capital en USDC y esperar (no reinvertir en mercados malos) |
| **Drift de Precio** | Con capital creciente: monitorear el mismo mercado cada 4h para verificar estabilidad Si el mercado tiene un evento que podria resolverlo antes de 24h: cambiar de mercado |

| PILAR 4  —  VALIDACION DE LA SEÑAL |  |
| :---- | :---- |
| **Confluencia** | Para cada ciclo de reinversion, verificar: (A) El nuevo mercado tiene el mismo nivel de liquidez que el anterior (B) El capital actual encaja en el tamano del mercado (no ser \> 5% del open interest) (C) No hay eventos de alta volatilidad programados para las proximas 24h |
| **Volumen / OI** | A medida que el capital crece, los requisitos de volumen crecen Capital $1,000: mercado con volume\_24h \> $10,000 Capital $2,000: mercado con volume\_24h \> $20,000 Capital $5,000: mercado con volume\_24h \> $50,000 |
| **Liquidez Falsa** | Con capital creciente: evitar mercados donde las propias ordenes representen \> 10% del volume Diversificar en multiples mercados cuando el capital supere $3,000 por ciclo |

| PILAR 5  —  PROTOCOLO DE SALIDA Y COBERTURA |  |
| :---- | :---- |
| **Cierre Objetivo** | Objetivo del compounding: acumular capital sin retiros durante el periodo planificado Salida de la meta-estrategia: definir un horizonte temporal (ej. 12 meses) y un capital objetivo Al alcanzar el capital objetivo \=\> convertir a estrategia de retiro parcial (50% reinvierte, 50% retira) |
| **Stop-Loss** | Stop del compounding: si 3 ciclos consecutivos producen \< 0.5% neto \=\> pausar y revisar Si el portafolio pierde \> 5% del pico historico \=\> reducir el tamaño de ciclo al 50% Stop total: si la plataforma cambia su estructura de fees afectando el modelo \=\> recalcular |
| **Hedging** | El hedge del compounding es la diversificacion de mercados en ciclos paralelos Nunca poner todo el capital en un solo ciclo cuando supere $2,000 Distribuir el compounding en 2-3 mercados distintos para reducir el riesgo de concentracion |

| TRADE-02 RIESGO MEDIO | Trading de Impulso (Momentum) — Automatizado |
| :---: | :---- |
|  | El agente sigue la tendencia cuando una probabilidad sube con fuerza (\> 8%/periodo) acompanada de volumen alto (\> percentil 80). Compra cuando la probabilidad esta en 10-30% y vende al llegar a \~50%. NUNCA mantiene posicion hasta la resolucion del evento. |
|  | **Grupo:** Grupo 3 — Trading Activo Automatizado   |   **Modulo:** pma\_full\_collector (market\_snapshots) \+ arb\_engine — Fase 2 |

| PILAR 1  —  GESTION DE RIESGO Y POSITION SIZING |  |
| :---- | :---- |
| **Kelly Criterion** | f\* \= (p x b \- q) / b donde: p \= probabilidad estimada de que el momentum continue b \= ganancia si el precio llega al objetivo (ratio precio\_objetivo/precio\_entrada) q \= 1 \- p | Kelly Fraccionado: f\_real \= f\* x 0.30 |
| **Limite Exposicion** | Maximo 10% del bankroll por posicion de momentum Bankroll $10,000 \=\> max $1,000 por trade TRADE-02 Maximo 3 posiciones de momentum simultaneas (30% del bankroll) |
| **Control Slippage** | Slippage de entrada: usar ordenes limit a precio de mercado \+ 0.5% Si el precio se mueve \> 2% antes de que la orden se llene \=\> cancelar No perseguir el precio: si se perdio la entrada optima \=\> esperar el siguiente setup |

| PILAR 2  —  UMBRALES DE RENTABILIDAD NETA |  |
| :---- | :---- |
| **Costos Totales** | Gas Polygon: \~$0.02 por trade (compra \+ venta) Fee Polymarket: 2% sobre la ganancia (solo si hay profit) Slippage estimado: 0.5-1% de impacto en mercados de liquidez media Hurdle Rate: 5% bruto minimo para absorber fees, gas y slippage \=\> neto \~2.5% |
| **Hurdle Rate** | Solo ejecutar si el objetivo proyectado (precio alcanza 50%) representa \>= 5% de ganancia bruta Ejemplo: comprar a 30% \=\> objetivo 50% \=\> ganancia 67% sobre el capital invertido Menos que eso: no compensa el riesgo de momentum falso |
| **Ejemplo Neto** | Entrada en 20% \=\> objetivo 50% \=\> ganancia 150% sobre tokens comprados Capital $1,000 / precio $0.20 \= 5,000 tokens \=\> valor objetivo $2,500 \=\> ganancia $1,500 bruto |

| PILAR 3  —  VENTANA DE TIEMPO Y CADUCIDAD |  |
| :---- | :---- |
| **Cercanía al Cierre** | El momentum es mas confiable en mercados con \> 14 dias al cierre Mercados \< 7 dias: el momentum puede ser manipulacion pre-cierre \=\> EVITAR Mercados \< 24h: NO OPERAR en ningun caso con TRADE-02 |
| **TTL de la Señal** | Tiempo de vida de la senal de entrada: 2 minutos Si delta\_precio \> 0.08 pero el volumen de confirmacion no llega en 2min \=\> senal invalida No retener posicion de momentum por mas de 48h: si el objetivo no se alcanza \=\> salir con lo que hay |
| **Drift de Precio** | Monitorear la senal cada 5 minutos: si el momentum se detiene o revierte antes del objetivo Si delta\_precio \< 0.01 por 2 periodos consecutivos \=\> el momentum se agoto \=\> SALIR |

| PILAR 4  —  VALIDACION DE LA SEÑAL |  |
| :---- | :---- |
| **Confluencia** | Minimo 2 de 4 senales deben coincidir: (A) delta\_precio \> 0.08/periodo Y vol \> percentil\_80 (B) RSI sobre la serie de probabilidades: RSI \> 60 y subiendo (C) MACD de la probabilidad: linea MACD cruza por encima de la senal (D) Volumen del periodo actual \> 2x el promedio de los ultimos 10 periodos |
| **Volumen / OI** | Confirmar que el volumen alto no es de un unico actor (whale) Si el 80% del volumen de confirmacion es de 1 wallet \=\> senal potencialmente manipulada Volumen de confirmacion: al menos 10 transacciones distintas en el periodo de la senal |
| **Liquidez Falsa** | El gran riesgo de TRADE-02: el volumen alto puede ser wash trading o manipulacion Verificar que el Open Interest tambien sube junto con el precio (validacion real) Si el precio sube pero el OI cae \=\> traders cerrando posiciones, no abriendo \=\> senal falsa |

| PILAR 5  —  PROTOCOLO DE SALIDA Y COBERTURA |  |
| :---- | :---- |
| **Cierre Objetivo** | Objetivo primario: precio alcanza 50% (venta automatica) Objetivo secundario: precio alcanza 40% (tomar 50% de la ganancia y dejar el resto correr) Nunca mantener hasta la resolucion del evento: el riesgo binario es inaceptable |
| **Stop-Loss** | Stop-loss duro: \-15% desde el precio de entrada (ej. compre a 20% \=\> stop a 17%) Stop-loss de momentum: si el precio cae de vuelta al punto de entrada \=\> salir sin discusion Stop de tiempo: si en 48h el precio no alcanzo el objetivo \=\> salir al precio de mercado |
| **Hedging** | No hay hedge natural en TRADE-02: es una posicion direccional pura Hedge parcial opcional: si se compra YES a 20%, comprar tambien NO a 80% \= $0.80 por seguridad Esta cobertura reduce el profit potencial pero elimina el riesgo de quiebra total de la posicion |

| IA-01 RIESGO MEDIO | Front-Running Automatizado de Noticias |
| :---: | :---- |
|  | Monitorear APIs de noticias en tiempo real (Reuters, AP, OpenWeather, SportRadar, FRED macro) y ejecutar ordenes en \< 500ms antes de que los traders manuales puedan reaccionar. Pipeline: API → NLP scorer → Delta\_prob → Build order → Sign → Send. |
|  | **Grupo:** Grupo 4 — IA y Automatizacion Avanzada   |   **Modulo:** Externo — Nodo RPC Polygon propio — Fase 3 |

| PILAR 1  —  GESTION DE RIESGO Y POSITION SIZING |  |
| :---- | :---- |
| **Kelly Criterion** | f\* basado en el delta de probabilidad estimado por el NLP scorer Si NLP scorer predice un movimiento de 20 puntos: f\* \= 0.20 x Kelly\_fraction Kelly Fraccionado: f\_real \= f\* x 0.25 (incertidumbre del NLP scorer) |
| **Limite Exposicion** | Maximo 8% del bankroll por evento de noticia individual Bankroll $10,000 \=\> max $800 por trade IA-01 Maximo 3 eventos simultaneos: 24% del bankroll expuesto |
| **Control Slippage** | Critico: la ventana de oportunidad es \< 500ms despues de que la noticia es publica Si el precio ya se movio \> 3% antes de que la orden llegue \=\> CANCELAR Usar ordenes market solo en los primeros 200ms; despues usar limit |

| PILAR 2  —  UMBRALES DE RENTABILIDAD NETA |  |
| :---- | :---- |
| **Costos Totales** | Gas Polygon: \~$0.02 (nodo propio \< 30ms) Fee Polymarket: 2% sobre la ganancia Costo de APIs: Reuters \~$500/mes, SportRadar \~$300/mes (prorrateado: \~$2.60/dia) Hurdle Rate: \> 3% neto por evento para cubrir costo de APIs e infraestructura |
| **Hurdle Rate** | Con costo de infraestructura de $800/mes: necesitar al menos 10 trades exitosos/mes Cada trade exitoso debe generar \> $80 neto para cubrir el costo fijo mensual Si el capital es \< $5,000: la infraestructura de IA-01 no es rentable |
| **Ejemplo Neto** | Evento predice movimiento de 15 puntos porcentuales Compra $800 de tokens a 30% \=\> precio sube a 45% \=\> ganancia 50% \=\> \+$400 \- fees \- infra |

| PILAR 3  —  VENTANA DE TIEMPO Y CADUCIDAD |  |
| :---- | :---- |
| **Cercanía al Cierre** | Solo actuar en mercados con \> 7 dias al cierre (evitar manipulacion pre-cierre) Los eventos de noticias tienen mayor impacto cuando el mercado esta lejos de 50/50 Evitar noticias sobre eventos cuyo mercado cierra en \< 48h (ya 'priceado') |
| **TTL de la Señal** | La ventana de front-running es de 100-500ms post-noticia Despues de 500ms: otros bots ya habran reaccionado y la oportunidad desaparece Si la latencia del pipeline supera 500ms: desactivar IA-01 hasta optimizar la infraestructura |
| **Drift de Precio** | Las noticias tienen un impacto inmediato y luego un ajuste posterior La senal es valida solo en los primeros 500ms: despues el mercado ya la digirió |

| PILAR 4  —  VALIDACION DE LA SEÑAL |  |
| :---- | :---- |
| **Confluencia** | Minimo 2 de 3: (A) NLP scorer confidence \> 85% en el impacto de la noticia (B) El mercado relevante tiene volumen \> $10,000 (suficiente para absorber la orden) (C) No hay otras noticias contradictoras en las ultimas 2h sobre el mismo tema |
| **Volumen / OI** | El mercado objetivo debe tener suficiente liquidez para absorber la orden en \< 200ms Volumen\_24h \> $20,000 para que el front-running sea efectivo Si el mercado es iliquido: el propio trade movera el precio en contra (se convierte en el precio) |
| **Liquidez Falsa** | Verificar que la noticia es de una fuente verificada (Reuters, AP, fuentes oficiales) NO actuar sobre noticias de redes sociales o fuentes no verificadas Confirmar que la noticia no es un 'duplicate' de informacion ya conocida por el mercado |

| PILAR 5  —  PROTOCOLO DE SALIDA Y COBERTURA |  |
| :---- | :---- |
| **Cierre Objetivo** | Salida cuando el mercado ha ajustado completamente la noticia (nuevo equilibrio) Tipicamente 5-30 minutos despues del evento Si el precio llego al objetivo proyectado por el NLP scorer: salir inmediatamente |
| **Stop-Loss** | Stop-loss: si el precio se mueve en la direccion CONTRARIA a la noticia \=\> error del NLP Umbral: si el precio cae \> 5% desde la entrada \=\> salir sin esperar Stop de tiempo: si en 1 hora el mercado no reacciono a la noticia \=\> la noticia ya era conocida \=\> salir |
| **Hedging** | En noticias de alto impacto: comprar el lado favorecido Y vender el lado opuesto Ejemplo: Fed sube tasas \=\> comprar YES en 'tasas \> X%' Y vender YES en 'tasas \< Y%' Este hedge bilateral captura el movimiento en cualquier direccion |

| IA-02 RIESGO MEDIO | Copy-Trading de Ballenas (Whale Following) |
| :---: | :---- |
|  | Monitorear wallets Polygon con historial de win\_rate \> 70% y replicar sus posiciones en \< 2 segundos cuando colocan ordenes significativas. Polymarket es 100% transparente on-chain: todas las transacciones son publicas. |
|  | **Grupo:** Grupo 4 — IA y Automatizacion Avanzada   |   **Modulo:** pma\_full\_collector \+ indexador on-chain — Fase 2 |

| PILAR 1  —  GESTION DE RIESGO Y POSITION SIZING |  |
| :---- | :---- |
| **Kelly Criterion** | f\* de la wallet seguida: si win\_rate \= 75% y ratio promedio \= 2x f\* \= (0.75 x 2 \- 0.25) / 2 \= 0.625 \=\> Kelly Fraccionado: f\_real \= 0.625 x 0.20 \= 0.125 Capital por replica: 12.5% del bankroll por posicion copiada |
| **Limite Exposicion** | Maximo 12% del bankroll por wallet replicada por evento Bankroll $10,000 \=\> max $1,200 por copia de whale Maximo 3 whales distintas replicando simultaneamente: 36% del bankroll |
| **Control Slippage** | La ballena mueve el precio al entrar: la replica llega despues \=\> precio ya movido Estimar el slippage de la replica: si la orden de la ballena fue \> $5,000 en un mercado de $20,000 el precio ya se movio \~2% antes de que el agente pueda copiar \=\> ajustar el tamano al 50% |

| PILAR 2  —  UMBRALES DE RENTABILIDAD NETA |  |
| :---- | :---- |
| **Costos Totales** | Gas Polygon: \~$0.02 | Fee Polymarket: 2% Costo de infraestructura de indexacion on-chain: \~$100/mes (nodo Polygon full) Hurdle Rate: \> 4% neto por operacion (compensar slippage de replica) |
| **Hurdle Rate** | El slippage de replica (llegar despues de la ballena) reduce el profit esperado Solo replicar si el precio post-ballena aun tiene \> 5% de upside hasta el objetivo Si la ballena compra a 30% y el precio ya subio a 34% al detectarlo \=\> solo replicar si objetivo es \> 40% |
| **Ejemplo Neto** | Whale compra $10,000 en YES a 25% \=\> precio sube a 28% antes de que replicas Replica a 28%, objetivo de la whale es 50% \=\> ganancia potencial 79% \=\> neto \~75% \=\> REPLICAR |

| PILAR 3  —  VENTANA DE TIEMPO Y CADUCIDAD |  |
| :---- | :---- |
| **Cercanía al Cierre** | Replicar solo en mercados con \> 7 dias al cierre Las ballenas suelen anticipar movimientos de mediano plazo: sus posiciones duran dias/semanas No replicar en mercados que cierran en \< 48h (la ballena puede estar liquidando) |
| **TTL de la Señal** | Ventana de replica: 2 segundos desde que se detecta la transaccion on-chain Si se detecta con \> 5s de retraso: evaluar si el precio ya se movio demasiado Monitorear las transacciones del mempool de Polygon para reducir latencia |
| **Drift de Precio** | Monitorear si la ballena mantiene o vende su posicion Si la ballena empieza a vender su posicion \=\> senales de salida para la replica tambien |

| PILAR 4  —  VALIDACION DE LA SEÑAL |  |
| :---- | :---- |
| **Confluencia** | Minimo 3 de 4: (A) win\_rate(wallet) \> 70% en los ultimos 90 dias con \>= 20 trades (B) Tamano de la orden \> $1,000 (compromiso real, no prueba) (C) El mercado tiene volumen\_24h \> $10,000 (D) La wallet no ha tenido una racha de 3 perdidas consecutivas recientes |
| **Volumen / OI** | Verificar que la ballena opera en mercados con suficiente liquidez para la replica Si el mercado es iliquido: la ballena ya consumio toda la liquidez disponible Whale \> $50,000 en mercado de $100,000: la liquidez restante podria ser insuficiente |
| **Liquidez Falsa** | RIESGO CRITICO: la ballena puede tener informacion privilegiada (potencialmente ilegal) Solo replicar whales con historial \> 90 dias y \> 20 trades (no puede ser siempre suerte) Evitar whales que solo ganan en mercados muy especificos (podrian tener insider info) |

| PILAR 5  —  PROTOCOLO DE SALIDA Y COBERTURA |  |
| :---- | :---- |
| **Cierre Objetivo** | Salida sincronizada con la whale: monitorear cuando empieza a vender Si la whale vende \> 30% de su posicion \=\> la replica tambien vende el 50% No quedarse en la posicion mas tiempo que la whale |
| **Stop-Loss** | Stop-loss: si la whale pierde \> 20% de su posicion sin vender \=\> algo salio mal Umbral: precio cae \> 10% desde la entrada de la replica \=\> salir independientemente de la whale Si la wallet cae de win\_rate 70% a \< 60% en las ultimas 10 operaciones: dejar de seguirla |
| **Hedging** | No hay hedge directo (es posicion direccional siguiendo a otro) Hedge de portafolio: no poner mas del 12% en ninguna single whale Diversificar en 3+ whales distintas con estrategias no correlacionadas |

| IA-03 RIESGO MEDIO | Modelo de Probabilidad Fair Value |
| :---: | :---- |
|  | Calcular la probabilidad justa de cada evento usando modelos estadisticos propios y fuentes externas. Ejecutar cuando la divergencia entre el fair\_value calculado y el precio actual supera el 5%. La ventaja competitiva es la calidad del modelo estadistico interno. |
|  | **Grupo:** Grupo 4 — IA y Automatizacion Avanzada   |   **Modulo:** pma\_full\_logic\_oracle \+ market\_snapshots — Fase 2 |

| PILAR 1  —  GESTION DE RIESGO Y POSITION SIZING |  |
| :---- | :---- |
| **Kelly Criterion** | f\* \= (p\_modelo \- p\_mercado) / (1 \- p\_mercado) si el modelo dice que el evento es mas probable f\_real \= f\* x 0.25 (incertidumbre del modelo propio) Ejemplo: modelo dice 65%, mercado dice 50% \=\> f\*=0.30 \=\> f\_real=0.075 |
| **Limite Exposicion** | Maximo 10% del bankroll por posicion de fair value Bankroll $10,000 \=\> max $1,000 por divergencia detectada Maximo 5 divergencias simultaneas: 50% del bankroll (portfolio de fair value) |
| **Control Slippage** | No es critico el tiempo de ejecucion (divergencia suele durar horas/dias) Usar ordenes limit al precio de entrada calculado por el modelo Nunca usar market orders para esta estrategia: el spread puede consumir la ventaja |

| PILAR 2  —  UMBRALES DE RENTABILIDAD NETA |  |
| :---- | :---- |
| **Costos Totales** | Gas Polygon: \~$0.02 | Fee Polymarket: 2% Costo del modelo: datos de fuentes externas (encuestas, APIs) \~$200/mes Hurdle Rate: \> 5% de divergencia para operar (absorbe fees \+ incertidumbre del modelo) |
| **Hurdle Rate** | Divergencia minima requerida: 5 puntos porcentuales Ejemplo: modelo=65%, mercado=50% \=\> divergencia=15pp \=\> OPERAR con plena conviccion Divergencia 5-8pp: OPERAR con tamano reducido (50% del Kelly) Divergencia \< 5pp: NO OPERAR (dentro del margen de error del modelo) |
| **Ejemplo Neto** | Compra YES a 50% (precio mercado) | Fair Value del modelo: 65% Si el modelo es correcto y el mercado converge: ganancia 30% sobre capital invertido |

| PILAR 3  —  VENTANA DE TIEMPO Y CADUCIDAD |  |
| :---- | :---- |
| **Cercanía al Cierre** | La estrategia tiene horizonte de tiempo mas largo que el arbitraje puro Ideal: mercados con 7-30 dias al cierre para que el mercado tenga tiempo de converger Mercados \< 7 dias: el modelo puede ser correcto pero el tiempo de convergencia es insuficiente |
| **TTL de la Señal** | Tiempo de vida de la senal: 24 horas (revaluar con datos frescos cada dia) Si la divergencia se reduce a \< 3pp al revaluar: salir de la posicion Si nuevos datos contradicen el modelo: actualizar el modelo y revaluar |
| **Drift de Precio** | La convergencia es gradual: monitorear si el precio de mercado se acerca al fair value Si el precio diverge mas (se aleja del fair value): aumentar la posicion con el mismo riesgo |

| PILAR 4  —  VALIDACION DE LA SEÑAL |  |
| :---- | :---- |
| **Confluencia** | Minimo 2 de 3: (A) Divergencia \> 5pp entre modelo y mercado (B) Al menos 2 fuentes externas independientes confirman el fair value del modelo (C) El volumen del mercado ha sido creciente en las ultimas 48h (mercado activo) |
| **Volumen / OI** | Volume\_24h \> $5,000 (mercado suficientemente liquido para que la convergencia ocurra) Open Interest \> $3,000 Si el mercado tiene volumen muy bajo: puede que el 'error' de precio persista eternamente |
| **Liquidez Falsa** | Verificar que el 'fair value' calculado no esta contaminado por datos desactualizados Actualizar el modelo con los datos mas recientes antes de calcular cada divergencia Si las fuentes externas discrepan entre si: no usar IA-03 hasta resolver la discrepancia |

| PILAR 5  —  PROTOCOLO DE SALIDA Y COBERTURA |  |
| :---- | :---- |
| **Cierre Objetivo** | Salida cuando el precio de mercado converge al fair value del modelo (dentro de 2pp) Objetivo: el mercado 'descubre' el precio correcto antes de la resolucion Si el precio converge: tomar ganancias y re-evaluar si hay nueva divergencia |
| **Stop-Loss** | Stop-loss conceptual: si el modelo era INCORRECTO y el precio se mueve en contra \> 10pp Ejemplo: modelo dice 65%, mercado en 50%. El mercado sube a 55%: el mercado empieza a validar el modelo. Pero si el mercado CAE a 40%: el modelo estaba equivocado \=\> salir Si el evento se resuelve en contra del modelo: aceptar la perdida y actualizar el modelo |
| **Hedging** | Hedge parcial: si el modelo dice 65% YES, comprar YES Y vender un poco de NO (70-30 split) Esto reduce el profit pero protege contra errores del modelo Alternativa: diversificar en 5+ divergencias de distinto mercado para reducir el riesgo del modelo individual |

| IA-04 RIESGO BAJO — ACTIVO EN PRODUCCION | Bot de Arbitraje Tipos 1-3 (Sistema Automatizado) |
| :---: | :---- |
|  | Implementacion automatizada en produccion de ARB-01, ARB-02 y ARB-03. El pma\_full detecta estas oportunidades. Para produccion real el ciclo debe bajar a cada 2 segundos via WebSocket. Capital dimension con Kelly Criterion y asyncio.gather() en \< 30ms. |
|  | **Grupo:** Grupo 4 — IA y Automatizacion Avanzada   |   **Modulo:** pma\_full\_arb\_engine — ACTIVO (detect\_type1/2/3()) |

| PILAR 1  —  GESTION DE RIESGO Y POSITION SIZING |  |
| :---- | :---- |
| **Kelly Criterion** | Kelly combinado para el portafolio de tipos 1/2/3: Tipo 1: Kelly x 0.25 (alta frecuencia, bajo riesgo individual) Tipo 2: Kelly x 0.20 (latencia 4-6s, mayor riesgo) Tipo 3: Kelly x 0.15 (multi-leg, mayor complejidad) Capital total del bot: max 25% del bankroll activo en operaciones simultaneas |
| **Limite Exposicion** | Tipo 1: max 8% bankroll | Tipo 2: max 7% bankroll | Tipo 3: max 5% bankroll El bot puede ejecutar hasta 5 operaciones simultaneas Limite de portafolio: max 3 Tipo 1 \+ 1 Tipo 2 \+ 1 Tipo 3 al mismo tiempo |
| **Control Slippage** | Configurar umbral de slippage diferente por tipo: Tipo 1: abortar si precio se mueve \> 0.3% | Tipo 2: \> 0.5% | Tipo 3: \> 0.4% por leg El bot verifica el slippage en tiempo real antes de firmar cada tx |

| PILAR 2  —  UMBRALES DE RENTABILIDAD NETA |  |
| :---- | :---- |
| **Costos Totales** | Gas Polygon: \~$0.02 (Tipo 1\) | \~$0.05 (Tipo 2\) | \~$0.05-$0.20 (Tipo 3 segun legs) Fee Polymarket: 2% sobre el profit de cada tipo Hurdle Rate por tipo: Tipo 1: 1.5% | Tipo 2: 2.0% | Tipo 3: 3.0% El bot filtra automaticamente oportunidades bajo el hurdle rate correspondiente |
| **Hurdle Rate** | Configuracion del bot: MIN\_PROFIT\_THRESHOLD \= 0.005 (actual en pma\_full) Upgrade recomendado para produccion real: ajustar a 0.015, 0.020, 0.030 por tipo El bot no ejecuta si profit\_neto \< hurdle\_rate del tipo correspondiente |
| **Ejemplo Neto** | Tipo 1 (50 oportunidades/dia x $500 promedio x 3% neto): $750/dia teorico En la practica con 87% de exito: $652/dia | 13% de fallos: \-$65 \=\> Neto: $587/dia |

| PILAR 3  —  VENTANA DE TIEMPO Y CADUCIDAD |  |
| :---- | :---- |
| **Cercanía al Cierre** | El bot aplica filtros de tiempo automaticamente segun el tipo: Tipo 1/2: mercado debe cerrar en \> 2h Tipo 3 NegRisk: mercado debe cerrar en \> 24h Configurar en arb\_engine/config.py: MIN\_HOURS\_TO\_CLOSE \= {'type1': 2, 'type2': 4, 'type3': 24} |
| **TTL de la Señal** | Tipo 1: TTL \= 5s | Tipo 2: TTL \= 10s | Tipo 3: TTL \= 15s Si la deteccion-a-ejecucion supera el TTL: descartar y esperar el proximo ciclo Upgrade critico: pasar de ciclo 5min a WebSocket en tiempo real para eliminar el TTL como limitante |
| **Drift de Precio** | El bot monitorea el drift de precios en tiempo real durante la ejecucion Si el precio se mueve mas del umbral de slippage durante el gather: rollback total |

| PILAR 4  —  VALIDACION DE LA SEÑAL |  |
| :---- | :---- |
| **Confluencia** | El bot aplica automaticamente la confluencia del pma\_full: (A) arb\_detector confirma la oportunidad del tipo correspondiente (B) VWAP calculator valida la profundidad del libro (C) Bregman optimizer da el score boost (si KL \< 0.05: \+15pts al score) Solo ejecutar si score \> 50 (configurable en arb\_engine/config.py) |
| **Volumen / OI** | Filtro de volumen minimo en el bot: Volumen\_24h minimo del mercado: $5,000 book\_depth minimo por lado: $200 Estos parametros estan en arb\_engine/config.py como MIN\_VOLUME y MIN\_BOOK\_DEPTH |
| **Liquidez Falsa** | El VWAP calculator es el filtro de liquidez falsa del sistema Si el VWAP es significativamente peor que el best price \=\> hay liquidez falsa \=\> rechazar El bot ya implementa este check en vwap\_calculator.py |

| PILAR 5  —  PROTOCOLO DE SALIDA Y COBERTURA |  |
| :---- | :---- |
| **Cierre Objetivo** | Tipo 1: salida natural (tokens a $1.00 en resolucion) Tipo 2: salida activa (ventas post-minteo en \< 500ms) Tipo 3: salida natural (condicion ganadora paga $1.00) El bot gestiona las salidas automaticamente segun el tipo |
| **Stop-Loss** | Tipo 1: si una pierna falla en el gather \=\> cancelar la otra en \< 100ms Tipo 2: si el minteo tarda \> 8s \=\> gestion manual del set Tipo 3: si alguna condicion falla \=\> cancelar todas las piernas restantes Registrar todos los fallos en la DB para analisis de errores |
| **Hedging** | Todos los tipos usan asyncio.gather() para ejecucion simultanea de piernas El hedge esta integrado en la estructura del arbitraje (las piernas son mutuamente cobertura) El alert\_manager registra cada oportunidad y su resultado para ajuste de parametros |

| IA-05 RIESGO ALTO — Capital \> $500k | Deteccion de Dependencias LLM \+ IP Solver |
| :---: | :---- |
|  | Pipeline de 3 fases: heuristica NLP, LLM DeepSeek-R1-Distill-Qwen-32B y verificacion con PuLP/CBC. Detecta dependencias logicas entre mercados distintos para arbitraje combinatorio. Limitacion critica: latencia 15-35s vs ventana \~200ms. |
|  | **Grupo:** Grupo 4 — IA y Automatizacion Avanzada   |   **Modulo:** pma\_full\_logic\_oracle \+ ip\_solver \+ LLM (Fase 2 pendiente) |

| PILAR 1  —  GESTION DE RIESGO Y POSITION SIZING |  |
| :---- | :---- |
| **Kelly Criterion** | Kelly del portafolio de dependencias (no por dependencia individual) f\_real \= 0.10 (45% tasa de exito, capital alto requerido, latencia critica) Capital minimo para que el ROI absoluto justifique la infraestructura: $500,000 Cada dependencia activa: max 3% del bankroll |
| **Limite Exposicion** | Maximo 15% del bankroll total en posiciones de dependencias activas simultaneamente Bankroll $500,000 \=\> max $75,000 distribuido en max 5 dependencias ($15,000 c/u) Nunca acumular mas dependencias de las que el IP Solver puede verificar en tiempo real |
| **Control Slippage** | Con capital de $15,000 por dependencia: usar ordenes limit obligatoriamente Estimar el impacto de la orden en ambos mercados (A y B) antes de ejecutar Si el impacto combinado en ambos mercados \> 2% \=\> reducir tamano al 50% |

| PILAR 2  —  UMBRALES DE RENTABILIDAD NETA |  |
| :---- | :---- |
| **Costos Totales** | Gas Polygon: \~$0.04 (2 mercados) | Fee: 2% por pierna Infraestructura LLM: \~$500/mes | IP Solver (Gurobi licencia): \~$1,000/mes Total infra: \~$1,500/mes \=\> necesitar \>= $75,000 de ganancia mensual para justificarlo Hurdle Rate: 5% neto por dependencia ($750 minimo en una dependencia de $15,000) |
| **Hurdle Rate** | Con capital $500,000 al 45% de exito y 5% neto: Ganancia esperada: $500,000 x 15% (expuesto) x 45% x 5% \= $1,687/ciclo de dependencias Objetivo mensual: \> $1,500/mes neto para cubrir infraestructura If neto \< infra cost por 3 meses consecutivos \=\> discontinuar IA-05 |
| **Ejemplo Neto** | Dependencia activa: Market A en 30%, Market B en 80%. Logicamente A IMPLIES B Compra YES en A ($15,000 @ $0.30) \+ Venta YES en B (short si la plataforma lo permite) Si A converge a 45% \=\> \+50% en la pierna A de $15,000 \=\> \+$7,500 bruto |

| PILAR 3  —  VENTANA DE TIEMPO Y CADUCIDAD |  |
| :---- | :---- |
| **Cercanía al Cierre** | Ambos mercados deben cerrar en \> 7 dias y con menos de 30 dias de diferencia entre si Evitar dependencias donde los mercados tienen fechas de cierre muy distintas La latencia de 15-35s solo es aceptable en dependencias estructurales (horas de duracion) |
| **TTL de la Señal** | La latencia de 15-35s hace que el TTL de senal sea diferente: no segundos sino minutos Solo actuar en dependencias que llevan \> 60 minutos activas (no flashes) Reevaluar la dependencia cada 15 minutos con el pipeline completo |
| **Drift de Precio** | La oportunidad es estructural (horas/dias), no de alta frecuencia Si la dependencia desaparece en \< 60 min: era un flash \=\> excluir ese tipo de pares del modelo |

| PILAR 4  —  VALIDACION DE LA SEÑAL |  |
| :---- | :---- |
| **Confluencia** | Minimo 3 de 4 para ejecutar: (A) Fase 1 NLP: heuristica encuentra el par como candidato con score \> 0.6 (B) Fase 2 LLM: DeepSeek-R1 confidence \> 80% en la dependencia logica (C) Fase 3 IP Solver: PuLP/CBC verifica profit \> 5% neto (D) La dependencia ha persistido por \> 2 horas en los datos historicos |
| **Volumen / OI** | Volumen\_24h de ambos mercados (A y B) \>= $10,000 individualmente Open Interest combinado \>= $50,000 Rechazar si alguno de los dos mercados tiene volumen \< $5,000 |
| **Liquidez Falsa** | El IP Solver debe correr con datos en tiempo real, nunca cached Verificar manualmente las primeras 10 dependencias detectadas por el LLM para calibrar el modelo Documentar en la DB el resultado de cada dependencia para mejorar el modelo LLM iterativamente |

| PILAR 5  —  PROTOCOLO DE SALIDA Y COBERTURA |  |
| :---- | :---- |
| **Cierre Objetivo** | Salida cuando la dependencia logica se corrige (precios convergen al equilibrio) Objetivo de precio: el IP Solver calcula el precio de equilibrio como target Monitorear convergencia cada 15 minutos |
| **Stop-Loss** | Stop por rotura de dependencia: si el evento que funda la dependencia se resuelve inesperadamente Umbral de precio: si alguna pierna se mueve \> 15% en contra \=\> cerrar toda la posicion Stop de tiempo: si la dependencia persiste sin convergir por \> 7 dias \=\> salir con lo que queda Stop de modelo: si el LLM tiene 3 dependencias wrongas consecutivas \=\> revision manual del modelo |
| **Hedging** | Las dos piernas (compra en A, posicion en B) son el hedge mutuo Ambas piernas deben ejecutarse en \< 5s entre si para neutralizar el riesgo direccional Si solo se puede ejecutar una pierna: NO ejecutar la operacion completa Usar ordenes limit pre-configuradas en ambos mercados antes de trigger |

| IA-06 RIESGO BAJO — CAPA TRANSVERSAL ACTIVA | Optimizacion Matematica Bregman \+ Frank-Wolfe |
| :---: | :---- |
|  | Capa transversal que calcula el tamano optimo de cada posicion para TODAS las estrategias. Bregman minimiza la KL-divergence entre precios actuales y el politopo marginal. Frank-Wolfe reduce la complejidad de O(2^n) a O(1/epsilon\*t). Se aplica sobre cualquier oportunidad detectada. |
|  | **Grupo:** Grupo 4 — IA y Automatizacion Avanzada   |   **Modulo:** pma\_full\_optimizer — ACTIVO EN PRODUCCION |

| PILAR 1  —  GESTION DE RIESGO Y POSITION SIZING |  |
| :---- | :---- |
| **Kelly Criterion** | IA-06 NO reemplaza a Kelly: lo COMPLEMENTA y OPTIMIZA Flujo: Kelly calcula f\* \=\> IA-06 ajusta f\_optimo via Bregman f\_optimo \= argmin D\_KL(f\_kelly || distribucion\_precios\_actual) El resultado es un tamano de posicion coherente con el mercado completo |
| **Limite Exposicion** | IA-06 aplica el 'Score Boost' al capital calculado por otras estrategias: Si KL-divergence \< 0.01: boost de score \+15 pts \=\> aumentar exposicion en 20% Si KL-divergence 0.01-0.05: boost \+10 pts \=\> aumentar en 10% Si KL-divergence 0.05-0.10: boost \+5 pts \=\> mantener exposicion calculada Si KL-divergence \> 0.10: sin boost \=\> respetar el Kelly base sin ajuste |
| **Control Slippage** | Bregman calcula el precio de equilibrio matematico: si el precio actual difiere much del equilibrio Bregman, el slippage esperado es mayor IA-06 cuantifica el slippage esperado y lo incluye en el calculo de tamano optimo |

| PILAR 2  —  UMBRALES DE RENTABILIDAD NETA |  |
| :---- | :---- |
| **Costos Totales** | IA-06 no tiene costo de transaccion propio (es una capa de calculo, no de ejecucion) Costo de infraestructura: procesamiento de Bregman \+ Frank-Wolfe \< $50/mes (CPU) El beneficio de IA-06: reduce el numero de operaciones mal dimensionadas \=\> ahorra fees Hurdle de IA-06: cualquier reduccion de perdidas \> $50/mes en el portafolio justifica su uso |
| **Hurdle Rate** | IA-06 se evalua por su impacto en el portafolio total, no por operacion individual Metrica de exito: reduccion del drawdown maximo del portafolio en \> 15% Aumento del Sharpe Ratio del portafolio en \> 10% respecto a Kelly simple KL-divergence promedio mantenida \< 0.05 en el 80% de las operaciones |
| **Ejemplo Neto** | Sin IA-06: portafolio con Kelly simple, drawdown maximo 20% Con IA-06: mismo portafolio con Bregman-ajustado, drawdown maximo \~15% Reduccion de drawdown de 5pp en portafolio de $100,000 \=\> ahorro de $5,000 en perdidas |

| PILAR 3  —  VENTANA DE TIEMPO Y CADUCIDAD |  |
| :---- | :---- |
| **Cercanía al Cierre** | IA-06 ajusta automaticamente el calculo segun la cercanía al cierre del mercado Mercado \> 7 dias: Bregman converge con iteraciones normales (15-30 iter) Mercado 1-7 dias: Bregman usa menos iteraciones (5-10) para velocidad Mercado \< 24h: usar el calculo de Frank-Wolfe rapido (\< 10ms) en lugar de Bregman completo |
| **TTL de la Señal** | IA-06 se ejecuta en \< 100ms: siempre tiene tiempo antes de cualquier ejecucion Se recalcula cada vez que una nueva oportunidad es detectada Frecuencia de ciclo: 5 minutos (igual que el arb\_engine) Upgrade: calcular en tiempo real en el mismo thread de deteccion |
| **Drift de Precio** | Si el mercado cambia rapidamente: IA-06 recalcula en el siguiente ciclo de 5 min Si el KL-divergence cambia drasticamente entre ciclos: alerta para revision manual |

| PILAR 4  —  VALIDACION DE LA SEÑAL |  |
| :---- | :---- |
| **Confluencia** | IA-06 NO valida senales por si mismo: es una capa de calculo Se activa automaticamente para toda oportunidad que pasa los filtros de confluencia de la estrategia que la origino (ARB-01 a TRADE-02) Solo el score boost actua como validacion adicional: KL alto \=\> menor confianza \=\> menor tamano |
| **Volumen / OI** | IA-06 incluye la liquidez en el calculo del politopo marginal Mercados con bajo volumen tienen un politopo mas 'inestable' \=\> KL-divergence mas alta Esto automaticamente reduce el tamano de posicion en mercados iliquidos |
| **Liquidez Falsa** | Bregman naturalmente identifica precios inconsistentes con el mercado global Si el precio detectado es un outlier vs el politopo marginal: KL \> 0.10 \=\> score sin boost Esto sirve como filtro automatico de liquidez falsa y datos erroneos |

| PILAR 5  —  PROTOCOLO DE SALIDA Y COBERTURA |  |
| :---- | :---- |
| **Cierre Objetivo** | IA-06 calcula el precio de eficiencia (equilibrio Bregman) como target de salida Cuando el precio del mercado converge al precio de equilibrio Bregman: la oportunidad desaparecio Este target se comunica a la estrategia origen (ARB, MINT, TRADE) para su salida automatica |
| **Stop-Loss** | IA-06 no tiene stop-loss propio: actua como calculador del stop-loss optimo para otras estrategias Formula: stop\_loss\_optimo \= precio\_entrada \- (KL\_divergence x precio\_entrada x factor\_riesgo) Este stop-loss calculado se pasa al alert\_manager para configuracion automatica |
| **Hedging** | IA-06 calcula el hedge optimo para posiciones cross-market Usando Bregman: encuentra la combinacion de posiciones que minimiza el riesgo total del portafolio En mercados NegRisk: Frank-Wolfe reduce los 2^n outcomes posibles a combinaciones manejables para calcular el hedge optimo sin enumerar todas las combinaciones |

