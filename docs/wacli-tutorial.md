# wacli — WhatsApp desde la terminal

CLI para enviar y leer WhatsApp sin abrir el navegador. Funciona con OSAI como skill.

## Instalar

```bash
# macOS (Homebrew)
brew install AdrianEspi/tap/wacli

# O descarga directa desde GitHub releases
```

## Conectar tu WhatsApp

```bash
wacli auth
```

Te muestra un QR en la terminal. Escanea con WhatsApp > Dispositivos vinculados. Espera a que sincronice.

Verificar que estás conectado:
```bash
wacli auth status
```

## Buscar contactos

```bash
# Buscar por nombre
wacli contacts search "Yan"

# Ver detalle de un contacto
wacli contacts show 34612345678@s.whatsapp.net
```

Los contactos se identifican por JID:
- Personas: `34612345678@s.whatsapp.net` (codigo pais + numero)
- Grupos: `120363xxxxx@g.us`

## Enviar mensajes

```bash
# Texto simple (puedes usar el numero directamente)
wacli send text --to "34612345678" --message "Ey, que tal!"

# Con JID completo
wacli send text --to "34612345678@s.whatsapp.net" --message "Hola!"
```

## Enviar archivos (fotos, videos, docs, audio)

```bash
# Imagen con caption
wacli send file --to "34612345678" --file ~/Desktop/foto.jpg --caption "Mira esto"

# Documento PDF
wacli send file --to "34612345678" --file ~/Documents/informe.pdf

# Audio (MP3, OGG, M4A, WAV, OPUS)
wacli send file --to "34612345678" --file ~/audio.mp3
```

## Leer mensajes

```bash
# Ver chats recientes
wacli chats list --limit 20

# Mensajes de un chat
wacli messages list --chat "34612345678@s.whatsapp.net" --limit 20

# Mensajes de hoy
wacli messages list --chat "34612345678@s.whatsapp.net" --after "2026-03-19"

# Buscar mensajes por texto
wacli messages search "restaurante"

# Buscar en un chat especifico
wacli messages search "factura" --chat "34612345678@s.whatsapp.net"
```

## Grupos

```bash
# Listar grupos
wacli groups list

# Info de un grupo
wacli groups info 120363xxxxx@g.us

# Obtener link de invitacion
wacli groups invite get 120363xxxxx@g.us
```

## Sincronizar

Si no ves mensajes recientes:
```bash
wacli sync
```

## Usar con OSAI

Copia el skill de WhatsApp a tu carpeta de skills:

```bash
mkdir -p ~/.desktop-agent/skills
```

Crea `~/.desktop-agent/skills/whatsapp.md` con este contenido:

```yaml
---
name: WhatsApp
description: WhatsApp messaging via wacli CLI
triggers: [whatsapp, whats, wsp, mensaje, mensajes, chat, contacto, grupo, enviar mensaje, send message]
tools: [run_shell]
---
```

Luego en OSAI puedes decir cosas como:
- "Manda un whatsapp a Yan diciendo que llego tarde"
- "Lee mis ultimos mensajes de WhatsApp"
- "Busca el contacto de Adrian"
- "Envia esta foto a Mama"

## Tips

- Usa `--json` para output estructurado (util para scripts y OSAI)
- Los numeros van con codigo de pais sin + (ej: `34` para Espana)
- Si da error de autenticacion, ejecuta `wacli auth` de nuevo
- `wacli doctor` diagnostica problemas de conexion
