# Conceptos — JavaScript VI

*Explicados como si se los contara a alguien de 12 años.*

## Funciones Callback

Un *callback* es una **función que le pasás a otra función para que la llame
cuando corresponda**.

La palabra viene de "call back": llamame de vuelta.

### La idea

En JavaScript las funciones son valores, igual que un número o un string. Podés
guardarlas en variables, meterlas en arrays y —acá está la gracia— **pasarlas
como argumento**.

```js
function saludar() {
  return 'Hola!';
}

function hacerDosVeces(cb) {
  cb();
  cb();
}

hacerDosVeces(saludar);
```

`saludar` es el callback. `hacerDosVeces` no sabe ni le importa qué hace: solo
sabe que le pasaron algo que se puede ejecutar, y lo ejecuta dos veces.

### El detalle que más confunde

```js
hacerDosVeces(saludar);     // ✓ le pasás la función
hacerDosVeces(saludar());   // ✗ la ejecutás y le pasás el resultado
```

Con paréntesis la ejecutás **ahí mismo** y mandás lo que devolvió. Sin
paréntesis mandás la función misma, para que la otra decida cuándo usarla.

Es la diferencia entre **darle a alguien la receta** y **darle el bizcochuelo ya
hecho**.

### Para qué sirve

Para que una función sepa *cuándo* hacer algo sin saber *qué* hay que hacer.

```js
function operacion(a, b, cb) {
  return cb(a, b);
}

operacion(4, 2, function (x, y) { return x + y; });   // 6
operacion(4, 2, function (x, y) { return x * y; });   // 8
```

`operacion` es siempre la misma: lo que cambia es la función que le pasás. Es
como un taladro al que le cambiás la mecha.

### Dónde los vas a ver

En un montón de métodos de arrays:

```js
[1, 2, 3].map(function (n) { return n * 2; });      // [2, 4, 6]
[1, 2, 3].filter(function (n) { return n > 1; });   // [2, 3]
[1, 2, 3].forEach(function (n) { console.log(n); });
```

Todos hacen lo mismo por dentro: recorren el array y en cada vuelta llaman al
callback pasándole el elemento actual.

También aparecen para cosas que tardan: "cuando termine de cargar el archivo,
llamá a esta función". Ahí el callback es la forma de decir *qué hacer después*,
sin quedarte esperando.
