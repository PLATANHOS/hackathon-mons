# UniRewards

UniRewards es una aplicación web educativa que conecta estudiantes y profesores mediante un contrato inteligente en Monad Testnet. Los estudiantes pueden unirse a clases, entregar actividades, acumular puntos, mantener rachas y canjear recompensas simuladas. Los profesores pueden crear clases, publicar actividades y calificar entregas.

## Contrato en Monad Testnet

- **Red:** Monad Testnet
- **Chain ID:** `10143`
- **Dirección:** [`0xC4EdfFa3b5872121E9B38Cc536965fDE78B446DA`](https://testnet.monadexplorer.com/address/0xC4EdfFa3b5872121E9B38Cc536965fDE78B446DA)
- **RPC configurado:** `https://rpc.ankr.com/monad_testnet`

La dirección del contrato está configurada en `index.html`. Si despliegas otra instancia, actualiza la constante `CONTRACT` con la nueva dirección.

## Requisitos

- Navegador moderno y conexión a internet.
- Python 3 (opcional, para servir la aplicación localmente).
- MON de prueba en Monad Testnet para pagar el gas.

## Ejecutar localmente

Desde la carpeta raíz del proyecto, inicia un servidor estático:

```powershell
py -m http.server 8000
```

Abre [http://localhost:8000](http://localhost:8000) en el navegador. También puedes abrir `index.html` directamente, aunque un servidor local suele ser más compatible con las funciones web del navegador.

La aplicación carga ethers.js y las fuentes desde servicios externos, así que necesita conexión a internet.

## Desplegar el contrato

1. Abre `contracts/Contract.sol` en Remix.
2. Compila con una versión compatible con Solidity `^0.8.20`.
3. Conecta Remix a Monad Testnet y despliega `UniRewards`.
4. Copia la dirección desplegada y actualiza `CONTRACT` en `index.html`.
5. Abre la aplicación y prueba el registro con MON de testnet.

El contrato inicializa las recompensas y los logros al desplegarse. Las recompensas del catálogo son simuladas; no representan acuerdos ni premios reales.

## Configuración opcional

En `index.html`:

- `PINATA_JWT`: permite cargar archivos a IPFS mediante Pinata. Si queda vacío, la aplicación acepta enlaces a archivos en lugar de subirlos.
- `AI_ENDPOINT`: endpoint opcional para generar ejercicios y quizzes. Debe aceptar un `POST` JSON con `prompt` y `files`, y responder con `{ "text": "..." }`. Si queda vacío, el asistente funciona en modo demo.

No publiques credenciales, claves privadas ni tokens en el código cliente. El prototipo guarda las billeteras creadas en el almacenamiento local del navegador; utiliza únicamente cuentas y fondos de prueba, y no hay recuperación de claves.
