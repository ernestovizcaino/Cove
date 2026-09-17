# Cove · 0.2.0

**Una ventana pequeña y tranquila para hablar con cualquier modelo.**

Cove es un cliente de chat **nativo de macOS** para modelos de IA: una sola ventana de 540 × 640 que puedes fijar encima de tu trabajo, sin sidebar, sin cuenta y sin backend. Conecta un servidor local —Ollama o LM Studio, en esta Mac o en otra computadora de tu red— o una API key de un proveedor que ya pagas, y cambia de modelo desde el mismo composer. Las conversaciones se guardan en esta Mac con SwiftData, las claves en el Keychain, y nada sale de tu equipo hasta que apruebas cada endpoint externo.

Escrito en Swift 6 y SwiftUI, sin Electron, sin telemetría y sin servicio propio.

> Es código fuente, no una app compilada ni un instalador. Consulta `docs/VALIDATION.md` para distinguir lo verificado de lo pendiente.

## Abrir en tu Mac

1. Descomprime la carpeta completa.
2. Abre **`Cove.xcodeproj`**, no `Package.swift`.
3. Deja que Xcode resuelva las dependencias de Swift Package Manager.
4. Selecciona el esquema **Cove**, destino **My Mac**, y presiona **⌘R**.
5. Acepta el permiso de red local cuando macOS lo solicite y mantén la PC encendida en la misma red.

El proyecto está configurado para macOS 15+, Swift 6 y firma local ad hoc. Usa Xcode con Swift 6.1 o posterior como punto de partida. La compilación completa con esas versiones concretas queda pendiente de validación en macOS. No necesita Node, Electron, Homebrew, un backend ni Ollama instalado en la Mac.

No viene ninguna conexión preconfigurada. La primera vez, la pantalla de inicio muestra una tarjeta de **onboarding**: elige **Local server** (Ollama o LM Studio), **API key** (un proveedor) o **Custom…**, y se abre el formulario de conexión de siempre. La tarjeta desaparece cuando guardas una conexión, y la primera que guardes queda seleccionada. Los servidores locales sugieren `http://localhost:11434` (Ollama) y `http://localhost:1234/v1` (LM Studio); cambia `localhost` por la IP de otra computadora de tu red cuando el servidor sea remoto.

No se hace ninguna solicitud hasta que envías un mensaje o pulsas **Discover models**. Ese botón consulta el catálogo, no ejecuta una generación y no garantiza que una API key sea válida cuando el catálogo es público.

Si Xcode pide resolver la firma, en el target Cove → Signing & Capabilities usa **Sign to Run Locally** o tu equipo de desarrollo. Conserva los permisos de App Sandbox y conexiones salientes. No desactives todas las protecciones de red para resolver un fallo.

## La interfaz

La ventana inicia en **540 × 640 puntos**, con mínimo de 400 × 420 y tamaño redimensionable. No hay sidebar permanente. La cabecera es pequeña; abajo aparecen hasta tres conversaciones recientes y el campo de escritura.

- **New chat / ⌘N:** crea un chat, preservando los borradores locales existentes.
- **See all / ⌘K:** historial y búsqueda por título. Clic secundario para renombrar o eliminar.
- **Título con ⌄ (arriba a la izquierda):** abre el historial; el chevron indica que se puede desplegar.
- **Arriba a la derecha:** solo **nueva conversación** y el menú **⋯**. Mantener la ventana arriba, minimizar, conexiones y exportar viven dentro del menú. El pin aparece en la cabecera únicamente mientras está activo, para poder quitarlo de un clic.
- **Composer en dos filas:** el mensaje ocupa todo el ancho arriba; debajo, una fila de controles con **+** (adjuntar) y el selector de modelo a la izquierda, y enviar/dictar a la derecha.
- **+ en el composer:** adjuntar archivo o imagen. Las conexiones nuevas se agregan desde la tarjeta de onboarding, el menú ⋯ o Settings.
- **Selector de modelo:** buscador de conexiones y modelos; muestra el nombre de la conexión y del modelo activo.
- **Return:** enviar. **Shift/Option + Return:** nueva línea. Se respeta la composición de texto de los métodos de entrada.
- **Botón cuadrado / ⌘.**: detener. El texto parcial se conserva.
- **⌘, / Connections:** conexiones, apariencia (System/Light/Dark), ventana (**Translucent** o **Plain**), atajo global e icono de la barra de menús.
- **⇧⌘C (configurable):** mostrar u ocultar Cove desde cualquier app. Ocultar no cierra la ventana: conserva el borrador, la posición de lectura y una respuesta en curso.
- **Icono en la barra de menús:** abrir/ocultar, nuevo chat, historial, ajustes y salir.
- **Sin icono en el Dock:** Cove vive en la barra de menús y no aparece en ⌘Tab. Actívalo con **Show in the Dock** en Settings. Mientras el Dock esté oculto, el icono de la barra de menús no se puede desactivar: es la única forma de volver a la app. Para salir, usa **Quit Cove** en ese menú.
- **Menú Chat:** exportar la conversación actual como Markdown o JSON, sin credenciales.

No hay botones decorativos de micrófono o adjuntos sin implementación. Tampoco hay una pantalla de bienvenida grande, métricas, cuentas ni contenido de ejemplo presentado como historial real.

Para cambiar el tamaño inicial, edita esta línea en `Cove/App/CoveApp.swift`:

```swift
.defaultSize(width: 540, height: 640)
```

## Conectar un proveedor

Desde el **+ del composer** o **Settings → + Connect**, elige un proveedor. Aparece un formulario separado con nombre, credencial cuando corresponde, modelo y URL del servidor. La URL de los proveedores cloud está en Advanced; en servidores locales y Cloudflare aparece directamente.

**Discover models** consulta el catálogo sin mandar un chat. También puedes escribir el identificador manualmente. **Save and use**, al conectar desde el composer, guarda y selecciona la conexión; **Save connection**, desde Settings, no cambia tu conversación activa. Cancelar no guarda el borrador.

| Grupo | Configuraciones incluidas |
|---|---|
| API | Anthropic, Cloudflare AI Gateway, DeepSeek, Google, Kimi (Moonshot API), OpenAI, OpenRouter, Vercel AI Gateway, xAI (Grok API), Z.ai |
| Local | LM Studio y Ollama, también en otra computadora de tu red |
| Custom | API compatible con OpenAI Chat Completions, URL y clave propia opcional |

Puedes guardar dos conexiones del mismo proveedor, con nombres y claves diferentes. El buscador distingue la conexión **y** el modelo, sin el límite anterior de 30 entradas. No descarga modelos ni ejecuta servidores.

Cloudflare usa la REST API actual: `https://api.cloudflare.com/client/v4/accounts/ACCOUNT_ID/ai/v1`. Debes reemplazar el ID de cuenta, indicar el Gateway ID y usar un token con permiso **Account > Workers AI > Read**. No se configura la antigua ruta `/compat`. Cloudflare y Z.ai usan entrada manual de modelos en esta versión: no se inventa un endpoint de catálogo.

Ollama usa `http://localhost:11434` como sugerencia inicial y `/api/chat` nativo. LM Studio usa por defecto `http://localhost:1234/v1`; cambia localhost por la IP de la otra computadora cuando sea remoto. Los demás presets usan sus APIs documentadas a través del Swift AI SDK. La integración OpenAI usa Chat Completions, no Responses, y no presupone que todos los modelos listados admitan chat.

**No hay login con suscripciones en esta versión.** “About subscriptions…” explica los métodos y enlaza documentación oficial. Las API keys no equivalen a una suscripción de chat; Copilot o un runtime oficial de un agente requieren integraciones independientes. No se toman cookies ni tokens de sesión de otras aplicaciones.

Ninguna de las nuevas conexiones se ha probado con credenciales reales en este entorno. El código implementa las rutas, autenticación, formularios y adaptación al transporte; la prueba end-to-end en macOS sigue pendiente. Detalles de endpoints, fuentes, paginación y límites: **`docs/CONNECT.md`**.

## Historial, privacidad y límites

Conversaciones, mensajes y conexiones no secretas se guardan con SwiftData, sin CloudKit. Las API keys se guardan en Keychain, asociadas a la conexión **y a su URL exacta normalizada**. Cambiar la URL no reutiliza automáticamente una clave guardada para otro endpoint.

Se solicita aprobación antes del primer envío de texto a cada conexión/endpoint no local. No hay cambio automático de Ollama a una nube cuando la PC no responde. La telemetría del SDK se deshabilita explícitamente. No se registran prompts ni secretos en logs y se rechazan redirecciones HTTP de las solicitudes de proveedores. Las imágenes y emojis remotos en Markdown no se descargan automáticamente. El contenido no ejecuta herramientas ni comandos.

El historial es local, pero **no tiene cifrado adicional implementado por esta app**. Los borradores del chat nuevo se almacenan localmente en preferencias; los de conversaciones existentes, en SwiftData. Protege la cuenta y el disco de tu Mac según tus necesidades.

Esta versión permite una generación a la vez. Cambiar de conversación no cambia el destino de una respuesta en curso. No hay reintentos automáticos de generación. Los checkpoints se guardan aproximadamente cada segundo cuando llegan eventos; un cierre forzoso puede perder el fragmento posterior al último checkpoint, pero no debería descartar la conversación completa. Una generación pendiente se marca como interrumpida al reabrir.

El contexto usa un presupuesto conservador de **32 000 caracteres**, no un contador exacto de tokens ni la ventana anunciada en los metadatos del modelo. Conserva turnos completos recientes, no reenvía razonamientos ni respuestas fallidas y avisa cuando omite turnos antiguos. El mensaje nuevo no se corta silenciosamente. El historial completo permanece guardado.

Durante el streaming se muestra texto nativo; al finalizar se aplica Markdown con Textual. Esto evita parsear repetidamente documentos incompletos, a cambio de que tablas y código se formateen al terminar. La búsqueda inicial es por título, no por todo el contenido. No se ha medido aún el rendimiento en un dispositivo macOS.

## Estructura

```text
Cove.xcodeproj/       Proyecto de la aplicación + esquema compartido
Cove/
  App/                     Entrada, ventana y comandos
  Components/              Composer nativo, mensajes y adaptación de ventana
  Domain/                  Modelos propios, contexto, validación, NDJSON
  Features/Chat/           ChatStore, pantalla principal y transcript
  Features/History/        Historial
  Features/Connect/        Menú, editor compartido y buscador de modelos
  Features/Settings/       Administración de conexiones
  Infrastructure/AI/       Ollama, SDK, catálogo y URLSession
  Infrastructure/Persistence/  SwiftData y esquema versionado
  Infrastructure/Security/     Keychain
MacTests/                  Pruebas de persistencia y controlador para macOS
Tests/CoreTests/           68 pruebas portables de dominio, catálogo y editor
Package.swift              Núcleo + editor sin interfaz en Linux; no ejecuta la app
Scripts/                   Comandos de compilación y pruebas
AGENTS.md                  Reglas para continuar con Codex / Claude Code
```

## El icono

El icono se genera desde su geometría, no se dibuja a mano:

```bash
swift Scripts/make-icon.swift
```

Calcula la marca a partir de un centro, un radio y un grosor de trazo, renderiza cada tamaño de macOS y escribe `Cove/Resources/Assets.xcassets/AppIcon.appiconset` junto con `docs/icon-1024.png`. Para cambiar color o proporciones, edita las constantes al inicio del script y vuelve a ejecutarlo.

## Pruebas y compilación por Terminal

Las pruebas portables no necesitan descargar paquetes:

```bash
swift test
```

Para compilar y abrir la app en una Mac con Xcode configurado:

```bash
bash Scripts/run.sh
```

Para ejecutar las pruebas de macOS, incluyendo SwiftData y el controlador:

```bash
xcodebuild -project Cove.xcodeproj -scheme Cove \
  -destination 'platform=macOS' -configuration Debug test
```

Estas pruebas de macOS están incluidas, pero **no se ejecutaron aquí**. No elimines una base de historial para solucionar una migración o un fallo de arranque.

## Dependencias fijadas

Se fijan las revisiones directas en el proyecto de Xcode:

- **Swift AI SDK** (`zaidmukaddam`, producto `AI`), revisión `d8d108ccf606a154647ef7eae948775a1e7aa969`. Se incluye una **copia local** en `Vendor/swift-ai-sdk`, referenciada por el proyecto como paquete local. Conserva la licencia MIT original y añade únicamente dos guardas de compilación; el cambio está documentado en `Vendor/swift-ai-sdk/NATIVECHAT_COMPATIBILITY_PATCH.json`.
- **Textual** (producto `Textual`), revisión `01b51875a5406eefc95f52a058cb059e7bc94dc4`. Xcode la descarga, junto con sus dependencias transitivas.

Tras la primera resolución correcta en macOS, conserva en Git el `Package.resolved` que Xcode genere. No se incluye un lockfile transitivo inventado ni incompleto.

Las interfaces de los adaptadores y del renderer se cotejaron con el código público de esas revisiones. Eso no sustituye la compilación ni la prueba end-to-end. Fuentes y rutas consultadas: `docs/SOURCES.md`.

## Actualizar desde el primer ZIP

Descomprime en una carpeta aparte y abre el nuevo `.xcodeproj`. Mantiene el bundle ID, el esquema de SwiftData y las revisiones de paquetes de la versión anterior; no se reinicia el historial. Los campos nuevos de conexión son opcionales y las pruebas portables cubren la lectura de registros antiguos. La recuperación de una base real todavía debe comprobarse en una Mac, sin borrarla ante un fallo. Si modificaste el proyecto por tu cuenta, conserva esos cambios antes de combinar las carpetas.

## Siguiente paso

Primero compilar en macOS y probar el recorrido real: abrir → enviar a tu Qwen → detener → cambiar de chat → cerrar/reabrir → consultar historial. Después verificar una conexión cloud con una clave propia. Solo entonces ampliar adjuntos, respuestas con formato durante streaming, ventana rápida global o herramientas.
