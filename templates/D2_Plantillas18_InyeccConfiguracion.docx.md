

**POLYMARKET**

**18 PLANTILLAS DE ESTRATEGIA PARA AGENTES IA**

*Arquitectura de Inyeccion de Configuracion | 5 Pilares | 3 Familias de Logica*

Documentos integrados: Catalogo18 | Parametros\_Usuario | Arquitectura\_Inyeccion | Manual\_Arquitectura\_General

Version 2.0 para Desarrolladores | Proyect\_Moni\_Arbitration\_Full | Marzo 2026

| FAMILIA A Arbitraje Puro ARB-01/02/03/04/05 · IA-04 Motor: asyncio | Pilar 3 Critico | FAMILIA B Correlacion y Dependencia ARB-05 · IA-01/02/05 · TRADE-02 Motor: Grafo de Mercados | FAMILIA C Optimizacion Estadistica MINT-01..06 · IA-03/06 Motor: Bregman | Pilar 4 Estricto |
| :---: | :---: | :---: |

ARB-01 · ARB-02 · ARB-03 · ARB-04 · ARB-05 · MINT-01 · MINT-02 · MINT-03 · MINT-04 · MINT-05 · MINT-06 · TRADE-02 · IA-01 · IA-02 · IA-03 · IA-04 · IA-05 · IA-06

# **PARTE I — ARQUITECTURA GENERAL DEL SISTEMA**

Este documento integra las 18 Plantillas de Estrategia con la Arquitectura de Inyeccion de Configuracion, los Parametros de Usuario y el Manual de Arquitectura General. El objetivo es que el desarrollador disponga de una guia completa y accionable para implementar el sistema de agentes IA.

## **1\. Separacion de Capas (Core vs. Config)**

El sistema se divide en dos capas de codigo que nunca se mezclan. Esta es la regla fundamental de la arquitectura:

| CAPA INMUTABLE — Logica de Estrategia strategy\_engine.py Algoritmo Bregman Projections Formulas Cross-Market Arbitrage Calculo de Normal Arbitrage (T1/T2/T3) Kelly Criterion (funcion matematica pura) VWAP Calculator IP Solver (PuLP/CBC) Frank-Wolfe Optimizer NO cambia segun el usuario — jamas. | CAPA MUTABLE — Perfil de Usuario user\_profile.json strategy\_id (cual de las 18 plantillas) market\_context (categoria, volumen minimo) pilar\_1\_risk (kelly\_fraction, max\_position\_size) pilar\_2\_yield (min\_net\_profit\_pct, hurdle\_rate) pilar\_3\_time (ttl\_sec, max\_latency\_ms) pilar\_4\_logic (confluencia, bregman\_min) pilar\_5\_exit (stop\_loss, target\_exit, hedge\_mode) El agente lee esto antes de CADA tick de mercado. |
| :---- | :---- |

## **2\. Objeto Base de Estrategia en Python**

Todas las 18 plantillas heredan de este objeto. Los 5 Pilares son parametros de entrada OBLIGATORIOS — sin ellos el agente no arranca.

| DEV | \# strategy\_base.py — Objeto Base (Inmutable) class BaseStrategy:     def \_\_init\_\_(self, user\_profile: dict, market\_engine, math\_lib):         self.\_validate\_profile(user\_profile)   \# Falla si faltan pilares         self.risk   \= user\_profile\['pilar\_1\_risk'\]         self.yield\_ \= user\_profile\['pilar\_2\_yield'\]         self.time\_  \= user\_profile\['pilar\_3\_time'\]         self.logic  \= user\_profile\['pilar\_4\_logic'\]         self.exit\_  \= user\_profile\['pilar\_5\_exit'\]         self.engine \= market\_engine         self.math   \= math\_lib   \# Bregman, VWAP, Kelly, etc.     def calculate\_size(self, balance: float) \-\> float:         kelly \= self.math.kelly(self.risk\['kelly\_fraction'\], ...)         return min(kelly, self.risk\['max\_position\_size\_usd'\])     def check\_profit(self, gross: float, fees: float) \-\> bool:         net \= gross \- fees         return net \>= self.yield\_\['min\_net\_profit\_pct'\]     def is\_signal\_alive(self, detected\_at: float) \-\> bool:         return (time.time() \- detected\_at) \<= self.time\_\['execution\_ttl\_sec'\]     def validate\_confluence(self, signals: list) \-\> bool:         return sum(signals) \>= self.logic\['required\_confluence\_count'\]     def should\_exit(self, pnl\_pct: float, bregman\_eq: bool) \-\> str:         if pnl\_pct \<= \-self.exit\_\['stop\_loss\_pct'\]: return 'STOP\_LOSS'         if bregman\_eq and self.exit\_\['target\_exit'\]=='equilibrium': return 'TAKE\_PROFIT'         return 'HOLD'     \# Las 18 plantillas sobreescriben este metodo:     def execute(self, opportunity): raise NotImplementedError |
| :---: | :---- |

## **3\. Las 3 Familias de Logica**

En lugar de 18 implementaciones independientes, el desarrollador construye 3 motores de logica y 18 configuraciones de parametros. Esto reduce drasticamente la complejidad de mantenimiento.

| FAMILIA A Arbitraje Puro ARB-01  ARB-02  ARB-03ARB-04  ARB-05  IA-04 Foco: VELOCIDAD y calculo de comisiones. Priorizar Pilar 3 (Latencia). Motor: asyncio.gather(). | FAMILIA B Correlacion y Dependencia IA-02  IA-03  IA-05ARB-05  TRADE-02 Foco: GRAFO DE MERCADOS. Si A cambia, re-evaluar B inmediatamente. Motor: dependency\_graph. | FAMILIA C Optimizacion Estadistica IA-06  IA-01MINT-01..06  IA-03 Foco: PRECISION MATEMATICA. Pilar 4 muy estricto. Motor: bregman\_projector \+ frank\_wolfe. |
| :---- | :---- | :---- |

## **4\. Ciclo de Ejecucion del Agente (por tick de mercado)**

El desarrollador debe implementar este ciclo exacto. El agente es 'ciego' a los datos hasta que el usuario define el mercado y el perfil de riesgo.

| PASO 1 — Ingesta | Recibe mercados filtrados por volumen desde Proyect\_Moni (Polymarket/Kalshi). Solo mercados activos con volumen \>= min\_volume\_threshold del perfil del usuario. collector.get\_active\_markets(category, min\_vol=profile\['market\_context'\]\['min\_volume\_threshold'\]) |
| :---- | :---- |
| **PASO 2 — Mapeo** | Identifica si el mercado es del tipo seleccionado por el usuario. if market.category \!= profile\['market\_context'\]\['category'\]: continue Carga los market\_ids y el diccionario de dependencias logicas de la categoria. |
| **PASO 3 — Evaluacion** | Cruza los datos del mercado con la Logica de la Estrategia elegida (la plantilla). opportunity \= strategy.detect(market\_data)   \# Funcion de la plantilla if not opportunity: continue   \# No hay oportunidad en este tick |
| **PASO 4 — Validacion 5 Pilares** | Verifica secuencialmente si la oportunidad pasa los 5 filtros del usuario: if not strategy.calculate\_size(balance) \> 0: ABORT (Pilar 1\) if not strategy.check\_profit(gross, fees): ABORT (Pilar 2\) if not strategy.is\_signal\_alive(detected\_at): ABORT (Pilar 3\) if not strategy.validate\_confluence(signals): ABORT (Pilar 4\) \=\> Solo si los 4 pasan: proceder a la ejecucion |
| **PASO 5 — Ejecucion** | Si todo es TRUE: lanzar la orden a la API de Polymarket o Kalshi. order \= strategy.execute(opportunity, size=calculated\_size) Monitorear la posicion abierta con should\_exit() en cada tick posterior. Registrar el resultado en DB para mejora continua de los parametros. |

## **5\. Esquema Maestro JSON (Plantilla Maestra)**

Cada una de las 18 plantillas sigue este esquema. Los valores entre \<\> son los que el usuario configura. Los valores fijos son los que el desarrollador programa en el motor de la estrategia.

| {   "strategy\_id": "ST\_XXX\_NOMBRE\_ESTRATEGIA",   "familia": "A | B | C",   "market\_context": {     "category": "\<NBA | Crypto | Politica | Economia | Sports | ...\>",     "min\_volume\_threshold": \<numero\_en\_USD\>,     "market\_expiry\_min\_hours": \<horas\_minimas\_antes\_del\_cierre\>   },   "user\_parameters": {     "pilar\_1\_risk": {       "kelly\_fraction": \<0.10 \- 0.25 segun estrategia\>,       "max\_position\_size\_usd": \<techo\_en\_USD\_absoluto\>,       "max\_bankroll\_pct": \<porcentaje\_max\_del\_balance\>     },     "pilar\_2\_yield": {       "min\_net\_profit\_pct": \<profit\_minimo\_neto\_como\_decimal\>,       "include\_gas\_fees": true,       "hurdle\_rate\_usd": \<minimo\_en\_USD\_para\_cubrir\_gas\>     },     "pilar\_3\_time": {       "execution\_ttl\_sec": \<segundos\_de\_vida\_de\_la\_senal\>,       "max\_latency\_ms": \<latencia\_maxima\_aceptable\>     },     "pilar\_4\_logic": {       "required\_confluence\_count": \<numero\_minimo\_de\_señales\_coincidentes\>,       "bregman\_deviation\_min": \<divergencia\_KL\_minima\>     },     "pilar\_5\_exit": {       "stop\_loss\_pct": \<porcentaje\_de\_perdida\_maxima\>,       "target\_exit": "\<equilibrium | price\_target | time\_based\>",       "hedge\_mode": "\<simultaneous | sequential | natural\>"     }   } } |
| :---- |

## **6\. Instrucciones de Implementacion por Pilar**

| PILAR 1 — calculate\_size(): Logica del Desarrollador |  |
| ----- | :---- |
| **DEV** | def calculate\_size(balance: float, profile: dict) \-\> float:     p1 \= profile\['pilar\_1\_risk'\]     kelly\_capital \= math\_lib.kelly(         fraction \= p1\['kelly\_fraction'\],         edge     \= opportunity.gross\_profit,         odds     \= opportunity.payout\_ratio     )     pct\_capital \= balance \* p1\['max\_bankroll\_pct'\]     \# Regla: el menor entre Kelly, porcentaje del balance y techo absoluto     return min(kelly\_capital, pct\_capital, p1\['max\_position\_size\_usd'\]) |
| **USER** | El usuario configura: kelly\_fraction (conservador: 0.10-0.25), max\_position\_size\_usd (ej. $500), max\_bankroll\_pct (ej. 0.08 \= 8%) El agente NUNCA enviara una orden que supere el max\_position\_size\_usd, sin importar que tan buena sea la oportunidad. |

| PILAR 2 — check\_profit(): Logica del Desarrollador |  |
| ----- | :---- |
| **DEV** | def check\_profit(gross: float, gas: float, spread: float, profile: dict) \-\> bool:     p2 \= profile\['pilar\_2\_yield'\]     net \= gross \- gas \- spread if p2\['include\_gas\_fees'\] else gross     if net \< p2\['min\_net\_profit\_pct'\]:         logger.info(f'ABORT: net {net:.4f} \< hurdle {p2\["min\_net\_profit\_pct"\]}')         return False   \# La funcion retorna FALSE: abortar la operacion     if (net \* position\_size) \< p2\['hurdle\_rate\_usd'\]:         return False   \# En terminos absolutos tampoco cubre el umbral     return True |
| **USER** | El usuario configura: min\_net\_profit\_pct (ej. 0.02 \= 2.0%). El agente filtrara oportunidades de 1.8% aunque sean positivas. hurdle\_rate\_usd: si el beneficio absoluto no cubre este minimo en USD, la operacion se descarta. |

| PILAR 3 — is\_signal\_alive() y check\_expiry(): Logica del Desarrollador |  |
| ----- | :---- |
| **DEV** | def is\_signal\_alive(detected\_at: float, profile: dict) \-\> bool:     elapsed \= time.time() \- detected\_at     if elapsed \> profile\['pilar\_3\_time'\]\['execution\_ttl\_sec'\]:         logger.warning(f'SIGNAL EXPIRED: {elapsed:.2f}s \> TTL')         return False     return True def check\_market\_expiry(market\_close\_ts: float, profile: dict) \-\> bool:     hours\_remaining \= (market\_close\_ts \- time.time()) / 3600     return hours\_remaining \>= profile\['market\_context'\]\['market\_expiry\_min\_hours'\] |
| **USER** | El usuario configura: execution\_ttl\_sec (ej. 5s para ARB, 60s para dependencias estructurales). market\_expiry\_min\_hours: si una discrepancia de precios en BTC dura mas de 5s sin ejecutarse, el agente la descarta. |

| PILAR 4 — validate\_confluence() y check\_bregman(): Logica del Desarrollador |  |
| ----- | :---- |
| **DEV** | def validate\_confluence(signals: list\[bool\], profile: dict) \-\> bool:     \# signals \= \[arb\_detected, bregman\_confirms, vwap\_confirms, volume\_ok, ...\]     count \= sum(signals)     required \= profile\['pilar\_4\_logic'\]\['required\_confluence\_count'\]     return count \>= required def check\_bregman(kl\_divergence: float, profile: dict) \-\> bool:     min\_dev \= profile\['pilar\_4\_logic'\]\['bregman\_deviation\_min'\]     \# Solo activa la senal si la divergencia KL supera el minimo configurado     return kl\_divergence \>= min\_dev |
| **USER** | El usuario configura: required\_confluence\_count (ej. 2 \= requiere que Bregman Y Logic Dependencies coincidan). Si solo hay arbitraje pero Bregman dice que el mercado es eficiente (KL bajo), el agente espera. |

| PILAR 5 — should\_exit() y hedge\_executor(): Logica del Desarrollador |  |
| ----- | :---- |
| **DEV** | def should\_exit(pnl\_pct: float, bregman\_eq: bool, profile: dict) \-\> str:     p5 \= profile\['pilar\_5\_exit'\]     if pnl\_pct \<= \-p5\['stop\_loss\_pct'\]: return 'STOP\_LOSS'     if p5\['target\_exit'\] \== 'equilibrium' and bregman\_eq: return 'TAKE\_PROFIT'     if p5\['target\_exit'\] \== 'price\_target' and price \>= target\_price: return 'TAKE\_PROFIT'     return 'HOLD' def hedge\_executor(opportunity, hedge\_mode: str):     if hedge\_mode \== 'simultaneous':         asyncio.gather(\*opportunity.legs)   \# ARB-01/02/03     elif hedge\_mode \== 'natural':         \# El minteo YES+NO \= $1.00 es el hedge natural         execute\_mint\_and\_hold(opportunity) |
| **USER** | El usuario configura: stop\_loss\_pct (ej. 0.05 \= \-5%), target\_exit ('equilibrium' \= salida al precio de equilibrio Bregman). hedge\_mode: 'simultaneous' para ARB, 'natural' para MINT, 'sequential' para dependencias estructurales. |

## **7\. Interfaz de Seleccion de Mercado**

El desarrollador debe implementar un selector de mercado que conecte con Proyect\_Moni. Al elegir la categoria, el agente carga automaticamente los market\_ids y el diccionario de dependencias logicas.

| DEV | \# market\_selector.py DEPENDENCY\_DICTIONARIES \= {     'NBA':     {'star\_injury': \['player\_health\_feed'\], 'home\_advantage': 0.05},     'Crypto':  {'btc\_oracle': 'chainlink\_feed', 'eth\_correlation': 0.82},     'Politica':{'implies\_rules': 'logic\_oracle\_db', 'negrisk\_markets': True},     'Economia':{'fed\_rate\_impact': 'fred\_api', 'treasury\_yield\_deps': True}, } def load\_market\_context(profile: dict, collector) \-\> dict:     cat \= profile\['market\_context'\]\['category'\]     min\_vol \= profile\['market\_context'\]\['min\_volume\_threshold'\]     market\_ids \= collector.get\_active\_markets(category=cat, min\_vol=min\_vol)     dep\_dict   \= DEPENDENCY\_DICTIONARIES.get(cat, {})     return {'market\_ids': market\_ids, 'dep\_dict': dep\_dict} |
| :---: | :---- |
| **USER** | El usuario ve un menu: NBA | Crypto (BTC) | Politica | Economia | Sports | etc. Al elegir 'NBA', el agente carga solo mercados NBA con el volumen minimo configurado y ajusta sus dependencias logicas. |

## **8\. Ejemplo de Flujo Completo — Usuario operando NBA**

| Paso 1 — Seleccion | Usuario elige la Plantilla \#ARB-01 (Arbitraje Binario Compra) Mercado: NBA\_Games\_Today Sistema carga: mercados NBA activos con volumen \> $10,000 |
| :---- | :---- |
| **Paso 2 — Configuracion** | Usuario ajusta en el panel o .json:   kelly\_fraction \= 0.25   (conservador)   max\_position\_size\_usd \= 500   min\_net\_profit\_pct \= 0.015   (1.5%)   execution\_ttl\_sec \= 5   stop\_loss\_pct \= 0.05 |
| **Paso 3 — Activacion** | El agente arranca el ciclo de deteccion:   \-\> Escanea solo mercados NBA   \-\> Detecta YES \+ NO \< $1.00 en Lakers vs Warriors   \-\> Gross profit: 4.2% | Net profit: 3.1% \> 1.5% (Pilar 2 OK)   \-\> Signal alive: 1.8s \< 5s TTL (Pilar 3 OK)   \-\> Confluence: 2/3 señales (Pilar 4 OK)   \-\> Size: min(Kelly=$320, max\_pos=$500, 8%=$800) \= $320 |
| **Paso 4 — Ejecucion** | asyncio.gather(buy\_YES, buy\_NO) \< 30ms Orden enviada a Polymarket API Monitoreo: should\_exit() en cada tick siguiente Registro en DB: oportunidad, size, resultado |

| ARB-01 *A* 87% Tasa Exito | Arbitraje Binario Compra |
| :---: | :---- |
|  | *Comprar YES y NO cuando su suma es inferior a $1.00. El cobro de $1.00 esta garantizado independientemente del resultado.* |
|  | **Condicion:**  YES\_ask \+ NO\_ask  \<  $1.00 |
|  | **Familia:** Familia A — Arbitraje Puro   |   **Plataforma:** Polymarket/Kalshi   |   Cap. Min: $500   |   **Latencia:** \<30ms |

| 87% Tasa Exito | $5.9M Extraido | 5-20% ROI Tipico | \<30ms Latencia |
| :---: | :---: | :---: | :---: |

### **Configuracion JSON — Perfil de Usuario**

El desarrollador inyecta este JSON antes de cada operacion. El agente es 'ciego' a los datos del mercado hasta que este perfil este definido.

| {   "strategy\_id": "ST\_001\_BINARY\_ARB\_BUY",   "familia": "Familia A — Arbitraje Puro",   "market\_context": {     "category": "NBA|Crypto|Politica",     "min\_volume\_threshold": 5000,     "market\_expiry\_min\_hours": 2   },   "user\_parameters": {     "pilar\_1\_risk": {       "kelly\_fraction": 0.25,       "max\_position\_size\_usd": 800,       "max\_bankroll\_pct": 0.08     },     "pilar\_2\_yield": {       "min\_net\_profit\_pct": 0.015,       "include\_gas\_fees": true,       "hurdle\_rate\_usd": 0.1     },     "pilar\_3\_time": {       "execution\_ttl\_sec": 5,       "max\_latency\_ms": 30     },     "pilar\_4\_logic": {       "required\_confluence\_count": 2,       "bregman\_deviation\_min": 0.02     },     "pilar\_5\_exit": {       "stop\_loss\_pct": 0.03,       "target\_exit": "natural\_resolution",       "hedge\_mode": "simultaneous"     }   } } |
| :---- |

### **Los 5 Pilares — Logica del Desarrollador \+ Configuracion del Usuario**

| PILAR 1  —  GESTION DE RIESGO Y POSITION SIZING |  |
| :---- | :---- |
| **Kelly Criterion** | f\* \= (Profit\_bruto \- Fee\_total) / Profit\_bruto Kelly Fraccionado recomendado: 0.25 (valor default en JSON) Resultado final: min(kelly, max\_pos\_usd, bankroll x max\_bankroll\_pct) |
| **Limite de Exposicion** | max\_position\_size\_usd: $800 (configurable, techo absoluto) max\_bankroll\_pct: 8% del balance disponible El agente usa el MENOR de los tres calculos: Kelly vs techo vs porcentaje |
| **Control Slippage** | Abortar si YES\_ask o NO\_ask se mueven \> 0.3% entre deteccion y ejecucion Ventana de ejecucion: \< 30ms (max\_latency\_ms en JSON) Fallo documentado (13%): ejecucion parcial \=\> rollback total |

| PILAR 2  —  UMBRALES DE RENTABILIDAD NETA |  |
| :---- | :---- |
| **Costos** | Gas Polygon: \~$0.02 | Fee Polymarket: 2% sobre ganancia neta Formula: (1.00 \- YES\_ask \- NO\_ask) \- $0.02 \- 0.02\*ganancia\_bruta \> min\_net\_profit\_pct |
| **Hurdle Rate** | min\_net\_profit\_pct: 0.015 (1.5%) por defecto en JSON — configurable por usuario Ejemplo: YES=0.48, NO=0.47 \=\> bruto 5.26% \=\> neto \~3.0% \=\> OPERAR Si neto \< 1.5% o capital \< $100: gas supera ganancia \=\> check\_profit() retorna FALSE |
| **Ejemplo Neto** | Capital $1,000 | bruto $50 | Gas \-$0.02 | Fee \-$1.00 | Neto $48.98 \= 4.90% Caso extremo (paper): YES=0.02, NO=0.02 \=\> \+2,400% ROI |

| PILAR 3  —  VENTANA DE TIEMPO Y CADUCIDAD |  |
| :---- | :---- |
| **Cercania al Cierre** | execution\_ttl\_sec: 5 segundos (valor default — critico para Familia A) Si elapsed \> TTL: is\_signal\_alive() retorna FALSE \=\> senal descartada No reintentar: si la oportunidad expiro, nunca forzar la entrada |
| **Filtro de Expiracion** | market\_expiry\_min\_hours: 2h (mercado debe cerrar en \> 2h) Mercado cierra \< 1h: NO OPERAR (riesgo de manipulacion pre-cierre) check\_market\_expiry() valida esto en cada tick antes de la deteccion |
| **Upgrade de Ciclo** | Ciclo objetivo produccion: cada 2s via WebSocket ws://clob.polymarket.com/ws Ciclo actual (deteccion batch): cada 5 minutos — reducir es Fase 2 |

| PILAR 4  —  VALIDACION DE LA SENAL |  |
| :---- | :---- |
| **Confluencia (min. 2 de 3\)** | required\_confluence\_count: 2 (configurable en JSON) (A) Detector: YES\_ask \+ NO\_ask \< $0.985 (B) VWAP confirma profundidad \< $0.975 (C) Bregman KL-divergence \>= bregman\_deviation\_min (0.02 default) validate\_confluence(\[A,B,C\]) \>= 2 \=\> proceder |
| **Volumen y OI** | book\_depth\_YES \>= $500 Y book\_depth\_NO \>= $500 Volumen\_24h \>= min\_volume\_threshold del JSON Rechazar si bid-ask spread \> 3% (posible liquidez falsa) |
| **Liquidez Falsa** | Si best\_ask es orden unica \> 10x el promedio: LIQUIDEZ FALSA check\_bregman() filtra automaticamente precios outlier del politopo marginal |

| PILAR 5  —  PROTOCOLO DE SALIDA Y COBERTURA |  |
| :---- | :---- |
| **Cierre por Objetivo** | target\_exit: 'natural\_resolution' (tokens resueltos a $1.00) should\_exit() monitorea en cada tick post-ejecucion Verificar que el mercado no sea declarado VOID por la plataforma |
| **Stop-Loss** | stop\_loss\_pct: 0.03 (3%) en JSON — configurable Si una pierna falla en el gather: rollback total en \< 100ms Si YES\_ask \+ NO\_ask \> $1.00 durante ejecucion: ABORTAR |
| **Hedging** | hedge\_mode: 'simultaneous' \=\> asyncio.gather(buy\_YES, buy\_NO) Timeout por pierna: max\_latency\_ms (30ms). Superado: abortar AMBAS El par YES+NO \= $1.00 es el hedge natural garantizado |

### **Instruccion de Implementacion para el Desarrollador**

| DEV | \# ARB-01 hereda de BaseStrategy (Familia A — Arbitraje Puro) class ARB\_01\_Strategy(BaseStrategy):     def execute(self, opportunity):         size \= self.calculate\_size(self.balance)         if not self.check\_profit(opportunity.gross, opportunity.fees): return None         if not self.is\_signal\_alive(opportunity.detected\_at): return None         if not self.validate\_confluence(opportunity.signals): return None         \# Familia A: motor especifico de la familia         return self.math.asyncio\_gather(\*opportunity.legs, timeout\_ms=30)         return self.market\_engine.submit\_order(opportunity, size) |
| :---: | :---- |

| USER | Mercado: NBA|Crypto|Politica | Capital Minimo: $500 | Latencia: \<30ms Pilar 1: kelly\_fraction=0.25, max\_position\_size\_usd=800, max\_bankroll\_pct=0.08 Pilar 2: min\_net\_profit\_pct=0.015 (1.5%), hurdle\_rate\_usd=$0.1 Pilar 3: execution\_ttl\_sec=5, max\_latency\_ms=30 Pilar 4: required\_confluence\_count=2, bregman\_deviation\_min=0.02 Pilar 5: stop\_loss\_pct=0.03 (3%), target\_exit='natural\_resolution', hedge\_mode='simultaneous' |
| :---: | :---- |

| ARB-02 *A* 87% Tasa Exito | Arbitraje Binario Venta / Minteo |
| :---: | :---- |
|  | *Mintear 1 YES \+ 1 NO por $1.00 USDC via contrato CTF Gnosis (Polygon ERC1155) y vender ambos cuando su suma supera $1.00. La ganancia es el exceso. Mayor latencia por el paso de minteo.* |
|  | **Condicion:**  YES\_bid \+ NO\_bid  \>  $1.00   |   $1 USDC \=\> mint() \=\> 1 YES \+ 1 NO \=\> sell\_both() |
|  | **Familia:** Familia A — Arbitraje Puro   |   **Plataforma:** Polymarket   |   Cap. Min: $500   |   **Latencia:** 4-6s |

| 87% Tasa Exito | $4.7M Extraido | 5-20% ROI Tipico | 4-6s Latencia Minteo |
| :---: | :---: | :---: | :---: |

### **Configuracion JSON — Perfil de Usuario**

El desarrollador inyecta este JSON antes de cada operacion. El agente es 'ciego' a los datos del mercado hasta que este perfil este definido.

| {   "strategy\_id": "ST\_002\_BINARY\_ARB\_SELL",   "familia": "Familia A — Arbitraje Puro",   "market\_context": {     "category": "Polymarket/Crypto",     "min\_volume\_threshold": 3000,     "market\_expiry\_min\_hours": 4   },   "user\_parameters": {     "pilar\_1\_risk": {       "kelly\_fraction": 0.2,       "max\_position\_size\_usd": 700,       "max\_bankroll\_pct": 0.07     },     "pilar\_2\_yield": {       "min\_net\_profit\_pct": 0.02,       "include\_gas\_fees": true,       "hurdle\_rate\_usd": 0.2     },     "pilar\_3\_time": {       "execution\_ttl\_sec": 10,       "max\_latency\_ms": 6000     },     "pilar\_4\_logic": {       "required\_confluence\_count": 2,       "bregman\_deviation\_min": 0.05     },     "pilar\_5\_exit": {       "stop\_loss\_pct": 0.04,       "target\_exit": "immediate\_sell",       "hedge\_mode": "natural"     }   } } |
| :---- |

### **Los 5 Pilares — Logica del Desarrollador \+ Configuracion del Usuario**

| PILAR 1  —  GESTION DE RIESGO Y POSITION SIZING |  |
| :---- | :---- |
| **Kelly Criterion** | f\* \= (YES\_bid+NO\_bid-1.00-Fee) / (YES\_bid+NO\_bid-1.00) Kelly Fraccionado: 0.20 (mayor riesgo por latencia 4-6s) Capital bloqueado 4-6s durante minteo: computar este riesgo de inmovilizacion |
| **Limite de Exposicion** | max\_position\_size\_usd: $700 (menor que ARB-01 por latencia) Nunca acumular \> 2 operaciones ARB-02 simultaneas (capital bloqueado doble) max\_bankroll\_pct: 7% por operacion |
| **Control Slippage** | Si la orden de venta \> 20% del book\_bid: reducir al 50% Umbral de aborto: si YES\_bid+NO\_bid \< 1.03 al momento de vender \=\> mantener par max\_latency\_ms: 6000 (6s para cubrir el minteo en Polygon) |

| PILAR 2  —  UMBRALES DE RENTABILIDAD NETA |  |
| :---- | :---- |
| **Costos** | Gas: \~$0.05 (1 mint tx \+ 2 sell tx) | Fee: 2% por venta Contrato CTF Gnosis en Polygon (ERC1155): $1.00 USDC exacto por minteo |
| **Hurdle Rate** | min\_net\_profit\_pct: 0.020 (2.0%) — mayor que ARB-01 por riesgo de latencia Si profit bruto \< 3%: margen insuficiente para 4-6s de exposicion \=\> FALSE Ejemplo: YES=0.58, NO=0.55 \=\> bruto 13% \=\> neto \~10.6% \=\> OPERAR |
| **Ejemplo Neto** | Capital $1,000 | Gas \-$0.05 | Fee \-$22.60 | Neto $107.35 \= 10.7% Base tecnica de toda la estrategia de Market Making |

| PILAR 3  —  VENTANA DE TIEMPO Y CADUCIDAD |  |
| :---- | :---- |
| **TTL y Expiracion** | execution\_ttl\_sec: 10 segundos (doble de ARB-01 por latencia de minteo) Reconfirmar YES\_bid Y NO\_bid ANTES de firmar la tx de minteo Si cualquier precio cambio \> 0.5% desde deteccion: CANCELAR antes de mintear |
| **Expiracion del Mercado** | market\_expiry\_min\_hours: 4h (el mercado NO debe resolver durante los 4-6s de minteo) Mercado cierra \< 24h: NO OPERAR — los 4-6s del minteo son el riesgo critico |
| **Drift Durante Minteo** | Monitorear YES\_bid en tiempo real durante los 4-6s del proceso de minteo Si YES\_bid cae \> 1% durante el minteo: abortar ventas, mantener el par completo |

| PILAR 4  —  VALIDACION DE LA SENAL |  |
| :---- | :---- |
| **Confluencia (min. 2 de 3\)** | (A) YES\_bid \+ NO\_bid \> 1.02 (margen real para fees) (B) VWAP\_bid\_YES \+ VWAP\_bid\_NO \> $1.015 (C) Bregman KL-divergence \>= 0.05 (valida que el precio esta lejos del equilibrio) |
| **Liquidez Bid** | book\_depth\_bid\_YES \>= $300 Y book\_depth\_bid\_NO \>= $300 Verificar que bids no provienen de un unico actor (wash trading) Open Interest del mercado \>= $2,000 |
| **Orden Trampa** | Si una orden representa \> 60% del book\_bid: posible trampa \=\> RECHAZAR Verificar age de los bids: si son recientes (\< 30s) y de gran tamano \=\> sospechosos |

| PILAR 5  —  PROTOCOLO DE SALIDA Y COBERTURA |  |
| :---- | :---- |
| **Cierre por Objetivo** | target\_exit: 'immediate\_sell' \=\> vender en \< 500ms post-confirmacion del minteo asyncio.gather(sell\_YES, sell\_NO) inmediatamente tras confirmar el mint |
| **Stop-Loss** | Si minteo tarda \> 8s en confirmar: gestionar par manualmente (no vender a panico) Si post-minteo precios cayeron: mantener par hasta resolucion (par \= $1.00 garantizado) |
| **Hedging Natural** | hedge\_mode: 'natural' \=\> el par minteado (YES+NO \= $1.00) es el hedge automatico Si ventas no se completan: el par actua como cobertura hasta la resolucion del mercado |

### **Instruccion de Implementacion para el Desarrollador**

| DEV | \# ARB-02 hereda de BaseStrategy (Familia A — Arbitraje Puro) class ARB\_02\_Strategy(BaseStrategy):     def execute(self, opportunity):         size \= self.calculate\_size(self.balance)         if not self.check\_profit(opportunity.gross, opportunity.fees): return None         if not self.is\_signal\_alive(opportunity.detected\_at): return None         if not self.validate\_confluence(opportunity.signals): return None         \# Familia A: motor especifico de la familia         return self.math.asyncio\_gather(\*opportunity.legs, timeout\_ms=6000)         return self.market\_engine.submit\_order(opportunity, size) |
| :---: | :---- |

| USER | Mercado: Polymarket/Crypto | Capital Minimo: $500 | Latencia: 4-6s Pilar 1: kelly\_fraction=0.2, max\_position\_size\_usd=700, max\_bankroll\_pct=0.07 Pilar 2: min\_net\_profit\_pct=0.02 (2.0%), hurdle\_rate\_usd=$0.2 Pilar 3: execution\_ttl\_sec=10, max\_latency\_ms=6000 Pilar 4: required\_confluence\_count=2, bregman\_deviation\_min=0.05 Pilar 5: stop\_loss\_pct=0.04 (4%), target\_exit='immediate\_sell', hedge\_mode='natural' |
| :---: | :---- |

| ARB-03 *A* 60% Tasa Exito | NegRisk Compra Multi-condicion |
| :---: | :---- |
|  | *Comprar YES de TODAS las condiciones en mercados NegRisk cuando Suma(YES\_i) \< $1.00. Mayor extraccion absoluta del paper ($11.1M). Cuello de botella: la condicion mas iliquida.* |
|  | **Condicion:**  Suma(YES\_i)  \<  $1.00   \[mercado NegRisk — outcomes mutuamente excluyentes\] |
|  | **Familia:** Familia A — Arbitraje Puro   |   **Plataforma:** Polymarket   |   Cap. Min: $1,000   |   **Latencia:** 4-8s |

| 60% Tasa Exito | $11.1M Extraido | 10-30% ROI Tipico | \~42% Frec. NegRisk |
| :---: | :---: | :---: | :---: |

### **Configuracion JSON — Perfil de Usuario**

El desarrollador inyecta este JSON antes de cada operacion. El agente es 'ciego' a los datos del mercado hasta que este perfil este definido.

| {   "strategy\_id": "ST\_003\_NEGRISK\_BUY",   "familia": "Familia A — Arbitraje Puro",   "market\_context": {     "category": "NBA|Politica|Sports",     "min\_volume\_threshold": 10000,     "market\_expiry\_min\_hours": 24   },   "user\_parameters": {     "pilar\_1\_risk": {       "kelly\_fraction": 0.2,       "max\_position\_size\_usd": 500,       "max\_bankroll\_pct": 0.05     },     "pilar\_2\_yield": {       "min\_net\_profit\_pct": 0.03,       "include\_gas\_fees": true,       "hurdle\_rate\_usd": 0.5     },     "pilar\_3\_time": {       "execution\_ttl\_sec": 15,       "max\_latency\_ms": 8000     },     "pilar\_4\_logic": {       "required\_confluence\_count": 3,       "bregman\_deviation\_min": 0.08     },     "pilar\_5\_exit": {       "stop\_loss\_pct": 0.05,       "target\_exit": "natural\_resolution",       "hedge\_mode": "simultaneous"     }   } } |
| :---- |

### **Los 5 Pilares — Logica del Desarrollador \+ Configuracion del Usuario**

| PILAR 1  —  GESTION DE RIESGO Y POSITION SIZING |  |
| :---- | :---- |
| **Kelly Criterion** | f\* \= (1.00-Suma(YES\_i)-Fee) / (1.00-Suma(YES\_i)) Kelly Fraccionado: 0.20 | Capital por condicion: (f\_real x balance) / num\_condiciones Ejemplo PA: 5 condiciones, suma=0.80 \=\> capital $500 total \=\> $100 por condicion |
| **Limite de Exposicion** | max\_position\_size\_usd: $500 TOTAL para toda la operacion NegRisk max\_bankroll\_pct: 5% (menor por complejidad multi-leg) Capital real \= min(f\_real x balance, max\_pos, min(liq\_i para todo i)) |
| **Control Slippage** | Slippage por condicion: max 0.5% de movimiento por leg Si MIN(liq\_i) \< $200 para cualquier condicion: RECHAZAR toda la operacion Fallo documentado (48%): liquidez insuficiente en al menos 1 condicion |

| PILAR 2  —  UMBRALES DE RENTABILIDAD NETA |  |
| :---- | :---- |
| **Costos** | Gas: \~$0.05 x num\_condiciones | Fee: 2% por condicion La condicion menos liquida define el tamano maximo de toda la operacion |
| **Hurdle Rate** | min\_net\_profit\_pct: 0.030 (3.0%) — mayor complejidad justifica umbral mas alto Formula: (1.00-Suma(YES\_i)) \- Gas\_total \- Fee\_total \> 0.030 Ejemplo: suma=0.80 \=\> bruto 25% \=\> neto \~20% \=\> OPERAR |
| **Ejemplo Neto** | Capital $500, 5 condiciones (PA): neto \~23% | KPI: $350.75 ganancia neta Si MIN(liq\_i) \< $100: reducir capital \=\> el calculo escala proporcionalmente |

| PILAR 3  —  VENTANA DE TIEMPO Y CADUCIDAD |  |
| :---- | :---- |
| **TTL Multi-Leg** | execution\_ttl\_sec: 15 segundos (multi-leg requiere mas tiempo) Reconfirmar TODOS los YES\_i antes de cada compra individual Si cualquier condicion cambio \> 1%: CANCELAR toda la operacion |
| **Expiracion** | market\_expiry\_min\_hours: 24h — critico para multi-leg Mercado cierra \< 24h: NO OPERAR (riesgo de resolucion parcial durante ejecucion) |
| **Drift Multi-Leg** | Suma(YES\_i actualizados) debe seguir siendo \< $0.97 para rentabilidad Usar ordenes LIMIT (no market) para control de precio en cada condicion |

| PILAR 4  —  VALIDACION DE LA SENAL |  |
| :---- | :---- |
| **Confluencia (min. 3 de 4\)** | required\_confluence\_count: 3 (mas estricto por multi-leg) (A) Suma(YES\_i) \< $0.97 | (B) MIN(liq\_i) \>= $300 para TODAS (C) VWAP confirma suma \< $0.97 | (D) Bregman KL \>= 0.08 (gran desviacion multi-outcome) |
| **Volumen y OI** | TODAS las condiciones: volumen\_24h \> $1,000 individualmente Open Interest total del mercado NegRisk \>= $10,000 Rechazar si alguna condicion tiene 0 trades en las ultimas 2 horas |
| **Cuello de Botella** | La condicion menos liquida define la viabilidad de TODA la operacion VWAP sobre book\_depth estima liquidez real vs nominal del best price |

| PILAR 5  —  PROTOCOLO DE SALIDA Y COBERTURA |  |
| :---- | :---- |
| **Cierre por Objetivo** | target\_exit: 'natural\_resolution' \=\> condicion ganadora paga $1.00 should\_exit() verifica que Suma(YES\_i post-compra) no suba a \> $0.98 (arb desaparecio) |
| **Stop-Loss** | Si Suma(YES\_i) \> $0.98 post-compra: stop\_loss \=\> evaluar salida parcial Si condicion ganadora probable sube a \> 0.90 abruptamente: vender las demas |
| **Hedging Multi-Leg** | hedge\_mode: 'simultaneous' \=\> asyncio.gather(\*\[buy(c) for c in conditions\]) Si CUALQUIER compra falla: cancelar TODAS en \< 200ms NUNCA quedar con compras parciales: el hedge solo funciona completo |

### **Instruccion de Implementacion para el Desarrollador**

| DEV | \# ARB-03 hereda de BaseStrategy (Familia A — Arbitraje Puro) class ARB\_03\_Strategy(BaseStrategy):     def execute(self, opportunity):         size \= self.calculate\_size(self.balance)         if not self.check\_profit(opportunity.gross, opportunity.fees): return None         if not self.is\_signal\_alive(opportunity.detected\_at): return None         if not self.validate\_confluence(opportunity.signals): return None         \# Familia A: motor especifico de la familia         return self.math.asyncio\_gather(\*opportunity.legs, timeout\_ms=8000)         return self.market\_engine.submit\_order(opportunity, size) |
| :---: | :---- |

| USER | Mercado: NBA|Politica|Sports | Capital Minimo: $1,000 | Latencia: 4-8s Pilar 1: kelly\_fraction=0.2, max\_position\_size\_usd=500, max\_bankroll\_pct=0.05 Pilar 2: min\_net\_profit\_pct=0.03 (3.0%), hurdle\_rate\_usd=$0.5 Pilar 3: execution\_ttl\_sec=15, max\_latency\_ms=8000 Pilar 4: required\_confluence\_count=3, bregman\_deviation\_min=0.08 Pilar 5: stop\_loss\_pct=0.05 (5%), target\_exit='natural\_resolution', hedge\_mode='simultaneous' |
| :---: | :---- |

| ARB-04 *A* 60% Tasa Exito | NegRisk Venta Multi-condicion |
| :---: | :---- |
|  | *Mintear sets completos (1 token de cada condicion por $1.00) y vender todos los YES cuando Suma \> $1.00. Ocurre en solo \~5% de mercados NegRisk. Latencia 6-8s.* |
|  | **Condicion:**  Suma(YES\_i)  \>  $1.00   |   mint\_set() \=\> sell(YES\_i para todo i) en paralelo |
|  | **Familia:** Familia A — Arbitraje Puro   |   **Plataforma:** Polymarket   |   Cap. Min: $1,000   |   **Latencia:** 6-8s |

| 60% Tasa Exito | $0.6M Extraido | 10-20% ROI Tipico | \~5% Frec. NegRisk |
| :---: | :---: | :---: | :---: |

### **Configuracion JSON — Perfil de Usuario**

El desarrollador inyecta este JSON antes de cada operacion. El agente es 'ciego' a los datos del mercado hasta que este perfil este definido.

| {   "strategy\_id": "ST\_004\_NEGRISK\_SELL",   "familia": "Familia A — Arbitraje Puro",   "market\_context": {     "category": "NBA|Politica|Sports",     "min\_volume\_threshold": 5000,     "market\_expiry\_min\_hours": 24   },   "user\_parameters": {     "pilar\_1\_risk": {       "kelly\_fraction": 0.15,       "max\_position\_size\_usd": 500,       "max\_bankroll\_pct": 0.05     },     "pilar\_2\_yield": {       "min\_net\_profit\_pct": 0.035,       "include\_gas\_fees": true,       "hurdle\_rate\_usd": 0.5     },     "pilar\_3\_time": {       "execution\_ttl\_sec": 10,       "max\_latency\_ms": 10000     },     "pilar\_4\_logic": {       "required\_confluence\_count": 2,       "bregman\_deviation\_min": 0.05     },     "pilar\_5\_exit": {       "stop\_loss\_pct": 0.04,       "target\_exit": "immediate\_sell",       "hedge\_mode": "natural"     }   } } |
| :---- |

### **Los 5 Pilares — Logica del Desarrollador \+ Configuracion del Usuario**

| PILAR 1  —  GESTION DE RIESGO Y POSITION SIZING |  |
| :---- | :---- |
| **Kelly Criterion** | f\* \= (Suma(YES\_bid\_i)-1.00-Fee) / (Suma(YES\_bid\_i)-1.00) Kelly Fraccionado: 0.15 (latencia 6-8s, frecuencia muy baja \~5%) Ejemplo: suma=1.15 \=\> exceso 15% \=\> f\_real=0.13 |
| **Limite de Exposicion** | max\_position\_size\_usd: $500 | max\_bankroll\_pct: 5% Nunca \> 2 operaciones ARB-04 simultaneas Establecer floor de precio para cada YES\_bid ANTES de firmar el minteo |
| **Control Slippage** | Si orden \> 20% del book\_bid de alguna condicion: usar ordenes LIMIT Si Suma(YES\_bid post-slippage) \< 1.03: RECHAZAR (margen insuficiente) max\_latency\_ms: 10000 (10s para cubrir minteo del set completo) |

| PILAR 2  —  UMBRALES DE RENTABILIDAD NETA |  |
| :---- | :---- |
| **Costos** | Gas: \~$0.08 (1 mint\_set \+ N sell tx) | Fee: 2% por venta de cada condicion Hurdle Rate: min\_net\_profit\_pct \= 0.035 (3.5%) — mayor que ARB-03 |
| **Hurdle Rate** | Ejemplo: suma=1.15, 3 condiciones \=\> bruto 15% \=\> neto 12.5% \=\> OPERAR Si suma \< 1.05 con 5+ condiciones: fees superan profit \=\> FALSE |
| **Ejemplo Neto** | Capital $1,000 | 3 cond: Gas \-$0.08 | Fee \-$23 | Neto $126.92 \= 12.7% |

| PILAR 3  —  VENTANA DE TIEMPO Y CADUCIDAD |  |
| :---- | :---- |
| **TTL** | execution\_ttl\_sec: 10 segundos | market\_expiry\_min\_hours: 24h Mercado cierra \< 24h: NO OPERAR en ningun caso Reconfirmar TODOS los YES\_bid antes de firmar el mint\_set |
| **Drift** | Monitorear bid prices durante los 6-8s del minteo Si cualquier YES\_bid cae \> 1.5%: vender las piernas mas liquidas primero |
| **Floor de Precio** | Establecer ordenes LIMIT con floor de precio ANTES de ejecutar el minteo El set completo es su propio hedge: no vender \=\> resolucion natural a $1.00 |

| PILAR 4  —  VALIDACION DE LA SENAL |  |
| :---- | :---- |
| **Confluencia (min. 2 de 3\)** | (A) Suma(YES\_bid\_i) \> 1.06 (margen amplio para latencia 6-8s) (B) MIN(book\_depth\_bid\_i) \>= $200 para TODAS las condiciones (C) Baja volatilidad: precio no se movio \> 2c en las ultimas 4h |
| **Bids Reales** | Verificar que bids han persistido \> 30 minutos (no son ordenes trampa) Si bid aparecio en \< 5 minutos y es de gran tamano: sospechoso \=\> RECHAZAR |
| **OI y Volumen** | Volumen\_24h \>= $5,000 | Cada condicion: \>= 5 trades en la ultima hora |

| PILAR 5  —  PROTOCOLO DE SALIDA Y COBERTURA |  |
| :---- | :---- |
| **Cierre por Objetivo** | target\_exit: 'immediate\_sell' \=\> vender todos los YES en \< 1s post-minteo asyncio.gather(\*\[sell(YES\_i) for YES\_i in conditions\]) con LIMIT orders |
| **Stop-Loss** | Si minteo tarda \> 10s: gestionar el set manualmente Si ventas no se completan en 30s: mantener el set (hedge natural, paga $1.00) |
| **Hedging** | hedge\_mode: 'natural' \=\> el set completo vale $1.00 en resolucion Priorizar ventas de condiciones mas liquidas primero para asegurar profit parcial |

### **Instruccion de Implementacion para el Desarrollador**

| DEV | \# ARB-04 hereda de BaseStrategy (Familia A — Arbitraje Puro) class ARB\_04\_Strategy(BaseStrategy):     def execute(self, opportunity):         size \= self.calculate\_size(self.balance)         if not self.check\_profit(opportunity.gross, opportunity.fees): return None         if not self.is\_signal\_alive(opportunity.detected\_at): return None         if not self.validate\_confluence(opportunity.signals): return None         \# Familia A: motor especifico de la familia         return self.math.asyncio\_gather(\*opportunity.legs, timeout\_ms=10000)         return self.market\_engine.submit\_order(opportunity, size) |
| :---: | :---- |

| USER | Mercado: NBA|Politica|Sports | Capital Minimo: $1,000 | Latencia: 6-8s Pilar 1: kelly\_fraction=0.15, max\_position\_size\_usd=500, max\_bankroll\_pct=0.05 Pilar 2: min\_net\_profit\_pct=0.035 (3.5%), hurdle\_rate\_usd=$0.5 Pilar 3: execution\_ttl\_sec=10, max\_latency\_ms=10000 Pilar 4: required\_confluence\_count=2, bregman\_deviation\_min=0.05 Pilar 5: stop\_loss\_pct=0.04 (4%), target\_exit='immediate\_sell', hedge\_mode='natural' |
| :---: | :---- |

| ARB-05 *B* 45% Tasa Exito | Arbitraje Combinatorio Cross-Market |
| :---: | :---- |
|  | *Pipeline de 3 fases: Heuristica NLP \=\> LLM DeepSeek-R1 \=\> IP Solver PuLP/Gurobi. PROBLEMA CRITICO: latencia 15-35s vs ventana \~200ms. Solo viable con capital \>$500k en dependencias estructurales.* |
|  | **Condicion:**  Heuristica NLP \=\> LLM \=\> IP Solver \=\> arbitraje verificado   |   Solo dependencias que duran \> 60 minutos |
|  | **Familia:** Familia B — Correlacion y Dependencia   |   **Plataforma:** Polymarket   |   Cap. Min: \>$500,000   |   **Latencia:** 15-35s CRITICO |

| 45% Tasa Exito | $95k Extraido (1 ano) | \>$500k Capital Minimo | 15-35s Latencia CRITICA |
| :---: | :---: | :---: | :---: |

### **Configuracion JSON — Perfil de Usuario**

El desarrollador inyecta este JSON antes de cada operacion. El agente es 'ciego' a los datos del mercado hasta que este perfil este definido.

| {   "strategy\_id": "ST\_005\_CROSS\_MARKET\_ARB",   "familia": "Familia B — Correlacion y Dependencia",   "market\_context": {     "category": "Politica|Economia|Crypto",     "min\_volume\_threshold": 10000,     "market\_expiry\_min\_hours": 168   },   "user\_parameters": {     "pilar\_1\_risk": {       "kelly\_fraction": 0.1,       "max\_position\_size\_usd": 15000,       "max\_bankroll\_pct": 0.03     },     "pilar\_2\_yield": {       "min\_net\_profit\_pct": 0.05,       "include\_gas\_fees": true,       "hurdle\_rate\_usd": 750     },     "pilar\_3\_time": {       "execution\_ttl\_sec": 3600,       "max\_latency\_ms": 35000     },     "pilar\_4\_logic": {       "required\_confluence\_count": 3,       "bregman\_deviation\_min": 0.1     },     "pilar\_5\_exit": {       "stop\_loss\_pct": 0.15,       "target\_exit": "equilibrium",       "hedge\_mode": "sequential"     }   } } |
| :---- |

### **Los 5 Pilares — Logica del Desarrollador \+ Configuracion del Usuario**

| PILAR 1  —  GESTION DE RIESGO Y POSITION SIZING |  |
| :---- | :---- |
| **Kelly Criterion** | Kelly Fraccionado: 0.10 (tasa 45%, capital institucional) Capital minimo: $500,000 para justificar infra (LLM \+ Gurobi \~$1,500/mes) Por dependencia verificada: max 3% del bankroll \= max\_bankroll\_pct max\_position\_size\_usd: $15,000 por dependencia (5 simultaneas max \= 15%) |
| **Limite de Exposicion** | Maximo 15% del bankroll total en dependencias activas simultaneamente Ordenes LIMIT obligatorias en AMBAS piernas Si impacto combinado en ambos mercados \> 2%: reducir tamano al 50% |
| **Grafo de Mercados** | FAMILIA B: si Market A cambia, el agente re-evalua Market B INMEDIATAMENTE dependency\_graph.on\_price\_change(market\_a, callback=reevaluate\_market\_b) Esta es la instruccion central de la Familia B |

| PILAR 2  —  UMBRALES DE RENTABILIDAD NETA |  |
| :---- | :---- |
| **Costos e Infra** | Gas: \~$0.04 | Fee: 2% por pierna en cada mercado LLM DeepSeek-R1: \~$500/mes | IP Solver Gurobi: \~$1,000/mes Total infra: \~$1,500/mes | hurdle\_rate\_usd: $750 por dependencia verificada |
| **Hurdle Rate** | min\_net\_profit\_pct: 0.050 (5.0%) — el mas alto de todas las estrategias Contexto: $95k extraido en 1 ano \= 0.43% del total de $22.4M Solo viable en dependencias ESTRUCTURALES (horas, no milisegundos) |
| **Calibracion del LLM** | Verificar manualmente las primeras 10 dependencias para calibrar el modelo Documentar resultados en DB para mejora iterativa del modelo LLM |

| PILAR 3  —  VENTANA DE TIEMPO Y CADUCIDAD |  |
| :---- | :---- |
| **TTL Estructural** | execution\_ttl\_sec: 3600 (1 hora) — NO es una estrategia de alta frecuencia Solo actuar en dependencias que llevan \> 60 minutos activas (no flashes) La latencia de 15-35s hace inviable actuar en dependencias de \< 60 min |
| **Expiracion** | market\_expiry\_min\_hours: 168 (7 dias) — ambos mercados deben cerrar en \> 7 dias Diferencia de fechas de cierre entre A y B: \< 30 dias |
| **Re-evaluacion** | Reevaluar la dependencia cada 15 minutos con el pipeline completo Si desaparece en \< 60 min: era un flash \=\> excluir ese tipo de par del modelo |

| PILAR 4  —  VALIDACION DE LA SENAL |  |
| :---- | :---- |
| **Pipeline de 3 Fases (min. 3 de 4\)** | required\_confluence\_count: 3 (muy estricto por capital institucional) (A) Heuristica NLP: score \> 0.60 (46,360 \=\> 1,576 candidatos) (B) LLM DeepSeek-R1: confidence \> 80% (C) IP Solver PuLP/Gurobi: profit neto \> 5% verificado matematicamente (D) Dependencia persistente \> 2 horas en datos historicos |
| **Volumen y OI** | Volumen\_24h de AMBOS mercados \>= $10,000 | OI combinado \>= $50,000 |
| **IP Solver en Tiempo Real** | El IP Solver debe usar datos en tiempo real (nunca cacheados) La familia B usa un Grafo de Mercados: actualizacion continua |

| PILAR 5  —  PROTOCOLO DE SALIDA Y COBERTURA |  |
| :---- | :---- |
| **Cierre por Objetivo** | target\_exit: 'equilibrium' \=\> salida cuando precios convergen al equilibrio del IP Solver Monitorear convergencia cada 15 minutos con el pipeline completo |
| **Stop-Loss** | stop\_loss\_pct: 0.15 (15%) | Stop por rotura de dependencia: evento fundacional resuelve Stop de tiempo: si dependencia persiste \> 7 dias sin convergencia \=\> SALIR Stop de modelo: 3 dependencias incorrectas consecutivas \=\> revision manual del LLM |
| **Hedging Secuencial** | hedge\_mode: 'sequential' \=\> las dos piernas ejecutadas en \< 5s entre si Si solo se puede ejecutar UNA pierna: NO ejecutar la operacion completa Ordenes LIMIT pre-configuradas en ambos mercados ANTES del trigger |

### **Instruccion de Implementacion para el Desarrollador**

| DEV | \# ARB-05 hereda de BaseStrategy (Familia B — Correlacion y Dependencia) class ARB\_05\_Strategy(BaseStrategy):     def execute(self, opportunity):         size \= self.calculate\_size(self.balance)         if not self.check\_profit(opportunity.gross, opportunity.fees): return None         if not self.is\_signal\_alive(opportunity.detected\_at): return None         if not self.validate\_confluence(opportunity.signals): return None         \# Familia B: motor especifico de la familia         self.math.dependency\_graph.reevaluate(opportunity.related\_markets)         return self.market\_engine.submit\_order(opportunity, size) |
| :---: | :---- |

| USER | Mercado: Politica|Economia|Crypto | Capital Minimo: \>$500,000 | Latencia: 15-35s CRITICO Pilar 1: kelly\_fraction=0.1, max\_position\_size\_usd=15000, max\_bankroll\_pct=0.03 Pilar 2: min\_net\_profit\_pct=0.05 (5.0%), hurdle\_rate\_usd=$750 Pilar 3: execution\_ttl\_sec=3600, max\_latency\_ms=35000 Pilar 4: required\_confluence\_count=3, bregman\_deviation\_min=0.1 Pilar 5: stop\_loss\_pct=0.15 (15%), target\_exit='equilibrium', hedge\_mode='sequential' |
| :---: | :---- |

| MINT-01 *C* Alta Tasa Exito | Minteo Simple $1,000 de Una Vez |
| :---: | :---- |
|  | *Mintear $1,000 USDC generando 1,000 YES \+ 1,000 NO, con ordenes de venta a \+0.75c del midpoint. Neto: \+$13.575/ciclo. Base del compounding (\~40.6%/mes). Familia C: Bregman optimiza el tamano y la seleccion del mercado.* |
|  | **Condicion:**  $1,000 USDC \=\> mint() | sell\_YES @ 0.5825 | sell\_NO @ 0.4325 | LP Rewards Factor 0.55x |
|  | **Familia:** Familia C — Optimizacion Estadistica   |   **Plataforma:** Polymarket   |   Cap. Min: $500   |   **Latencia:** \~3-6s |

| \+1.33% ROI / Ciclo 24h | \+$13.575 Ganancia Total | \~$0.05 Gas (3 tx) | \~40.6% Proyeccion/mes |
| :---: | :---: | :---: | :---: |

### **Configuracion JSON — Perfil de Usuario**

El desarrollador inyecta este JSON antes de cada operacion. El agente es 'ciego' a los datos del mercado hasta que este perfil este definido.

| {   "strategy\_id": "ST\_006\_MINT\_SIMPLE",   "familia": "Familia C — Optimizacion Estadistica",   "market\_context": {     "category": "NBA|Crypto|Politica|Economia",     "min\_volume\_threshold": 10000,     "market\_expiry\_min\_hours": 48   },   "user\_parameters": {     "pilar\_1\_risk": {       "kelly\_fraction": 0,       "max\_position\_size\_usd": 1000,       "max\_bankroll\_pct": 0.2     },     "pilar\_2\_yield": {       "min\_net\_profit\_pct": 0.0133,       "include\_gas\_fees": true,       "hurdle\_rate\_usd": 13     },     "pilar\_3\_time": {       "execution\_ttl\_sec": 86400,       "max\_latency\_ms": 6000     },     "pilar\_4\_logic": {       "required\_confluence\_count": 2,       "bregman\_deviation\_min": 0.01     },     "pilar\_5\_exit": {       "stop\_loss\_pct": 0.05,       "target\_exit": "order\_fill",       "hedge\_mode": "natural"     }   } } |
| :---- |

### **Los 5 Pilares — Logica del Desarrollador \+ Configuracion del Usuario**

| PILAR 1  —  GESTION DE RIESGO Y POSITION SIZING |  |
| :---- | :---- |
| **Sizing Deterministico** | Position sizing DETERMINISTICO (no usa Kelly probabilistico): el profit es calculable antes de mintear. calculate\_size() retorna directamente max\_position\_size\_usd ($1,000 por defecto). Escalar: bankroll $5,000 \=\> 5 ciclos de $1,000 en 5 mercados distintos. |
| **Limite y Capture Rate** | max\_bankroll\_pct: 20% en ciclos MINT-01 activos simultaneamente Riesgo principal: que las ordenes no se ejecuten (capture rate bajo) Si capture rate \< 50% en 36h: cambiar de mercado \=\> es la 'senal de stop-loss' de MINT-01 |
| **Bregman en Familia C** | IA-06 optimiza la seleccion del mercado y el offset via Bregman: bregman\_deviation\_min: 0.01 (mercado con KL-divergence baja \=\> precio estable \=\> ideal para MINT) Usar Bregman para confirmar que el mercado objetivo tiene bajo riesgo de movimiento brusco |

| PILAR 2  —  UMBRALES DE RENTABILIDAD NETA |  |
| :---- | :---- |
| **Desglose Exacto (Catalogo18)** | Fee YES: 0.002 x min(0.5825,0.4175) x 1,000 \= \-$0.835 Fee NO:  0.002 x min(0.4325,0.5675) x 1,000 \= \-$0.865 Gas: \-$0.05 | LP Rewards (Factor 0.55x): \+$0.275 | TOTAL NETO: \+$13.575 |
| **Hurdle Rate** | min\_net\_profit\_pct: 0.0133 (1.33%) | hurdle\_rate\_usd: $13.00 por ciclo Si mercado tiene volumen\_24h \< $10,000: LP rewards podrian ser menores al calculo check\_profit() verifica el desglose completo antes de cada ciclo |
| **Proyeccion Compounding** | 30 ciclos/mes x 1.3575% \= \~40.6% mensual proyectado Capital $10,000 a 12 meses (MINT-06): \~$78,000 con reinversion total |

| PILAR 3  —  VENTANA DE TIEMPO Y CADUCIDAD |  |
| :---- | :---- |
| **Ciclo de 24h** | execution\_ttl\_sec: 86400 (24 horas) — las ordenes LIMIT tienen vida de 24h market\_expiry\_min\_hours: 48h — mercado debe cerrar en \> 48h para completar el ciclo Revision de competitividad de las ordenes: cada 6h |
| **Reposicion** | Si el midpoint del mercado se mueve \> 1c: cancelar y reposicionar Si midpoint se mueve \> 3c en el ciclo: recalcular las ordenes al nuevo midpoint \+ 0.75c |
| **Drift** | Drift lento (\< 2c en 6h): reposicionar preventivamente Drift rapido (\> 2c en 30min): posible noticia \=\> pausar hasta estabilizacion |

| PILAR 4  —  VALIDACION DE LA SENAL |  |
| :---- | :---- |
| **Seleccion de Mercado (3 de 3\)** | (A) Volumen\_24h \> min\_volume\_threshold ($10,000) (B) Midpoint estable en las ultimas 4h (variacion \< 2c) (C) Sin eventos de resolucion inminente en las proximas 48h Bregman confirma: KL-divergence baja \=\> mercado eficiente \=\> ideal para MINT |
| **Familia C — Bregman Estricto** | required\_confluence\_count: 2 (incluyendo confirmacion de Bregman) bregman\_deviation\_min: 0.01 (mercados con KL \> 0.05 son inestables \=\> evitar para MINT) Mercados con KL bajo son los candidatos ideales para Market Making pasivo |
| **Capture Rate como Validacion** | Si el capture rate historico del mercado es \< 60%: no es adecuado para MINT-01 El Bregman de Familia C puede estimar el capture rate esperado antes de mintear |

| PILAR 5  —  PROTOCOLO DE SALIDA Y COBERTURA |  |
| :---- | :---- |
| **Cierre por Objetivo** | target\_exit: 'order\_fill' \=\> salida natural cuando ordenes LIMIT se ejecutan should\_exit() monitorea si el midpoint se mueve \> 5c (senal de cancel) Si ordenes no se ejecutan en 36h: cambiar de mercado |
| **Stop-Loss del Ciclo** | Si volumen del mercado cae \> 60%: cancelar y reubicar capital Si noticia importante cambia el mercado abruptamente: cancelar y esperar estabilizacion |
| **Hedge Natural** | hedge\_mode: 'natural' \=\> el par YES+NO \= $1.00 en resolucion garantizada Si ordenes no se ejecutan: capital retorna completo al cierre del mercado Estrategia NO puede perder capital principal si el minteo es correcto |

### **Instruccion de Implementacion para el Desarrollador**

| DEV | \# MINT-01 hereda de BaseStrategy (Familia C — Optimizacion Estadistica) class MINT\_01\_Strategy(BaseStrategy):     def execute(self, opportunity):         size \= self.calculate\_size(self.balance)         if not self.check\_profit(opportunity.gross, opportunity.fees): return None         if not self.is\_signal\_alive(opportunity.detected\_at): return None         if not self.validate\_confluence(opportunity.signals): return None         \# Familia C: motor especifico de la familia         size \= self.math.bregman\_optimizer.optimize(size, opportunity.kl\_divergence)         return self.market\_engine.submit\_order(opportunity, size) |
| :---: | :---- |

| USER | Mercado: NBA|Crypto|Politica|Economia | Capital Minimo: $500 | Latencia: \~3-6s Pilar 1: kelly\_fraction=0, max\_position\_size\_usd=1000, max\_bankroll\_pct=0.2 Pilar 2: min\_net\_profit\_pct=0.0133 (1.3%), hurdle\_rate\_usd=$13 Pilar 3: execution\_ttl\_sec=86400, max\_latency\_ms=6000 Pilar 4: required\_confluence\_count=2, bregman\_deviation\_min=0.01 Pilar 5: stop\_loss\_pct=0.05 (5%), target\_exit='order\_fill', hedge\_mode='natural' |
| :---: | :---- |

| MINT-02 *C* Alta Tasa Exito | Minteo en Dos Partes $500 \+ $500 |
| :---: | :---- |
|  | *Mismo capital en 2 ciclos de $500. El agente ajusta precios entre ciclos segun el mercado. Recomendado para mercados de liquidez media. Familia C usa Bregman para evaluar la estabilidad del mercado entre ciclos.* |
|  | **Condicion:**  Ciclo 1: $500 \=\> mint() 24h  |  Ciclo 2: $500 \=\> mint() con precio ajustado por Bregman |
|  | **Familia:** Familia C — Optimizacion Estadistica   |   **Plataforma:** Polymarket   |   Cap. Min: $200   |   **Latencia:** \~3-6s |

| \+1.33% ROI/Ciclo | 48h Duracion Total | \~$0.10 Gas (6 tx) | 15 Ciclos/mes |
| :---: | :---: | :---: | :---: |

### **Configuracion JSON — Perfil de Usuario**

El desarrollador inyecta este JSON antes de cada operacion. El agente es 'ciego' a los datos del mercado hasta que este perfil este definido.

| {   "strategy\_id": "ST\_007\_MINT\_TWO\_PARTS",   "familia": "Familia C — Optimizacion Estadistica",   "market\_context": {     "category": "Economia|Sports|NBA",     "min\_volume\_threshold": 5000,     "market\_expiry\_min\_hours": 72   },   "user\_parameters": {     "pilar\_1\_risk": {       "kelly\_fraction": 0,       "max\_position\_size\_usd": 500,       "max\_bankroll\_pct": 0.15     },     "pilar\_2\_yield": {       "min\_net\_profit\_pct": 0.0133,       "include\_gas\_fees": true,       "hurdle\_rate\_usd": 6.5     },     "pilar\_3\_time": {       "execution\_ttl\_sec": 86400,       "max\_latency\_ms": 6000     },     "pilar\_4\_logic": {       "required\_confluence\_count": 2,       "bregman\_deviation\_min": 0.01     },     "pilar\_5\_exit": {       "stop\_loss\_pct": 0.05,       "target\_exit": "order\_fill",       "hedge\_mode": "natural"     }   } } |
| :---- |

### **Los 5 Pilares — Logica del Desarrollador \+ Configuracion del Usuario**

| PILAR 1  —  GESTION DE RIESGO Y POSITION SIZING |  |
| :---- | :---- |
| **Sizing por Ciclo** | $500 fijo por sub-ciclo (max\_position\_size\_usd: 500\) Ventaja clave vs MINT-01: entre Ciclo 1 y Ciclo 2 se ajusta el offset si el mercado cambio Bregman recalcula el offset optimo antes de lanzar el Ciclo 2 |
| **Escalado y Exposicion** | max\_bankroll\_pct: 15% | Escalar: bankroll $5k \=\> 5 pares en distintos mercados La estructura de 2 ciclos separa el riesgo: un ciclo malo no contamina al otro |
| **Bregman Entre Ciclos** | FAMILIA C: Bregman evalua si el mercado sigue siendo estable antes del Ciclo 2 Si KL-divergence subio \> 0.05 en las 24h del Ciclo 1: mercado inestable \=\> NO lanzar Ciclo 2 |

| PILAR 2  —  UMBRALES DE RENTABILIDAD NETA |  |
| :---- | :---- |
| **Desglose por Ciclo** | Ciclo 1: $500 \=\> \+$6.65 neto | Ciclo 2: $500 \=\> \+$6.65 neto | Total: \+$13.30 Gas total: \-$0.10 (vs \-$0.05 de MINT-01) \=\> diferencia de $0.05 es irrelevante LP Rewards: \+$0.14/dia por sub-ciclo (menor capital activo) |
| **Confluencia Pre-Ciclo 2** | Antes de lanzar Ciclo 2 adicional: (A) Ciclo 1 ejecuto al menos una orden correctamente (B) Midpoint no se movio \> 3c durante las 24h del Ciclo 1 (C) Volumen\_24h sigue siendo \> min\_volume\_threshold ($5,000) |
| **Ventaja del Ajuste** | La ventaja real de MINT-02: el Ciclo 2 usa informacion actualizada del mercado Si mercado se volvio mas liquido: subir a $1,000 para el Ciclo 2 (escalar a MINT-01) |

| PILAR 3  —  VENTANA DE TIEMPO Y CADUCIDAD |  |
| :---- | :---- |
| **Ciclos Secuenciales** | market\_expiry\_min\_hours: 72h (3 dias) para completar ambos ciclos con margen Si mercado cierra en 48-72h: ejecutar solo el Ciclo 1 de $500 |
| **Revision Entre Ciclos** | Al final del Ciclo 1 (24h): revisar midpoint antes de lanzar Ciclo 2 Si midpoint cambio \> 2c: recalcular precios con el nuevo midpoint Bregman confirma la estabilidad antes de cada nuevo ciclo |
| **Adaptabilidad Temporal** | Si el mercado se volvio mas liquido en 24h: escalar a MINT-01 para el Ciclo 2 Si se volvio menos liquido: cancelar el Ciclo 2 y reubicar capital |

| PILAR 4  —  VALIDACION DE LA SENAL |  |
| :---- | :---- |
| **Seleccion Mercado Liquidez Media** | Target: mercados con volumen\_24h entre $5,000 y $20,000 (sweet spot de MINT-02) Este rango es suficiente para LP rewards pero sin competencia extrema de otros MMs |
| **Bregman por Ciclo** | FAMILIA C: Bregman recalcula antes de CADA ciclo Si KL aumenta entre ciclos \=\> mercado se volvio menos predecible \=\> reducir tamano |
| **Validacion del Ciclo 2** | (A) Ciclo 1 exitoso | (B) Midpoint movimiento \< 3c | (C) Volumen sostenido |

| PILAR 5  —  PROTOCOLO DE SALIDA Y COBERTURA |  |
| :---- | :---- |
| **Salida Adaptativa** | target\_exit: 'order\_fill' por ciclo Si Ciclo 1 no ejecuta ninguna orden en 24h: NO lanzar Ciclo 2 automaticamente check\_profit() debe confirmar que las condiciones del mercado siguen siendo validas |
| **Stop y Hedge** | Cada minteo es su propio hedge natural (YES+NO \= $1.00) La estructura de 2 ciclos separa el riesgo: stop por ciclo, no stop total |
| **Continuidad** | Si el Ciclo 2 no se puede lanzar: el capital del Ciclo 1 esta protegido por el par minteado |

### **Instruccion de Implementacion para el Desarrollador**

| DEV | \# MINT-02 hereda de BaseStrategy (Familia C — Optimizacion Estadistica) class MINT\_02\_Strategy(BaseStrategy):     def execute(self, opportunity):         size \= self.calculate\_size(self.balance)         if not self.check\_profit(opportunity.gross, opportunity.fees): return None         if not self.is\_signal\_alive(opportunity.detected\_at): return None         if not self.validate\_confluence(opportunity.signals): return None         \# Familia C: motor especifico de la familia         size \= self.math.bregman\_optimizer.optimize(size, opportunity.kl\_divergence)         return self.market\_engine.submit\_order(opportunity, size) |
| :---: | :---- |

| USER | Mercado: Economia|Sports|NBA | Capital Minimo: $200 | Latencia: \~3-6s Pilar 1: kelly\_fraction=0, max\_position\_size\_usd=500, max\_bankroll\_pct=0.15 Pilar 2: min\_net\_profit\_pct=0.0133 (1.3%), hurdle\_rate\_usd=$6.5 Pilar 3: execution\_ttl\_sec=86400, max\_latency\_ms=6000 Pilar 4: required\_confluence\_count=2, bregman\_deviation\_min=0.01 Pilar 5: stop\_loss\_pct=0.05 (5%), target\_exit='order\_fill', hedge\_mode='natural' |
| :---: | :---- |

| MINT-03 *C* Variable Tasa Exito | Market Making en el Midpoint — Escenario A |
| :---: | :---- |
|  | *Ordenes en el midpoint exacto. Proximity Factor 1.00x, LP Score 3,000 pts, \+$0.50/dia. PERDIDA si las ordenes se ejecutan (-$1.21). Solo rentable si las ordenes permanecen sin ejecutarse. APY \~16.5%. Familia C usa Bregman para detectar cuando el mercado se vuelve inestable.* |
|  | **Condicion:**  YES @ 0.575 (midpoint exacto) | NO @ 0.425 | Factor 1.00x | Score 3,000 pts |
|  | **Familia:** Familia C — Optimizacion Estadistica   |   **Plataforma:** Polymarket   |   Cap. Min: $500   |   **Latencia:** Pasivo |

| \-$1.21 ⚠ Neto si Ejecuta | \+$0.50/dia LP Rewards | 3,000 pts Score Maximo | \~16.5% APY Pasivo |
| :---: | :---: | :---: | :---: |

### **Configuracion JSON — Perfil de Usuario**

El desarrollador inyecta este JSON antes de cada operacion. El agente es 'ciego' a los datos del mercado hasta que este perfil este definido.

| {   "strategy\_id": "ST\_008\_MM\_MIDPOINT",   "familia": "Familia C — Optimizacion Estadistica",   "market\_context": {     "category": "Politica|Economia",     "min\_volume\_threshold": 20000,     "market\_expiry\_min\_hours": 336   },   "user\_parameters": {     "pilar\_1\_risk": {       "kelly\_fraction": 0,       "max\_position\_size\_usd": 3000,       "max\_bankroll\_pct": 0.3     },     "pilar\_2\_yield": {       "min\_net\_profit\_pct": 0.165,       "include\_gas\_fees": true,       "hurdle\_rate\_usd": 0.5     },     "pilar\_3\_time": {       "execution\_ttl\_sec": 1209600,       "max\_latency\_ms": 0     },     "pilar\_4\_logic": {       "required\_confluence\_count": 3,       "bregman\_deviation\_min": 0.005     },     "pilar\_5\_exit": {       "stop\_loss\_pct": 0,       "target\_exit": "rewards\_accumulation",       "hedge\_mode": "natural"     }   } } |
| :---- |

### **Los 5 Pilares — Logica del Desarrollador \+ Configuracion del Usuario**

| PILAR 1  —  GESTION DE RIESGO Y POSITION SIZING |  |
| :---- | :---- |
| **Sizing Pasivo** | calculate\_size() retorna directamente el capital asignado (no Kelly probabilistico) max\_bankroll\_pct: 30% distribuido en minimo 5 mercados distintos El riesgo principal NO es la direccion del mercado sino que las propias ordenes se ejecuten |
| **Riesgo Invertido** | Si las ordenes del midpoint se ejecutan: PERDIDA \-$1.21 por ciclo Umbral de proteccion: si precio se mueve \> 2c en 1h \=\> cancelar y cambiar a MINT-04 Bregman es el guardian: si KL aumenta \=\> mercado se vuelve inestable \=\> accion preventiva |
| **Cambio Automatico a MINT-04** | Si las ordenes del midpoint se ejecutan mas de 1 vez por semana: CAMBIAR A MINT-04 Esta regla debe ser automatica en el agente: no requiere intervencion del usuario |

| PILAR 2  —  UMBRALES DE RENTABILIDAD NETA |  |
| :---- | :---- |
| **Hurdle en Modo Pasivo** | Hurdle Rate: APY rewards \>= 16.5% anual (no es profit de spread) hurdle\_rate\_usd: $0.50/dia por $1,000 invertido en modo pasivo Comparacion: MINT-04 supera a MINT-03 en \+1,222% en mercados liquidos |
| **Comparacion Critica** | MINT-03: spread \-$1.21 si ejecuta rapido \+ rewards $0.50/dia \=\> APY \~16.5% MINT-04: spread \+$13.30 \+ rewards $0.275/dia \=\> APY \~26.2% MINT-04 es siempre mejor cuando las ordenes se ejecutan con frecuencia |
| **Evaluacion Mensual** | Si rewards acumulados \< 10% anual tras 30 dias: reasignar capital a MINT-04 El agente debe calcular el APY realizado cada semana y comparar con el objetivo |

| PILAR 3  —  VENTANA DE TIEMPO Y CADUCIDAD |  |
| :---- | :---- |
| **Horizonte Largo Plazo** | market\_expiry\_min\_hours: 336 (14 dias minimo) para acumulacion de rewards execution\_ttl\_sec: 1209600 (14 dias) — las ordenes son permanentes hasta ejecucion Cuando el mercado se acerca a \< 7 dias al cierre: convertir a MINT-04 o cerrar |
| **Bregman como Alarma Temporal** | FAMILIA C: Bregman detecta cuando el mercado se vuelve inestable Si KL-divergence sube repentinamente: alerta anticipada de posible movimiento brusco bregman\_deviation\_min: 0.005 (muy sensible para detectar cualquier anomalia temprano) |
| **Revision Periodica** | Revision de posicion: cada 12 horas (no necesita ser mas frecuente en modo pasivo) Alerta de deriva: si precio se mueve \> 2c en 30 minutos \=\> cancelar ordenes preventivamente |

| PILAR 4  —  VALIDACION DE LA SENAL |  |
| :---- | :---- |
| **Seleccion de Mercado (3 de 3 obligatorio)** | required\_confluence\_count: 3 (todos los criterios son obligatorios) (A) Alta estabilidad: no crypto, no elecciones proximas, mercados sin noticias programadas (B) Open Interest \> $20,000 (mercado maduro con rewards altos) (C) Variacion de precio \< 5c en las ultimas 72 horas consecutivas |
| **Bregman Muy Estricto** | bregman\_deviation\_min: 0.005 (el mas bajo de todas las estrategias) Mercados con KL \> 0.02: demasiado volatiles para MINT-03 \=\> cambiar a MINT-05 Familia C requiere que la libreria Bregman sea exacta: es el filtro principal |
| **Riesgo de Ejecucion Propia** | El riesgo no es la liquidez del mercado sino la ejecucion de las PROPIAS ordenes Monitorear el flujo: si hay mas compradores que vendedores \=\> cambiar a MINT-04 inmediatamente |

| PILAR 5  —  PROTOCOLO DE SALIDA Y COBERTURA |  |
| :---- | :---- |
| **Objetivo: NO Ejecutar** | target\_exit: 'rewards\_accumulation' \=\> objetivo principal es que las ordenes NO se ejecuten should\_exit() en modo MINT-03 monitorea el flujo de ordenes, no el PnL del spread Salida planificada: cuando el mercado se acerca a \< 14 dias de cierre |
| **Stop de Modo** | Si las ordenes se ejecutan UNA VEZ: cambiar automaticamente a MINT-04 en ese mercado Si precio se mueve \> 5c en 2h: cancelar ordenes del midpoint PREVENTIVAMENTE stop\_loss\_pct: 0.0 (no aplica para modo pasivo — el capital no puede perderse con el minteo) |
| **Hedge Natural** | hedge\_mode: 'natural' \=\> el par YES+NO \= $1.00 en resolucion Peor caso de MINT-03: recuperar el capital original al cierre (sin perdida de capital principal) |

### **Instruccion de Implementacion para el Desarrollador**

| DEV | \# MINT-03 hereda de BaseStrategy (Familia C — Optimizacion Estadistica) class MINT\_03\_Strategy(BaseStrategy):     def execute(self, opportunity):         size \= self.calculate\_size(self.balance)         if not self.check\_profit(opportunity.gross, opportunity.fees): return None         if not self.is\_signal\_alive(opportunity.detected\_at): return None         if not self.validate\_confluence(opportunity.signals): return None         \# Familia C: motor especifico de la familia         size \= self.math.bregman\_optimizer.optimize(size, opportunity.kl\_divergence)         return self.market\_engine.submit\_order(opportunity, size) |
| :---: | :---- |

| USER | Mercado: Politica|Economia | Capital Minimo: $500 | Latencia: Pasivo Pilar 1: kelly\_fraction=0, max\_position\_size\_usd=3000, max\_bankroll\_pct=0.3 Pilar 2: min\_net\_profit\_pct=0.165 (16.5%), hurdle\_rate\_usd=$0.5 Pilar 3: execution\_ttl\_sec=1209600, max\_latency\_ms=0 Pilar 4: required\_confluence\_count=3, bregman\_deviation\_min=0.005 Pilar 5: stop\_loss\_pct=0 (0%), target\_exit='rewards\_accumulation', hedge\_mode='natural' |
| :---: | :---- |

| MINT-04 *C* Alta Tasa Exito | Market Making Premium — Escenario B |
| :---: | :---- |
|  | *Ordenes a \+0.75c del midpoint. Factor 0.55x, Score 1,650 pts. Spread \+$13.30 supera masivamente la perdida de rewards vs MINT-03. APY 26.2%. GANADORA en mercados liquidos. Familia C: Bregman optimiza el offset y calcula el capture rate esperado.* |
|  | **Condicion:**  YES @ 0.5825 (+0.75c) | NO @ 0.4325 (+0.75c) | Factor 0.55x | NETO: \+$13.575/ciclo |
|  | **Familia:** Familia C — Optimizacion Estadistica   |   **Plataforma:** Polymarket   |   Cap. Min: $500   |   **Latencia:** \~3-6s |

| \+$13.575 Neto Total/Ciclo | 1,650 pts LP Score | \~26.2% APY | \+1,222% Vs MINT-03 |
| :---: | :---: | :---: | :---: |

### **Configuracion JSON — Perfil de Usuario**

El desarrollador inyecta este JSON antes de cada operacion. El agente es 'ciego' a los datos del mercado hasta que este perfil este definido.

| {   "strategy\_id": "ST\_009\_MM\_PREMIUM",   "familia": "Familia C — Optimizacion Estadistica",   "market\_context": {     "category": "NBA|Crypto|Politica|Economia",     "min\_volume\_threshold": 20000,     "market\_expiry\_min\_hours": 48   },   "user\_parameters": {     "pilar\_1\_risk": {       "kelly\_fraction": 0,       "max\_position\_size\_usd": 1000,       "max\_bankroll\_pct": 0.25     },     "pilar\_2\_yield": {       "min\_net\_profit\_pct": 0.0133,       "include\_gas\_fees": true,       "hurdle\_rate\_usd": 13     },     "pilar\_3\_time": {       "execution\_ttl\_sec": 86400,       "max\_latency\_ms": 6000     },     "pilar\_4\_logic": {       "required\_confluence\_count": 2,       "bregman\_deviation\_min": 0.02     },     "pilar\_5\_exit": {       "stop\_loss\_pct": 0.05,       "target\_exit": "order\_fill",       "hedge\_mode": "natural"     }   } } |
| :---- |

### **Los 5 Pilares — Logica del Desarrollador \+ Configuracion del Usuario**

| PILAR 1  —  GESTION DE RIESGO Y POSITION SIZING |  |
| :---- | :---- |
| **Sizing por Capture Rate** | Sizing por capture rate historico: capital \= capture\_rate x capital\_disponible Capture rate en mercados liquidos (vol \> $50k): \~90-95% de ordenes ejecutadas en 24h Bregman calcula el capture rate esperado antes de cada ciclo (Familia C) |
| **Exposicion y Escalado** | max\_bankroll\_pct: 25% | max\_position\_size\_usd: $1,000 Mercados vol \> $50k: usar offset \+1.0c (mas agresivo) | Vol $10k-$50k: offset \+0.75c (estandar) Si capture rate consistentemente \< 50%: bajar a MINT-05 (sweet spot) |
| **Bregman Selecciona el Mercado** | FAMILIA C: Bregman compara el KL-divergence de mercados candidatos Mercado con KL bajo y volumen alto: candidato ideal para MINT-04 bregman\_deviation\_min: 0.02 (umbral de estabilidad minima requerida) |

| PILAR 2  —  UMBRALES DE RENTABILIDAD NETA |  |
| :---- | :---- |
| **Desglose Exacto** | Fee YES: \-$0.835 | Fee NO: \-$0.865 | Gas: \-$0.05 LP Rewards (Factor 0.55x): \+$0.275 | TOTAL NETO: \+$13.575 (+1.3575%) Vs MINT-03: \+$13.575 vs \-$1.21 en mercados liquidos \= \+1,222% diferencia |
| **Hurdle Rate** | min\_net\_profit\_pct: 0.0133 (1.33%) | hurdle\_rate\_usd: $13.00 por ciclo 30 ciclos/mes con MINT-06 compounding: proyeccion \~40.6% mensual |
| **Escalado de Fees** | Los fees crecen proporcionalmente con el capital El crecimiento neto del 1.3575% se mantiene constante a cualquier escala MINT-06 aprovecha esta escala perfecta para el compounding |

| PILAR 3  —  VENTANA DE TIEMPO Y CADUCIDAD |  |
| :---- | :---- |
| **Ciclo de 24h** | market\_expiry\_min\_hours: 48h | execution\_ttl\_sec: 86400 (24h) Reposicion: cada 6h si el midpoint se movio \> 1c Si capture rate \= 0 en 36h: cambiar de mercado |
| **Offset Dinamico** | Bregman ajusta el offset segun la estabilidad del mercado: Mercado muy estable (KL \< 0.01): offset \+1.0c (mas agresivo) Mercado moderado (KL 0.01-0.05): offset \+0.75c (estandar MINT-04) Mercado inestable (KL \> 0.05): cambiar a MINT-05 |
| **Drift** | Drift lento (\< 2c en 6h): reposicionar preventivamente Drift rapido (\> 2c en 30min): noticia posible \=\> pausar hasta estabilizacion |

| PILAR 4  —  VALIDACION DE LA SENAL |  |
| :---- | :---- |
| **Seleccion Mercado (min. 2 de 3\)** | (A) Volumen\_24h \> $20,000 (actividad suficiente para spread \+0.75c) (B) Al menos 10 trades en la ultima hora en el CLOB (C) Bid-ask spread actual \< 1.5c (mercado ajustado y activo) |
| **Bregman Confirma** | FAMILIA C: Bregman valida que el mercado es adecuado para Market Making bregman\_deviation\_min: 0.02 (KL minimo que indica el mercado no esta en equilibrio perfecto) Si KL \< 0.02: mercado demasiado eficiente \=\> las ordenes no se ejecutaran |
| **Volumen Artificial** | Verificar que el volumen proviene de multiples wallets (no wash trading) Si el mismo actor \> 50% del volumen: mercado artificial \=\> evitar |

| PILAR 5  —  PROTOCOLO DE SALIDA Y COBERTURA |  |
| :---- | :---- |
| **Cierre por Objetivo** | target\_exit: 'order\_fill' \=\> salida natural cuando ordenes LIMIT se ejecutan Capture rate objetivo: \> 80% en 24h Bregman calcula el precio de equilibrio como referencia de salida (Familia C) |
| **Stop por Deterioro** | Si volumen cae \> 60%: cancelar y mover capital a otro mercado Si capture rate \< 50% en 2 ciclos: reducir offset a MINT-05 Si ninguna orden se ejecuta en 36h: cambiar de mercado |
| **Hedge Natural del Minteo** | hedge\_mode: 'natural' \=\> YES+NO \= $1.00 en resolucion Si solo una pierna se ejecuta: el token restante se mantiene hasta resolucion |

### **Instruccion de Implementacion para el Desarrollador**

| DEV | \# MINT-04 hereda de BaseStrategy (Familia C — Optimizacion Estadistica) class MINT\_04\_Strategy(BaseStrategy):     def execute(self, opportunity):         size \= self.calculate\_size(self.balance)         if not self.check\_profit(opportunity.gross, opportunity.fees): return None         if not self.is\_signal\_alive(opportunity.detected\_at): return None         if not self.validate\_confluence(opportunity.signals): return None         \# Familia C: motor especifico de la familia         size \= self.math.bregman\_optimizer.optimize(size, opportunity.kl\_divergence)         return self.market\_engine.submit\_order(opportunity, size) |
| :---: | :---- |

| USER | Mercado: NBA|Crypto|Politica|Economia | Capital Minimo: $500 | Latencia: \~3-6s Pilar 1: kelly\_fraction=0, max\_position\_size\_usd=1000, max\_bankroll\_pct=0.25 Pilar 2: min\_net\_profit\_pct=0.0133 (1.3%), hurdle\_rate\_usd=$13 Pilar 3: execution\_ttl\_sec=86400, max\_latency\_ms=6000 Pilar 4: required\_confluence\_count=2, bregman\_deviation\_min=0.02 Pilar 5: stop\_loss\_pct=0.05 (5%), target\_exit='order\_fill', hedge\_mode='natural' |
| :---: | :---- |

| MINT-05 *C* Alta Tasa Exito | Market Making Sweet Spot |
| :---: | :---- |
|  | *Balance optimo entre MINT-03 y MINT-04. Offset dinamico 0.25c-0.50c segun el volumen. Bregman elige el offset optimo automaticamente. Target: mercados con volumen $10k-$30k.* |
|  | **Condicion:**  Offset dinamico 0.25c-0.50c | Factor 0.70x-0.85x | Bregman selecciona offset optimo |
|  | **Familia:** Familia C — Optimizacion Estadistica   |   **Plataforma:** Polymarket   |   Cap. Min: $500   |   **Latencia:** \~3-6s |

| Positivo Spread Garantizado | 70-85% LP Rewards | Balance Modo Operativo | Dinamico Ajuste Offset |
| :---: | :---: | :---: | :---: |

### **Configuracion JSON — Perfil de Usuario**

El desarrollador inyecta este JSON antes de cada operacion. El agente es 'ciego' a los datos del mercado hasta que este perfil este definido.

| {   "strategy\_id": "ST\_010\_MM\_SWEET\_SPOT",   "familia": "Familia C — Optimizacion Estadistica",   "market\_context": {     "category": "Economia|Sports|NBA",     "min\_volume\_threshold": 10000,     "market\_expiry\_min\_hours": 48   },   "user\_parameters": {     "pilar\_1\_risk": {       "kelly\_fraction": 0,       "max\_position\_size\_usd": 1000,       "max\_bankroll\_pct": 0.2     },     "pilar\_2\_yield": {       "min\_net\_profit\_pct": 0.005,       "include\_gas\_fees": true,       "hurdle\_rate\_usd": 3     },     "pilar\_3\_time": {       "execution\_ttl\_sec": 86400,       "max\_latency\_ms": 6000     },     "pilar\_4\_logic": {       "required\_confluence\_count": 2,       "bregman\_deviation\_min": 0.015     },     "pilar\_5\_exit": {       "stop\_loss\_pct": 0.05,       "target\_exit": "order\_fill",       "hedge\_mode": "natural"     }   } } |
| :---- |

### **Los 5 Pilares — Logica del Desarrollador \+ Configuracion del Usuario**

| PILAR 1  —  GESTION DE RIESGO Y POSITION SIZING |  |
| :---- | :---- |
| **Kelly Adaptativo por Offset** | A 0.25c: capture rate \~90% \=\> max\_bankroll\_pct 20% | A 0.50c: 70% \=\> max 15% Bregman elige el offset: si KL bajo \=\> 0.25c (mercado estable) | KL medio \=\> 0.50c El agente ajusta el offset automaticamente cada 12h segun el capture rate observado |
| **Escalado por Volumen** | Volumen \> $30,000: offset 0.50c | Volumen $10k-$30k: offset 0.25c Ajuste automatico: si en 12h no ejecuta ninguna orden \=\> bajar offset 0.25c Si capture rate \> 80%: subir offset 0.25c (capturar mas spread) |
| **Bregman Selecciona el Offset** | FAMILIA C: este es el uso mas avanzado de Bregman en MINT-05 Bregman computa el offset que maximiza el spread capturado mientras mantiene KL \< 0.05 El resultado de Bregman se inyecta como parametro al calculate\_size() |

| PILAR 2  —  UMBRALES DE RENTABILIDAD NETA |  |
| :---- | :---- |
| **Escenarios de Offset** | A 0.25c: Factor 0.85x \=\> Rewards $0.425/dia | spread \+$2.50/ciclo A 0.50c: Factor 0.70x \=\> Rewards $0.35/dia | spread \+$7.50/ciclo Ambos siempre positivos: ventaja de MINT-05 vs MINT-03 |
| **Hurdle Rate** | min\_net\_profit\_pct: 0.005 (0.5%) — el mas bajo de MINT (offset bajo \= menor spread) hurdle\_rate\_usd: $3.00 por ciclo como minimo check\_profit() evalua segun el offset actual, no un valor fijo |
| **Comparacion** | MINT-05 a 0.50c: APY \~20% | MINT-04 a 0.75c: APY \~26.2% MINT-05 es preferible cuando el mercado no tiene suficiente liquidez para MINT-04 |

| PILAR 3  —  VENTANA DE TIEMPO Y CADUCIDAD |  |
| :---- | :---- |
| **Offset segun Tiempo** | Mercado \> 72h: offset 0.25c (maximizar rewards) | 48-72h: offset 0.50c Mercado \< 48h: cambiar a MINT-04 (0.75c) para maximizar capture antes del cierre execution\_ttl\_sec: 86400 | market\_expiry\_min\_hours: 48h |
| **Revision del Offset** | Revision cada 12h: ajustar segun el capture rate observado Si capture rate \< 40%: bajar offset 0.25c | Si \> 80%: subir offset 0.25c Bregman recalcula el offset optimo en cada revision |
| **Drift** | Si midpoint se mueve \> 2c en 6h: reposicionar al nuevo midpoint El offset se mantiene igual, solo cambia el precio base (nuevo midpoint) |

| PILAR 4  —  VALIDACION DE LA SENAL |  |
| :---- | :---- |
| **Seleccion por Volumen** | Target: mercados con volumen\_24h entre $10,000 y $30,000 (sweet spot de MINT-05) No compite con MINT-04 en mercados muy liquidos (\> $50k) Bregman determina si el mercado es adecuado para MINT-05 o debe ir a MINT-04 |
| **Bregman Elige** | FAMILIA C: bregman\_deviation\_min: 0.015 (entre MINT-03 y MINT-04) Si KL \< 0.01: MINT-03 (muy estable) | KL 0.01-0.05: MINT-05 | KL \> 0.05: MINT-04 Esta logica puede implementarse como un clasificador de mercado automatico |
| **Mercado Zombie** | Rechazar mercados con \< 2 trades/hora: mercado zombie Si volumen cae \> 50%: cerrar posicion y reubicar capital |

| PILAR 5  —  PROTOCOLO DE SALIDA Y COBERTURA |  |
| :---- | :---- |
| **Objetivo Dinamico** | target\_exit: 'order\_fill' | El objetivo se ajusta dinamicamente con el offset Capture rate objetivo: \> 70% con el offset actual en cada ciclo de 24h Bregman calcula el precio de equilibrio como referencia de salida |
| **Stop por Capture Rate** | Si capture rate \< 30% durante 48h: escalar a MINT-04 (+0.75c) Si mercado pierde \> 50% del volumen: cerrar y reubicar capital La adaptabilidad del offset es la ventaja clave de MINT-05 vs las demas |
| **Hedge Natural** | hedge\_mode: 'natural' \=\> cada minteo es su propio hedge (YES+NO \= $1.00) La flexibilidad del offset protege de quedarse en el extreme menos eficiente |

### **Instruccion de Implementacion para el Desarrollador**

| DEV | \# MINT-05 hereda de BaseStrategy (Familia C — Optimizacion Estadistica) class MINT\_05\_Strategy(BaseStrategy):     def execute(self, opportunity):         size \= self.calculate\_size(self.balance)         if not self.check\_profit(opportunity.gross, opportunity.fees): return None         if not self.is\_signal\_alive(opportunity.detected\_at): return None         if not self.validate\_confluence(opportunity.signals): return None         \# Familia C: motor especifico de la familia         size \= self.math.bregman\_optimizer.optimize(size, opportunity.kl\_divergence)         return self.market\_engine.submit\_order(opportunity, size) |
| :---: | :---- |

| USER | Mercado: Economia|Sports|NBA | Capital Minimo: $500 | Latencia: \~3-6s Pilar 1: kelly\_fraction=0, max\_position\_size\_usd=1000, max\_bankroll\_pct=0.2 Pilar 2: min\_net\_profit\_pct=0.005 (0.5%), hurdle\_rate\_usd=$3 Pilar 3: execution\_ttl\_sec=86400, max\_latency\_ms=6000 Pilar 4: required\_confluence\_count=2, bregman\_deviation\_min=0.015 Pilar 5: stop\_loss\_pct=0.05 (5%), target\_exit='order\_fill', hedge\_mode='natural' |
| :---: | :---- |

| MINT-06 *C* Alta Tasa Exito | Compounding Acelerado Multi-Ciclo |
| :---: | :---- |
|  | *Meta-estrategia de reinversion total automatizada. Capital(n) \= Capital(n-1) x 1.01357. Bregman selecciona el mercado optimo para cada ciclo basandose en la estabilidad proyectada.* |
|  | **Condicion:**  Capital(n) \= Capital(n-1) x 1.01357  |  Reinversion inmediata y total al completar cada ciclo |
|  | **Familia:** Familia C — Optimizacion Estadistica   |   **Plataforma:** Polymarket   |   Cap. Min: $500   |   **Latencia:** Ciclos 24h |

| \~40.6% Proyeccion/mes | 30 Ciclos/mes | $500 Capital Minimo | x7.8 Capital en 12m |
| :---: | :---: | :---: | :---: |

### **Configuracion JSON — Perfil de Usuario**

El desarrollador inyecta este JSON antes de cada operacion. El agente es 'ciego' a los datos del mercado hasta que este perfil este definido.

| {   "strategy\_id": "ST\_011\_COMPOUNDING",   "familia": "Familia C — Optimizacion Estadistica",   "market\_context": {     "category": "NBA|Crypto|Politica|Economia|Sports",     "min\_volume\_threshold": 10000,     "market\_expiry\_min\_hours": 72   },   "user\_parameters": {     "pilar\_1\_risk": {       "kelly\_fraction": 0,       "max\_position\_size\_usd": 5000,       "max\_bankroll\_pct": 0.4     },     "pilar\_2\_yield": {       "min\_net\_profit\_pct": 0.013,       "include\_gas\_fees": true,       "hurdle\_rate\_usd": 13     },     "pilar\_3\_time": {       "execution\_ttl\_sec": 86400,       "max\_latency\_ms": 6000     },     "pilar\_4\_logic": {       "required\_confluence\_count": 3,       "bregman\_deviation\_min": 0.01     },     "pilar\_5\_exit": {       "stop\_loss\_pct": 0.05,       "target\_exit": "order\_fill",       "hedge\_mode": "natural"     }   } } |
| :---- |

### **Los 5 Pilares — Logica del Desarrollador \+ Configuracion del Usuario**

| PILAR 1  —  GESTION DE RIESGO Y POSITION SIZING |  |
| :---- | :---- |
| **Formula de Compounding** | Capital(n) \= Capital(n-1) x 1.01357 (factor de crecimiento neto por ciclo) Ciclo 1: $1,000 \=\> $1,013.57 | Ciclo 10: \~$1,144 | Ciclo 30: \~$1,500 | 12m: x7.8 Techo de ciclo: cuando supere $5,000 \=\> dividir en 2 ciclos de $2,500 |
| **Escalado de Liquidez** | Capital $1,000: min\_volume\_threshold $10,000 (ratio 1:10) Capital $2,000: min\_volume\_threshold $20,000 (mismo ratio) Capital $5,000: min\_volume\_threshold $50,000 (mismo ratio) Bregman verifica que el capital es \< 5% del Open Interest del mercado seleccionado |
| **Bregman Selecciona el Mercado** | FAMILIA C: antes de cada ciclo, Bregman evalua todos los mercados candidatos Selecciona el mercado con: mejor combinacion de KL bajo \+ volumen alto Si no hay mercado disponible que cumpla los criterios: mantener en USDC y esperar |

| PILAR 2  —  UMBRALES DE RENTABILIDAD NETA |  |
| :---- | :---- |
| **Escala Perfecta de Fees** | Los fees crecen proporcionalmente con el capital: el 1.3575% neto es constante fee\_n \= fee\_base x Capital(n) / $1,000 (escala perfectamente lineal) hurdle\_rate\_usd: $13.00 (se ajusta automaticamente con Capital(n)) |
| **Horizonte del Compounding** | Objetivo: acumular capital sin retiros durante el periodo planificado Al alcanzar el capital objetivo: convertir a modelo 50% reinvierte / 50% retira Stop: si 3 ciclos consecutivos producen \< 0.5% neto \=\> pausar y revisar |
| **Proyeccion** | $10,000 a 12 meses: \~$78,000 con reinversion total y 30 ciclos/mes Esta proyeccion asume que Bregman siempre encuentra el mercado optimo |

| PILAR 3  —  VENTANA DE TIEMPO Y CADUCIDAD |  |
| :---- | :---- |
| **Cola de Mercados** | La reinversion en \< 30 minutos post-ciclo requiere cola de mercados pre-evaluados Bregman genera la cola en orden de prioridad: mejor KL \+ mejor volumen Si no hay mercado disponible: mantener en USDC (no forzar un ciclo suboptimo) |
| **Expiracion** | market\_expiry\_min\_hours: 72h para completar el ciclo con margen Si el mercado tiene un evento que podria resolverlo antes de 24h: cambiar de mercado |
| **Ciclo Deterministico** | execution\_ttl\_sec: 86400 (24h fijo por diseno del modelo MINT-06) Bregman recalcula antes de CADA ciclo con datos frescos del mercado |

| PILAR 4  —  VALIDACION DE LA SENAL |  |
| :---- | :---- |
| **Criterios por Ciclo (3 de 3\)** | required\_confluence\_count: 3 (todos obligatorios para el compounding) (A) El mercado tiene liquidez minima para el capital actual (ratio 1:10) (B) El capital representa \< 5% del Open Interest del mercado (C) Sin eventos de alta volatilidad programados para las proximas 24h |
| **Bregman como Motor de Seleccion** | FAMILIA C: Bregman es el motor central de MINT-06 Evalua y rankea los mercados candidatos en cada ciclo de reinversion bregman\_deviation\_min: 0.01 (mercado debe ser suficientemente estable) |
| **Deteccion de Saturacion** | Si las propias ordenes representan \> 10% del volumen del mercado: demasiada concentracion Diversificar en 2-3 mercados cuando el capital supere $3,000 por ciclo |

| PILAR 5  —  PROTOCOLO DE SALIDA Y COBERTURA |  |
| :---- | :---- |
| **Horizonte y Diversificacion** | target\_exit: 'order\_fill' por ciclo Al alcanzar capital objetivo: convertir a retiro parcial (50%/50%) Con capital \> $5,000: distribuir en 3+ mercados con ciclos paralelos |
| **Stop del Compounding** | stop\_loss\_pct: 0.05 (5% del pico historico del portafolio total) Si plataforma cambia estructura de fees: recalcular toda la proyeccion Si 3 ciclos consecutivos \< 0.5% neto: pausar y revisar la seleccion de mercados |
| **Hedge por Diversificacion** | hedge\_mode: 'natural' \+ diversificacion de mercados en ciclos paralelos La diversificacion es el hedge del compounding: si un mercado falla, los demas continuan |

### **Instruccion de Implementacion para el Desarrollador**

| DEV | \# MINT-06 hereda de BaseStrategy (Familia C — Optimizacion Estadistica) class MINT\_06\_Strategy(BaseStrategy):     def execute(self, opportunity):         size \= self.calculate\_size(self.balance)         if not self.check\_profit(opportunity.gross, opportunity.fees): return None         if not self.is\_signal\_alive(opportunity.detected\_at): return None         if not self.validate\_confluence(opportunity.signals): return None         \# Familia C: motor especifico de la familia         size \= self.math.bregman\_optimizer.optimize(size, opportunity.kl\_divergence)         return self.market\_engine.submit\_order(opportunity, size) |
| :---: | :---- |

| USER | Mercado: NBA|Crypto|Politica|Economia|Sports | Capital Minimo: $500 | Latencia: Ciclos 24h Pilar 1: kelly\_fraction=0, max\_position\_size\_usd=5000, max\_bankroll\_pct=0.4 Pilar 2: min\_net\_profit\_pct=0.013 (1.3%), hurdle\_rate\_usd=$13 Pilar 3: execution\_ttl\_sec=86400, max\_latency\_ms=6000 Pilar 4: required\_confluence\_count=3, bregman\_deviation\_min=0.01 Pilar 5: stop\_loss\_pct=0.05 (5%), target\_exit='order\_fill', hedge\_mode='natural' |
| :---: | :---- |

| TRADE-02 *B* Variable Tasa Exito | Trading de Impulso (Momentum) — Automatizado |
| :---: | :---- |
|  | *Sigue la tendencia cuando una probabilidad sube con fuerza acompanada de volumen alto. Familia B: el Grafo de Mercados monitorea si el momentum es causado por dependencias logicas entre mercados relacionados.* |
|  | **Condicion:**  delta\_precio \> 0.08/periodo  AND  vol \> percentil\_80  \=\>  compra cuando prob: 10% \=\> 30% |
|  | **Familia:** Familia B — Correlacion y Dependencia   |   **Plataforma:** Polymarket   |   Cap. Min: $100   |   **Latencia:** \<2s |

| Variable Tasa Exito | Cuantitativa Senal | \<2s Latencia | Automatico Stop-Loss |
| :---: | :---: | :---: | :---: |

### **Configuracion JSON — Perfil de Usuario**

El desarrollador inyecta este JSON antes de cada operacion. El agente es 'ciego' a los datos del mercado hasta que este perfil este definido.

| {   "strategy\_id": "ST\_012\_MOMENTUM",   "familia": "Familia B — Correlacion y Dependencia",   "market\_context": {     "category": "NBA|Crypto|Sports|Politica",     "min\_volume\_threshold": 5000,     "market\_expiry\_min\_hours": 168   },   "user\_parameters": {     "pilar\_1\_risk": {       "kelly\_fraction": 0.3,       "max\_position\_size\_usd": 1000,       "max\_bankroll\_pct": 0.1     },     "pilar\_2\_yield": {       "min\_net\_profit\_pct": 0.05,       "include\_gas\_fees": true,       "hurdle\_rate\_usd": 5     },     "pilar\_3\_time": {       "execution\_ttl\_sec": 120,       "max\_latency\_ms": 2000     },     "pilar\_4\_logic": {       "required\_confluence\_count": 2,       "bregman\_deviation\_min": 0.05     },     "pilar\_5\_exit": {       "stop\_loss\_pct": 0.15,       "target\_exit": "price\_target",       "hedge\_mode": "natural"     }   } } |
| :---- |

### **Los 5 Pilares — Logica del Desarrollador \+ Configuracion del Usuario**

| PILAR 1  —  GESTION DE RIESGO Y POSITION SIZING |  |
| :---- | :---- |
| **Kelly Criterion** | f\* \= (p x b \- q) / b Kelly Fraccionado: 0.30 (posicion direccional, sin hedge natural) Max 10% del bankroll por posicion | Max 3 posiciones simultaneas (30%) Usar ordenes LIMIT a precio de mercado \+ 0.5% (nunca market orders) |
| **Exposicion** | max\_position\_size\_usd: $1,000 | max\_bankroll\_pct: 10% Si precio se mueve \> 2% antes de que la LIMIT se llene: CANCELAR No perseguir el precio: si se perdio la entrada optima \=\> esperar el siguiente setup |
| **Grafo de Mercados** | FAMILIA B: el Grafo detecta si el momentum es causado por dependencias logicas Si mercado A (BTC price) mueve mercado B (BTC \> $100k): el impulso es real Si el grafo no confirma la causa del momentum: reducir el kelly a 0.15 |

| PILAR 2  —  UMBRALES DE RENTABILIDAD NETA |  |
| :---- | :---- |
| **Costos y Hurdle** | Gas: \~$0.02 | Fee: 2% sobre la ganancia | Slippage estimado: 0.5-1.0% min\_net\_profit\_pct: 0.050 (5%) — compensar gas \+ fee \+ slippage Solo ejecutar si el objetivo proyectado (\~50%) representa \>= 5% de ganancia bruta |
| **Ejemplo Neto** | Capital $1,000 | Compra a $0.20 \=\> 5,000 tokens Objetivo a $0.50 \=\> valor $2,500 \=\> bruto $1,500 (150%) | Neto \~$1,455 |
| **Hurdle Absoluto** | hurdle\_rate\_usd: $5.00 por trade Si la ganancia esperada en USD \< $5: no vale el riesgo de la posicion direccional |

| PILAR 3  —  VENTANA DE TIEMPO Y CADUCIDAD |  |
| :---- | :---- |
| **TTL de la Senal** | execution\_ttl\_sec: 120 segundos (2 minutos desde la deteccion del momentum) Si el volumen de confirmacion no llega en 2 min: senal invalida \=\> descartar No retener posicion \> 48h: stop de tiempo automatico |
| **Expiracion del Mercado** | market\_expiry\_min\_hours: 168 (7 dias) — momentum confiable lejos del cierre Mercado \< 7 dias: puede ser manipulacion pre-cierre \=\> EVITAR Mercado \< 24h: NO OPERAR en ningun caso |
| **Agotamiento del Momentum** | Monitorear senal cada 5 minutos post-entrada Si delta\_precio \< 0.01 por 2 periodos consecutivos: momentum agotado \=\> SALIR El Grafo de Mercados detecta si el evento causante del momentum ya fue procesado |

| PILAR 4  —  VALIDACION DE LA SENAL |  |
| :---- | :---- |
| **Confluencia (min. 2 de 4\)** | (A) delta\_precio \> 0.08/periodo Y vol \> percentil\_80 (B) RSI sobre serie de probabilidades: RSI \> 60 en tendencia ascendente (C) MACD de probabilidad: linea MACD cruza por encima de la senal (D) Volumen actual \> 2x el promedio de los ultimos 10 periodos |
| **Grafo de Mercados — Confirmacion Causal** | FAMILIA B: el agente re-evalua los mercados relacionados si hay cambio en A Si el momentum en NBA Lakers coincide con cambio en 'Kevin Durant injured': confirmado Si no hay causa identificable en el Grafo: reducir el tamano al 50% |
| **Senal Falsa** | Si precio sube pero OI CAE: traders cerrando posiciones \=\> senal falsa Si 80% del volumen \= 1 wallet: posible manipulacion \=\> RECHAZAR Al menos 10 transacciones distintas en el periodo de la senal |

| PILAR 5  —  PROTOCOLO DE SALIDA Y COBERTURA |  |
| :---- | :---- |
| **Cierre por Objetivo** | target\_exit: 'price\_target' \=\> venta automatica cuando precio alcanza \~50% Objetivo secundario: tomar 50% de la ganancia en 40% y dejar el resto NUNCA mantener hasta la resolucion del evento: riesgo binario inaceptable |
| **Stop-Loss Automatico** | stop\_loss\_pct: 0.15 (15%) desde el precio de entrada Stop de momentum: si precio vuelve al punto de entrada \=\> SALIR sin discusion Stop de tiempo: si en 48h no alcanzo el objetivo \=\> salir al precio de mercado |
| **Hedging Direccional** | hedge\_mode: 'natural' (opcional) Hedge parcial: comprar YES a 20% \+ NO a \~$0.80 (cobertura bilateral opcional) Diversificar: nunca mas del 10% del bankroll en un solo trade TRADE-02 |

### **Instruccion de Implementacion para el Desarrollador**

| DEV | \# TRADE-02 hereda de BaseStrategy (Familia B — Correlacion y Dependencia) class TRADE\_02\_Strategy(BaseStrategy):     def execute(self, opportunity):         size \= self.calculate\_size(self.balance)         if not self.check\_profit(opportunity.gross, opportunity.fees): return None         if not self.is\_signal\_alive(opportunity.detected\_at): return None         if not self.validate\_confluence(opportunity.signals): return None         \# Familia B: motor especifico de la familia         self.math.dependency\_graph.reevaluate(opportunity.related\_markets)         return self.market\_engine.submit\_order(opportunity, size) |
| :---: | :---- |

| USER | Mercado: NBA|Crypto|Sports|Politica | Capital Minimo: $100 | Latencia: \<2s Pilar 1: kelly\_fraction=0.3, max\_position\_size\_usd=1000, max\_bankroll\_pct=0.1 Pilar 2: min\_net\_profit\_pct=0.05 (5.0%), hurdle\_rate\_usd=$5 Pilar 3: execution\_ttl\_sec=120, max\_latency\_ms=2000 Pilar 4: required\_confluence\_count=2, bregman\_deviation\_min=0.05 Pilar 5: stop\_loss\_pct=0.15 (15%), target\_exit='price\_target', hedge\_mode='natural' |
| :---: | :---- |

| IA-01 *B* Variable Tasa Exito | Front-Running Automatizado de Noticias |
| :---: | :---- |
|  | *Monitoriza APIs de noticias en tiempo real y ejecuta ordenes en \< 500ms. Familia B: el Grafo de Mercados identifica que mercados son afectados por cada tipo de noticia.* |
|  | **Condicion:**  API \=\> NLP scorer \=\> Impact Dprob \=\> Build order \=\> Sign \=\> Send  |  \< 500ms end-to-end |
|  | **Familia:** Familia B — Correlacion y Dependencia   |   **Plataforma:** Polymarket   |   Cap. Min: $1,000   |   **Latencia:** \<500ms |

| Variable Tasa Exito | \<500ms Latencia Total | Reuters/AP Fuentes | Nodo RPC Infra Requerida |
| :---: | :---: | :---: | :---: |

### **Configuracion JSON — Perfil de Usuario**

El desarrollador inyecta este JSON antes de cada operacion. El agente es 'ciego' a los datos del mercado hasta que este perfil este definido.

| {   "strategy\_id": "ST\_013\_NEWS\_FRONTRUN",   "familia": "Familia B — Correlacion y Dependencia",   "market\_context": {     "category": "NBA|Politica|Economia|Crypto",     "min\_volume\_threshold": 10000,     "market\_expiry\_min\_hours": 168   },   "user\_parameters": {     "pilar\_1\_risk": {       "kelly\_fraction": 0.25,       "max\_position\_size\_usd": 800,       "max\_bankroll\_pct": 0.08     },     "pilar\_2\_yield": {       "min\_net\_profit\_pct": 0.03,       "include\_gas\_fees": true,       "hurdle\_rate\_usd": 80     },     "pilar\_3\_time": {       "execution\_ttl\_sec": 0.5,       "max\_latency\_ms": 500     },     "pilar\_4\_logic": {       "required\_confluence\_count": 2,       "bregman\_deviation\_min": 0.05     },     "pilar\_5\_exit": {       "stop\_loss\_pct": 0.1,       "target\_exit": "equilibrium",       "hedge\_mode": "natural"     }   } } |
| :---- |

### **Los 5 Pilares — Logica del Desarrollador \+ Configuracion del Usuario**

| PILAR 1  —  GESTION DE RIESGO Y POSITION SIZING |  |
| :---- | :---- |
| **Kelly por Impacto NLP** | f\* basado en el delta de probabilidad estimado por el NLP scorer Kelly Fraccionado: 0.25 | max\_position\_size\_usd: $800 | max\_bankroll\_pct: 8% Max 3 eventos simultaneos: 24% del bankroll expuesto en cualquier momento |
| **Slippage \< 500ms** | Si precio ya se movio \> 3% antes de que llegue la orden: CANCELAR Market orders solo en primeros 200ms; despues: LIMIT orders obligatorias Nodo RPC propio de Polygon: max\_latency\_ms \= 500 (requisito de infraestructura) |
| **Grafo de Mercados** | FAMILIA B: el Grafo mapea que mercados son afectados por cada categoria de noticia 'Fed sube tasas' \=\> re-evaluar: KXFEDDECISION, KXRATES, KXBTC, KXGOLD El Grafo actua en \< 100ms para identificar todos los mercados afectados |

| PILAR 2  —  UMBRALES DE RENTABILIDAD NETA |  |
| :---- | :---- |
| **Costos e Infra** | Gas (nodo propio): \~$0.02 | Fee: 2% sobre la ganancia APIs: Reuters \~$500/mes \+ AP \~$300/mes \+ SportRadar \~$300/mes Costo prorrateado: \~$2.60/dia | hurdle\_rate\_usd: $80 por evento |
| **Hurdle Rate** | min\_net\_profit\_pct: 0.030 (3.0%) | Necesitar \>= 10 trades exitosos/mes Cada trade exitoso debe generar \> $80 neto para cubrir el costo fijo mensual Si capital \< $5,000: la infraestructura de IA-01 no resulta rentable |
| **Ventana de Rentabilidad** | La ventana de front-running es de 100-500ms post-noticia Despues de 500ms: otros bots ya reaccionaron \=\> oportunidad desaparece El execution\_ttl\_sec: 0.5 (medio segundo) es el TTL mas corto de todas las estrategias |

| PILAR 3  —  VENTANA DE TIEMPO Y CADUCIDAD |  |
| :---- | :---- |
| **TTL Ultra-Critico** | execution\_ttl\_sec: 0.5 segundos (el TTL mas corto de las 18 estrategias) Si latencia del pipeline supera 500ms: desactivar IA-01 hasta optimizar la infra max\_latency\_ms: 500 (hard limit — no negociable) |
| **Expiracion del Mercado** | market\_expiry\_min\_hours: 168 (7 dias) — solo actuar en mercados con tiempo suficiente Los eventos de noticias tienen mayor impacto cuando el mercado esta lejos del 50/50 |
| **Impacto Temporal** | La senal es valida solo en los primeros 500ms: el mercado ya la digirió despues No mantener la posicion mas de 30 minutos post-noticia: el edge desaparece |

| PILAR 4  —  VALIDACION DE LA SENAL |  |
| :---- | :---- |
| **Confluencia (min. 2 de 3\)** | (A) NLP scorer confidence \> 85% en el impacto de la noticia (B) Mercado relevante tiene volumen\_24h \> min\_volume\_threshold (C) Sin noticias contradictoras en las ultimas 2h sobre el mismo tema |
| **Fuentes Verificadas** | SOLO: Reuters, AP, Bloomberg, fuentes oficiales NUNCA actuar sobre noticias de redes sociales o fuentes no verificadas El Grafo de Mercados filtra las fuentes no confiables automaticamente |
| **Grafo Confirma Mercados Afectados** | FAMILIA B: el Grafo identifica TODOS los mercados afectados por la noticia Si el Grafo identifica 3+ mercados afectados: considerar cobertura bilateral |

| PILAR 5  —  PROTOCOLO DE SALIDA Y COBERTURA |  |
| :---- | :---- |
| **Cierre por Objetivo** | target\_exit: 'equilibrium' \=\> salida cuando el mercado ha absorbido la noticia Tipicamente 5-30 minutos despues del evento Si precio llego al objetivo proyectado por el NLP: salir inmediatamente |
| **Stop-Loss** | stop\_loss\_pct: 0.10 (10%) — si NLP fue incorrecto el precio cae contra nosotros Stop de tiempo: si en 1 hora el mercado no reacciono \=\> la noticia ya era conocida \=\> salir |
| **Hedge Bilateral en Noticias Grandes** | hedge\_mode: 'natural' (bilateral opcional para noticias de alto impacto) Fed sube tasas \=\> comprar YES en 'tasas \> X%' Y vender YES en 'tasas \< Y%' El Grafo identifica los dos lados del hedge automaticamente |

### **Instruccion de Implementacion para el Desarrollador**

| DEV | \# IA-01 hereda de BaseStrategy (Familia B — Correlacion y Dependencia) class IA\_01\_Strategy(BaseStrategy):     def execute(self, opportunity):         size \= self.calculate\_size(self.balance)         if not self.check\_profit(opportunity.gross, opportunity.fees): return None         if not self.is\_signal\_alive(opportunity.detected\_at): return None         if not self.validate\_confluence(opportunity.signals): return None         \# Familia B: motor especifico de la familia         self.math.dependency\_graph.reevaluate(opportunity.related\_markets)         return self.market\_engine.submit\_order(opportunity, size) |
| :---: | :---- |

| USER | Mercado: NBA|Politica|Economia|Crypto | Capital Minimo: $1,000 | Latencia: \<500ms Pilar 1: kelly\_fraction=0.25, max\_position\_size\_usd=800, max\_bankroll\_pct=0.08 Pilar 2: min\_net\_profit\_pct=0.03 (3.0%), hurdle\_rate\_usd=$80 Pilar 3: execution\_ttl\_sec=0.5, max\_latency\_ms=500 Pilar 4: required\_confluence\_count=2, bregman\_deviation\_min=0.05 Pilar 5: stop\_loss\_pct=0.1 (10%), target\_exit='equilibrium', hedge\_mode='natural' |
| :---: | :---- |

| IA-02 *B* Variable \>70% Tasa Exito | Copy-Trading de Ballenas (Whale Following) |
| :---: | :---- |
|  | *Replica posiciones de wallets Polygon con win\_rate \> 70% en \< 2 segundos. Familia B: el Grafo de Mercados evalua si la whale esta operando basandose en dependencias logicas identificables.* |
|  | **Condicion:**  win\_rate(wallet) \> 70% (90 dias, \>= 20 trades)  AND  orden \> $X  \=\>  replicar en \< 2s |
|  | **Familia:** Familia B — Correlacion y Dependencia   |   **Plataforma:** Polymarket   |   Cap. Min: $500   |   **Latencia:** \<2s |

| \>70% Filtro Win Rate | On-Chain Transparencia | \<2s Latencia Replica | Polygon Blockchain |
| :---: | :---: | :---: | :---: |

### **Configuracion JSON — Perfil de Usuario**

El desarrollador inyecta este JSON antes de cada operacion. El agente es 'ciego' a los datos del mercado hasta que este perfil este definido.

| {   "strategy\_id": "ST\_014\_WHALE\_COPY",   "familia": "Familia B — Correlacion y Dependencia",   "market\_context": {     "category": "NBA|Crypto|Politica|Economia|Sports",     "min\_volume\_threshold": 10000,     "market\_expiry\_min\_hours": 168   },   "user\_parameters": {     "pilar\_1\_risk": {       "kelly\_fraction": 0.2,       "max\_position\_size\_usd": 1200,       "max\_bankroll\_pct": 0.12     },     "pilar\_2\_yield": {       "min\_net\_profit\_pct": 0.04,       "include\_gas\_fees": true,       "hurdle\_rate\_usd": 10     },     "pilar\_3\_time": {       "execution\_ttl\_sec": 2,       "max\_latency\_ms": 2000     },     "pilar\_4\_logic": {       "required\_confluence\_count": 3,       "bregman\_deviation\_min": 0.05     },     "pilar\_5\_exit": {       "stop\_loss\_pct": 0.1,       "target\_exit": "whale\_exit",       "hedge\_mode": "natural"     }   } } |
| :---- |

### **Los 5 Pilares — Logica del Desarrollador \+ Configuracion del Usuario**

| PILAR 1  —  GESTION DE RIESGO Y POSITION SIZING |  |
| :---- | :---- |
| **Kelly de la Whale** | f\* \= (win\_rate x ratio\_promedio \- loss\_rate) / ratio\_promedio Kelly Fraccionado: 0.20 (incertidumbre de replica) Ejemplo: win\_rate=75%, ratio=2x \=\> f\_real=0.125 max\_position\_size\_usd: $1,200 | max\_bankroll\_pct: 12% |
| **Slippage de Replica** | La ballena mueve el precio al entrar: la replica llega DESPUES Si precio ya subio \> 3% desde la entrada de la whale: NO replicar Si orden de la whale \> $5,000 en mercado de $20,000: reducir replica al 50% |
| **Grafo Confirma la Whale** | FAMILIA B: el Grafo verifica si la whale esta explotando dependencias logicas Si la wallet gana sistematicamente en mercados relacionados: estrategia de Familia B Si la wallet gana en mercados no correlacionados: posible insider info \=\> no replicar |

| PILAR 2  —  UMBRALES DE RENTABILIDAD NETA |  |
| :---- | :---- |
| **Hurdle de Replica** | min\_net\_profit\_pct: 0.040 (4.0%) — compensar slippage de replica Solo replicar si el precio post-whale aun tiene \> 5% de upside hasta el objetivo Infra de indexacion on-chain: \~$100/mes (nodo Polygon full) |
| **Ejemplo** | Whale compra $10k a $0.25 \=\> precio sube a $0.28 | Replica a $0.28 Objetivo: $0.50 \=\> ganancia potencial 79% \=\> neto \~75% \=\> REPLICAR |
| **Evaluacion de la Wallet** | Actualizar win\_rate cada 7 dias con los ultimos 90 dias de historial Si win\_rate cae de \> 70% a \< 60% en las ultimas 10 operaciones: dejar de seguir |

| PILAR 3  —  VENTANA DE TIEMPO Y CADUCIDAD |  |
| :---- | :---- |
| **TTL de Replica** | execution\_ttl\_sec: 2 segundos (ventana critica desde la deteccion on-chain) max\_latency\_ms: 2000 | Monitorear mempool de Polygon para reducir latencia |
| **Señal de Salida** | La salida es sincronizada con la whale Si whale vende \> 30% de su posicion: la replica vende 50% automaticamente monitorear el Grafo: si el evento causante del trade de la whale se resuelve \=\> salir |
| **Expiracion** | market\_expiry\_min\_hours: 168 (7 dias) — las whales operan en medio plazo NO replicar en mercados que cierran en \< 48h: la whale puede estar liquidando |

| PILAR 4  —  VALIDACION DE LA SENAL |  |
| :---- | :---- |
| **Confluencia (min. 3 de 4\)** | (A) win\_rate(wallet) \> 70% en 90 dias con \>= 20 trades documentados (B) Orden de la whale \> $1,000 (compromiso real de capital) (C) Mercado tiene volumen\_24h \> min\_volume\_threshold (D) Wallet sin racha de 3 perdidas consecutivas recientes |
| **Grafo de Dependencias** | FAMILIA B: el Grafo verifica si la whale opera siguiendo dependencias logicas Si la whale compra YES en 'Lakers win' despues de 'LeBron regresa': logica clara Si no hay causa logica identificable en el Grafo: reducir replica al 30% |
| **Riesgo Insider** | ADVERTENCIA: la whale puede tener informacion privilegiada (potencialmente ilegal) Solo replicar wallets con historial \> 90 dias y \> 20 trades |

| PILAR 5  —  PROTOCOLO DE SALIDA Y COBERTURA |  |
| :---- | :---- |
| **Whale Exit** | target\_exit: 'whale\_exit' \=\> salida sincronizada con la whale Si whale vende \> 30% de su posicion: ejecutar salida del 50% de la replica El Grafo detecta si el evento causante fue resuelto: salida inmediata |
| **Stop Independiente** | stop\_loss\_pct: 0.10 (10%) desde la entrada de LA REPLICA (no de la whale) Si wallet cae de \> 70% a \< 60% win rate en las ultimas 10 operaciones: detener |
| **Diversificacion como Hedge** | hedge\_mode: 'natural' Max 12% del bankroll en ninguna whale individual Diversificar en 3+ whales distintas con estrategias no correlacionadas |

### **Instruccion de Implementacion para el Desarrollador**

| DEV | \# IA-02 hereda de BaseStrategy (Familia B — Correlacion y Dependencia) class IA\_02\_Strategy(BaseStrategy):     def execute(self, opportunity):         size \= self.calculate\_size(self.balance)         if not self.check\_profit(opportunity.gross, opportunity.fees): return None         if not self.is\_signal\_alive(opportunity.detected\_at): return None         if not self.validate\_confluence(opportunity.signals): return None         \# Familia B: motor especifico de la familia         self.math.dependency\_graph.reevaluate(opportunity.related\_markets)         return self.market\_engine.submit\_order(opportunity, size) |
| :---: | :---- |

| USER | Mercado: NBA|Crypto|Politica|Economia|Sports | Capital Minimo: $500 | Latencia: \<2s Pilar 1: kelly\_fraction=0.2, max\_position\_size\_usd=1200, max\_bankroll\_pct=0.12 Pilar 2: min\_net\_profit\_pct=0.04 (4.0%), hurdle\_rate\_usd=$10 Pilar 3: execution\_ttl\_sec=2, max\_latency\_ms=2000 Pilar 4: required\_confluence\_count=3, bregman\_deviation\_min=0.05 Pilar 5: stop\_loss\_pct=0.1 (10%), target\_exit='whale\_exit', hedge\_mode='natural' |
| :---: | :---- |

| IA-03 *C* Variable Tasa Exito | Modelo de Probabilidad Fair Value |
| :---: | :---- |
|  | *Calcula la probabilidad justa de cada evento con modelos estadisticos propios. Ejecuta cuando la divergencia supera el 5%. Familia C: Bregman valida que la divergencia detectada es real y no un artefacto de iliquidez.* |
|  | **Condicion:**  divergencia \= abs(fair\_value \- precio\_mercado)  \>  5%  \=\>  BUY / SELL segun direccion |
|  | **Familia:** Familia C — Optimizacion Estadistica   |   **Plataforma:** Polymarket   |   Cap. Min: $500   |   **Latencia:** \<1s |

| Variable Tasa Exito | \>5% div. Umbral Minimo | \<1s Latencia | Estadistico Tipo Modelo |
| :---: | :---: | :---: | :---: |

### **Configuracion JSON — Perfil de Usuario**

El desarrollador inyecta este JSON antes de cada operacion. El agente es 'ciego' a los datos del mercado hasta que este perfil este definido.

| {   "strategy\_id": "ST\_015\_FAIR\_VALUE",   "familia": "Familia C — Optimizacion Estadistica",   "market\_context": {     "category": "NBA|Politica|Economia|Crypto",     "min\_volume\_threshold": 5000,     "market\_expiry\_min\_hours": 168   },   "user\_parameters": {     "pilar\_1\_risk": {       "kelly\_fraction": 0.25,       "max\_position\_size\_usd": 1000,       "max\_bankroll\_pct": 0.1     },     "pilar\_2\_yield": {       "min\_net\_profit\_pct": 0.05,       "include\_gas\_fees": true,       "hurdle\_rate\_usd": 5     },     "pilar\_3\_time": {       "execution\_ttl\_sec": 86400,       "max\_latency\_ms": 1000     },     "pilar\_4\_logic": {       "required\_confluence\_count": 2,       "bregman\_deviation\_min": 0.05     },     "pilar\_5\_exit": {       "stop\_loss\_pct": 0.1,       "target\_exit": "convergence",       "hedge\_mode": "natural"     }   } } |
| :---- |

### **Los 5 Pilares — Logica del Desarrollador \+ Configuracion del Usuario**

| PILAR 1  —  GESTION DE RIESGO Y POSITION SIZING |  |
| :---- | :---- |
| **Kelly por Divergencia** | f\* \= (p\_modelo \- p\_mercado) / (1 \- p\_mercado) Kelly Fraccionado: 0.25 (incertidumbre del modelo propio) Ejemplo: modelo=65%, mercado=50% \=\> f\*=0.30 \=\> f\_real=0.075 |
| **Exposicion** | max\_position\_size\_usd: $1,000 | max\_bankroll\_pct: 10% Max 5 divergencias activas simultaneamente: 50% del bankroll Usar siempre ordenes LIMIT (no market): el spread puede consumir la ventaja |
| **Bregman Valida la Divergencia** | FAMILIA C: Bregman verifica si la divergencia es real o un artefacto bregman\_deviation\_min: 0.05 — si el KL es bajo y hay divergencia: posible error del modelo Si Bregman y el modelo de fair value coinciden: senal muy fuerte |

| PILAR 2  —  UMBRALES DE RENTABILIDAD NETA |  |
| :---- | :---- |
| **Hurdle de Divergencia** | Divergencia minima: 5pp | Divergencia 5-8pp: tamano al 50% del Kelly Divergencia \< 5pp: NO OPERAR (dentro del margen de error estadistico del modelo) min\_net\_profit\_pct: 0.050 (5.0%) |
| **Ejemplo Neto** | Capital $1,000 | Compra a $0.50 (mercado) | fair value: $0.65 Si converge: ganancia \= 30% | Gas \-$0.02 | Fee \-$6 | Neto $293.98 \= 29.4% |
| **Costo del Modelo** | APIs de fuentes externas: encuestas, modelos electorales, SportRadar \~$200/mes hurdle\_rate\_usd: $5.00 por trade para cubrir el costo prorrateado del modelo |

| PILAR 3  —  VENTANA DE TIEMPO Y CADUCIDAD |  |
| :---- | :---- |
| **Revaluacion Diaria** | execution\_ttl\_sec: 86400 (24h) — divergencias de fair value duran horas o dias Si divergencia se reduce a \< 3pp al revaluar: salir de la posicion Horizonte ideal: mercados con 7-30 dias al cierre para que el mercado converja |
| **Bregman Confirma Convergencia** | FAMILIA C: Bregman calcula el precio de equilibrio matematico Si el precio de mercado converge hacia el precio de equilibrio Bregman: senal de salida Esta convergencia es la confirmacion de que el modelo de fair value era correcto |
| **Anti-Stale Data** | Actualizar el modelo con datos frescos ANTES de calcular cada divergencia Si las fuentes externas discrepan \> 10pp entre si: no usar IA-03 hasta resolver |

| PILAR 4  —  VALIDACION DE LA SENAL |  |
| :---- | :---- |
| **Confluencia (min. 2 de 3\)** | (A) Divergencia \> 5pp entre modelo y precio de mercado (B) Al menos 2 fuentes externas independientes confirman el fair value (C) Volumen\_24h creciente en las ultimas 48h (convergencia organica esperada) |
| **Bregman como Validador Central** | FAMILIA C — Pilar 4 muy estricto: bregman\_deviation\_min: 0.05 — si KL \< 0.05 el mercado es eficiente \=\> modelo posiblemente incorrecto required\_confluence\_count: 2 incluyendo la confirmacion de Bregman |
| **Anti-Liquidez Falsa** | Verificar que la divergencia no es un artefacto de iliquidez (spread bid-ask amplio) Si el mercado tiene spread \> 5%: la divergencia puede ser ficticia \=\> RECHAZAR |

| PILAR 5  —  PROTOCOLO DE SALIDA Y COBERTURA |  |
| :---- | :---- |
| **Cierre por Convergencia** | target\_exit: 'convergence' \=\> salida cuando precio converge al fair value (dentro de 2pp) should\_exit() compara precio actual con fair\_value y precio\_equilibrio\_bregman Bregman \+ fair value model coinciden en el target de salida: senal fuerte |
| **Stop por Error del Modelo** | stop\_loss\_pct: 0.10 (10%) — si el modelo era incorrecto Si precio se mueve \> 10pp en contra: aceptar la perdida y actualizar el modelo con el aprendizaje |
| **Hedge por Diversificacion** | hedge\_mode: 'natural' | Diversificar en 5+ divergencias de distintos mercados Hedge parcial: 70% YES \+ 30% NO para proteger ante errores del modelo |

### **Instruccion de Implementacion para el Desarrollador**

| DEV | \# IA-03 hereda de BaseStrategy (Familia C — Optimizacion Estadistica) class IA\_03\_Strategy(BaseStrategy):     def execute(self, opportunity):         size \= self.calculate\_size(self.balance)         if not self.check\_profit(opportunity.gross, opportunity.fees): return None         if not self.is\_signal\_alive(opportunity.detected\_at): return None         if not self.validate\_confluence(opportunity.signals): return None         \# Familia C: motor especifico de la familia         size \= self.math.bregman\_optimizer.optimize(size, opportunity.kl\_divergence)         return self.market\_engine.submit\_order(opportunity, size) |
| :---: | :---- |

| USER | Mercado: NBA|Politica|Economia|Crypto | Capital Minimo: $500 | Latencia: \<1s Pilar 1: kelly\_fraction=0.25, max\_position\_size\_usd=1000, max\_bankroll\_pct=0.1 Pilar 2: min\_net\_profit\_pct=0.05 (5.0%), hurdle\_rate\_usd=$5 Pilar 3: execution\_ttl\_sec=86400, max\_latency\_ms=1000 Pilar 4: required\_confluence\_count=2, bregman\_deviation\_min=0.05 Pilar 5: stop\_loss\_pct=0.1 (10%), target\_exit='convergence', hedge\_mode='natural' |
| :---: | :---- |

| IA-04 *A* 60-87% Tasa Exito | Bot de Arbitraje Tipos 1-3 (Sistema Automatizado) |
| :---: | :---- |
|  | *Implementacion automatizada de ARB-01, ARB-02 y ARB-03 en un unico bot. Familia A: el motor de asyncio es el nucleo. Kelly diferenciado por tipo. Para produccion real: ciclo cada 2s via WebSocket.* |
|  | **Condicion:**  Ciclo cada 2s via WebSocket  |  Kelly diferenciado por tipo  |  asyncio.gather() \< 30ms  |  Score \> 50 |
|  | **Familia:** Familia A — Arbitraje Puro   |   **Plataforma:** Polymarket   |   Cap. Min: $1,000   |   **Latencia:** \<30ms |

| 60-87% Tasa por Tipo | \<30ms Latencia | Kelly Por Tipo | WebSocket Deteccion Real-Time |
| :---: | :---: | :---: | :---: |

### **Configuracion JSON — Perfil de Usuario**

El desarrollador inyecta este JSON antes de cada operacion. El agente es 'ciego' a los datos del mercado hasta que este perfil este definido.

| {   "strategy\_id": "ST\_016\_BOT\_ARB\_TYPES123",   "familia": "Familia A — Arbitraje Puro",   "market\_context": {     "category": "NBA|Crypto|Politica|Economia|Sports",     "min\_volume\_threshold": 5000,     "market\_expiry\_min\_hours": 2   },   "user\_parameters": {     "pilar\_1\_risk": {       "kelly\_fraction": 0.2,       "max\_position\_size\_usd": 800,       "max\_bankroll\_pct": 0.08     },     "pilar\_2\_yield": {       "min\_net\_profit\_pct": 0.015,       "include\_gas\_fees": true,       "hurdle\_rate\_usd": 0.1     },     "pilar\_3\_time": {       "execution\_ttl\_sec": 5,       "max\_latency\_ms": 30     },     "pilar\_4\_logic": {       "required\_confluence\_count": 3,       "bregman\_deviation\_min": 0.02     },     "pilar\_5\_exit": {       "stop\_loss\_pct": 0.03,       "target\_exit": "natural\_resolution",       "hedge\_mode": "simultaneous"     }   } } |
| :---- |

### **Los 5 Pilares — Logica del Desarrollador \+ Configuracion del Usuario**

| PILAR 1  —  GESTION DE RIESGO Y POSITION SIZING |  |
| :---- | :---- |
| **Kelly Diferenciado** | Tipo 1 (ARB-01): kelly\_fraction=0.25 | Tipo 2 (ARB-02): 0.20 | Tipo 3 (ARB-03): 0.15 Formula universal: min(kelly, book\_depth x 0.5, max\_pos, bankroll x max\_bankroll\_pct) El bot aplica automaticamente el kelly correspondiente al tipo detectado |
| **Limites por Tipo** | Tipo 1: max 8% bankroll | Tipo 2: max 7% | Tipo 3: max 5% Max 5 operaciones simultaneas: 3 Tipo 1 \+ 1 Tipo 2 \+ 1 Tipo 3 El JSON tiene max\_position\_size\_usd global; el bot lo ajusta por tipo internamente |
| **Slippage por Tipo** | Tipo 1: abortar si precio mueve \> 0.3% | Tipo 2: \> 0.5% | Tipo 3: \> 0.4%/leg Rollback automatico: si asyncio.gather() detecta fallo \=\> cancelar TODAS las piernas |

| PILAR 2  —  UMBRALES DE RENTABILIDAD NETA |  |
| :---- | :---- |
| **Hurdle por Tipo** | Tipo 1: min\_net\_profit\_pct=0.015 (1.5%) | Tipo 2: 0.020 (2.0%) | Tipo 3: 0.030 (3.0%) El JSON tiene un valor global; el bot lo ajusta internamente por tipo antes de check\_profit() Gas: Tipo 1 \~$0.02 | Tipo 2 \~$0.05 | Tipo 3 \~$0.05-$0.25 |
| **Score Minimo** | El bot filtra oportunidades con score \< 50 (parametro configurable en JSON) Score \= profit\_pct x 40 \+ liquidity\_score x 30 \+ vwap\_score x 30 \+ bregman\_boost |
| **Proyeccion del Portafolio** | Tipo 1 (87% exito, alta frecuencia): volumen alto, margen bajo Tipo 3 (60% exito, baja frecuencia): volumen bajo, margen alto El bot prioriza Tipo 1 por frecuencia y Tipo 3 por ROI unitario |

| PILAR 3  —  VENTANA DE TIEMPO Y CADUCIDAD |  |
| :---- | :---- |
| **Filtros por Tipo** | Tipo 1: market\_expiry \>= 2h | Tipo 2: \>= 4h | Tipo 3: \>= 24h TTL por tipo: Tipo 1: 5s | Tipo 2: 10s | Tipo 3: 15s Upgrade critico: ciclo 5min \=\> WebSocket en tiempo real (cada 2s por bloque) |
| **Produccion Real** | Para produccion: ws://clob.polymarket.com/ws (stream en tiempo real) Ciclo actual (batch): 5 minutos — reducir a 2s \= Fase 2 del desarrollo max\_latency\_ms: 30 (hard limit para Familia A) |
| **Rollback por TTL** | Si la deteccion-a-ejecucion supera el TTL del tipo: descartar y esperar el proximo ciclo El bot no reintenta oportunidades expiradas |

| PILAR 4  —  VALIDACION DE LA SENAL |  |
| :---- | :---- |
| **3 Capas Automatizadas** | required\_confluence\_count: 3 (3 capas internas) Capa 1: Detector confirma el tipo de arbitraje con la formula exacta Capa 2: VWAP Calculator valida la profundidad real del libro Capa 3: Bregman Optimizer da el score boost (KL \< 0.05: \+15pts al score final) |
| **Filtros de Volumen** | Volumen\_24h \>= min\_volume\_threshold ($5,000) | book\_depth \>= $200 por lado VWAP filtra automaticamente la liquidez falsa: si VWAP \>\> best\_price \=\> rechazar |
| **Score de Confianza** | Solo ejecutar si score\_total \> 50 (configurable en JSON) Bregman contribuye hasta \+15pts al score via KL-divergence boost |

| PILAR 5  —  PROTOCOLO DE SALIDA Y COBERTURA |  |
| :---- | :---- |
| **Salida por Tipo** | Tipo 1: target\_exit='natural\_resolution' (tokens a $1.00) Tipo 2: target\_exit='immediate\_sell' (ventas post-minteo \< 500ms) Tipo 3: target\_exit='natural\_resolution' (condicion ganadora \= $1.00) |
| **Rollback y Stop** | Tipo 1: si pierna falla \=\> cancelar la otra en \< 100ms Tipo 2: si minteo tarda \> 8s \=\> gestionar par manualmente Tipo 3: si alguna condicion falla \=\> cancelar TODAS inmediatamente |
| **Hedge Integrado** | hedge\_mode: 'simultaneous' \=\> asyncio.gather() es el hedge integrado Todos los tipos usan ejecucion simultanea: las piernas son mutuamente cobertura El sistema registra cada oportunidad y resultado en DB para ajuste de parametros |

### **Instruccion de Implementacion para el Desarrollador**

| DEV | \# IA-04 hereda de BaseStrategy (Familia A — Arbitraje Puro) class IA\_04\_Strategy(BaseStrategy):     def execute(self, opportunity):         size \= self.calculate\_size(self.balance)         if not self.check\_profit(opportunity.gross, opportunity.fees): return None         if not self.is\_signal\_alive(opportunity.detected\_at): return None         if not self.validate\_confluence(opportunity.signals): return None         \# Familia A: motor especifico de la familia         return self.math.asyncio\_gather(\*opportunity.legs, timeout\_ms=30)         return self.market\_engine.submit\_order(opportunity, size) |
| :---: | :---- |

| USER | Mercado: NBA|Crypto|Politica|Economia|Sports | Capital Minimo: $1,000 | Latencia: \<30ms Pilar 1: kelly\_fraction=0.2, max\_position\_size\_usd=800, max\_bankroll\_pct=0.08 Pilar 2: min\_net\_profit\_pct=0.015 (1.5%), hurdle\_rate\_usd=$0.1 Pilar 3: execution\_ttl\_sec=5, max\_latency\_ms=30 Pilar 4: required\_confluence\_count=3, bregman\_deviation\_min=0.02 Pilar 5: stop\_loss\_pct=0.03 (3%), target\_exit='natural\_resolution', hedge\_mode='simultaneous' |
| :---: | :---- |

| IA-05 *B* 45% Tasa Exito | Deteccion de Dependencias LLM \+ IP Solver |
| :---: | :---- |
|  | *Pipeline 3 fases: Heuristica NLP \+ LLM DeepSeek-R1 \+ IP Solver PuLP/Gurobi. Familia B: implementacion completa del Grafo de Mercados con LLM como motor de deteccion de dependencias. Solo viable con capital \>$500k.* |
|  | **Condicion:**  Fase 1: NLP 46,360=\>1,576 | Fase 2: DeepSeek-R1=\>374 | Fase 3: PuLP/Gurobi=\>13 verificados |
|  | **Familia:** Familia B — Correlacion y Dependencia   |   **Plataforma:** Polymarket   |   Cap. Min: \>$500,000   |   **Latencia:** 15-35s CRITICO |

| 45% Tasa Exito | $95k Extraido (1 ano) | \>$500k Capital Minimo | 15-35s ⚠ Latencia CRITICA |
| :---: | :---: | :---: | :---: |

### **Configuracion JSON — Perfil de Usuario**

El desarrollador inyecta este JSON antes de cada operacion. El agente es 'ciego' a los datos del mercado hasta que este perfil este definido.

| {   "strategy\_id": "ST\_017\_LLM\_IP\_DEPS",   "familia": "Familia B — Correlacion y Dependencia",   "market\_context": {     "category": "Politica|Economia|Crypto",     "min\_volume\_threshold": 10000,     "market\_expiry\_min\_hours": 168   },   "user\_parameters": {     "pilar\_1\_risk": {       "kelly\_fraction": 0.1,       "max\_position\_size\_usd": 15000,       "max\_bankroll\_pct": 0.03     },     "pilar\_2\_yield": {       "min\_net\_profit\_pct": 0.05,       "include\_gas\_fees": true,       "hurdle\_rate\_usd": 750     },     "pilar\_3\_time": {       "execution\_ttl\_sec": 3600,       "max\_latency\_ms": 35000     },     "pilar\_4\_logic": {       "required\_confluence\_count": 3,       "bregman\_deviation\_min": 0.1     },     "pilar\_5\_exit": {       "stop\_loss\_pct": 0.15,       "target\_exit": "equilibrium",       "hedge\_mode": "sequential"     }   } } |
| :---- |

### **Los 5 Pilares — Logica del Desarrollador \+ Configuracion del Usuario**

| PILAR 1  —  GESTION DE RIESGO Y POSITION SIZING |  |
| :---- | :---- |
| **Kelly Institucional** | Kelly Fraccionado: 0.10 (tasa 45%, capital institucional) Capital minimo: $500,000 para justificar LLM \+ Gurobi (\~$1,500/mes) max\_position\_size\_usd: $15,000 por dependencia | max\_bankroll\_pct: 3% Max 15% del bankroll en dependencias activas (max 5 simultaneas) |
| **Slippage Institucional** | Con $15,000 por dependencia: ordenes LIMIT obligatorias en AMBAS piernas Si impacto combinado en ambos mercados \> 2%: reducir tamano al 50% |
| **Grafo de Mercados — Motor Principal** | FAMILIA B: IA-05 ES la implementacion completa del Grafo de Mercados LLM DeepSeek-R1 construye y actualiza el Grafo dinamicamente Si mercado A cambia, el Grafo re-evalua TODOS los mercados conectados inmediatamente |

| PILAR 2  —  UMBRALES DE RENTABILIDAD NETA |  |
| :---- | :---- |
| **Costos e Infra** | Gas: \~$0.04 | Fee: 2% por pierna LLM DeepSeek-R1: \~$500/mes | IP Solver Gurobi: \~$1,000/mes Total infra: \~$1,500/mes | hurdle\_rate\_usd: $750 por dependencia verificada |
| **Hurdle Rate** | min\_net\_profit\_pct: 0.050 (5.0%) — el mas alto de todas las 18 estrategias Contexto: $95k extraido en 1 ano \= 0.43% del total de $22.4M del paper IA-05 es un complemento de capital grande, no la estrategia principal |
| **Calibracion LLM** | Verificar manualmente las primeras 10 dependencias para calibrar el LLM Documentar resultados en DB para mejora iterativa del modelo El IP Solver debe usar datos en tiempo real (nunca cacheados) |

| PILAR 3  —  VENTANA DE TIEMPO Y CADUCIDAD |  |
| :---- | :---- |
| **TTL Estructural** | execution\_ttl\_sec: 3600 (1 hora) — dependencias estructurales duran horas Solo actuar en dependencias que llevan \> 60 minutos activas en el Grafo La latencia de 15-35s hace inviable actuar en dependencias de \< 60 min |
| **Re-evaluacion del Grafo** | FAMILIA B: el Grafo se actualiza cada vez que cualquier mercado conectado cambia Si la dependencia desaparece del Grafo en \< 60 min: era un flash \=\> excluir ese par Reevaluar con el pipeline completo cada 15 minutos |
| **Expiracion** | Ambos mercados: cerrar en \> 7 dias | Diferencia de fechas \< 30 dias |

| PILAR 4  —  VALIDACION DE LA SENAL |  |
| :---- | :---- |
| **Pipeline 3 Fases (min. 3 de 4\)** | (A) Fase 1 Heuristica NLP: score \> 0.60 (de 46,360 a 1,576 candidatos) (B) Fase 2 LLM DeepSeek-R1: confidence \> 80% en la dependencia logica (C) Fase 3 IP Solver PuLP/Gurobi: profit neto \> 5% matematicamente verificado (D) Dependencia persistente \> 2 horas en el Grafo de Mercados |
| **Grafo Confirma** | FAMILIA B — Pilar 4 es el corazon de IA-05: El Grafo de Mercados es el validador principal de la dependencia logica Si el LLM detecta una dependencia que el Grafo no confirma: no ejecutar required\_confluence\_count: 3 (LLM \+ IP Solver \+ Grafo de Mercados) |
| **Volumen y OI** | Ambos mercados: volumen\_24h \>= $10,000 | OI combinado \>= $50,000 |

| PILAR 5  —  PROTOCOLO DE SALIDA Y COBERTURA |  |
| :---- | :---- |
| **Cierre por Equilibrio** | target\_exit: 'equilibrium' \=\> salida cuando precios convergen al equilibrio del IP Solver El Grafo detecta la convergencia: si la dependencia se resuelve, salir inmediatamente |
| **Stop de Dependencia** | stop\_loss\_pct: 0.15 (15%) | Stop por rotura de dependencia (evento fundacional resuelto) Stop de modelo: 3 dependencias incorrectas consecutivas \=\> revision manual del LLM Stop de tiempo: dependencia persiste \> 7 dias sin convergencia \=\> SALIR |
| **Hedging Secuencial** | hedge\_mode: 'sequential' \=\> ambas piernas en \< 5s entre si Si solo se puede ejecutar UNA pierna: NO ejecutar la operacion completa Ordenes LIMIT pre-configuradas en ambos mercados ANTES del trigger final |

### **Instruccion de Implementacion para el Desarrollador**

| DEV | \# IA-05 hereda de BaseStrategy (Familia B — Correlacion y Dependencia) class IA\_05\_Strategy(BaseStrategy):     def execute(self, opportunity):         size \= self.calculate\_size(self.balance)         if not self.check\_profit(opportunity.gross, opportunity.fees): return None         if not self.is\_signal\_alive(opportunity.detected\_at): return None         if not self.validate\_confluence(opportunity.signals): return None         \# Familia B: motor especifico de la familia         self.math.dependency\_graph.reevaluate(opportunity.related\_markets)         return self.market\_engine.submit\_order(opportunity, size) |
| :---: | :---- |

| USER | Mercado: Politica|Economia|Crypto | Capital Minimo: \>$500,000 | Latencia: 15-35s CRITICO Pilar 1: kelly\_fraction=0.1, max\_position\_size\_usd=15000, max\_bankroll\_pct=0.03 Pilar 2: min\_net\_profit\_pct=0.05 (5.0%), hurdle\_rate\_usd=$750 Pilar 3: execution\_ttl\_sec=3600, max\_latency\_ms=35000 Pilar 4: required\_confluence\_count=3, bregman\_deviation\_min=0.1 Pilar 5: stop\_loss\_pct=0.15 (15%), target\_exit='equilibrium', hedge\_mode='sequential' |
| :---: | :---- |

| IA-06 *C* N/A (Capa Transversal) Tasa Exito | Optimizacion Matematica Bregman \+ Frank-Wolfe |
| :---: | :---- |
|  | *Capa transversal que calcula el tamano optimo de posicion para TODAS las estrategias. Bregman minimiza KL-divergence. Frank-Wolfe reduce O(2^n) a O(1/epsilon\*t). Se aplica automaticamente sobre cualquier oportunidad que pase los filtros de su estrategia origen.* |
|  | **Condicion:**  min D\_KL(mu||theta)  s.t. mu en politopo\_marginal  |  Frank-Wolfe: O(1/epsilon\*t) vs O(2^n) |
|  | **Familia:** Familia C — Optimizacion Estadistica   |   **Plataforma:** Polymarket \+ Kalshi   |   Cap. Min: Cualquiera   |   **Latencia:** \<100ms |

| Optimiza Funcion | Bregman+FW Algoritmos | \<100ms Latencia | Transversal Aplicacion |
| :---: | :---: | :---: | :---: |

### **Configuracion JSON — Perfil de Usuario**

El desarrollador inyecta este JSON antes de cada operacion. El agente es 'ciego' a los datos del mercado hasta que este perfil este definido.

| {   "strategy\_id": "ST\_018\_BREGMAN\_OPTIMIZER",   "familia": "Familia C — Optimizacion Estadistica",   "market\_context": {     "category": "Todas (capa transversal)",     "min\_volume\_threshold": 0,     "market\_expiry\_min\_hours": 0   },   "user\_parameters": {     "pilar\_1\_risk": {       "kelly\_fraction": 0,       "max\_position\_size\_usd": 0,       "max\_bankroll\_pct": 0     },     "pilar\_2\_yield": {       "min\_net\_profit\_pct": 0,       "include\_gas\_fees": true,       "hurdle\_rate\_usd": 0     },     "pilar\_3\_time": {       "execution\_ttl\_sec": 0,       "max\_latency\_ms": 100     },     "pilar\_4\_logic": {       "required\_confluence\_count": 0,       "bregman\_deviation\_min": 0     },     "pilar\_5\_exit": {       "stop\_loss\_pct": 0,       "target\_exit": "bregman\_equilibrium",       "hedge\_mode": "optimal"     }   } } |
| :---- |

### **Los 5 Pilares — Logica del Desarrollador \+ Configuracion del Usuario**

| PILAR 1  —  GESTION DE RIESGO — KELLY COMPLEMENTADO POR BREGMAN |  |
| :---- | :---- |
| **Kelly \+ Bregman** | IA-06 NO reemplaza Kelly: lo COMPLEMENTA matematicamente Flujo: Kelly calcula f\* \=\> Bregman ajusta f\_optimo via proyeccion al politopo marginal f\_optimo \= argmin D\_KL(f\_kelly || distribucion\_precios\_actual) Resultado: tamano de posicion coherente con la estructura completa del mercado |
| **Score Boost por KL (Catalogo18 exacto)** | KL \< 0.01: boost \+15pts \=\> aumentar exposicion en 20% KL 0.01-0.05: boost \+10pts \=\> aumentar en 10% KL 0.05-0.10: boost \+5pts \=\> mantener exposicion base KL \> 0.10: sin boost \=\> respetar el Kelly base sin modificacion |
| **Implementacion en el Ciclo** | FAMILIA C — Bregman se ejecuta en \< 100ms en el PASO 4 del ciclo del agente: Despues de validate\_confluence() y ANTES de execute() calculated\_size \= bregman\_optimizer.optimize(kelly\_size, kl\_divergence, market\_data) |

| PILAR 2  —  IMPACTO EN EL PORTAFOLIO (NO tiene costo transaccional propio) |  |
| :---- | :---- |
| **Metrica de Exito** | IA-06 se evalua por su impacto en el portafolio TOTAL (no por operacion individual) Metrica 1: reduccion del drawdown maximo del portafolio en \> 15% vs Kelly simple Metrica 2: aumento del Sharpe Ratio del portafolio total en \> 10% KL-divergence promedio mantenida \< 0.05 en el 80% de las operaciones |
| **Costo de Infraestructura** | IA-06 NO tiene costo de transaccion propio (es capa de calculo) Costo de computo: \< $50/mes (CPU local o cloud) Beneficio: reduce operaciones mal dimensionadas \=\> ahorra fees en las demas estrategias NCAA 63 juegos: 2^63 \= 9.2 quintillones \=\> Bregman+FW \=\> 63 outcomes manejables |
| **Ejemplo de Impacto** | Sin IA-06: portafolio con Kelly simple, drawdown maximo 20% Con IA-06: drawdown maximo reducido a \~15% En portafolio de $100,000: ahorro de \~$5,000 en perdidas maximas |

| PILAR 3  —  ADAPTACION TEMPORAL DE BREGMAN |  |
| :---- | :---- |
| **Iteraciones por Tiempo al Cierre** | Mercado \> 7 dias: Bregman 15-30 iteraciones (convergencia completa) Mercado 1-7 dias: Bregman 5-10 iteraciones (velocidad prioritaria) Mercado \< 24h: Frank-Wolfe rapido \< 10ms (en lugar del Bregman completo) Ciclo de actualizacion del politopo marginal: cada 5 minutos |
| **TTL de IA-06** | execution\_ttl\_sec: 0 (se ejecuta en \< 100ms, siempre disponible) Se recalcula para CADA nueva oportunidad detectada por cualquier estrategia max\_latency\_ms: 100 (limite de computo de Bregman) |
| **Grafo \+ Bregman** | IA-06 puede combinarse con el Grafo de Mercados (Familia B) para calcular el hedge optimo en posiciones cross-market Frank-Wolfe reduce las 2^n posibles coberturas a combinaciones manejables |

| PILAR 4  —  VALIDACION Y DETECCION DE LIQUIDEZ FALSA VIA BREGMAN |  |
| :---- | :---- |
| **Bregman como Filtro Universal** | Bregman identifica automaticamente precios inconsistentes con el politopo marginal Si precio es outlier vs el politopo: KL \> 0.10 \=\> sin boost \=\> posicion reducida Este filtro actua automaticamente en TODAS las estrategias que usan IA-06 |
| **Liquidez y Politopo** | La liquidez real del mercado esta implicitamente en el calculo del politopo marginal Mercados con bajo volumen tienen un politopo mas inestable \=\> KL mayor automaticamente Esto reduce la posicion en mercados iliquidos sin necesidad de filtros adicionales |
| **Sin Confluencia Propia** | IA-06 NO tiene required\_confluence\_count propio Se activa automaticamente cuando la estrategia origen supera sus filtros de confluencia El score boost de KL-divergence es su unica contribucion a la confluencia total |

| PILAR 5  —  TARGET, STOP-LOSS Y HEDGE OPTIMO VIA BREGMAN |  |
| :---- | :---- |
| **Target de Salida Bregman** | target\_exit: 'bregman\_equilibrium' \=\> precio de eficiencia del politopo marginal Cuando precio de mercado converge al equilibrio Bregman: la oportunidad desaparecio Este target se comunica a la estrategia origen para su salida automatica |
| **Stop-Loss Optimo Calculado** | IA-06 calcula el stop-loss optimo para cada estrategia: stop\_optimo \= precio\_entrada \- (KL x precio\_entrada x factor\_riesgo\_del\_tipo) Este valor se pasa al should\_exit() de la estrategia origen automaticamente |
| **Hedge Optimo via Frank-Wolfe** | hedge\_mode: 'optimal' \=\> Frank-Wolfe calcula el hedge optimo del portafolio completo Reduce 2^n posibles coberturas a la combinacion optima en \< 100ms NCAA 63 juegos: sin FW se necesitarian evaluar 9.2 quintillones de combinaciones |

### **Instruccion de Implementacion para el Desarrollador**

| DEV | \# IA-06 hereda de BaseStrategy (Familia C — Optimizacion Estadistica) class IA\_06\_Strategy(BaseStrategy):     def execute(self, opportunity):         size \= self.calculate\_size(self.balance)         if not self.check\_profit(opportunity.gross, opportunity.fees): return None         if not self.is\_signal\_alive(opportunity.detected\_at): return None         if not self.validate\_confluence(opportunity.signals): return None         \# Familia C: motor especifico de la familia         size \= self.math.bregman\_optimizer.optimize(size, opportunity.kl\_divergence)         return self.market\_engine.submit\_order(opportunity, size) |
| :---: | :---- |

| USER | Mercado: Todas (capa transversal) | Capital Minimo: Cualquiera | Latencia: \<100ms Pilar 1: kelly\_fraction=0, max\_position\_size\_usd=0, max\_bankroll\_pct=0 Pilar 2: min\_net\_profit\_pct=0 (0.0%), hurdle\_rate\_usd=$0 Pilar 3: execution\_ttl\_sec=0, max\_latency\_ms=100 Pilar 4: required\_confluence\_count=0, bregman\_deviation\_min=0 Pilar 5: stop\_loss\_pct=0 (0%), target\_exit='bregman\_equilibrium', hedge\_mode='optimal' |
| :---: | :---- |

