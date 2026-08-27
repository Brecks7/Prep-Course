# Conceptos — JavaScript III

*Explicados como si se los contara a alguien de 12 años.*

## Arrays

Un array es una **lista ordenada de cosas**, guardada en una sola caja.

Si una variable es una caja con una cosa adentro, un array es una **caja con
cajones numerados**.

```js
let frutas = ['manzana', 'banana', 'pera'];
```

### Los cajones empiezan en 0

Esto es lo que más confunde al principio: el primer cajón es el **0**, no el 1.

```js
frutas[0]   // 'manzana'
frutas[1]   // 'banana'
frutas[2]   // 'pera'
```

Por eso, si el array tiene 3 elementos, el último cajón es el **2**. La fórmula
para llegar al último siempre es:

```js
frutas[frutas.length - 1]
```

### `.length`

Te dice **cuántas** cosas hay adentro. Ojo: cuenta desde 1, aunque los cajones
se numeren desde 0. `frutas.length` es 3.

### Recorrerlo

Casi todo lo que hacés con arrays es pasar por cada cajón, de a uno:

```js
for (let i = 0; i < frutas.length; i++) {
  console.log(frutas[i]);
}
```

`i` va valiendo 0, 1, 2... y `frutas[i]` va sacando lo que hay en cada cajón.

### Métodos útiles

- `.push(algo)` → agrega al **final**.
- `.unshift(algo)` → agrega al **principio** (y corre todo lo demás).
- `.pop()` → saca el **último** y te lo devuelve.
- `.includes(algo)` → te dice `true` o `false` si eso está adentro.
- `.join(' ')` → pega todo en un solo string, con lo que le pases en el medio.

### Un detalle importante

Los arrays se pasan a las funciones **por referencia**: la función no recibe una
copia, recibe el array original. Si adentro le hacés `push`, el array de afuera
también cambia. Es como prestarle tu cuaderno a alguien: si escribe, escribe en
el tuyo, no en una fotocopia.
