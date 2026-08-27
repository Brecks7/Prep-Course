# Conceptos — JavaScript I

*Explicados como si se los contara a alguien de 12 años.*

## Variables

Una variable es una **caja con una etiqueta**. Adentro guardás algo, y la
etiqueta es el nombre con el que después lo pedís.

```js
let edad = 12;
```

Ahí creaste una caja etiquetada `edad` y adentro pusiste el número 12. Cada vez
que escribas `edad`, JavaScript va a la caja y saca lo que haya adentro.

Hay tres formas de crear cajas:

- `let` → podés cambiar lo que hay adentro después.
- `const` → una vez que la llenás, no la podés reemplazar. Es una caja sellada.
- `var` → la forma vieja. Funciona, pero hoy se usa `let` o `const`.

## Strings

Un *string* (cadena) es **texto**. Se escribe entre comillas para que
JavaScript entienda que es texto y no una orden.

```js
let saludo = 'Hola';
```

Sin las comillas, JavaScript pensaría que `Hola` es el nombre de una caja y se
enojaría porque no existe.

Los strings se pueden pegar con `+`:

```js
'Hola' + ' ' + 'mundo'   // 'Hola mundo'
```

Y tienen un `.length` que te dice cuántos caracteres tienen (los espacios
cuentan).

## Funciones (argumentos, `return`)

Una función es una **máquina**: le metés cosas por un lado y sale un resultado
por el otro. Lo bueno es que la armás una sola vez y la usás mil.

```js
function sumar(a, b) {
  return a + b;
}

sumar(2, 3);   // 5
```

- **Argumentos**: `a` y `b`. Son lo que le metés a la máquina. Cuando escribís
  `sumar(2, 3)`, adentro de la función `a` vale 2 y `b` vale 3.
- **`return`**: es lo que **sale** de la máquina. Sin `return`, la máquina hace
  ruido pero no entrega nada (devuelve `undefined`).

Cuidado con confundir `return` y `console.log`:

- `return` **entrega** el resultado para que lo puedas usar.
- `console.log` solo lo **muestra** en pantalla, como gritarlo por la ventana.
  Nadie lo puede agarrar.

## Declaraciones `if`

Un `if` es una **bifurcación en el camino**. Si se cumple la condición, hacés
una cosa; si no, otra.

```js
if (edad >= 18) {
  console.log('Podés entrar');
} else {
  console.log('No podés entrar');
}
```

Se lee: "si la edad es 18 o más, entonces... si no, entonces...".

Podés encadenar varios con `else if` para tener más de dos caminos. JavaScript
los prueba **en orden** y se queda con el primero que se cumple — por eso el
orden en que los escribís importa.

## Valores booleanos (`true`, `false`)

Un booleano es una respuesta de **sí o no**. Solo puede valer `true`
(verdadero) o `false` (falso). No hay término medio.

Cada vez que comparás dos cosas, el resultado es un booleano:

```js
5 > 3        // true
5 === 3      // false
'a' === 'a'  // true
```

Por eso esto está de más:

```js
if (x === y) return true;
else return false;
```

`x === y` **ya es** `true` o `false`. Alcanza con `return x === y`.

Ojo con la diferencia:

- `===` compara valor **y** tipo. `0 === '0'` es `false`.
- `==` convierte antes de comparar. `0 == '0'` es `true`, lo cual confunde.

Usá siempre `===`.
