# Contexto del proyecto

Este repositorio es el **Prep Course de Henry**: el curso preparatorio de
Desarrollo Web Full Stack. Contiene material de lectura (`README.md` por módulo)
y ejercicios con tests (`homework/`), sobre JavaScript, HTML y CSS.

## Sobre mí

Soy estudiante y estoy aprendiendo. Cuando me ayudes con un ejercicio:

- **Explicá el porqué**, no me des solo la solución. Si me pasás el código
  resuelto sin más, no aprendo nada y el Henry Challenge lo rindo yo, no vos.
- Si me equivoco, señalá dónde está el error y por qué falla, antes de corregirlo.
- Respondeme en español.

## Entorno

- Ubuntu 24.04 LTS (vengo de Windows, avisame si algo es específico de Linux).
- Node instalado con **nvm**, no con apt.
- Editor: VS Code.

## Correr los tests

```bash
npm install
npm test          # jest sobre los homework
```

Ojo: las dependencias de este repo son de 2021 (Eleventy 0.12, Jest 27). Si
`npm install` o `npm test` fallan con una versión moderna de Node, probá con
una más vieja: `nvm install 16 && nvm use 16`.

## Sitio local

```bash
npm start         # levanta Eleventy en http://localhost:8080
```

## Qué no tocar

Las carpetas numeradas (`00-PrimerosPasos/`, `01a-Git/`, `02-JS-I/`, ...) son
material del curso de Henry. Los archivos dentro de `homework/` sí son míos para
resolver.
