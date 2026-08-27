# Conceptos — JavaScript IV

*Explicados como si se los contara a alguien de 12 años.*

## Objetos

Si un array es una lista con cajones **numerados**, un objeto es una lista con
cajones **con nombre**.

Sirve para juntar varios datos que describen una misma cosa:

```js
let perro = {
  nombre: 'Fido',
  edad: 3,
  raza: 'caniche'
};
```

Es como la ficha de un jugador: en vez de acordarte que "el 0 es el nombre y el
1 es la edad", cada dato tiene su etiqueta.

## Propiedades

Cada par **etiqueta: valor** dentro del objeto es una propiedad.

En el ejemplo, `nombre`, `edad` y `raza` son las propiedades. La etiqueta se
llama *clave* (o *key*) y lo que hay guardado es el *valor*.

Podés agregar propiedades nuevas cuando quieras:

```js
perro.color = 'blanco';
```

Y borrarlas:

```js
delete perro.color;
```

## Métodos

Un método es una propiedad que, en vez de guardar un dato, guarda una
**función**. O sea: una cosa que el objeto **sabe hacer**.

```js
let perro = {
  nombre: 'Fido',
  ladrar: function () {
    return 'Guau!';
  }
};

perro.ladrar();   // 'Guau!'
```

Los paréntesis al final son los que lo ejecutan. Sin los paréntesis
(`perro.ladrar`) no lo ejecutás: solo estás señalando la función.

Adentro de un método, la palabra `this` significa **"el objeto al que
pertenezco"**. Sirve para que el método use los datos de su propio objeto:

```js
let perro = {
  nombre: 'Fido',
  presentarse: function () {
    return 'Soy ' + this.nombre;
  }
};
```

## Bucle `for…in`

Es un `for` especial para objetos: recorre **las claves** una por una.

```js
for (let clave in perro) {
  console.log(clave + ': ' + perro[clave]);
}
```

En cada vuelta, `clave` vale `'nombre'`, después `'edad'`, después `'raza'`.

Ojo con un detalle: `clave` es el **nombre** de la propiedad, no el valor. Para
el valor tenés que pedir `perro[clave]`.

## Notación de puntos vs notación de corchetes

Son dos maneras de entrar a una propiedad.

### Puntos: `perro.nombre`

Corta y clara. Se usa cuando **ya sabés** cómo se llama la propiedad al momento
de escribir el código.

### Corchetes: `perro['nombre']`

Hace exactamente lo mismo, pero la propiedad va como **string**. Y ahí está la
gracia: adentro de los corchetes podés poner una **variable**.

```js
let cual = 'nombre';
perro[cual];    // 'Fido'  ← usa el valor de la variable
perro.cual;     // undefined ← busca una propiedad llamada literalmente "cual"
```

Por eso los corchetes son obligatorios cuando:

- El nombre de la propiedad te llega como argumento de una función.
- El nombre tiene espacios o caracteres raros: `objeto['mi propiedad']`.
- El nombre se arma sobre la marcha.
