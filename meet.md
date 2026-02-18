16 feb 2026
DEGA - AI development foundation - Transcripción
00:00:00
 
Carlos Rene: cague demasiado, pues porque ustedes dos vieron qué tipo de errores habían, pues, o sea, esos errores son bárbaros en mi opinión, pues, ¿entendés? Para para mí eso no noía tal vez lo esperaría de un junior developer que acaba de salir, pero cometiendo cadales de que no usan cashing y un montón de otras cosas. Ustedes dos creo que fueron los que llegaron a salvar el día realmente con con la salida, pues, ¿verdad? Entonces el punto es tomar esto y ahora ya verlo directamente en Code. Ustedes cuando la mar agarre las tareas, entonces que se desarrolle el código y que tengan las revisiones correctas, ¿verdad? Y a partir de eso este evitar estos problemas. Pues entonces e en podemos partir con algo
Daniel Tutila: Ah.
Carlos Rene: sencillo que es lo que mandó Daniel que usan los maes de Trader Bit. Está muy bueno. Su maes son de un sistema de una empresa de seguridad. Entonces ustedes deberían de revisar ahí lo que están usando ellos, pero yo me imagino que cubren un montón de patrones, ¿verdad? Y luego si ocupamos algo específico de nosotros lo vamos agregando. Por decir algo, si tal vez trailer bita, que los handpints estén usando algún metodología de cashing, si ellos no lo tienen, nosotros sí lo tenemos que tener, ¿verdad?
 
 
00:01:16
 
Carlos Rene: Entonces, y para ends, ¿verdad? para todo. Tal vez, obviamente, no van a estar preguntando yo, ¿dónde está la caché cuando estoy revisando un file system de pegando la base de datos, verdad? Un ORM. ¿Para qué vamos a revisar el catch?
Daniel Tutila: Mhm.
Carlos Rene: Ahí pues ahí no tiene no tiene nada que ver. Eso es un un ejemplo para que ustedes entiendan cómo quiero que lo ataquen y lo vean. Entonces, end point, esto es lo que tengo que ver, base de dat,
Daniel Tutila: Sí.
Carlos Rene: pero en base de datos necesito ver que estén usando, por ejemplo, connection pools, ¿verdad? que fue algo que también tuvo que arreglar Blood, si no me equivoco, creo que él fue el que arregló eso, que que Abu no lo estaba usando. Entonces, imagínense, o sea, m*****, por eso yo lo sé desde el 2014 cuando lo inventaron ayer. Entonces, eso debería estar ya revisado para que nunca se vuelva a cometer ese tipo de error. Entonces, el rol de la marata, people tiene que pasar a ser más interactuar con cloud. Siempre quiero que ellos dirijan la parte del desarrollo porque este, bueno, podemos hacerle algo como que CL agarre una tarea y que haga una sugerencia de los patrones a utilizar para que alguien los revise, porque por darle un ejemplo con lo que con lo del sistema de de control de los agentes, eso de combinar, de hacer un híbrido de Ves con Ll, eso se me ocurrió a mí.
 
 
00:02:30
 
Carlos Rene: Cloud no me lo recomendó para nada, pues y no me lo hubiera recomendado porque es algo demasiado específico y tendría que tener el contexto de qué quiero hacer yo. Lo que yo quiero hacer es reducir los los hits al Llm. Entonces, por eso yo fui el que le dijo, mira, que qué podemos hacer aquí para, bueno, como yo conozco los patrones, entonces le dije yo, podemos usar behavior trees y tal y tal, pero quiero usar el LLM para tener flexibilidad en el comportamiento. Entonces ahí Cloud me dijo, mira, está bien, lo que deberíamos de hacer es un blackboard pattern. me dice, "Ya me lo muestro." Me dice, "Mira, vamos a poner acá el behavior tree y acá el Llm y el Blackboard es el punto de conexión para los dos." Entonces, el B te da soluciones inteligentes si la pregunta es inteligente, ¿verdad? Entonces, lo que tenemos que tener ahí es tal vez tener algún par de que el mismo genere un par de patrones de sugerencia como sugerencia y el developer es el que tiene que tener juicio de cómo de si aplicarlas o no. En el peor escenario, digamos que la Mara está huevona y aplica el patrón ese, pero por lo menos, o sea, Cloud Opus 4.6 te va a dar una sugerencia de nivel so, pues no te dar una sugerencia tonta.
 
 
00:03:38
 
Carlos Rene: Eh, con Sonet todavía te daba algunas sugerencias un poco mensas, por decirlo así, te hacía repetir clases o repetir funciones en clases y funciones así. Entonces, por lo menos ese es como un piso, pues esto le llamo yo el baseline, el piso de la calidad. No es que encima de él no se pueda hacer más calidad, pero esto nos va a garantizar que por eso lo hací el peor c***** posible llegamos a ese piso, ¿verdad? Entonces este entonces vamos a agrar lo de trailer bits. Tenemos que ver cómo eso lo adaptamos con nuestras tareas. Ahí estaba también este caso del del método BMAT, ¿verdad? Pablo lo ha utilizado bastante. Bimat te genera como unas tareas, ¿verdad? genera múltiples roles y uno los puede invitar a una vaina que se llama algo así como start party o party talk o algo así y el mae el mismo determina cuáles de sus agentes invitar y los carga y los pone a conversar y los pone a debatir,
Daniel Tutila: Hm.
Carlos Rene: ¿verdad? Entonces uno puede ser un UI engineer, el otro un database engineer y así. Entonces los maes se ponen a debatir y hay como creo que 23 tipos de roles o algo así en el BMAT. Entonces, ese puede ser un buen approach para atacar cada una de las eh de las tareas de las user stories, ¿verdad?
 
 
00:04:52
 
Carlos Rene: Entonces, quedaría ahí como decisión que vean ustedes que le un vistazo al BMAT y vean cómo se puede integrar con eso y cómo lo pegamos todo, ¿verdad? Porque ahorita creo que estamos usando Clickup, pero creo que todo el mundo dijo que prefería usar los git eh issues, ¿verdad? Mi opinión está bien, genial. Menos integraciones, mejor. Entonces tiene que haber alguna forma ahí donde el PMAT pueda crear las tareas en kit y jalarlas de ahí en vez de estar hablando con creo que ahorita solo usa MD files, ¿verdad? Entonces, el mismo cloud code ahí ustedes le pueden hacer un fork al BMAT,
Alberto Cerrato: Sí.
Carlos Rene: lo pueden modificar y eso si quieren lo hagan la open source, incluso lo forquean ahí en su repo y lo modifican y le agregan que ahora hable con los kitus. Tal vez hasta alguien ya tenga un PR de eso o no sé, un branch de eso, pero bueno,
Daniel Tutila: Michael,
Carlos Rene: ese sería,
Daniel Tutila: Michael tiene algo,
Carlos Rene: creo.
Daniel Tutila: ahora estoy hablando con Michael. Michael tiene algo con los GitHubs y todo eso ya implementado en en un framework que él está usando. Eh, esta semana vamos a hacer una llamada para que nos lo muestre. Te voy a invitar, Alberto, para ver que que estemos ahí.
 
 
00:05:53
 
Carlos Rene: H
Daniel Tutila: Ya lo voy a decir a David para coordinar esa parte. No sé qué tanto lleguemos a implementar o qué tan lejos lleguemos la implementación esta semana con para lo de la para Min City,
Alberto Cerrato: Yes.
Daniel Tutila: pero si esto lo veo más a largo plazo y o sea que va a pasar después de esto y si lo necesitamos implementar.
Carlos Rene: Bueno, sí, como habíamos hablado, lo podemos ir haciendo de forma paulatina. Lo primero, por ejemplo, sería todo el mundo tiene Code, ¿verdad? Con los estándares de esto, de todos los bits. Y por ejemplo, me sentiría bien con que le hagan el TDD, el test driven development y y luego el code review,
Daniel Tutila: Ya está
Alberto Cerrato: Mm.
Daniel Tutila: ahí.
Carlos Rene: que Code ayude con esas dos cosas. De nuevo, eso nos va a dar un piso de tal manera que por mucho que la caguemos, vamos a llegar a un top donde de aquí para abajo no la vamos a c****.
Alberto Cerrato: ese que que mencionan que han compartido Trail of Beat, ese, ¿dónde dónde está esa ese documento, la referencia?
Daniel Tutila: Ya te lo paso.
Carlos Rene: Ya te lo pasado. Yo tenemos un repo, de hecho, que ya lo forqué yo a al repo de Tedega.
 
 
00:07:03
 
Alberto Cerrato: Excelente. T
Carlos Rene: Entonces, sí. Ese ese Trail of Beats es como una empresa que se dedica a hacer eh auditorías y servicios de seguridad, pero hacen varias cosas, penetration testing, eh po bounties, un montón de vainas así son como los rockstar de de todo lo que es seguridad. Entonces, una buena base, pues, ¿verdad?
Alberto Cerrato: Excelente.
Daniel Tutila: Sí. Okay.
Alberto Cerrato: Ok.
Daniel Tutila: La parte del TDD ya está, ya la metió Blada. Ahora después de esta reunión va a dar la demo. Y de mi lado yo estaba metiendo los skills y de la definición de los agents MD para que ya funcionara. Y lo que he estado probando, estado, lo que estado haciendo ahorita es probar el comando o el agente que está haciendo los reviews, porque yo tengo el que uso para poder hacer los reviews, eh, pero ese lo copio y pego eh a medida de lo que yo quiero que haga.
Alberto Cerrato: Mhm.
Daniel Tutila: Entonces estoy tratando de hacer uno más genérico para que me funcione. El problema es de que los tests que he estado haciendo no me encuentra la misma cantidad de de issues el comando que quiero que quiero meter en el repo que el que yo
Carlos Rene: M.
Daniel Tutila: uso para copy paste.
 
 
00:08:26
 
Daniel Tutila: Y el que yo uso para copy paste es horrible, es feo, pero me funciona. O sea, porque le digo, hace esto acá y al final le vuelvo a decirlo acá y le meto al final alguna cosa extra. enfocate solo en esto o enfocate solo en lo otro. Pero no sé por qué, no sé por qué no me está funcionando.
Carlos Rene: Okay.
Daniel Tutila: No lo he encontrado. Porque no me genera bien los
Carlos Rene: ¿Cómo? O sea, cuando, o sea,
Daniel Tutila: issos.
Carlos Rene: el prom que vos metés normalmente de forma manual para decirle que te haga el DDD cuando lo has querido convertir a un skill no funciona. Eso es lo que estás diciendo.
Daniel Tutila: Si no, para el TDD, para los para el COD review.
Alberto Cerrato: Hebría
Daniel Tutila: Ajá.
Carlos Rene: Ah, para el cor,
Daniel Tutila: Para el COD review.
Carlos Rene: perdón.
Daniel Tutila: Ajá. Déjame, déjame te voy a mostrar dónde lo
Carlos Rene: Ah.
Daniel Tutila: tengo.
Alberto Cerrato: que ver el el prom, como tú dices, eh, una una y la otra cosa, como mencionaste,
Daniel Tutila: Sí.
Alberto Cerrato: creo que tú dices que tú lo haces como en dos o tres pasos.
 
 
00:09:22
 
Alberto Cerrato: Eso podría estar afectando también, ¿verdad? Si él primero genera eh cierta información base y tú luego lo haces reaccionar, tal vez esa parte no está bien configurada en el skill, que el skill también tenga como varias etapas.
Daniel Tutila: Ya te voy a poner este. Mira, porque ¿dónde estamos? Lo voy a pegar acá. Por ejemplo, eso es lo que yo hago. Yo utilizo el code review que se viene ya de cloud. Entonces nada más se instala y le digo y es un comando review. Hacerme el review de este PR. Le digo, el código ha sido actualizado y todo. Eh, le quito unas cosas acá de que no vaya a modificar nada del código porque no quiero que me vaya a hacer ninguna actualización el código y que no me vaya a postear nada a a al kit porque mi intención no es que lo haga directo,
Alberto Cerrato: Mhm.
Daniel Tutila: sino que yo lo que he estado haciendo es revisando los issos y validándolos para ver si tienen sentido o no contra la lógica o lo que se tenía que que hacer el el PI. Esto es lo que quiero automatizar y por algún
Carlos Rene: O sea, cuando cuando lo metí en un comando es que no te funciona.
Daniel Tutila: motivo cuando lo cuando le pego esto a Clow
 
 
00:10:39
 
Carlos Rene: Sí.
Daniel Tutila: directamente me funciona, pero ya cuando le digo lo le dije al clow le dije convertíme esto a un a un comando. me lo convirtió en un comando, lo corrí y dice, "Usá ese comando, el code review, code review, pero el output que me tira no es el mismo,
Carlos Rene: Qué loco.
Daniel Tutila: no es para nada del mismo. O sea, lo ejecuto, pasa haciendo toda la ejecución. Yo veo que está lanzando todos los agentes para ver toda la toda la parte de los review y al final solo me tira en el reporte solo me tira dos issus, solo dos issues y borro ese reporte, vuelvo a correr el copy pego esta cosa en el prompt y me encuentra 15 issues. Entonces ahí todavía lo estoy.
Carlos Rene: No, qué raro.
Daniel Tutila: Ah, lo estoy toneando porque no sé qué pasa, la verdad. O sea, no es no es como que ya le
Carlos Rene: Y cuando no le preguntaste a él mismo, ¿qué te pasa que cuando hago esto no funciona?
Daniel Tutila: dije y y me y me dijo, "Ah, sí, ya vi el error que no estaba no está no se está llamando bien al al a la gente, pero no sé, ya voy a ver, voy a quitarle, voy a tratar de hacer lo más simplificado del comando y si no, pues ni modo, voy a ver qué diablos le hago.
 
 
00:11:56
 
Daniel Tutila: meto algún agente o algo para que lo haga el agente y no un comando.
Carlos Rene: Bueno, está bien. Okay. Entonces, mira,
Daniel Tutila: Ok.
Carlos Rene: primeros pasos para Midnight City es el TDD y el C review Review. Arranquemos con eso, ¿verdad? Este, como Alberto está arrancando con un proyecto nuevo, ¿verdad? Entonces, él puede ir implementando un par de cosas más. Entonces, eh sería de ver cuáles cuáles son las que son relevantes para Midnight Simulation y él de repente las puede adelantar, ¿verdad? Ya sea, por ejemplo, usar el usar lo del BMAT,
Daniel Tutila: Ah.
Carlos Rene: este o por bueno, uno que se ha vuelto bien popular, que todo el mundo dice que está usando es como base es la metodología que publicó Openi el otro día y yo ya hice un documento en este en el fork nuestro de lo de Trits. Ahí hice un documento que que habla de cómo implementar esa
Daniel Tutila: Mhm.
Carlos Rene: metodología con cloud code y le dije, "No, porque el me decía, le veo, mira, quiero implementar esta." Ah, entonces sí vamos a crear estos comandos y los tenés que correr aquí, allá. Yo no quiero estar corriendo mi madre, yo quiero correr un comando para que me instale la configuración global en cloud y quiero comer luego otro comando que sea como un init en el repo para que entonces comience a trabajar todo eso.
 
 
00:13:13
 
Carlos Rene: Entonces el má, ah okay, ya lo podemos hacer así. Así. Entonces empezó y obviamente hay que darle una revisada a esa, ¿verdad? Antes de tirarse ahí de cabeza, pero por ahí va la cosa. Entonces este lo primero entonces, Alberto sería que te familiaricés con lo de trailer Beats. Si quieres darle una probadita, mira a ver cómo funciona con con el proyecto, ¿verdad? Este, cómo se utilizaría, hacerle un cambio sencillo, cambiarle los colores, ¿me entendés? Y y que yo te voy a decir, el otro va a ser un fork de Visual Studio Code. Entonces, bien, la llamada que tengo más tarde te voy a dar los requerimientos.
Alberto Cerrato: Sí.
Carlos Rene: Pero esencialmente por por ahí va la onda. Entonces, eh, puedes probarlo, puedes experimentarlo ese bits, a ver cómo cómo lo ves, cómo lo sentís. lo de si te buscas otro branch es el único otro branch que hay ahí que es el mío y ahí vas a ver un MD file y ese men va a tener las instrucciones de cómo aplicarlo de Open AI ahí y tiene la
Alberto Cerrato: Mhm.
Carlos Rene: referencia de la URL de Open AI por si te quieres ir a leer lo que Open ya escribió a tardar como una hora y media tal vez dos horas en leerlo lo que Open ya hizo y luego entonces lo acá Open le llama el hardness no sé qué vaina hardness es como arnés
 
 
00:14:22
 
Alberto Cerrato: Sí, sí.
Carlos Rene: Porque tienen como guindado a los con hooks, ¿verdad? Como yo termino esta vaina, entonces eso arranca otra vaina y eso termina y eso arranca otra vaina, ¿verdad?
Alberto Cerrato: Perfecto. Sí, sí,
Carlos Rene: Eso es como lo veo
Alberto Cerrato: sí. Yo ahorita si tengo bastante información por absorber, pero no hay problema. Pues tú tú sabes,
Carlos Rene: yo.
Alberto Cerrato: solo estoy en esta parte ahorita y en la que tenemos con Canon. Entonces sí, pues solo me voy a meter a leer esta parte. Ya vi el MD que tenés ahí, lo voy a revisar a profundidad junto con la extensión de Open AI, per con el documento completo y también el el repo de Trail of Beats, el Cloud Code Config.
Carlos Rene: Y otra cosa que puedes probar es, digamos, no semana, sino que la siguiente, por ejemplo, todos los de la siguiente en adelante, todos los viernes haces un chequeo de los cambios en el repo de Trad Beats y haces un pull para de
Alberto Cerrato: Ok.
Carlos Rene: nosotros y lo meras y probas esa misma metodología para esa m*****, ¿me entendés? volvés a probar todo es que tenga que ser como quien dice compounding effect, ¿verdad? Es como cuando uno ahorra plata que te genera plata, luego agarrás esa plata y la volves a ahorrar y te genera más plata y así,
 
 
00:15:42
 
Alberto Cerrato: Mhm.
Carlos Rene: ¿verdad? Tiene que haber un proceso acumulativo.
Daniel Tutila: Ah.
Carlos Rene: Entonces, eh lo mismo que ya estás usando para ayudarte a desarrollar, lo vas a usar para mantener el repo actualizado con otras con las herramientas o las mejoras de trailer bits para
Alberto Cerrato: Ok.
Carlos Rene: mantenernos siempre al al tanto, ¿verdad? Y ahí continuamos, ¿verdad? con eso. Entonces, eso de aquí a unos 6 meses, ¿verdad?, la vaina se va a ver que va a empezar a sacar las cosas de una manera muy estable y muy de muy alta calidad. Este,
Daniel Tutila: Mhm.
Carlos Rene: entonces así vas procesando y en cambio Daniel va viendo entonces todo lo que vos vas trabajando y lo va ir jalando y aplicándolo en Min City Simulat un poco más despacio, ¿verdad? Como dijimos primero TDD y COD reviews, después de eso, este, lo siguiente podría ser bueno como el BBAT, ¿verdad? Como pasar a hacer todo el project management con el AI directamente en el GitHub issues. Cada quien agarra su tarea, aplica el BMAT a través de esa misma. Bueno, cada quien agarra su user story, porque eso es lo queía tener. Cada quien genera sus tareas, las trabaja con el mismo BMAT, se actualiza el GHub issues, ¿verdad?
 
 
00:16:50
 
Carlos Rene: Y luego se hace el PR y viene todo el contexto,
Alberto Cerrato: Mhm.
Carlos Rene: pues viene mi issue con mis task y mi código y toda m***** viene de un solo, ¿verdad? Incluso creo que les pasé a ustedes un link ahí, los tallé de un man que hace que hasta le genera un video p*** ya y de cómo funciona todo y se lo empata al PR. No mames, entonces ya estamos en otro niño,
Alberto Cerrato: Hm.
Carlos Rene: o sea, estamos ya estamos atrás nosotros, pues ya no estamos adelantados con el Entonces eh con eso,
Daniel Tutila: Ce?
Carlos Rene: pero repito, ya nos vamos a poner al día. Entonces, con eso ya vamos a ir subiendo el nivel, ¿verdad? Y después de esa parte, entonces vamos a llegar a buscar a ver cómo aplicamos todo el end to end como lo hace el hardness con lo con MCS,
Alberto Cerrato: Ah.
Carlos Rene: pues entonces ya todo el mundo porque realmente se fija, entonces lo que todo el mundo debe estar haciendo es validaciones decisiones de diseño, validaciones de el código y luego Cuba, pues testealo, miralo, porque yo ahorita estoy haciendo uno bien loco est para que vean. Por es que yo más o menos sé por dónde están las cosas, por qué me pongo a jugar con esto cada rato. Como yo sé que en el Q2 Midnight City Simulation para Q2 necesitamos hacer ya que se generen los distritos por los usuarios a la misma mar tiene que crear más distritos, tiene que crear sus propios agents.
 
 
00:18:10
 
Carlos Rene: Entonces ya estoy viendo cómo hacer eso, pues porque si se lo tiro a la mar así, o sea, y esto más le dan duro, pues ps y todo ellos, pero no van a manejar ese nivel de complejidad, pues. Esta vaina ya necesita generación procedural, ¿verdad? Pero yo quería ver, yo agarré un asset pack gratis, todo. Entonces lo agarré y me puse con el con el II, ya he estado trabajando con la imagen para ver cómo el men puede comandar módulos procedurales, ¿verdad? Pero yo le digo, "Dame una un mapa con casita, va y no sé qué y árboles." Entonces, el maje va y usa lo procedural, pero él lo comanda, lo parametriza, lo procedural para que ese pueda entonces generar las cosas así, ¿verdad?
Alberto Cerrato: Mhm.
Carlos Rene: Si ven todavía la embarrás en un par de lados, me costó un poco, ¿no? Esa no exagerada al cansancio, pero sí me costó como unas 3 horas que este man generara las calles bien, las casas bien y los árboles bien, ¿verdad? Y en parte pues yo como no nunca había hecho esto también no sé.
Daniel Tutila: Hm.
Alberto Cerrato: Claro.
Carlos Rene: Ahora le voy a decir yo que extraigamos esos patrones que salieron bien en la casa y en los árboles y en la calle y que
 
 
00:19:07
 
Alberto Cerrato: No.
Carlos Rene: arreglemos ese pinche árbol rosalo, ¿verdad? Para para que lo arregle. Y ahí va. Yo ahí voy ir viendo hasta dónde el mae pueda llegar. Tal vez hay algo que uno pueda hacer como agarrar los porque él aquí la confusión principal del men es que como para los juegos uno hace esta vaina en un solo en un solo sprite, ¿verdad? El sprite trae un montón de cosas. Entonces esa vaina es lo que lo tiene mamado, porque el men sabe,
Alberto Cerrato: Hm.
Carlos Rene: no sabe cómo, no tiene ojos para ver, pues, y aunque se lo mando al Gemini,
Alberto Cerrato: Sí.
Carlos Rene: la descripción del Gemini no es precisa, pues, ¿verdad? Entonces, para arreglarlo de las casas, el mae tuvo que hacer una cosa de un algoritmo que busca espacios vacíos y lo combinó ese con el con el visual para entonces hacer un doble chequeo y así extraer las cosas y funcionó bien para algunos, pero para otros no,
Daniel Tutila: M.
Carlos Rene: ¿verdad? Entonces, algunas casas, algunas cosas no quedan tan fácil. Mira, esta m***** le va a costar al maje y eso y este tiene aunque sea espacio vacío,
Alberto Cerrato: Sí, sí, a
Carlos Rene: porque hay unos que no hay unos que tienen ¿Dónde están?
 
 
00:20:09
 
Alberto Cerrato: huevo.
Carlos Rene: Mira esta vaina, o sea, eh, este de azul claro no tiene un espacio en blanco entre él y el otro. Entonces, el dice, "Ah, pues sí, toda esta vaina es un solo, una sola imagen." Entonces me lo me lo corta todo para acá el men.
Alberto Cerrato: Aha. Sí, sí, sí, sí, sí.
Carlos Rene: Entonces, la embarra tal vez hubiera una forma en que yo lo encapsulo y se lo digo, pues,
Daniel Tutila: Sí,
Carlos Rene: pero el punto es ese,
Daniel Tutila: como creando un Jason de metadata que te mapee el píxel por píxel y le digas,
Carlos Rene: pues.
Daniel Tutila: "Esto es un asset, esto es el
Carlos Rene: Sí, sí, de hecho sí lo hice con metadata,
Daniel Tutila: otro.
Carlos Rene: ¿verdad? Este men, ¿verdad? Lo hice con MD porque a los Hens por alguna razón MD le gusta más que que Jason,
Alberto Cerrato: M.
Carlos Rene: ¿verdad? Eh, como que él se hizo unos Jason de apoyo, pero este es el principal, ¿verdad? Si ven, ahí está diciéndole como mira house de tal a tal y tal,
Daniel Tutila: Ahí estás.
Carlos Rene: pero algo ahí está faltando,
Alberto Cerrato: Es que es que parece que parece que los Jason les cuesta un poquito a los a los agent.
 
 
00:21:07
 
Carlos Rene: ¿verdad?
Alberto Cerrato: De hecho, por ahí anda un otra mecánica que altera un poquito cómo funciona el Jason para que sea más fácil para los agentes. Si a largo plazo se piensa utilizar,
Carlos Rene: Mm.
Alberto Cerrato: pues también podríamos ir ubicando ese tipo de forma de trabajar para que los maes tengan la ventaja de usar Jason sin que les cueste usar Jon.
Carlos Rene: Sí, probablemente, pero sí por momentos le le decidí ponerle en D. Este, entonces como ven, este es el tipo de cosas que ya se está mamado, entonces tengo que entrar yo y decirle, "Mirá, no estás cagándola ahí." Y y el el men me dice hasta él se hizo un propio visor de cuando termina el trabajo y según él dice que está bueno y leas la v**** le digo, "Mira esto que está malo." "Ah, sí, tenés razón", dice eso está malo. Entonces los de Jais no están al nivel todavía de poder garantizar la entrega final que un ser humano la agarre la us y diga, "Esta vaina está increíblemente buena." Pues entonces en una palabra lo resumo como juicio, ¿verdad? Lo que le tiene todavía es un juicio de lo necesario, ¿verdad? Y también hay un montón de cosas de contexto, cosas como el movimiento. Yo puedo decir, mira, es p*** movimiento está demasiado rápido, demasiado saltado o como ahorita que parecían esquizofrénicos, los más volteando para todos lados.
 
 
00:22:22
 
Carlos Rene: Entonces le digo, "No, o sea, necesito que caminen más así y les enseñé Town y todo." Entonces eso es lo que lo que lo que hace falta, pues, un juicio de que las cosas estén bien. Entonces, por eso es Queardo le va a dar el el taller, el workshop de Cuba a todo el mundo, porque todo el mundo tiene que garantizar eso, porque, ¿qué pasa? Cuando estamos haciendo una cantidad de código estúpida, ya no va a poder un Cuba garantizar eso porque va a morir, pues va a tener un pijo de US case que nunca va a poder pasarlo, pues entonces cada quien tiene que hacer su Cuba de todo el de todo de todo su entrega y después de eso, o sea, imagínense las capas va TDD, Code Review, QA personal, va, después se hace el PR y después se hace una revisión, digamos, del Happy Pass, porque tal vez eso es lo que el cubano pueda revisar. va que las cosas básicas estén allí. Entonces, así garantizamos un sistema que tiene y si ya ahí sale un bot, va a ser una cosa así remota, pues de que alguien cuando le da clic aquí, aquí, ahí y ahí se caga la Okay, está bien, pues, pero me pasó a uno de 10,000 usuarios, no hay pedo, pues.
 
 
00:23:26
 
Carlos Rene: Entonces eso eso ese es el nivel al que tenemos que llegar con este proceso,
Alberto Cerrato: Claro,
Carlos Rene: ¿verdad?
Alberto Cerrato: no Bueno,
Carlos Rene: Eh,
Alberto Cerrato: ahí solo solamente una una una nota que que nunca es el el momento de de excusar
Daniel Tutila: Ça.
Alberto Cerrato: a los a los deps. La verdad que enviar código sin probarlo uno es un atrevimiento, digo yo. Pero eso es conocimiento general, pero la Mara lo hace. La Mara, vos le pedís un cambio,
Daniel Tutila: Sí.
Alberto Cerrato: ah, ah, es pequeño, se va. Y eso es lo incorrecto, ¿verdad? Al a lo largo de de muchos tiempos, eh, malas entregas y buenas entregas. Eh, al menos el el equipo core que que estuvimos ya por por último con con Dega, que eran Eduardo Isa y yo, pues sí teníamos esa como insistencia, pues ey, vas a hacer algo, probarlo. No lo abriste, pues,
Daniel Tutila: Lo
Alberto Cerrato: no lo abriste porque corregiste ahí y se jodió B. Entonces esa parte eh aunque tengamos todas estas mecánicas hay que estresarla. No se puede estar mandando cosas como que la gente es perfecto, la gente la caga, la caga y la va a seguir cagando por un buen rato.
 
 
00:24:31
 
Alberto Cerrato: La responsabilidad máxima es del desarrollador. Cero excusas y cero cuentos de que,
Daniel Tutila: Exact.
Alberto Cerrato: ah, no, es que yo lo configuré, yo le puse el el acceptance y y se la saltó. Ese es como como vos decís, la única tarea que tenemos ahora es asegurarnos que lo hagan bien. Entonces el nos viene a acelerar y a potenciar, no es que va a ser la chamba de uno ni que nos vamos a a excusar en esa parte. solamente poniendo esa esa nota que es importante siempre comunicarle al al equipo que los desarrolladores responsable 100% por el código que están mandando.
Daniel Tutila: Sí, sí. La reunión esta que vamos a tener con Blad,
Carlos Rene: Correcto.
Daniel Tutila: lo voy a decir igual que antes de mandar el PR tienen que levantar los tres servicios, ver que funcionen, ver que estén hablando y después mandarlo, porque si no hacen eso,
Carlos Rene: Hm.
Daniel Tutila: lo decís, se arreglan una cosa en un archivo, pero joden otra y eso es lo que ha estado pasando. Entonces, y eso es lo que estoy haciendo yo ya ahorita cada par estoy levantando todo, viendo que funcione y que y que no vaya a quebrarse nada. Pero eso ya lo tendría que haber hecho eh el de operantes.
 
 
00:25:40
 
Carlos Rene: Correcto, correcto, exacto. Entonces, por eso ahorita este eso tiene que quedar ya hecho, ¿verdad? De tal manera que cuando la Mara venga y haga todo esto, le vamos a hacer nosotros siempre una revisión con el con el cloud code, correr los tests, ¿verdad? Por lo menos eso debería de validarnos algo y digamos sí deberían de tener ellos como algún comentario con las con los Qargas, ¿verdad? Entonces, eso es lo que Eduardo tiene que hacer y eso tiene que ir en el PR, ¿me entendés? Porque si ya me estás diciendo que lo hiciste y me pajeaste, ¿me entendés? Ya es un nivel distinto. Ya no es que me descuidé, no es que estaba con sueño y desvelado y por lo tanto no lo vea. Y es que me estás diciendo que me vale v****, me estás diciendo, me vale pija lo que vos me digas, Carlos, no lo voy a hacer. Entonces ahí ya no hay más nada que platicar. Ahí es, lo siento, no puede estar en el equipo y vamos a buscar a quién más.
Daniel Tutila: M.
Carlos Rene: Entonces es eso es lo que en eso se va a convertir un PR, ¿verdad? En test, en core review de AI y es el y o sea, parte del que ellos van a correr localmente, el que vos vas a automatizar, ¿verdad?
 
 
00:26:46
 
Carlos Rene: Entonces, cada vez que caiga el Baje lo va a correr y va a dejar los comentarios y después el cub de la gente,
Daniel Tutila: Sí.
Carlos Rene: ¿verdad?
Daniel Tutila: Y tal vez, diría yo, en este momento también los tasco. El plan hay que dejarlo por ahí en algún lado para revisarlo. Si alguien la cagó o algo salió mal, hay que ir a revisar el plan y cómo fue que quedó, porque desde que si no estás planeando bien las cosas y y le de solo le decís a la ella hacerlo, implementarlo, no estás viendo qué es lo que va a implementar. Pero en cambio, si empezas planeándolo o diseñándolo, entonces ahí puedes identificar los errores desde un principio que le decís, "No, mira, esto, este patrón no va aquí o o se puede implementar un patrón en esta solución y por qué no lo
Carlos Rene: Ah.
Daniel Tutila: pensaste, le puedes preguntar." Entonces, eso también sería bueno de trackarlo, de dejar ese plan ahí y y ver por si salió un error, ver este atrás trazabilidad de cómo fue que se implementó el
Carlos Rene: Yeah.
Alberto Cerrato: Correcto. Como los planes de las tareas que se almacenen también,
Daniel Tutila: campo.
Alberto Cerrato: no solo que sea que se cree temporalmente para la tarea, sino que quede guardado tal vez en un folder de MTs por categorías o algo así y que vaya quedando cada plan de
 
 
00:27:51
 
Daniel Tutila: Exacto.
Alberto Cerrato: cada tarea hecha. Se podría hacer una limpieza cada cierto tiempo,
Daniel Tutila: Y así nos hace Exacto.
Alberto Cerrato: pero que quede ahí el récord.
Daniel Tutila: Y así nos aseguramos de que no confíen ciegamente en la Ya, sino que ellos lo vean, porque lo vamos a poder ir a revisar y vamos a y vamos a poder ver por dónde fue que que entró algún
Carlos Rene: O sea,
Daniel Tutila: iso.
Carlos Rene: vos decís en el en el issue del Github, ahí están las tareas y luego dentro de cada tarea el plan de implementación y los patrones que va a hacer. Eso es lo que decimos o
Daniel Tutila: Ah, más o menos. O sea,
Carlos Rene: qué.
Daniel Tutila: vos tenés tu piar. Entonces, para hacer tu par vos vos tenés que saber qué es lo que vas a implementar. Entonces, si es algo pequeño, lo puedes decir, haceme tal cambio. Pero si es un sistema nuevo como la el nuevo server de API que API que va a implementar Au, que vea qué es lo que va a hacer la II, por lo menos que le dé. Sí,
Carlos Rene: Pero, pero,
Daniel Tutila: te acepto el plan.
Carlos Rene: ¿dónde? O sea,
 
 
00:28:47
 
Daniel Tutila: Eh,
Carlos Rene: eh,
Daniel Tutila: como en una carpeta,
Carlos Rene: ¿dónde va a
Daniel Tutila: en una carpeta de documentos, planes,
Carlos Rene: estar?
Daniel Tutila: por ejemplo, o sea, prácticamente si ya estás usando cloud cloud y estás usando cursor el plan, ese plan meterlo dentro del del PR, dentro del del
Carlos Rene: Yo digo que eso debería estar en las tareas del issue,
Daniel Tutila: repo.
Carlos Rene: pues, ¿verdad? Porque el PR lo podemos amarrar a un issue, ¿no? A un a una tarea de git de githop.
Daniel Tutila: Sí.
Alberto Cerrato: Sí, sí.
Carlos Rene: Entonces yo diría allí tiene que estar y no ser algo efímero,
Daniel Tutila: Okay.
Carlos Rene: sino que se queda permanentemente en esta tarea, ¿verdad?
Alberto Cerrato: Okay. Sí, sí,
Carlos Rene: Entonces, así voy a ver la tarea,
Daniel Tutila: Okay.
Alberto Cerrato: también.
Carlos Rene: veo la user story, veo las tareas, ¿verdad? Eh, bueno, el user story tiene una descripción general de la implementación, pero cada tarea, los pasos específicos y en base a eso entonces ya el sigue esas tareas,
Alberto Cerrato: Mm.
Carlos Rene: ¿verdad?
Daniel Tutila: Mhm.
Carlos Rene: Que es esencialmente lo que les dije yo que era de cómo amarramos el BMAT a esa vaina,
 
 
00:29:43
 
Daniel Tutila: Exacto.
Carlos Rene: ¿verdad? Entonces, primero un porque Bima te hace PRD, luego no sé si hace user stories o TAS, pero el mismo concepto porque uno le puede decir qué tan extensivo y qué para qué estructura quiero en cada TAS. La la task mayor o user story, ¿verdad? Este es la que tiene la descripción, el feature, ¿verdad? Y luego debajo de ella tengo las tareitas micro de cada cosita que tengo que hacer y esas deberían de tener su sus indicaciones de cómo verificarlas y validarlas. Entonces, en base a eso, el má crea su TDD y eso lo verifica, lo verificad. Entonces, ese es como el amarre ahí,
Daniel Tutila: Okay.
Carlos Rene: ¿verdad? La tarea con las test para el PR.
Daniel Tutila: Sí.
Alberto Cerrato: Correcto. Correcto.
Daniel Tutila: Okay.
Carlos Rene: Okay. Bueno, entonces está bien así hagámoslo. Incluso eso se puede implementar ya si lo si no lo hacemos ahorita, automáticamente con el BM se puede hacer ya manualmente, pues, ¿verdad? Este, se puede se puede ir agarrando cada una de las tareas,
Daniel Tutila: Sí.
Carlos Rene: pedirle a Code que haga un plan de implementación, signal de tiene que revisarlo, confirmar que le parece bien y luego comenzar a proceder.
 
 
00:30:57
 
Carlos Rene: Ahorita,
Daniel Tutila: Exacto.
Carlos Rene: ¿quién está haciendo eso? Ahorita se asigna la tarea y cada quien tiene que ir y ver cómo lo implementa o no.
Daniel Tutila: Sí, así se está haciendo. O sea, se le asigna la tarea que le decís, "Tenés que hacer esto, tienes que hacer lo otro y es a criterio de cada developer cómo le implementa. Si usa ya o no, ya es cosa de él.
Carlos Rene: Entonces, yo creo que para no hacer bot de crear una dependencia de alguien, debería de crearse este cada quien tiene que ver cómo hacer ese diseño de implementación cada quien de su tarea con el apoyo de AI, ¿verdad? Y luego tiene que hacer un review de alguien más, ¿verdad? queía ser, no sé si eso te caería mucho pesada a vos la carga, Daniel, si se te asigna a vos eso o lo o lo agarra Black, por ejemplo, y él entonces hace la revisión.
Daniel Tutila: que sea que sean los dos, que seamos los dos. O sea, si yo estoy disponible lo hago, sino que lo que lo agarre blad para que no para que no esté solo en uno,
Carlos Rene: Okay.
Daniel Tutila: porque si yo estoy viendo otro,
Carlos Rene: Okay.
Daniel Tutila: entonces tiene que esperarse que termine ese para seguir con el otro.
 
 
00:31:57
 
Daniel Tutila: Entonces, por lo menos si está Vlad y yo podemos
Carlos Rene: Vaya, pues perfecto, ¿verdad? Eh,
Daniel Tutila: repartirnos.
Carlos Rene: está bien, perfecto, ¿verdad? Y para ese deberíamos de tener también entonces un prompt como el que estás haciendo vos ahorita, ¿verdad? Como el que estás usando para el core review. sería como el specification review, llamémosle, ¿verdad? Entonces, ocupamos un ocupamos ese prom.
Daniel Tutila: Ok.
Carlos Rene: Entonces, yo creo que esas dos cositas nos ayudan bastante eh ahorita pues que lo arrancamos, digamos, como todavía con el AI como un support en vez de que el AI todavía no sea el principal como procesador, por decirlo así, ¿va?
Daniel Tutila: Sí. Okay. Me interesa entonces.
Carlos Rene: Okay,
Daniel Tutila: Dale, está
Carlos Rene: perfecto. Entonces, este, si querés ayudarnos con algo, Alberto, y esto de nuevo, porque también te va a servir a vos y vos lo vas a poder hacer más rápido porque estás arrancando ahorita de cero y no tenés ni siquiera más teammates.
Alberto Cerrato: Correcto.
Carlos Rene: Entonces, hacete como un diagramita este pipeline que acabamos de discutir,
Alberto Cerrato: Sí.
Daniel Tutila: Ah.
 
 
00:33:01
 
Carlos Rene: ¿verdad? Que es que se crea la tarea. La tarea se tiene que crear un spec, ¿verdad? Se pueden apoyar con ella y para eso habría que ver cuál es el promp correcto para usar para ello. Luego tiene que haber un promp para hacer un review del expect, right? Luego cada developer comienza a utilizarlo para implementarlo y luego de la implementación, ¿verdad?, hacemos el code new prompt. Ellos lo tienen que correr localmente y Daniel también va a configurar para que se active con un trigger, ¿verdad? Cuando se cuando alguien haga un PR, pum, cae el primero que va a leer Scot y deja unos comentarios, ¿verdad? Ya cuando los comentarios de cloud se han resolverto, tal vez él dice, "No, pues sí está todo revisado, entonces lo revisa un humano, ¿verdad? Y ve que lo que se ha creado match con lo que se está entregando. No sé si les parece a ustedes para MCS, ¿verdad? Eh, porque esto como Alberto no va a tener muchos teammates ahorita, realmente no hace falta tanta coordinación, pero podríamos también pedirle a cada quien que en el PR grabe el video de él corriendo esa vaina y testeándola y que los y que lo atachee al PR. No sé ustedes, ¿qué opinan?
Alberto Cerrato: Mira, si tú tienes features, esto ya lo hemos conversado muchas veces, si yo estoy trabajando una semana en una tarea, grabarte un videito de un minuto es una cosa minúscula.
 
 
00:34:24
 
Alberto Cerrato: O sea, sí vale la pena. Pues si me decís vos, no, voy a poner un módulo para que envíe las transacciones al L2 que que no existía antes ponerle.
Carlos Rene: Ok.
Alberto Cerrato: Entonces hago el módulo y todo y que eso toma, no sé, pues va varios días y yo creo que es valedero que se grabe un video, pues algo rápido, eh, uno no puede grabar rápido con con herramientas de las que ya vienen en el en el sistema y puede ser algo sencillo.
Daniel Tutila: de un minuto.
Alberto Cerrato: E y lo otro que que puede ser, que eso yo se lo había visto, creo que era Pabel, es el que tenía esa costumbre. Si correron los tests, obviamente sabemos que que corren en el en el pipe, pero subiré una captura, pues se me corrieron en el local y y habría que ver, ¿no? Y todo eso apoya porque qué tal que falla algo en el pipe o que no te falla en el local y ahí uno puede entrar a tema inversionamientos y otras cosas. Entonces,
Daniel Tutila: Co?
Alberto Cerrato: eh sí, pues poner esas pruebas, una captura de los test y un y un y un videíto de un feature que es grande,
Carlos Rene: un video,
Alberto Cerrato: yo lo veo válido.
Carlos Rene: un video corriendo entonces el Cuba y voy a decirle Eduardo que en el workshop explique
 
 
00:35:30
 
Alberto Cerrato: Mmh.
Daniel Tutila: Mhm.
Carlos Rene: cómo es que él testea, porque digamos hay veces que hace solo el smoke test, ¿verdad? Que es el happy puff, ¿verdad? Y para ciertas cosas eso está bien y luego para otras cosas no. Para otras cosas quieres full regression testing, ¿verdad? Entonces eso es lo que quiero. Y así se se fuerza eso, pues, entendés? Ya el que no subo un video pajeándonos de que teste una m*****, que no testeó, ya de nuevo ese ya no está ya no está diciendo es que me pela lo que ustedes me digan no lo voy a
Daniel Tutila: Todavía peor.
Carlos Rene: hacer y ahí pues ya las decisiones son más fáciles pues para nosotros bueno entonces
Alberto Cerrato: Correcto.
Daniel Tutila: Sí.
Carlos Rene: ayudaros con ese deamita Alberto para MCS el tu era un poco diferente pues no tenes que subir un video a nadie porque estás vos entonces eh pero ayúdanos haciéndonos ese pipeline ahorita, ¿verdad? como mostrando esa es ese proceso que acabamos de describir,
Alberto Cerrato: Sí.
Carlos Rene: dónde está el humano, ¿verdad? Y qué es lo que tiene que hacer.
Daniel Tutila: Exacto. Ahí también mandé un un repo de Hos. Ese lo creo que ya le había dicho,
 
 
00:36:33
 
Alberto Cerrato: M.
Daniel Tutila: lo usé hace un montón, hace como tres meses. Es bastante bueno como para hacer los specs, la forma en como en cómo funciona. Entonces, no estoy diciendo copiémoslo o forquémoslo, pero como para revisar cómo tienen estructurados los archivos y cómo tienen los estructurados los agentes, eso nos puede dar bastante bastante guía porque si si no no es malo ese no es malo, ese funciona.
Alberto Cerrato: Perfecto.
Carlos Rene: Agentos.
Alberto Cerrato: Sí.
Carlos Rene: Okay.
Daniel Tutila: M.
Carlos Rene: Agent a system for injecting code standards and writing better specs for spec development. Está excelente, ¿o sí? Lo ocupamos, o sea, pero este men es como que es tipo BBAT, que lo que carga es como un montón de prompt engineering para que yo pueda aplicarlo con mi AI o es como un set de skills de algo o cómo es.
Daniel Tutila: Eh, veamos. Son como tres, ya no me acuerdo. Hay como cuatro o cinco comandos con los que empezas. Entonces, el primer comando es analizarme el código y generarme el overview de todas las tecnologías que uso, todos los estándares y todo lo que tengo. Entonces, ya tiene la descripción del proyecto.
Alberto Cerrato: Mhm.
 
 
00:37:47
 
Daniel Tutila: Una vez tiene eso de base, le decís, le correso, que es para generar un spec. Entonces, ese spec lo que hace es que te comienza a hacer interviews, te dice, le decís, yo quiero generar este feature en mi en mi proyecto. Entonces, comienza a hacer interview. ¿Cómo lo queres hacer? ¿Cómo lo queres implementar? ¿Qué pasa con esto? ¿Qué pasa con otro? Como que ya empieza a ver a H cases y escenarios que tiene que implementarlos si no lo tiene claro. Y a partir de eso crea las tareas. Y una vez tenés creadas las tareas, el siguiente paso es correr otro comando que tienen ellos para poner a poner a unos agentes a hacer la parte del la parte de la implementación. Entonces, ya implementa todo, bla bla bla bla bla. Y creo de esto, no me acuerdo si tiene de QA, o sea, le decís, "Revisame el código contra el spec" y ya lo ya lo hace. Entonces este está un poco más tirado también la parte de UI porque ti una parte de que le decís si tenés algún sketch o o algo, pégámelo y a partir de ahí yo genero el código y el spec para que para que lo para que lo haga.
 
 
00:39:00
 
Daniel Tutila: O sea, al final no es creo que es un poco más para la parte web, como les digo, pero la forma en cómo ha estructurado todo eh es muy buena y le hizo la la última vez que lo vi le hizo una actualización o al menos como para ya quitar cosas que ya trae cloud y basarse solo en skills para que no para que no el contexto sea menor a
Alberto Cerrato: Mhm.
Daniel Tutila: lo a como lo estaba usando antes. Pero esa esa parte si ya no la he probado, entonces no puedo decir cómo funciona. Pero al menos la parte de cómo poner el agente y cómo hacer el el chaning de un agente a otro, esa parte sí me ha gustado y tal vez si la podemos usar de
Carlos Rene: Yo creo que sería hacer un comparativo entre este y P porque suena como que son muy parecidos,
Daniel Tutila: base.
Carlos Rene: la verdad.
Daniel Tutila: Sí. No,
Carlos Rene: Entonces,
Alberto Cerrato: Mhm.
Daniel Tutila: yo no digo copiar la Ajá.
Carlos Rene: a comprarlo.
Daniel Tutila: No, no digo copiarlo lo que hace, sino copiar la técnica en cómo manda llamar un agente al otro, o sea, cómo lo está cómo lo está encadenando esa esa orquestración de los agentes.
Carlos Rene: Mm.
Daniel Tutila: Bueno, igual hay igual hay que revisarlo y y comprarlo,
 
 
00:40:05
 
Carlos Rene: Okay.
Daniel Tutila: o sea, no no digo nunca dije copiémoslo, sino analicémoslo, estudiémoslo. Vale.
Carlos Rene: Bueno, entonces eh las tareas que tenemos ahí entonces es analizar cómo aplicar el spec driven development, analizar cómo hacer el review de los specs, eh amarrar,
Alberto Cerrato: Mhm.
Carlos Rene: poner eso en el gitubsues, ¿verdad? Ya sea que lo quieran scriptear,
Alberto Cerrato: Mhm.
Carlos Rene: yo creo que no deje ser tan complicado en mi opinión que un solo lo mande para GitHub, ¿verdad? O si lo quieren copiar manual, como quieran, ¿verdad? Esos son los primeros tres cosas. Y ahí el cuarto es el C review Review, que es el que ya estás trabajando vos ahorita, ¿verdad?
Daniel Tutila: M.
Carlos Rene: Esos cuatro serían las cosas que hay que implementar a nivel de Yo le tengo que comprar ahorita Colamara para para dárselos este y en base a eso nos vamos pues y lo otro es el bueno el video del Cuba y que eso lo va a manejar Eduardo, pero estas primeras hay que asignar esta porque vos voy a tener la del C review Review, entonces hay que asignar este del spec o no sé si lo querés hacer vos después de que termines lo del review.
Daniel Tutila: Si quieres lo veo
 
 
00:41:19
 
Carlos Rene: Está bien.
Daniel Tutila: yo.
Carlos Rene: Entonces, nada más decirle a David ahí que te cree la tarea y te la asigne eh con la respectiva
Daniel Tutila: Mm.
Carlos Rene: prioridad.
Alberto Cerrato: Claro, yo eh sumarizo de mi de mi lado, tengo que leer bastante, voy a a pasarme por los repos que me facilitaron y tengo la tarea específica del diagrama, de todo lo que conversamos, ¿verdad? que es el flujo completo, crear tarea, crear spec, review del spec, eh luego implementarlo en local por cada dep,
Carlos Rene: M.
Alberto Cerrato: luego cada dep eh revisa el el prompt que se utiliza para el code review y luego pasamos a grabar el video, subirlo al PR y en el PR también se activa eh los proms de revisión de de código y agregar un detalle, pues para especificar claramente cuáles son los puntos de interacción humano y quiénes es el responsable en ese momento de la etapa.
Carlos Rene: Correcto. Y después vos tenés que hacer el equivalente diagrama, pero con el harness, ¿verdad? con el hardness,
Alberto Cerrato: Correcto.
Daniel Tutila: Mhm.
Carlos Rene: solo que estamos usando cloud code y mira, esto más pasa peleando que cloud code, que open codex y así un rato está mejor el uno, después el otro y hoy todo el mundo está enamorado de este, mañana el otro.
 
 
00:42:36
 
Carlos Rene: Este, eventualmente lo vamos a hacer nosotros de tal que de tal manera que nuestro pipeline sea dinámico, pero por el momento para no ahogarnos y andar con tanta vuelta escojamos uno que es el Cloud C, me parece que es el que tiene el ecosistema más grande de mayor crecimiento y nos vamos con ese cabrón, pues, ¿verdad?
Alberto Cerrato: Mhm.
Carlos Rene: Ya después sí vamos a poder hacerle de tal manera que podés configurar múltiples agentes y entonces el más se va a levantar cuando necesita probablemente cloud code para todo lo general y alto estratégico y revisiones y después tiramos a codex por ejemplo para que haga cada tareíta individual y así, ¿verdad? Y vamos a ir viendo cuál es lo que vamos a usar. Yo sí he encontrado valor cuando los pongo a los maes a criticarse uno al otro porque sí encuentra uno cosas del otro, incluso cloud coach se le pasan y ah,
Daniel Tutila: Sí.
Alberto Cerrato: Sí.
Carlos Rene: no, fíjate que Gemen ahí tiene razón. no estoy de acuerdo con esto, pero con esto otro creo que sí y debo mejorarlo de esta forma. Entonces, empiezan a trabajar ahí entre ellos. Entonces es el tipo de vaina que ocupamos, ¿verdad? Eventualmente vamos a llegar a eso, pero ahorita arrancamos con
Daniel Tutila: Sí. Okay.
Alberto Cerrato: Perfecto.
 
 
00:43:32
 
Carlos Rene: Code.
Daniel Tutila: Excelente. Entonces sí, de mi lado solo voy a terminar la parte de core review. Después voy a empezar con lo de spec driving y mandar todo esto al repo para que ya lo empiecen a usar la gente de
Carlos Rene: Perfecto.
Daniel Tutila: Mir.
Carlos Rene: Lo otro que sería entonces ver si agregamos Alberto al canal de Midnight Sim, solo para que cuando hagas algo vos relevante, lo tuyo, Daniel, lo hagas un tag, ¿verdad?
Daniel Tutila: Sí.
Carlos Rene: Este, o no sé si quieren hacer un channel específico para esto,
Daniel Tutila: Okay.
Carlos Rene: para Driven Development, ¿verdad? Podríamos hacer eso también.
Daniel Tutila: Sí. mejor el chat, el el
Alberto Cerrato: Sí, con correcto.
Carlos Rene: Pedísselo ahí a David, porfa. Pedísselo ahí.
Alberto Cerrato: Hm.
Carlos Rene: AIDD, ¿verdad? AI Driven Development. y agregan a todo el mundo ahí, ¿verdad? Ustedes dos van a ser los principales, pero que todo el mundo lea lo que está haciendo y así se taguean el uno al otro y las mejoras
Alberto Cerrato: Correcto.
Carlos Rene: nuestras eh tienen que estar en ese fork nuestro de eh de Trill Beats.
Alberto Cerrato: De Cloud Config. Correcto. Oh.
Carlos Rene: Chévere. Pues sí, sí. O sea, imagínate si todo el mundo está haciendo coama y todo el mundo está eh sacando los feature, o sea, deberíamos de volar, pues, porque eso es el rollo que va a tener mucha gente que me entendés, ponen ellos como programador. Sí, yo solo y lanzo dos 12 agentes en paralelo. La vanas para hacer un vergueo nunca por revisar esa vaina, pues, como a revisar 12 agentes de código, ¿me entendés? Mientras que si tenemos 10 personas trabajando 10 agentes,
Daniel Tutila: Sí.
Carlos Rene: entonces revisando esa vaina y sacándola toda v**** en 5 días sacas lo que antes sacaba en 25 pues o tal vez más. Entonces eh garantizada la calidad, ¿verdad? Sin sorpresas, pues,
Alberto Cerrato: Sí,
Carlos Rene: ¿verdad?
Alberto Cerrato: sí.
Carlos Rene: Bueno, perfecto. Entonces ahí estamos viéndonos en la meeting de TDD. No sé, creo que Alberto no está agregado a esa porque no está en el proyecto, pero te vamos a agregar, Alberto,
Daniel Tutila: Sí,
Carlos Rene: para que veas.
Daniel Tutila: que entre.
 
 
La transcripción finalizó después de 00:46:30

Esta transcripción editable se ha generado por ordenador y puede contener errores. Los usuarios también pueden cambiar el texto después de que se haya generado.
