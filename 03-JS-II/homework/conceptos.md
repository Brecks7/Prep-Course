# Conceptos — JavaScript II

*Explicados como si se los contara a alguien de 12 años.*

## `for`

Un `for` es **repetir algo muchas veces sin escribirlo muchas veces**.

Si querés saludar a 100 personas, no escribís 100 líneas: le decís a la
computadora "hacé esto, 100 veces".

```js
for (let i = 0; i < 5; i++) {
  console.log('Vuelta número ' + i);
}
```

El paréntesis tiene tres partes separadas por `;`:

1. `let i = 0` → **dónde arranca** el contador. (Se hace una sola vez.)
2. `i < 5` → **hasta cuándo sigue**. Antes de cada vuelta se pregunta esto; si
   la respuesta es `false`, se corta.
3. `i++` → **cuánto avanza** después de cada vuelta.

Es como subir una escalera: empezás en el escalón 0, seguís mientras te falten
escalones, y subís de a uno.

Si la condición nunca se vuelve falsa, el bucle no termina nunca. Eso se llama
*bucle infinito* y te cuelga el programa.

## `&&`, `||`, `!`

Son las tres formas de **combinar respuestas de sí/no**.

### `&&` — "Y"

Da `true` solo si **las dos** cosas son verdad. Es exigente.

```js
edad >= 18 && tieneEntrada   // true solo si se cumplen las dos
```

Como decir "podés ir al recital si sos mayor **y** tenés entrada". Si te falta
una, no entrás.

### `||` — "O"

Da `true` si **al menos una** es verdad. Es generoso.

```js
esSabado || esDomingo   // true si es cualquiera de los dos
```

Como decir "es fin de semana si es sábado **o** es domingo". Con una alcanza.

### `!` — "NO"

Da vuelta la respuesta. Lo verdadero se hace falso y al revés.

```js
!true    // false
!(5 > 3) // false, porque 5 > 3 era true
```

Como cuando alguien dice "no está lloviendo": estás negando lo de adentro.

### Un truco: cortocircuito

JavaScript es vago. Con `&&`, si la primera parte ya es `false`, ni mira la
segunda: ya sabe que el total va a ser `false`. Con `||`, si la primera ya es
`true`, tampoco mira la segunda.
