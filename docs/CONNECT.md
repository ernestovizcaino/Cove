# Connect: implementación 0.2.0

Fecha de investigación y actualización: 16 de septiembre de 2026. Este documento describe el código entregado, no una prueba de proveedores en vivo.

## Interacción

El botón + del composer y el botón Connect de Settings comparten `ProviderMenuItems`. Es un `Menu` nativo con `Section`, no una lista web dibujada para imitar macOS. La apariencia exacta la decide la versión de macOS. Se usan SF Symbols genéricos, no logotipos de terceros descargados.

Seleccionar un proveedor cierra el menú y presenta `ConnectionEditorView` como sheet. Un único enum `ConnectionSheet` coordina el editor y la información sobre suscripciones. El selector de modelos es otro control: un popover pequeño con búsqueda, lista nativa agrupada por conexión y selección por teclado. No apila editores encima del popover. La ventana principal conserva 540 × 640 puntos.

El editor mantiene un borrador. Cancelar no escribe conexiones; los cambios sin guardar requieren confirmación para descartarse. La edición comprueba que el registro original no haya cambiado en otra ventana. Desde el composer se guarda y selecciona; desde Settings solo se guarda. Los chats antiguos no cambian de procedencia.

## Presets no son protocolos

`ProviderKind` conserva los seis protocolos de la primera versión. `ProviderPreset` agrega nombre, grupo, URL sugerida, documentación, símbolo, necesidad de clave y disponibilidad del catálogo. DeepSeek, Moonshot, LM Studio y otros servicios compatibles reutilizan el adaptador compatible: no hace falta un cliente por marca.

`ProviderConnection.presetID` y `.gatewayID` son opcionales en el JSON propio guardado por SwiftData. Los registros anteriores siguen decodificando sin esos campos; el esquema de SwiftData V1 no se modifica. Cada conexión tiene su propio UUID. Dos conexiones con el mismo model ID se distinguen en el selector por ambos identificadores.

| Preset | Base sugerida | Autenticación | Catálogo de esta versión |
|---|---|---|---|
| Anthropic | `https://api.anthropic.com/v1` | `x-api-key` | `/models`, cursor `after_id` |
| Cloudflare AI Gateway | `https://api.cloudflare.com/client/v4/accounts/ACCOUNT_ID/ai/v1` | Bearer + `cf-aig-gateway-id` | ID manual |
| DeepSeek | `https://api.deepseek.com` | Bearer | `/models` |
| Google | `https://generativelanguage.googleapis.com/v1beta` | `x-goog-api-key` | `/models`, `pageToken` |
| Kimi (Moonshot API) | `https://api.moonshot.ai/v1` | Bearer | `/models` |
| OpenAI | `https://api.openai.com/v1` | Bearer | `/models` |
| OpenRouter | `https://openrouter.ai/api/v1` | Bearer | `/models` |
| Vercel AI Gateway | `https://ai-gateway.vercel.sh/v1` | Bearer | `/models` |
| xAI (Grok API) | `https://api.x.ai/v1` | Bearer | `/models` |
| Z.ai | `https://api.z.ai/api/paas/v4` | Bearer | ID manual |
| LM Studio | `http://localhost:1234/v1` | Token opcional según servidor | `/models` |
| Ollama | `http://localhost:11434` | Sin clave en este preset | `/api/tags` |
| Custom | Introducida por el usuario | Bearer opcional | `/models` cuando el servidor lo implemente |

La disponibilidad de modelos, permisos, capacidad y cobro puede variar. Un GET del catálogo no verifica una generación, saldo ni autorización si el catálogo es público. Algunos proveedores pueden listar modelos que no aceptan Chat Completions. No se incluyen modelos cloud inventados como valores predeterminados.

### Cloudflare

Se usa la REST API documentada actualmente. El token necesita `Account > Workers AI > Read`; un permiso de AI Gateway por sí solo no basta para esa ruta. El formulario valida el ID de cuenta y el Gateway ID antes de enviar credenciales. Incluye `cf-aig-gateway-id`, inicialmente `default`, y usa un model ID de su catálogo. Debe corresponder a un gateway válido en la cuenta. La configuración no crea gateways ni añade créditos. La ruta anterior `/compat` no es el preset recomendado para nuevas llamadas a un modelo; quien necesite configuraciones distintas debe implementarlas de forma explícita.

Cloudflare y Z.ai permiten introducir un ID manual. El botón de descubrimiento se oculta porque no se validó para estos presets un endpoint de listado equivalente al de OpenAI. Eso no afirma que el proveedor carezca de catálogos u otras APIs.

### Suscripciones y agentes

No se confunde una suscripción con una API key. La opción “About subscriptions…” es informativa y no anuncia una conexión que aún no existe.

ChatGPT Plus factura el API por separado. Esta app usa la API de OpenAI, no una sesión de ChatGPT. Anthropic exige que el inicio de sesión con una cuenta Claude use su propio flujo y restringe la captura/intermediación de credenciales de usuarios por terceros; también documenta el uso del binario oficial sin modificar de Claude Code en determinadas integraciones. No implementamos ese runtime aquí. GitHub sí ofrece un SDK oficial de Copilot que utiliza el CLI autenticado: requeriría su propio proceso, ciclo de vida y adaptación de eventos. Su ausencia aquí no significa que sea técnicamente imposible.

Kimi es el API general de Moonshot, no Kimi Code. Z.ai es su API general, no un endpoint de Coding Plan. xAI es el API, no una sesión del sitio Grok. No se reutilizan client IDs de otras aplicaciones, cookies ni tokens privados para simular autenticación.

## Descubrimiento y seguridad

`ModelCatalogProtocol` construye y analiza solicitudes sin interfaz. `ModelCatalogService` aplica ese contrato con una sesión efímera. La carga sucede solo al pulsar Discover models. Hay un máximo de diez páginas, detección de cursores repetidos y una etiqueta de catálogo parcial cuando no se completó el listado. Los cursores se codifican como parámetros en el mismo endpoint; nunca se sigue un `next` URL arbitrario de la respuesta.

Se conservan solo los IDs textuales conocidos en Google/OpenRouter cuando la respuesta declara sus capacidades; la ausencia de metadatos no se transforma en una garantía. Se rechazan envelopes malformados en lugar de mostrarlos como un catálogo vacío exitoso.

El editor captura URL, clave y un ID único de consulta. Cambiar la URL o clave cancela la consulta. Una respuesta tardía no puede sobrescribir una consulta posterior. Cambiar URL borra inmediatamente la clave pegada y los modelos del borrador; una clave guardada se recupera solo para el UUID y endpoint exactos. Se limpia el campo al cerrar. Cancelar una edición no revoca una clave previamente guardada.

No hay reintentos de generación ni fallback cloud. La categoría Local es visual: el permiso de envío de historial depende del endpoint real, no del logo ni del nombre. Las restricciones de HTTPS/HTTP local y rechazo de redirecciones de la primera versión permanecen.

## Pruebas

`ConnectTests.swift` añade 31 pruebas: presets, registros antiguos, separación de conexiones, URL/credenciales, Cloudflare, paginación, envelopes, filtros y selección sin el límite de 30.

`ConnectionEditorTests.swift` añade 9: borrador, preservación de un ID manual, consultas parciales, claves ausentes, cambio de endpoint o clave, cancelación, cierre y respuestas tardías que ignoran la cancelación del servidor simulado.

Se ejecutan junto a las 28 pruebas originales: **68 pruebas portables**. El editor se compila sin `@Observable` en Linux; la observación de SwiftUI solo se activa en macOS. No equivale a compilar la interfaz ni el binario macOS. Hay tres pruebas adicionales de persistencia/selección en `MacTests/ConnectPersistenceTests.swift`, pendientes de ejecutar en una Mac.

## Fuentes primarias

Las URLs y hechos se contrastaron con las fuentes listadas en `SOURCES.md`, sección Connect 0.2. No se ha ejecutado una solicitud pagada ni una conexión al servidor privado del usuario desde este entorno.
