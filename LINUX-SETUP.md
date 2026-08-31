# De Windows a Ubuntu

Guía de referencia para consultar rápido. El material del Prep Course muestra
todo en Windows; acá está el equivalente en Linux.

Para instalar y configurar todo automáticamente: [`setup/README.md`](setup/README.md).

---

## Atajos de teclado (GNOME 46 y posteriores)

La tecla `Windows` ahora se llama `Super`.

| Atajo | Qué hace |
|---|---|
| `Super` | Buscador global: apps, archivos, configuración. Tu nuevo menú inicio. |
| `Ctrl` + `Alt` + `T` | Abrir terminal |
| `Super` + `←` / `→` | Media pantalla (como `Win`+flechas) |
| `Super` + `↑` / `↓` | Maximizar / restaurar |
| `Super` + `PgUp` / `PgDn` | Cambiar de escritorio virtual |
| `Super` + `Shift` + `PgUp` / `PgDn` | Llevarte la ventana al otro escritorio |
| `Alt` + `Tab` | Cambiar entre aplicaciones |
| `` Alt `` + `` ` `` | Cambiar entre ventanas de la **misma** app |
| `Super` + `L` | Bloquear pantalla |
| `Super` + `D` | Mostrar el escritorio |
| `PrtSc` | Captura de pantalla (incluye grabar video) |
| `Super` + `1`...`9` | Abrir la app N del dock |

Los escritorios virtuales son lo mejor que vas a encontrar viniendo de Windows.
Uno para el editor, otro para el navegador, otro para lo demás.

### PaperWM: por qué no podés arrastrar las esquinas

En esta máquina está **PaperWM**, que cambia la regla más básica que traés de Windows:
las ventanas ya no flotan, se acomodan solas en una **tira horizontal** por la que te
desplazás. La contrapartida es que **el tamaño lo decide el gestor**, no el mouse — por eso
arrastrar una esquina no hace nada. No es un bug ni una opción apagada: es cómo funciona un
gestor en mosaico.

Cuando necesitás una ventana "de Windows", que se estire libre desde cualquier esquina,
existe la **capa flotante**:

| Atajo | Qué hace |
|---|---|
| **`Super` + `Escape`** | Saca la ventana enfocada a flotante — **ahí sí se arrastra desde las esquinas** |
| `Super` + `Shift` + `Escape` | Muestra u oculta todas las flotantes |
| `Super` + `+` / `-` | Ancho de la ventana, dentro de la tira |
| `Super` + `Shift` + `+` / `-` | Alto de la ventana, dentro de la tira |
| `Super` + `F` | Ocupar todo el ancho |
| `Super` + `Shift` + `F` | Pantalla completa |
| `Super` + `Shift` + `W` | Cambiar hacia qué lado se abre la próxima ventana |

Es lo más parecido a tener las dos cosas: la tira para trabajar, y `Super`+`Escape` para el
rato en que necesitás mover una ventana a mano.

---

## Atajos de terminal

Acá está la ganancia real. Estos seis te ahorran horas:

| Atajo | Qué hace |
|---|---|
| `Ctrl` + `Shift` + `C` / `V` | **Copiar / pegar.** Ojo: `Ctrl+C` a secas **cancela** el comando. |
| `Ctrl` + `R` | Buscar en el historial. El más útil de todos. |
| `Tab` | Autocompletar comandos, rutas y nombres de archivo |
| `Ctrl` + `L` | Limpiar la pantalla |
| `Ctrl` + `C` | Cancelar el comando que está corriendo |
| `Ctrl` + `D` | Salir de la terminal |

Edición de la línea que estás escribiendo:

| Atajo | Qué hace |
|---|---|
| `Ctrl` + `A` / `E` | Ir al inicio / final de la línea |
| `Ctrl` + `U` | Borrar toda la línea |
| `Ctrl` + `W` | Borrar la palabra anterior |
| `Alt` + `←` / `→` | Moverse de a una palabra |

Y dos comodines:

```bash
!!          # repite el último comando
sudo !!     # lo repite con sudo (cuando te olvidaste)
cd -        # vuelve a la carpeta anterior
```

---

## Equivalencias con Windows

| Windows | Ubuntu |
|---|---|
| Explorador de archivos | **Archivos** (Nautilus) |
| Bloc de notas | **Editor de texto** |
| Administrador de tareas | `btop` en la terminal, o **Monitor del sistema** |
| Panel de control | **Configuración** |
| cmd / PowerShell | **Terminal** (bash) |
| Instalar un `.exe` | `sudo apt install <programa>` o Centro de Software |
| `C:\Users\vos\` | `/home/vos/` — se escribe `~` |
| `\` en las rutas | `/` |
| Barra de tareas | Dock |

---

## apt, snap y flatpak

Ubuntu tiene tres gestores de paquetes conviviendo. La regla práctica:

- **`apt`** — herramientas de sistema y de línea de comandos. Es el nativo y el
  más rápido. `sudo apt install ripgrep`
- **`flatpak`** — aplicaciones de escritorio (Spotify, Discord, GIMP). Versiones
  más nuevas y aisladas del sistema. `flatpak install flathub <app>`
- **`snap`** — el formato de Canonical. Funciona, pero las apps tardan más en
  abrir porque cada snap monta su propia imagen comprimida. Se puede vivir sin
  él.

---

## Las cuatro trampas al venir de Windows

Estas cuatro son las que hacen perder tardes enteras. Vale la pena leerlas antes
de necesitarlas.

### 1. Linux distingue mayúsculas de minúsculas

En Windows `Header.js` y `header.js` son el mismo archivo. En Linux **no**.

```js
import Header from './header';   // ✅ en Windows, ❌ en Linux si el archivo es Header.js
```

Es el error número uno de los que migran, y el más desconcertante: el proyecto
te andaba perfecto y de golpe no compila. Si un `import` falla y jurás que la
ruta está bien, revisá las mayúsculas letra por letra.

### 2. Los finales de línea (CRLF vs LF)

Windows termina las líneas con dos caracteres invisibles (`CRLF`), Linux con uno
(`LF`). Sin configurarlo, git te va a mostrar archivos enteros como modificados
cuando no tocaste nada.

```bash
git config --global core.autocrlf input
```

### 3. Nunca instales Node con `apt`

La versión de los repositorios queda vieja enseguida, y en desarrollo web vas a
necesitar cambiar de versión según el proyecto. Usá **nvm**:

```bash
nvm install --lts      # instalar la última LTS
nvm install 16         # instalar una versión vieja
nvm use 16             # cambiar a ella
nvm ls                 # ver cuáles tenés
```

> **Para este repo (Prep Course):** las dependencias son de 2021 (Eleventy 0.12,
> Jest 27). Si `npm install` o `npm test` te fallan con una versión moderna de
> Node, probá `nvm install 16 && nvm use 16`.

### 4. Nunca uses `sudo` con `npm`

```bash
sudo npm install -g algo     # ❌ NO
```

Te deja archivos de root dentro de tu carpeta personal y después nada funciona
bien. Con nvm no hace falta `sudo` nunca, porque Node vive en tu `$HOME`.

Regla general: **`sudo` solo para cosas del sistema.** Si un tutorial te dice de
usar `sudo` para algo dentro de `/home`, desconfiá.

---

## Herramientas que valen la pena

Estas reemplazan a las clásicas y se aprenden en cinco minutos:

| Herramienta | Reemplaza a | Para qué |
|---|---|---|
| `rg` (ripgrep) | `grep` | Buscar texto en un proyecto entero, al instante |
| `fzf` | — | Buscador difuso; hace que `Ctrl+R` sea interactivo |
| `bat` | `cat` | Ver archivos con colores y números de línea |
| `eza` | `ls` | Listar archivos, más legible |
| `zoxide` | `cd` | `cd` con memoria: `z config` te lleva a `~/Documentos/Proyectos/Configurador` |
| `btop` | Administrador de tareas | Ver CPU, RAM y procesos |

```bash
sudo apt install ripgrep fzf bat btop eza zoxide
```

> En Ubuntu el binario de `bat` se llama `batcat` (por un conflicto de nombres).
> El script de setup crea el alias `bat` automáticamente.

Para el escritorio: **Extension Manager** y **Retoques** (gnome-tweaks) para
personalizar, **Timeshift** para snapshots antes de romper algo, y **Flathub**
para el resto de las apps.

---

## Si seguiste un tutorial de "Ubuntu como macOS"

Casi todos esos videos dejan el equipo más lento, y la causa rara vez es el
tema. Lo que hay que mirar, en orden:

1. **¿Está acelerando la placa de video?** Corré `glxinfo -B | grep "OpenGL
   renderer"`. Si dice `llvmpipe`, estás dibujando todo con la CPU y nada va a
   ir fluido hasta arreglar eso. Ojo: una GPU AMD real dice algo como
   `AMD Radeon RX 7600 (radeonsi, navi33, LLVM 17.0.6)` — eso tiene "LLVM"
   pero **no** es `llvmpipe`, está bien.
2. **¿Cuántos docks tenés activos?** `gnome-extensions list --enabled`. Si
   aparecen `ubuntu-dock` y `dash-to-dock` juntos, se están peleando.
3. **¿Qué corre de fondo?** `pgrep -l "plank|conky|cairo-dock"`. Estos comen
   GPU todo el tiempo.

El diagnóstico completo, con el veredicto ya interpretado:

```bash
bash setup/doctor.sh
```

## Trabajar mejor con Claude

Claude Code corre nativo en Linux, sin WSL de por medio:

```bash
curl -fsSL https://claude.ai/install.sh | bash
claude          # arrancarlo dentro de la carpeta de un proyecto
```

Lo que más mejora las respuestas es un archivo **`CLAUDE.md`** en la raíz del
repositorio. Se lee solo cada vez que abrís Claude Code ahí, así que no tenés
que repetir el contexto nunca más. Sirve para decirle:

- Qué es el proyecto y qué estás intentando lograr
- Que estás aprendiendo y preferís que te explique antes que resolver
- En qué idioma responder
- Cómo se corren los tests

En este repo ya hay uno: [`CLAUDE.md`](CLAUDE.md). Editalo a tu gusto.
