# Conceptos — JavaScript V

*Explicados como si se los contara a alguien de 12 años.*

## Constructors (de Clases)

Un *constructor* es un **molde para fabricar objetos**.

Si tenés que crear 50 usuarios, no vas a escribir 50 objetos a mano. Hacés un
molde una vez y después estampás todos los que quieras.

```js
class Perro {
  constructor(nombre, edad) {
    this.nombre = nombre;
    this.edad = edad;
  }
}

let fido = new Perro('Fido', 3);
let toby = new Perro('Toby', 5);
```

Las dos palabras clave:

- **`constructor`** es la función que se ejecuta en el momento en que se fabrica
  el objeto. Es donde le ponés los datos que lo hacen único.
- **`new`** es la que dispara la fábrica. Sin `new` no se crea nada nuevo.

`this` adentro del constructor significa **"el objeto que estoy fabricando en
este momento"**. Por eso `this.nombre = nombre` guarda el nombre recibido dentro
del objeto nuevo.

Cada objeto fabricado se llama una **instancia** del molde.

## `prototype`

Acá está la idea buena. Si cada perro guardara su propia copia de la función
`ladrar`, con 1000 perros tendrías 1000 copias idénticas ocupando memoria al
pedo.

El `prototype` es un **estante compartido**: una sola copia de las funciones,
que todos los objetos del mismo molde pueden usar.

```js
Perro.prototype.ladrar = function () {
  return 'Guau!';
};

fido.ladrar();   // 'Guau!'
toby.ladrar();   // 'Guau!'  ← la misma función, no una copia
```

### Cómo lo busca JavaScript

Cuando escribís `fido.ladrar()`, JavaScript hace esto:

1. Busca `ladrar` **dentro** de `fido`. ¿No está?
2. Sube al `prototype` de `Perro` y busca ahí. ¿Está? Lo usa.
3. Si tampoco estuviera, sigue subiendo hasta el final. Si no aparece, error.

A esa escalera hacia arriba se la llama **cadena de prototipos**.

Es como buscar unas tijeras: primero mirás en tu cartuchera; si no están, vas al
armario del aula, que es compartido por todos.

### Detalle

Los métodos que escribís dentro de una `class` van al `prototype`
automáticamente. La sintaxis de `class` es azúcar sobre este mismo mecanismo: no
es un sistema distinto, es una forma más cómoda de escribir lo mismo.

Y como el estante es compartido, si le agregás algo **después** de haber creado
los objetos, esos objetos igual lo ven. Por eso funciona esto:

```js
let p = new Perro('Fido', 3);
Perro.prototype.saludar = function () { return 'Hola'; };
p.saludar();   // 'Hola' ← aunque p ya existía antes
```
