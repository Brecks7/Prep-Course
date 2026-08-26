#!/usr/bin/env bash
# 10-amd — drivers de GPU.
#
# Decisión importante: en Ubuntu 24.04 el stack correcto para AMD es el open
# source que YA viene en el sistema (amdgpu en el kernel + Mesa en espacio de
# usuario). NO instalamos el driver propietario de AMD ("Radeon Software for
# Linux" / amdgpu-install):
#
#   - Para escritorio y juegos rinde igual o peor que Mesa.
#   - Es la causa número uno de sistemas que arrancan sin entorno gráfico.
#   - Solo tiene sentido para ROCm (cómputo/IA) o software profesional
#     certificado, que no es este caso.
#
# Lo que sí hacemos es asegurarnos de que Vulkan, OpenGL y la aceleración de
# video por hardware (VA-API) estén completos, porque Ubuntu no instala todo
# por defecto.

modulo_gpu() {
    log_step "10-gpu · Drivers de video"

    local gpu modelo
    gpu="$(detect_gpu)"
    modelo="$(gpu_model)"
    log_info "GPU detectada: ${modelo:-desconocida}"

    case "$gpu" in
        amd)
            log_info "Stack AMD open source (amdgpu + Mesa). No se instala driver propietario."
            if apt_install \
                mesa-vulkan-drivers mesa-va-drivers vulkan-tools \
                libdrm-amdgpu1 mesa-utils vainfo
            then
                note_ok "Drivers AMD (Mesa/Vulkan/VA-API) instalados"
            else
                note_err "Falló la instalación de los drivers AMD"
                return 1
            fi

            # Bibliotecas de 32 bits: las necesitan Steam, Wine y Proton.
            if ask "¿Vas a usar Steam, Wine o Proton? (agrega soporte 32 bits)"; then
                run sudo dpkg --add-architecture i386
                run sudo apt-get update
                if apt_install mesa-vulkan-drivers:i386 libgl1-mesa-dri:i386; then
                    note_ok "Soporte gráfico de 32 bits instalado (Steam/Wine)"
                else
                    note_warn "No se pudo instalar el soporte gráfico de 32 bits"
                fi
            fi

            verificar_gpu
            ;;
        nvidia)
            note_warn "GPU NVIDIA detectada — este módulo está pensado para AMD, se saltea"
            note_todo "Para NVIDIA usá la app 'Controladores adicionales' de Ubuntu, o 'sudo ubuntu-drivers autoinstall'"
            ;;
        intel)
            log_info "GPU Intel: el driver ya viene en el kernel, solo completamos Vulkan/VA-API."
            if apt_install mesa-vulkan-drivers intel-media-va-driver mesa-utils vainfo; then
                note_ok "Drivers Intel completados"
            else
                note_err "Falló la instalación de los drivers Intel"
            fi
            verificar_gpu
            ;;
        *)
            note_warn "No se pudo identificar la GPU — no se tocó nada de video"
            ;;
    esac
}

verificar_gpu() {
    if [[ "$DRY_RUN" == "1" ]]; then
        log_info "[dry] se verificaría con glxinfo -B y vulkaninfo --summary"
        return 0
    fi

    if has_cmd glxinfo; then
        local render
        render="$(glxinfo -B 2>/dev/null | grep -i 'OpenGL renderer' || true)"
        [[ -n "$render" ]] && log_ok "OpenGL: ${render#*: }"
    fi

    if has_cmd vulkaninfo; then
        if vulkaninfo --summary >/dev/null 2>&1; then
            log_ok "Vulkan responde correctamente"
        else
            note_warn "Vulkan no responde — revisá 'vulkaninfo --summary' a mano"
        fi
    fi

    if has_cmd vainfo; then
        if vainfo >/dev/null 2>&1; then
            log_ok "Aceleración de video (VA-API) funcionando"
        else
            note_warn "VA-API no responde — el video por hardware puede no andar"
        fi
    fi
}
